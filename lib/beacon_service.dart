import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vazhikaatti/services/console_service.dart';

class BeaconNavigationService {
  // Map (same as before)
  final Map<String, dynamic> _mapData = {
    "rooms": {
      "Entrance": {
        "coords": [1.5, 0],
        "beacons": ["Hallway-Beacon"],
        "features": {"door": [1.5, 1]},
        "neighbors": {
          "Hallway": {"distance": 8, "direction": "Walk straight 8m through door"}
        }
      },
      "Hallway": {
        "coords": [1, 8],
        "beacons": ["Hallway-Beacon"],
        "features": {"turn": [1, 12]},
        "neighbors": {
          "Entrance": {"distance": 8, "direction": "Turn back 8m"},
          "Room1": {"distance": 5, "direction": "Walk straight 5m at turn"}
        }
      },
      "Room1": {
        "coords": [1, 13.5],
        "beacons": ["Room1-Beacon"],
        "features": {"door": [1, 12]},
        "neighbors": {
          "Hallway": {"distance": 5, "direction": "Exit through door 5m"}
        }
      }
    }
  };

  // State
  String? _currentRoom;
  Timer? _scanTimer;
  bool _isNavigating = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  final StreamController<Map<String, dynamic>> _navigationStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  String? get currentRoom => _currentRoom;
  bool get isNavigating => _isNavigating;
  List<String> get availableRooms => _mapData['rooms'].keys.toList().cast<String>();

  // Live navigation state
  List<String> _currentPath = [];
  int _currentStepIndex = 0;
  String? _targetDestination;

  void startScanning() {
    print("BeaconNavigationService: Starting real-time BLE scanning...");

    _scanTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 2));
      } catch (e) {
        print("Scan error: $e");
      }
    });

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      ScanResult? strongest;
      int beaconCount = 0;

      for (var r in results) {
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName;

        if (name == "Room1-Beacon" || name == "Hallway-Beacon") {
          beaconCount++;
          if (r.rssi > -95 && (strongest == null || r.rssi > strongest.rssi)) {
            strongest = r;
          }
        }
      }

      if (strongest != null) {
        final name = strongest.device.platformName.isNotEmpty
            ? strongest.device.platformName
            : strongest.advertisementData.advName;

        // Distance estimation
        double distance = pow(10, (-69 - strongest.rssi) / 20.0).toDouble();

        ConsoleService().log(
            "[BLE] Nearest: $name | RSSI: ${strongest.rssi} | Dist: ${distance.toStringAsFixed(1)}m | Beacons seen: $beaconCount");

        // Determine room
        String? detectedRoom;
        final rooms = _mapData['rooms'] as Map<String, dynamic>;
        for (var entry in rooms.entries) {
          if ((entry.value['beacons'] as List).contains(name)) {
            detectedRoom = entry.key;
            break;
          }
        }

        // Hallway-Beacon disambiguation (simple but stable)
        if (name == "Hallway-Beacon") {
          detectedRoom = (_currentRoom == "Room1") ? "Hallway" : "Entrance";
        }

        // Update room only if strong signal and different
        if (detectedRoom != null &&
            _currentRoom != detectedRoom &&
            strongest.rssi > -85) {
          _currentRoom = detectedRoom;
          ConsoleService().log("[BLE] >>> ENTERED ROOM: $_currentRoom");

          if (_isNavigating) _evaluateNavigationStep();
        }
      }
    });
  }

  void stopScanning() {
    _scanTimer?.cancel();
    _scanSubscription?.cancel();
  }

  List<String> _findShortestPath(String start, String target) {
    if (start == target) return [start];
    final rooms = _mapData['rooms'] as Map<String, dynamic>;
    Queue<List<String>> queue = Queue();
    Set<String> visited = {};

    queue.add([start]);
    visited.add(start);

    while (queue.isNotEmpty) {
      List<String> path = queue.removeFirst();
      String current = path.last;
      if (current == target) return path;

      final neighbors = (rooms[current]['neighbors'] as Map<String, dynamic>).keys;
      for (String n in neighbors) {
        if (!visited.contains(n)) {
          visited.add(n);
          queue.add(List.from(path)..add(n));
        }
      }
    }
    return [];
  }

  void _evaluateNavigationStep() {
    if (!_isNavigating || _currentPath.isEmpty) return;

    if (_currentRoom == _targetDestination) {
      _navigationStreamController.add({
        "action": "ARRIVED",
        "description": "You have reached $_targetDestination.",
        "direction": "stop"
      });
      _isNavigating = false;
      return;
    }

    // Advance step only when we enter the expected next room
    if (_currentStepIndex + 1 < _currentPath.length &&
        _currentRoom == _currentPath[_currentStepIndex + 1]) {
      _currentStepIndex++;
      _issueInstructionsForCurrentStep();
    } 
    // Off-path → recalculate
    else if (!_currentPath.contains(_currentRoom!)) {
      _navigationStreamController.add({
        "action": "RECALCULATING",
        "description": "Off path. Recalculating...",
        "direction": "stop"
      });
      _currentPath = _findShortestPath(_currentRoom!, _targetDestination!);
      _currentStepIndex = 0;
      if (_currentPath.isNotEmpty) _issueInstructionsForCurrentStep();
    }
  }

  void _issueInstructionsForCurrentStep() {
    if (_currentStepIndex >= _currentPath.length - 1) return;

    String current = _currentPath[_currentStepIndex];
    String next = _currentPath[_currentStepIndex + 1];

    final rooms = _mapData['rooms'] as Map<String, dynamic>;
    var neighborData = (rooms[current]['neighbors'] as Map<String, dynamic>)[next];

    _navigationStreamController.add({
      "action": "PROCEED",
      "description": neighborData['direction'],
      "direction": neighborData['direction'].toLowerCase().contains("turn")
          ? "left"
          : "up"
    });

    // Feature check
    var features = rooms[current]['features'] as Map<String, dynamic>?;
    if (features != null) {
      for (var f in features.keys) {
        _navigationStreamController.add({
          "action": "FEATURE",
          "description": f == 'door' ? "Door ahead" : "Turn now",
          "direction": "up"
        });
      }
    }
  }

  Stream<Map<String, dynamic>> startNavigation(String destination) {
    _isNavigating = true;
    _targetDestination = null;

    String destLower = destination.toLowerCase();
    final rooms = _mapData['rooms'] as Map<String, dynamic>;
    for (String node in rooms.keys) {
      if (destLower.contains(node.toLowerCase()) ||
          (node.toLowerCase() == "room1" && destLower.contains("room 1"))) {
        _targetDestination = node;
        break;
      }
    }

    if (_targetDestination == null || _currentRoom == null) {
      _navigationStreamController.add({
        "action": "ERROR",
        "description": "Cannot start navigation yet. Wait for room detection.",
        "direction": "stop"
      });
      _isNavigating = false;
      return _navigationStreamController.stream;
    }

    _currentPath = _findShortestPath(_currentRoom!, _targetDestination!);
    _currentStepIndex = 0;

    if (_currentPath.isNotEmpty) {
      _issueInstructionsForCurrentStep();
    }

    return _navigationStreamController.stream;
  }

  void stopNavigation() {
    _isNavigating = false;
    _currentPath.clear();
  }
}