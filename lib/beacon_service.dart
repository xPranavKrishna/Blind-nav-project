import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vazhikaatti/services/console_service.dart';

class RssiTracker {
  List<double> values = [];
  List<DateTime> timestamps = [];

  void add(double rssi) {
    DateTime now = DateTime.now();
    values.add(rssi);
    timestamps.add(now);
  }

  void cleanOld() {
    DateTime now = DateTime.now();
    while (timestamps.isNotEmpty && now.difference(timestamps.first).inSeconds > 5) {
      timestamps.removeAt(0);
      values.removeAt(0);
    }
  }

  double? get average {
    cleanOld();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }
}

class BeaconNavigationService {
  // Map Data - Pure Coordinates, No Predefined Strings!
  final Map<String, dynamic> _mapData = {
    "nodes": {
      "Entrance": [1.0, 0.0],
      "Hallway": [1.0, 8.0],
      "Door1": [1.0, 13.5], // Point in hallway adjacent to Room 1
      "Room1": [-1.8, 13.5], // Center of Room 1
    },
    // Undirected edges for routing sequence
    "edges": [
      ["Entrance", "Hallway"],
      ["Hallway", "Door1"],
      ["Door1", "Room1"]
    ],
    // Known Absolute Coordinates of Beacons
    "beacons": {
      "Room1-Beacon": [-1.8, 13.5], // Center of Room 1
      "Hallway-Beacon": [1.0, 8.0]   // Middle of 2m Hallway
    },
    // Features for proximity triggers (1.5m radius)
    "features": {
      "Door ahead": [1.0, 13.5],
      "Turn now": [-0.5, 13.5]
    }
  };

  // State
  Timer? _scanTimer;
  bool _isNavigating = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  final StreamController<Map<String, dynamic>> _navigationStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool get isNavigating => _isNavigating;
  List<String> get availableRooms => ["Room1", "Hallway", "Entrance"]; 

  // Live Navigation State
  double? _userX;
  double? _userY;
  double _userHeading = pi / 2; // Default facing North (positive Y up the hallway)
  final Map<String, RssiTracker> _beaconsHistory = {};

  // Reverse mapping for getters
  String? get currentRoom {
    if (_userX == null || _userY == null) return null;
    double minD = double.infinity;
    String nearest = "Entrance";
    final nodes = _mapData['nodes'] as Map<String, List<double>>;
    for (var n in nodes.entries) {
      double d = sqrt(pow(_userX! - n.value[0], 2) + pow(_userY! - n.value[1], 2));
      if (d < minD) {
        minD = d;
        nearest = n.key;
      }
    }
    return nearest;
  }

  List<String> _currentPath = [];
  int _currentStepIndex = 0;
  String? _targetDestination;

  Set<String> _announcedFeatures = {};
  String _lastActionPhrase = "";
  int _lastBeaconCount = 0;
  int _recalcCooldown = 0;

  void startScanning() {
    print("BeaconNavigationService: Starting purely coordinate-based BLE scanning...");

    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 2));
      } catch (e) {
        print("Scan error: $e");
      }
    });

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      final beacons = _mapData['beacons'] as Map<String, List<double>>;
      bool updated = false;

      for (var r in results) {
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName;

        if (beacons.containsKey(name)) {
          if (!_beaconsHistory.containsKey(name)) {
            _beaconsHistory[name] = RssiTracker();
          }
          _beaconsHistory[name]!.add(r.rssi.toDouble());
          updated = true;
        }
      }

      if (updated || _beaconsHistory.isNotEmpty) {
        _evaluatePosition();
      }
    });

    // Fallback timer to evaluate position even if scans drop momentarily
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_scanTimer == null || !_scanTimer!.isActive) {
        timer.cancel();
        return;
      }
      if (_beaconsHistory.isNotEmpty) {
        _evaluatePosition();
      }
    });
  }

  void _evaluatePosition() {
    final beacons = _mapData['beacons'] as Map<String, List<double>>;
    double sumWeightX = 0;
    double sumWeightY = 0;
    double sumWeight = 0;
    int activeCount = 0;

    for (var name in beacons.keys) {
      if (_beaconsHistory.containsKey(name)) {
        double? avgRssi = _beaconsHistory[name]!.average;
        if (avgRssi != null) {
          activeCount++;
          // REQUIRED FORMULA: Distance = pow(10, (-69 - rssi) / 20.0)
          double distance = pow(10, (-69 - avgRssi) / 20.0).toDouble();
          
          // REQUIRED FORMULA: Weight = 1 / (distance + 0.1)
          double weight = 1 / (distance + 0.1);

          List<double> coords = beacons[name]!;
          sumWeightX += coords[0] * weight;
          sumWeightY += coords[1] * weight;
          sumWeight += weight;
        }
      }
    }

    _lastBeaconCount = activeCount;

    if (sumWeight > 0) {
      // REQUIRED FORMULA: User (x,y) = Σ (beacon_coord × weight) / Σ(weight)
      double newX = sumWeightX / sumWeight;
      double newY = sumWeightY / sumWeight;

      if (_userX != null && _userY != null) {
        // Handle gracefully: EMA smoothing to prevent teleportation and erratic jumps
        newX = _userX! * 0.7 + newX * 0.3;
        newY = _userY! * 0.7 + newY * 0.3;
        
        double smoothDx = newX - _userX!;
        double smoothDy = newY - _userY!;
        double smoothMoveDist = sqrt(smoothDx * smoothDx + smoothDy * smoothDy);
        
        // Update heading dynamically using vector differences if shifted steadily
        if (smoothMoveDist > 0.1) {
          double newHeading = atan2(smoothDy, smoothDx);
          double angleDiff = newHeading - _userHeading;
          while (angleDiff > pi) angleDiff -= 2 * pi;
          while (angleDiff < -pi) angleDiff += 2 * pi;
          _userHeading += angleDiff * 0.2; // Smooth heading
        }
      }

      _userX = newX;
      _userY = newY;
      
      if (_isNavigating) {
         _evaluateNavigationStep();
      }
    }
  }

  void stopScanning() {
    _scanTimer?.cancel();
    _scanSubscription?.cancel();
  }

  // Pure generic coordinate graph BFS
  List<String> _findShortestPath(String start, String target) {
    if (start == target) return [start];
    Map<String, List<String>> adj = {};
    for (var edge in _mapData['edges'] as List<List<dynamic>>) {
      adj.putIfAbsent(edge[0], () => []).add(edge[1]);
      adj.putIfAbsent(edge[1], () => []).add(edge[0]);
    }

    Queue<List<String>> queue = Queue();
    Set<String> visited = {};

    queue.add([start]);
    visited.add(start);

    while (queue.isNotEmpty) {
      List<String> path = queue.removeFirst();
      String current = path.last;
      if (current == target) return path;

      for (String n in adj[current] ?? []) {
        if (!visited.contains(n)) {
          visited.add(n);
          queue.add(List.from(path)..add(n));
        }
      }
    }
    return [];
  }

  void _evaluateNavigationStep() {
    if (!_isNavigating || _currentPath.isEmpty || _userX == null || _userY == null) return;
    
    if (_recalcCooldown > 0) _recalcCooldown--;
    final nodes = _mapData['nodes'] as Map<String, List<double>>;

    // 1. ARRIVED Check (at terminal node radius)
    if (_currentStepIndex >= _currentPath.length - 1) {
       List<double> finalCoords = nodes[_currentPath.last]!;
       double dx = _userX! - finalCoords[0];
       double dy = _userY! - finalCoords[1];
       if (sqrt(dx*dx + dy*dy) <= 1.5) {
          _navigationStreamController.add({
            "action": "ARRIVED",
            "description": "You have reached $_targetDestination",
            "direction": "stop"
          });
          _isNavigating = false;
          return;
       }
    }

    int targetIndex = _currentStepIndex + 1;
    if (targetIndex >= _currentPath.length) return; 
    
    String prevNode = _currentPath[_currentStepIndex];
    String targetNode = _currentPath[targetIndex];
    
    List<double> prevCoords = nodes[prevNode]!;
    List<double> targetCoords = nodes[targetNode]!;

    double tx = targetCoords[0];
    double ty = targetCoords[1];
    
    double dx = tx - _userX!;
    double dy = ty - _userY!;
    double distanceToWaypoint = sqrt(dx * dx + dy * dy);

    // 2. ADVANCE STEP: REQUIRED < 1.5m to next coordinate point
    if (distanceToWaypoint <= 1.5) {
      _currentStepIndex++;
      _lastActionPhrase = ""; // trigger immediate update upon step jump
      _evaluateNavigationStep(); // Recursively re-evaluate next step instantly
      return;
    }

    // 3. OFF-PATH: RECALCULATING (> 3m from segment vector)
    double segmentDistance = _pointToLineDistance(_userX!, _userY!, prevCoords[0], prevCoords[1], tx, ty);
    if (segmentDistance > 3.0 && _recalcCooldown == 0) {
      _navigationStreamController.add({
        "action": "RECALCULATING",
        "description": "Recalculating route",
        "direction": "stop"
      });
      ConsoleService().log("[NAV] Off-path by ${segmentDistance.toStringAsFixed(1)}m. Recalculating...");
      
      String nearestNode = _currentPath.first;
      double minDist = double.infinity;
      for (var entry in nodes.entries) {
        double dist = sqrt(pow(_userX! - entry.value[0], 2) + pow(_userY! - entry.value[1], 2));
        if (dist < minDist) {
          minDist = dist;
          nearestNode = entry.key;
        }
      }

      _currentPath = _findShortestPath(nearestNode, _targetDestination!);
      _currentStepIndex = 0;
      _lastActionPhrase = "";
      _recalcCooldown = 5; 
      if (_currentPath.isNotEmpty) _issueInstructionsForCurrentStep(distanceToWaypoint, tx, ty);
      return;
    }

    // 4. Feature Proximity trigger
    _checkFeatureProximity();

    // 5. Dynamic Guidance Vectoring
    _issueInstructionsForCurrentStep(distanceToWaypoint, tx, ty);
  }

  void _checkFeatureProximity() {
    if (_userX == null || _userY == null) return;
    var features = _mapData['features'] as Map<String, List<double>>;
    for (var entry in features.entries) {
      if (_announcedFeatures.contains(entry.key)) continue;
      
      double fx = entry.value[0];
      double fy = entry.value[1];
      double dist = sqrt(pow(_userX! - fx, 2) + pow(_userY! - fy, 2));
      
      // Proximity
      if (dist <= 1.5) {
        _announcedFeatures.add(entry.key);
        _navigationStreamController.add({
          "action": "FEATURE",
          "description": entry.key,
          "direction": "up"
        });
        ConsoleService().log("[NAV] Feature trigger: ${entry.key} at ${dist.toStringAsFixed(1)}m");
      }
    }
  }

  void _issueInstructionsForCurrentStep(double distanceToWaypoint, double targetX, double targetY) {
    if (_userX == null || _userY == null) return;
    
    // ATAN2 Vector direction math
    double targetHeading = atan2(targetY - _userY!, targetX - _userX!);
    double angleDiff = targetHeading - _userHeading;
    while (angleDiff > pi) angleDiff -= 2 * pi;
    while (angleDiff < -pi) angleDiff += 2 * pi;

    String actionStr;
    String directionStr;
    String phrase;
    String distStr = distanceToWaypoint.toStringAsFixed(1);

    // REQUIRED LOGIC: > 45° (0.785 rads)
    if (angleDiff > 0.785) {
      actionStr = "TURN LEFT";
      directionStr = "left";
      phrase = "Turn left in $distStr meters";
    } else if (angleDiff < -0.785) {
      actionStr = "TURN RIGHT";
      directionStr = "right";
      phrase = "Turn right in $distStr meters";
    } else {
      actionStr = "GO STRAIGHT";
      directionStr = "up";
      phrase = "Walk straight $distStr meters";
    }

    // Determine if we need to log and update the UI
    // We emit continuously so the UI updates live natively 
    if (phrase != _lastActionPhrase) {
      _lastActionPhrase = phrase;

      // REQUIRED LOG FORMAT EXACT MATCH
      ConsoleService().log("[NAV] User pos: (${_userX!.toStringAsFixed(1)}, ${_userY!.toStringAsFixed(1)}) | Distance to waypoint: ${distStr}m | Direction: $phrase | Beacons seen: $_lastBeaconCount");

      _navigationStreamController.add({
        "action": actionStr,
        "description": phrase, 
        "direction": directionStr
      });
    }
  }

  // Math point to line projection bounded to segment
  double _pointToLineDistance(double px, double py, double lx1, double ly1, double lx2, double ly2) {
    double l2 = pow(lx1 - lx2, 2).toDouble() + pow(ly1 - ly2, 2).toDouble();
    if (l2 == 0) return sqrt(pow(px - lx1, 2) + pow(py - ly1, 2));
    
    double t = max(0, min(1, ((px - lx1) * (lx2 - lx1) + (py - ly1) * (ly2 - ly1)) / l2));
    double projX = lx1 + t * (lx2 - lx1);
    double projY = ly1 + t * (ly2 - ly1);
    
    return sqrt(pow(px - projX, 2) + pow(py - projY, 2));
  }

  Stream<Map<String, dynamic>> startNavigation(String destination) {
    _isNavigating = true;
    _targetDestination = null;
    _announcedFeatures.clear();

    String destLower = destination.toLowerCase();
    final nodes = _mapData['nodes'] as Map<String, List<double>>;
    
    for (String node in nodes.keys) {
      if (destLower.contains(node.toLowerCase()) ||
          (node.toLowerCase() == "room1" && destLower.contains("room 1"))) {
        _targetDestination = node;
        break;
      }
    }

    if (_targetDestination == null) {
      _navigationStreamController.add({
        "action": "ERROR",
        "description": "Destination not found.",
        "direction": "stop"
      });
      _isNavigating = false;
      return _navigationStreamController.stream;
    }

    // Dynamic start node detection based purely on live coordinate math
    String startNode = "Entrance";
    if (_userX != null && _userY != null) {
      double minDist = double.infinity;
      for (var entry in nodes.entries) {
        double dist = sqrt(pow(_userX! - entry.value[0], 2) + pow(_userY! - entry.value[1], 2));
        if (dist < minDist) {
          minDist = dist;
          startNode = entry.key;
        }
      }
    }

    _currentPath = _findShortestPath(startNode, _targetDestination!);
    _currentStepIndex = 0;
    _lastActionPhrase = "";

    // DO NOT force immediate ARRIVED if startNode == _targetDestination, let _evaluateNavigationStep handle it.
    // Force absolute immediate first evaluation if coordinates exist
    if (_currentPath.length > 1 && _userX != null && _userY != null) {
       List<double> nextCoords = nodes[_currentPath[1]]!;
       _issueInstructionsForCurrentStep(
           sqrt(pow(nextCoords[0] - _userX!, 2) + pow(nextCoords[1] - _userY!, 2)),
           nextCoords[0], nextCoords[1]);
    } else if (_currentPath.isNotEmpty && _userX != null && _userY != null) {
       _evaluateNavigationStep();
    }

    return _navigationStreamController.stream;
  }

  void stopNavigation() {
    _isNavigating = false;
    _currentPath.clear();
    _announcedFeatures.clear();
  }
}