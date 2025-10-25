// lib/services/tts_service.dart

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _isInitialized = true;
  }

  Future<void> speak(String text) async {
    if (!_isInitialized) await initialize();
    await _flutterTts.speak(text);
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }

  // Speak navigation instructions
  Future<void> speakNavigation(String instruction) async {
    await speak(instruction);
  }

  // Speak location updates
  Future<void> speakLocation(String location) async {
    await speak("You are near $location");
  }

  // Speak destination reached
  Future<void> speakDestinationReached(String destination) async {
    await speak("Destination reached. You have arrived at $destination");
  }

  // Speak obstacle warning
  Future<void> speakObstacleWarning() async {
    await speak("Warning! Obstacle detected ahead. Please stop.");
  }

  // Speak emergency alert
  Future<void> speakEmergencyAlert() async {
    await speak("Emergency alert sent. Help is on the way.");
  }

  // Speak Bluetooth status
  Future<void> speakBluetoothStatus(String status) async {
    await speak(status);
  }

  void dispose() {
    _flutterTts.stop();
  }
}
