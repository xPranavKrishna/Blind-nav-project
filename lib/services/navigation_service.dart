// lib/services/navigation_service.dart

import 'dart:async';
import 'package:vibration/vibration.dart';
import 'tts_service.dart';
import '../models/beacon_model.dart';

class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  final TtsService _tts = TtsService();

  String? _currentLocation;
  String? _destination;
  bool _isNavigating = false;
  Timer? _navigationTimer;
  int _simulationStep = 0;

  // Simulated navigation route
  final List<Map<String, String>> _simulatedRoute = [
    {
      'location': 'Main Entrance',
      'instruction': 'Starting from Main Entrance. Walk straight ahead.',
    },
    {
      'location': 'Computer Lab',
      'instruction': 'Approaching Computer Lab. Turn right and continue.',
    },
    {
      'location': 'Library',
      'instruction': 'You are near the Library. Keep walking straight.',
    },
    {
      'location': 'Staff Room',
      'instruction': 'Destination reached. You have arrived at Staff Room.',
    },
  ];

  void startNavigation(String destination) {
    _destination = destination;
    _isNavigating = true;
    _simulationStep = 0;

    _tts.speak("Starting navigation to $destination");

    // Start simulated navigation
    _startSimulatedNavigation();
  }

  void _startSimulatedNavigation() {
    _navigationTimer?.cancel();

    _navigationTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (!_isNavigating || _simulationStep >= _simulatedRoute.length) {
        timer.cancel();
        _isNavigating = false;
        return;
      }

      var step = _simulatedRoute[_simulationStep];
      _currentLocation = step['location'];

      // Speak instruction
      _tts.speak(step['instruction']!);

      // Vibrate when reaching a point
      _vibrateOnArrival();

      _simulationStep++;

      // Check if destination reached
      if (_simulationStep >= _simulatedRoute.length) {
        _tts.speakDestinationReached(_destination ?? 'your destination');
        _vibrateDestinationReached();
        _isNavigating = false;
        timer.cancel();
      }
    });

    // Give first instruction immediately
    if (_simulatedRoute.isNotEmpty) {
      var step = _simulatedRoute[0];
      _currentLocation = step['location'];
      _tts.speak(step['instruction']!);
      _simulationStep++;
    }
  }

  void navigateWithBeacon(BeaconModel beacon) {
    _currentLocation = beacon.location;
    _tts.speakLocation(beacon.location);
    _vibrateOnArrival();

    // Provide navigation instruction based on proximity
    if (beacon.proximityLevel == "Immediate") {
      _tts.speak("You have reached ${beacon.location}");
    } else if (beacon.proximityLevel == "Near") {
      _tts.speak("${beacon.location} is nearby. Keep moving forward.");
    } else {
      _tts.speak("Heading towards ${beacon.location}");
    }
  }

  void announceObstacle() {
    _tts.speakObstacleWarning();
    _vibrateObstacle();
  }

  Future<void> _vibrateOnArrival() async {
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(duration: 200);
    }
  }

  Future<void> _vibrateDestinationReached() async {
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      // Three short vibrations
      for (int i = 0; i < 3; i++) {
        Vibration.vibrate(duration: 300);
        await Future.delayed(Duration(milliseconds: 200));
      }
    }
  }

  Future<void> _vibrateObstacle() async {
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      // Long continuous vibration for obstacle
      Vibration.vibrate(duration: 1000);
    }
  }

  void stopNavigation() {
    _isNavigating = false;
    _navigationTimer?.cancel();
    _tts.speak("Navigation stopped");
  }

  String? get currentLocation => _currentLocation;
  String? get destination => _destination;
  bool get isNavigating => _isNavigating;

  void dispose() {
    _navigationTimer?.cancel();
  }
}
