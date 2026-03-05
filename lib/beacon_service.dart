import 'dart:async';
import 'dart:collection';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BeaconNavigationService {
  // Hardcoded room map from user's JSON requirements
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

  // Stream controller to notify the UI of navigation steps
  final StreamController<Map<String, dynamic>> _navigationStreamController = StreamController<Map<String, dynamic>>.broadcast();

  String? get currentRoom => _currentRoom;
  bool get isNavigating => _isNavigating;
  List<String> get availableRooms => _mapData['rooms'].keys.toList().cast<String>();

  void startScanning() {
    print("BeaconNavigationService: Starting background BLE scanning...");
    // Every 5 seconds, scan for exactly 2 seconds
    _scanTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      // Do not interrupt existing connections, just run a background scan
      try {
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 2),
          // We don't filter by UUID here because we are looking for generic beacons
          // with specific names. Filtering by withNames is possible but keeping it broad
          // ensures we catch them if advertising formats differ.
        );
      } catch (e) {
        print("Beacon Scan error: $e");
      }
    });

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      ScanResult? strongestBeacon;
      for (var result in results) {
        final name = result.device.platformName.isNotEmpty 
            ? result.device.platformName 
            : result.advertisementData.advName;
            
        if (name == "Room1-Beacon" || name == "Hallway-Beacon") {
          if (result.rssi > -70) {
            if (strongestBeacon == null || result.rssi > strongestBeacon.rssi) {
              strongestBeacon = result;
            }
          }
        }
      }

      if (strongestBeacon != null) {
        final strongName = strongestBeacon.device.platformName.isNotEmpty 
            ? strongestBeacon.device.platformName 
            : strongestBeacon.advertisementData.advName;
            
        // Map beacon name to room roughly (Hallway-Beacon spans Entrance/Hallway, Room1-Beacon spans Room1)
        // In reality, this logic needs to be sophisticated, but we'll use a direct mapping based on map data.
        String? detectedRoom;
        
        // Find which room this beacon belongs to in the map
        final rooms = _mapData['rooms'] as Map<String, dynamic>;
        for (var entry in rooms.entries) {
           final roomData = entry.value as Map<String, dynamic>;
           final beacons = (roomData['beacons'] as List).cast<String>();
           if (beacons.contains(strongName)) {
               detectedRoom = entry.key; // Example: if it's Room1-Beacon -> Room1
               // If Hallway-Beacon, it could be Entrance or Hallway. We'll default to the first match if no current tracking.
               // For a robust system, we would refine this.
               // For now, Entrance/Hallway distinction could simply be Entrance if we haven't entered yet, else Hallway.
           }
        }
        
        // Specific disambiguation for Hallway vs Entrance since they share a beacon in the example
        if (strongName == "Hallway-Beacon") {
            // Keep current room if it's already Hallway or Entrance to prevent bouncing
            if (_currentRoom != "Hallway" && _currentRoom != "Entrance") {
                detectedRoom = "Entrance"; // Default entry point
            } else {
                detectedRoom = _currentRoom; 
            }
        }

        if (detectedRoom != null && _currentRoom != detectedRoom) {
          _currentRoom = detectedRoom;
          print("Current room detected: $_currentRoom (RSSI: ${strongestBeacon.rssi})");
        }
      }
    });
  }

  void stopScanning() {
    _scanTimer?.cancel();
    _scanSubscription?.cancel();
  }

  // Uses BFS to find the shortest path of rooms
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

      if (current == target) {
        return path;
      }

      final neighbors = (rooms[current]['neighbors'] as Map<String, dynamic>).keys;
      for (String neighbor in neighbors) {
        if (!visited.contains(neighbor)) {
          visited.add(neighbor);
          queue.add(List.from(path)..add(neighbor));
        }
      }
    }
    return []; // No path
  }

  Stream<Map<String, dynamic>> startNavigation(String destination) async* {
    _isNavigating = true;
    
    // Attempt to match destination string to room nodes
    String? targetNode;
    String destLower = destination.toLowerCase();
    
    final rooms = _mapData['rooms'] as Map<String, dynamic>;
    for (String node in rooms.keys) {
        if (destLower.contains(node.toLowerCase()) || 
           (node.toLowerCase() == "room1" && destLower.contains("room 1"))) {
            targetNode = node;
            break;
        }
    }

    if (targetNode == null) {
      yield {
        "action": "ERROR",
        "description": "Destination $destination not found in indoor map.",
        "direction": "stop"
      };
      _isNavigating = false;
      return;
    }

    if (_currentRoom == null) {
      // If we don't have a room yet, default to Entrance for the demo to work
      _currentRoom = "Entrance";
    }

    List<String> path = _findShortestPath(_currentRoom!, targetNode);
    if (path.isEmpty) {
        yield {
            "action": "ERROR",
            "description": "No path found from $_currentRoom to $targetNode.",
            "direction": "stop"
        };
        _isNavigating = false;
        return;
    }

    print("Calculated Path: $path");

    // Walk the path
    for (int i = 0; i < path.length - 1; i++) {
        if (!_isNavigating) break;
        
        String from = path[i];
        String to = path[i+1];
        
        var fromData = rooms[from] as Map<String, dynamic>;
        var toNodeData = fromData['neighbors'][to] as Map<String, dynamic>;
        
        String instruction = toNodeData['direction'];
        int distance = toNodeData['distance'];
        
        // Yield the main instruction
        yield {
            "action": "PROCEED",
            "description": instruction,
            "direction": instruction.toLowerCase().contains("turn") ? (instruction.toLowerCase().contains("left") ? "left" : "right") : "up"
        };
        
        // Yield feature warnings if applicable in the `from` room while moving to `to` room
        if (fromData.containsKey('features')) {
            var features = fromData['features'] as Map<String, dynamic>;
            for (var feature in features.entries) {
                String featureName = feature.key; // e.g., 'door' or 'turn'
                
                // We'll simulate walking time to the feature. For the app, we can just yield it halfway.
                // In a robust app, we'd trigger this based on location/RSSI continuous tracking.
                await Future.delayed(const Duration(seconds: 3));
                if (!_isNavigating) break;
                
                yield {
                    "action": "FEATURE",
                    "description": featureName == 'door' ? "Door ahead" : "Turn now",
                    "direction": "up" // Keep current direction arrow
                };
            }
        }
        
        // Wait for user to 'reach' next room. In demo, simulate duration based on distance (1m = 1s)
        await Future.delayed(Duration(seconds: distance)); 
        _currentRoom = to; // Simulate arriving
    }

    if (_isNavigating) {
        yield {
            "action": "ARRIVED",
            "description": "You have reached $targetNode.",
            "direction": "stop"
        };
        _isNavigating = false;
    }
  }

  void stopNavigation() {
    _isNavigating = false;
  }
}
