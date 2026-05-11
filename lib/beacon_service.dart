import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// sensors_plus ^7.0.0
// accelerometerEvents / gyroscopeEvents are DEPRECATED since v4.
// Correct modern API: accelerometerEventStream() / gyroscopeEventStream()
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vazhikaatti/services/console_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RSSI TRACKER  –  rolling 5-second window average
// ─────────────────────────────────────────────────────────────────────────────
class RssiTracker {
  final List<double> _values = [];
  final List<DateTime> _timestamps = [];

  void add(double rssi) {
    _values.add(rssi);
    _timestamps.add(DateTime.now());
    _cleanOld();
  }

  void _cleanOld() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 5));
    while (_timestamps.isNotEmpty && _timestamps.first.isBefore(cutoff)) {
      _timestamps.removeAt(0);
      _values.removeAt(0);
    }
  }

  double? get average {
    _cleanOld();
    if (_values.isEmpty) return null;
    return _values.reduce((a, b) => a + b) / _values.length;
  }

  bool get hasRecentReading => _values.isNotEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// BEACON NAVIGATION SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class BeaconNavigationService {
  // ── MAP DATA ─────────────────────────────────────────────────────────────
  // Floor plan: total 200cm wide × 1600cm tall.  All values in METRES.
  // Origin (0,0) = Entrance (bottom-right of floor plan).
  // Y increases upward (into building).  X is negative = left (into rooms).
  //
  // Rooms are 360×500 cm = 3.6m × 5.0m, on the LEFT side of the hallway.
  // Hallway runs along the RIGHT side (x ≈ 0).
  //
  // Explicit generic types prevent Dart inferring List<num> instead of List<double>.
  final Map<String, dynamic> _mapData = <String, dynamic>{
    "nodes": <String, List<double>>{
      "Entrance": [0.0,  0.0],   // bottom-right, user enters here
      "Door2":    [0.0,  2.5],   // hallway point level with Room2 door
      "Room2":    [-1.8, 2.5],   // centre of bottom room (360×500 cm)
      "Hallway":  [0.0,  8.0],   // mid-point of corridor
      "Door1":    [0.0,  13.5],  // hallway point level with Room1 door
      "Room1":    [-1.8, 13.5],  // centre of top room (360×500 cm)
    },
    "edges": <List<String>>[
      ["Entrance", "Door2"],
      ["Door2",    "Room2"],
      ["Door2",    "Hallway"],
      ["Hallway",  "Door1"],
      ["Door1",    "Room1"],
    ],
    // Beacon device name → absolute coordinate
    "beacons": <String, List<double>>{
      "Room1-Beacon":   [-1.8, 13.5],  // inside Room1
      "Hallway-Beacon": [0.0,  8.0],   // middle of hallway
      // "Room2-Beacon": [-1.8, 2.5],  // add when 3rd ESP32 is available
    },
    // Proximity announcements – fired when user comes within 1.5 m
    "features": <String, List<double>>{
      "Room 2 door ahead":    [0.0,  2.5],
      "Turn left for Room 2": [-0.5, 2.5],
      "Room 1 door ahead":    [0.0,  13.5],
      "Turn left for Room 1": [-0.5, 13.5],
    },
  };

  // ── CONSTANTS ─────────────────────────────────────────────────────────────

  // *** MUST CALIBRATE ***
  // Stand exactly 1 m from each ESP32, collect ~20 RSSI readings,
  // average them, and replace -65.0 with your measured value.
  static const double _txPowerAt1m = -65.0;

  // Log-distance path-loss exponent (2.0=free space, 2.5–3.5=indoor)
  static const double _pathLossN = 2.7;

  // RSSI above which beacon is "strong enough" to correct PDR (dBm)
  static const double _bleCorrectThreshold = -68.0;

  // Off-corridor threshold before route recalculates (metres)
  static const double _offPathThreshold = 3.0;

  // Arrival radius for waypoints (metres)
  static const double _waypointRadius = 1.5;

  // Step detection thresholds on raw accelerometer magnitude (m/s²)
  // Raw accelerometer includes gravity (~9.8), so peaks are above that.
  static const double _stepPeakThreshold   = 12.0;
  static const double _stepValleyThreshold =  9.5;

  // Average step length (metres) – tune per user
  static const double _stepLength = 0.65;

  // BLE correction EMA maximum alpha
  static const double _bleEmaAlpha = 0.35;

  // Gyroscope deadzone in rad/s (filters sensor noise)
  static const double _gyroDeadzone = 0.02;

  // Sensor sampling interval – normalInterval is ~200 ms, good balance
  // of responsiveness vs battery.  Change to fastestInterval for higher accuracy.
  static const Duration _sensorInterval = SensorInterval.normalInterval;

  // ── STATE ─────────────────────────────────────────────────────────────────

  double? _userX;
  double? _userY;

  // Heading in radians. 0=east(+X), π/2=north(+Y=into building)
  double _userHeading = pi / 2;

  // BLE
  Timer? _scanTimer;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final Map<String, RssiTracker> _beaconHistory = {};
  int  _lastBeaconCount = 0;
  bool _isNavigating    = false;

  // PDR – phone sensors (sensors_plus ^7.0.0 modern stream API)
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>?     _gyroSub;
  bool      _stepPending  = false;
  DateTime? _lastGyroTime;

  // Navigation
  List<String> _currentPath      = [];
  int          _currentStepIndex = 0;
  String?      _targetDestination;
  String       _lastActionPhrase = "";
  int          _recalcCooldown   = 0;
  final Set<String> _announcedFeatures = {};

  // Broadcast stream – multiple widgets can listen simultaneously
  final StreamController<Map<String, dynamic>> _navStream =
      StreamController<Map<String, dynamic>>.broadcast();

  // ── PUBLIC GETTERS ────────────────────────────────────────────────────────

  Stream<Map<String, dynamic>> get navigationStream => _navStream.stream;
  bool get isNavigating => _isNavigating;

  /// Nearest node name to user's current position – used by home_page.dart
  /// as "currentRoom" display.
  String? get currentRoom {
    if (_userX == null || _userY == null) return null;
    return _nearestNode();
  }

  List<String> get availableRooms =>
      ["Room1", "Room2", "Hallway", "Entrance"];

  // ── PUBLIC API ────────────────────────────────────────────────────────────

  /// Call once at app start. Begins BLE scanning + phone sensor tracking.
  void startScanning() {
    ConsoleService().log("[NAV] Starting BLE + PDR sensor tracking…");
    _startBleScanning();
    _startSensorTracking();
  }

  /// Call on dispose / background. Cancels all subscriptions.
  void stopScanning() {
    _scanTimer?.cancel();
    _scanSubscription?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    ConsoleService().log("[NAV] Scanning stopped.");
  }

  /// Begin navigation to [destination]. Returns the nav event stream.
  Stream<Map<String, dynamic>> startNavigation(String destination) {
    _isNavigating      = true;
    _targetDestination = null;
    _lastActionPhrase  = "";
    _announcedFeatures.clear();

    final nodes     = _mapData['nodes'] as Map<String, List<double>>;
    final destLower = destination.toLowerCase();

    for (final node in nodes.keys) {
      if (destLower.contains(node.toLowerCase()) ||
          (node.toLowerCase() == "room1" && destLower.contains("room 1")) ||
          (node.toLowerCase() == "room2" && destLower.contains("room 2"))) {
        _targetDestination = node;
        break;
      }
    }

    if (_targetDestination == null) {
      _navStream.add({
        "action":      "ERROR",
        "description": "Destination not found.",
        "direction":   "stop",
      });
      _isNavigating = false;
      return _navStream.stream;
    }

    final startNode   = _nearestNode();
    _currentPath      = _bfsPath(startNode, _targetDestination!);
    _currentStepIndex = 0;
    ConsoleService().log("[NAV] Route: ${_currentPath.join(" → ")}");

    if (_userX != null && _userY != null) {
      _evaluateNavigationStep();
    } else {
      _navStream.add({
        "action":      "WAITING",
        "description": "Locating you… please walk a few steps.",
        "direction":   "stop",
      });
    }

    return _navStream.stream;
  }

  /// Stop turn-by-turn guidance without stopping BLE/sensor scanning.
  void stopNavigation() {
    _isNavigating = false;
    _currentPath.clear();
    _announcedFeatures.clear();
    _lastActionPhrase = "";
  }

  // ── BLE ───────────────────────────────────────────────────────────────────

  void _startBleScanning() {
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 2));
      } catch (e) {
        ConsoleService().log("[BLE] Scan error: $e");
      }
    });

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      final beacons = _mapData['beacons'] as Map<String, List<double>>;
      bool updated  = false;

      for (final r in results) {
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName;

        if (beacons.containsKey(name)) {
          _beaconHistory.putIfAbsent(name, () => RssiTracker());
          _beaconHistory[name]!.add(r.rssi.toDouble());
          updated = true;
        }
      }

      if (updated) _onBleUpdate();
    });

    // Fallback: keep evaluating every second even if scan results go quiet
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (_scanTimer == null || !_scanTimer!.isActive) {
        t.cancel();
        return;
      }
      if (_beaconHistory.isNotEmpty) _onBleUpdate();
    });
  }

  void _onBleUpdate() {
    _lastBeaconCount = 0;
    final beacons = _mapData['beacons'] as Map<String, List<double>>;

    // Weighted centroid from BLE
    double sumWX = 0, sumWY = 0, sumW = 0;

    for (final name in beacons.keys) {
      final avg = _beaconHistory[name]?.average;
      if (avg == null) continue;
      _lastBeaconCount++;

      // Log-distance path-loss: d = 10 ^ ((TxPower − RSSI) / (10 × n))
      final distance =
          pow(10, (_txPowerAt1m - avg) / (10 * _pathLossN)).toDouble();
      final weight = 1.0 / (distance + 0.1);

      final coords = beacons[name]!;
      sumWX += coords[0] * weight;
      sumWY += coords[1] * weight;
      sumW  += weight;
    }

    if (sumW == 0) return;

    if (_userX == null || _userY == null) {
      // First fix: initialise from BLE
      _userX = sumWX / sumW;
      _userY = sumWY / sumW;
      ConsoleService().log(
          "[BLE] Initial fix: (${_userX!.toStringAsFixed(2)}, "
          "${_userY!.toStringAsFixed(2)})");
    } else {
      _applyBleCorrection();
    }

    if (_isNavigating) _evaluateNavigationStep();
  }

  /// Softly pull PDR position toward the nearest strong beacon.
  void _applyBleCorrection() {
    if (_userX == null || _userY == null) return;
    final beacons = _mapData['beacons'] as Map<String, List<double>>;

    String? bestName;
    double  bestRssi = _bleCorrectThreshold;

    for (final name in beacons.keys) {
      final avg = _beaconHistory[name]?.average ?? -999.0;
      if (avg > bestRssi) {
        bestRssi = avg;
        bestName = name;
      }
    }

    if (bestName == null) return;

    final coords   = beacons[bestName]!;
    final strength = ((bestRssi - _bleCorrectThreshold) / 10.0).clamp(0.0, 1.0);
    final alpha    = (_bleEmaAlpha * strength).clamp(0.05, 0.5);

    _userX = _userX! * (1 - alpha) + coords[0] * alpha;
    _userY = _userY! * (1 - alpha) + coords[1] * alpha;

    ConsoleService().log(
        "[BLE] Correction ← $bestName (${bestRssi.toStringAsFixed(0)} dBm, "
        "α=${alpha.toStringAsFixed(2)}) → "
        "(${_userX!.toStringAsFixed(2)}, ${_userY!.toStringAsFixed(2)})");

    _snapToNearestPath();
  }

  // ── PDR – SENSOR TRACKING ─────────────────────────────────────────────────

  void _startSensorTracking() {
    // ── Gyroscope → heading ──────────────────────────────────────────────
    // UPDATED: gyroscopeEventStream() replaces deprecated gyroscopeEvents
    // samplingPeriod controls how often events fire (normalInterval = ~200ms)
    _gyroSub = gyroscopeEventStream(samplingPeriod: _sensorInterval).listen(
      (GyroscopeEvent e) {
        final now = DateTime.now();
        if (_lastGyroTime != null) {
          final dt =
              now.difference(_lastGyroTime!).inMicroseconds / 1e6; // seconds
          // e.z = angular velocity around vertical axis (yaw), rad/s
          if (e.z.abs() > _gyroDeadzone) {
            _userHeading += e.z * dt;
            // Normalise to (−π, π]
            while (_userHeading >  pi) _userHeading -= 2 * pi;
            while (_userHeading < -pi) _userHeading += 2 * pi;
          }
        }
        _lastGyroTime = now;
      },
      onError: (error) {
        // Some devices may not have gyroscope
        ConsoleService().log("[PDR] Gyroscope not available: $error");
      },
      cancelOnError: false,
    );

    // ── Accelerometer → step detection ──────────────────────────────────
    // UPDATED: accelerometerEventStream() replaces deprecated accelerometerEvents
    // Using RAW accelerometer (includes gravity ~9.8 m/s²) for step detection.
    // Peak-valley detector: rising edge > 12.0, falling edge < 9.5 = 1 step.
    _accelSub = accelerometerEventStream(samplingPeriod: _sensorInterval).listen(
      (AccelerometerEvent e) {
        final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

        if (mag > _stepPeakThreshold && !_stepPending) {
          _stepPending = true;       // rising edge
        }
        if (_stepPending && mag < _stepValleyThreshold) {
          _stepPending = false;
          _onStepDetected();         // falling edge = confirmed step
        }
      },
      onError: (error) {
        ConsoleService().log("[PDR] Accelerometer not available: $error");
      },
      cancelOnError: false,
    );

    ConsoleService().log("[PDR] Sensor tracking started (sensors_plus ^7.0.0).");
  }

  void _onStepDetected() {
    if (_userX == null || _userY == null) return;

    // Dead-reckoning: advance one step in current heading
    _userX = _userX! + _stepLength * cos(_userHeading);
    _userY = _userY! + _stepLength * sin(_userHeading);

    _snapToNearestPath();

    ConsoleService().log(
        "[PDR] Step → (${_userX!.toStringAsFixed(2)}, "
        "${_userY!.toStringAsFixed(2)}) "
        "| heading ${(_userHeading * 180 / pi).toStringAsFixed(1)}°");

    if (_isNavigating) _evaluateNavigationStep();
  }

  // ── MAP MATCHING ──────────────────────────────────────────────────────────

  /// Project user position onto the nearest corridor edge.
  /// Prevents drifting through walls between sensor updates.
  void _snapToNearestPath() {
    if (_userX == null || _userY == null) return;

    final nodes = _mapData['nodes'] as Map<String, List<double>>;
    final edges = _mapData['edges'] as List<List<String>>;

    double minDist  = double.infinity;
    double snappedX = _userX!;
    double snappedY = _userY!;

    for (final edge in edges) {
      final a = nodes[edge[0]]!;
      final b = nodes[edge[1]]!;

      final l2 = pow(a[0] - b[0], 2) + pow(a[1] - b[1], 2);
      if (l2 == 0) continue;

      final t = (((_userX! - a[0]) * (b[0] - a[0]) +
                  (_userY! - a[1]) * (b[1] - a[1])) /
              l2)
          .clamp(0.0, 1.0);

      final projX = a[0] + t * (b[0] - a[0]);
      final projY = a[1] + t * (b[1] - a[1]);
      final dist  = sqrt(pow(_userX! - projX, 2) + pow(_userY! - projY, 2));

      if (dist < minDist) {
        minDist  = dist;
        snappedX = projX;
        snappedY = projY;
      }
    }

    _userX = snappedX;
    _userY = snappedY;
  }

  // ── NAVIGATION LOGIC ──────────────────────────────────────────────────────

  void _evaluateNavigationStep() {
    if (!_isNavigating || _currentPath.isEmpty ||
        _userX == null || _userY == null) return;

    if (_recalcCooldown > 0) _recalcCooldown--;

    final nodes = _mapData['nodes'] as Map<String, List<double>>;

    // Arrived at final destination?
    if (_currentStepIndex >= _currentPath.length - 1) {
      final finalCoords = nodes[_currentPath.last]!;
      if (_dist(_userX!, _userY!, finalCoords[0], finalCoords[1]) <=
          _waypointRadius) {
        _navStream.add({
          "action":      "ARRIVED",
          "description": "You have reached $_targetDestination",
          "direction":   "stop",
        });
        _isNavigating = false;
        ConsoleService().log("[NAV] Arrived at $_targetDestination");
        return;
      }
    }

    final targetIdx =
        (_currentStepIndex + 1).clamp(0, _currentPath.length - 1);
    if (targetIdx <= _currentStepIndex) return;

    final prevCoords   = nodes[_currentPath[_currentStepIndex]]!;
    final targetCoords = nodes[_currentPath[targetIdx]]!;
    final tx = targetCoords[0];
    final ty = targetCoords[1];

    final distToWaypoint = _dist(_userX!, _userY!, tx, ty);

    // Advance waypoint
    if (distToWaypoint <= _waypointRadius) {
      _currentStepIndex++;
      _lastActionPhrase = "";
      ConsoleService().log("[NAV] Passed: ${_currentPath[targetIdx]}");
      _evaluateNavigationStep();
      return;
    }

    // Off-path recalculation
    final segDist = _pointToSegmentDist(
        _userX!, _userY!, prevCoords[0], prevCoords[1], tx, ty);

    if (segDist > _offPathThreshold && _recalcCooldown == 0) {
      ConsoleService()
          .log("[NAV] Off-path ${segDist.toStringAsFixed(1)} m. Recalculating…");
      _navStream.add({
        "action":      "RECALCULATING",
        "description": "Recalculating route",
        "direction":   "stop",
      });
      _currentPath      = _bfsPath(_nearestNode(), _targetDestination!);
      _currentStepIndex = 0;
      _lastActionPhrase = "";
      _recalcCooldown   = 5;
      if (_currentPath.length > 1) _issueInstruction(distToWaypoint, tx, ty);
      return;
    }

    _checkFeatureProximity();
    _issueInstruction(distToWaypoint, tx, ty);
  }

  void _checkFeatureProximity() {
    if (_userX == null || _userY == null) return;
    final features = _mapData['features'] as Map<String, List<double>>;

    for (final entry in features.entries) {
      if (_announcedFeatures.contains(entry.key)) continue;
      final d = _dist(_userX!, _userY!, entry.value[0], entry.value[1]);
      if (d <= _waypointRadius) {
        _announcedFeatures.add(entry.key);
        _navStream.add({
          "action":      "FEATURE",
          "description": entry.key,
          "direction":   "up",
        });
        ConsoleService()
            .log("[NAV] Feature: ${entry.key} (${d.toStringAsFixed(1)} m)");
      }
    }
  }

  void _issueInstruction(
      double distToWaypoint, double targetX, double targetY) {
    if (_userX == null || _userY == null) return;

    final targetHeading = atan2(targetY - _userY!, targetX - _userX!);
    double angleDiff    = targetHeading - _userHeading;
    while (angleDiff >  pi) angleDiff -= 2 * pi;
    while (angleDiff < -pi) angleDiff += 2 * pi;

    final distStr = distToWaypoint.toStringAsFixed(1);

    String action, direction, phrase;
    if (angleDiff > 0.785) {
      action    = "TURN LEFT";
      direction = "left";
      phrase    = "Turn left in $distStr metres";
    } else if (angleDiff < -0.785) {
      action    = "TURN RIGHT";
      direction = "right";
      phrase    = "Turn right in $distStr metres";
    } else {
      action    = "GO STRAIGHT";
      direction = "up";
      phrase    = "Walk straight $distStr metres";
    }

    if (phrase != _lastActionPhrase) {
      _lastActionPhrase = phrase;
      ConsoleService().log(
          "[NAV] Pos: (${_userX!.toStringAsFixed(1)}, "
          "${_userY!.toStringAsFixed(1)}) | "
          "Dist: ${distStr}m | $phrase | Beacons: $_lastBeaconCount");
      _navStream.add({
        "action":      action,
        "description": phrase,
        "direction":   direction,
      });
    }
  }

  // ── GRAPH ─────────────────────────────────────────────────────────────────

  List<String> _bfsPath(String start, String target) {
    if (start == target) return [start];

    final adj = <String, List<String>>{};
    for (final edge in _mapData['edges'] as List<List<String>>) {
      adj.putIfAbsent(edge[0], () => []).add(edge[1]);
      adj.putIfAbsent(edge[1], () => []).add(edge[0]);
    }

    final queue   = Queue<List<String>>();
    final visited = <String>{start};
    queue.add([start]);

    while (queue.isNotEmpty) {
      final path    = queue.removeFirst();
      final current = path.last;
      if (current == target) return path;
      for (final n in adj[current] ?? []) {
        if (!visited.contains(n)) {
          visited.add(n);
          queue.add(List.from(path)..add(n));
        }
      }
    }
    return [start];
  }

  String _nearestNode() {
    final nodes = _mapData['nodes'] as Map<String, List<double>>;
    String nearest = nodes.keys.first;
    double minD    = double.infinity;

    for (final entry in nodes.entries) {
      final d = (_userX == null)
          ? double.infinity
          : _dist(_userX!, _userY!, entry.value[0], entry.value[1]);
      if (d < minD) {
        minD    = d;
        nearest = entry.key;
      }
    }
    return nearest;
  }

  // ── MATH ─────────────────────────────────────────────────────────────────

  double _dist(double x1, double y1, double x2, double y2) =>
      sqrt(pow(x1 - x2, 2) + pow(y1 - y2, 2));

  double _pointToSegmentDist(
    double px, double py,
    double ax, double ay,
    double bx, double by,
  ) {
    final l2 = pow(ax - bx, 2) + pow(ay - by, 2);
    if (l2 == 0) return _dist(px, py, ax, ay);
    final t = (((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / l2)
        .clamp(0.0, 1.0);
    return _dist(px, py, ax + t * (bx - ax), ay + t * (by - ay));
  }
}