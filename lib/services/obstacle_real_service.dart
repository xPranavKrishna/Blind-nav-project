// This file is deprecated as we have moved to direct BLE communication.
// Keeping it for reference but commented out to prevent compilation errors.

/*
import 'dart:async';
import 'dart:io';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';

import '../services/console_service.dart';

class ObstacleRealService {
  final StreamController<bool> _obstacleController = StreamController<bool>.broadcast();
  Stream<bool> get obstacleStream => _obstacleController.stream;
  
  DatabaseReference? _dbRef;
  StreamSubscription? _firebaseSubscription;

  Future<void> _initService() async {
    FirebaseApp app;
    try {
      app = Firebase.app('obstacleApp');
      ConsoleService().log("Using existing 'obstacleApp'");
    } catch (e) {
      ConsoleService().log("Initializing new 'obstacleApp'");
      app = await Firebase.initializeApp(
        name: 'obstacleApp',
        options: const FirebaseOptions(
          apiKey: "AIzaSyCwfUETc5T001Wrl0XQfsHrYLwWarIKtzw",
          appId: "1:435173981948:android:f10904f053671c8115a179",
          messagingSenderId: "435173981948",
          projectId: "navi-ai-indoor-navigation",
          storageBucket: "navi-ai-indoor-navigation.firebasestorage.app",
          databaseURL: "https://navi-ai-indoor-navigation-default-rtdb.asia-southeast1.firebasedatabase.app",
        ),
      );
    }
    
    _dbRef = FirebaseDatabase.instanceFor(app: app, databaseURL: "https://navi-ai-indoor-navigation-default-rtdb.asia-southeast1.firebasedatabase.app").ref("obstacle");
    
    // Enable Logging & Persistence for this app instance
    FirebaseDatabase.instance.setLoggingEnabled(true);
    FirebaseDatabase.instanceFor(app: app).setPersistenceEnabled(true);
    FirebaseDatabase.instanceFor(app: app).goOnline();
  }

  void startListening() async {
    ConsoleService().log("Starting Obstacle Service Listening...");
    
    // 1. Check Internet & DNS for Firebase Host
    try {
      final host = Uri.parse("https://navi-ai-indoor-navigation-default-rtdb.asia-southeast1.firebasedatabase.app/").host;
      ConsoleService().log("Looking up host: $host");
      final result = await InternetAddress.lookup(host);
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        ConsoleService().log("DNS Lookup Success: ${result[0].address}");
      } else {
        ConsoleService().log("DNS Lookup FAILED: No IP found");
      }
    } catch (e) {
      ConsoleService().log("DNS Lookup ERROR: $e");
    }

    // 2. Initialize Service (Named App)
    try {
      await _initService();
    } catch (e) {
      ConsoleService().log("Service Init FAILED: $e");
      return;
    }

    // 3. Connection Test with Timeout
    ConsoleService().log("Testing Firebase Connection...");
    if (_dbRef != null) {
      _dbRef!.once().timeout(const Duration(seconds: 5)).then((event) {
        ConsoleService().log("Connection Test Success: Data exists? ${event.snapshot.exists}");
        if (event.snapshot.exists) {
          ConsoleService().log("Initial Data: ${event.snapshot.value}");
        }
      }).catchError((error) {
        ConsoleService().log("Connection Test FAILED/TIMED OUT: $error");
      });

      _firebaseSubscription?.cancel();
      _firebaseSubscription = _dbRef!.onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        ConsoleService().log("Firebase Data Received: $data"); // Debug print
        if (data != null) {
          final bool detected = data['detected'] == true;
          
          // Handle distance as int, double, or string
          num distance = 0;
          if (data['distance'] is num) {
            distance = data['distance'];
          } else if (data['distance'] is String) {
            distance = num.tryParse(data['distance']) ?? 0;
          }
          
          ConsoleService().log("Detected: $detected, Distance: $distance"); // Debug print

          // Threshold is 60cm as per requirement
          if (detected && distance < 60) {
            ConsoleService().log("Obstacle Condition MET");
            _obstacleController.add(true);
          } else {
            ConsoleService().log("Obstacle Condition NOT MET");
            _obstacleController.add(false);
          }
        } else {
          ConsoleService().log("Firebase Data is NULL");
        }
      }, onError: (error) {
        ConsoleService().log("Firebase Listen Error: $error");
      });
    }
  }

  void stopListening() {
    _firebaseSubscription?.cancel();
  }

  void dispose() {
    _obstacleController.close();
    stopListening();
  }
}
*/
