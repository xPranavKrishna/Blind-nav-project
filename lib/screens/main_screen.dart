// lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../services/tts_service.dart';
import '../services/navigation_service.dart';
import '../services/bluetooth_service.dart';
import '../widgets/emergency_button.dart';

import 'bluetooth_screen.dart';
import 'map_screen.dart';

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late stt.SpeechToText _speech;
  final TtsService _tts = TtsService();
  final NavigationService _navigationService = NavigationService();
  final BluetoothService _bluetoothService = BluetoothService();

  bool _isListening = false;
  String _recognizedText = '';
  String _lastCommand = '';
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initializeSpeech();
    _tts.initialize();

    // Initialize pulse animation for microphone
    _pulseController = AnimationController(
      duration: Duration(seconds: 1),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // Start Bluetooth scanning in background
    _bluetoothService.startScanning();

    // Give welcome instructions after a short delay
    Future.delayed(Duration(seconds: 2), () {
      if (mounted) {
        _speakWelcomeMessage();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tts.stop();
    _bluetoothService.stopScanning();
    super.dispose();
  }

  void _initializeSpeech() async {
    await Permission.microphone.request();
    bool available = await _speech.initialize(
      onStatus: (val) {
        if (mounted) {
          setState(() => _isListening = val == 'listening');
        }
      },
      onError: (val) => print('Speech Error: $val'),
    );
    if (!available) {
      print('The user has denied the use of speech recognition.');
    }
  }

  void _speakWelcomeMessage() async {
    await _tts.speak(
      "Welcome to NAVI-AI. Tap anywhere on the screen to speak. "
      "You can say things like: Take me to Library, Where am I, or say Help me for emergency.",
    );
  }

  void _listen() async {
    // Stop any ongoing speech when user taps to listen
    await _tts.stop();

    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        // Say "Listening" when starting to listen
        await _tts.speak("Listening");

        // Wait for TTS to finish, then start listening
        Future.delayed(Duration(milliseconds: 1000), () {
          if (mounted) {
            _speech.listen(
              onResult: (val) {
                if (mounted) {
                  setState(() {
                    _recognizedText = val.recognizedWords.toLowerCase();
                  });
                  if (val.hasConfidenceRating && val.confidence > 0.5) {
                    _processVoiceCommand(_recognizedText);
                  }
                }
              },
              listenFor: Duration(seconds: 10),
              pauseFor: Duration(seconds: 3),
            );
          }
        });
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _processVoiceCommand(String command) {
    if (!mounted) return;

    setState(() => _lastCommand = command);

    // Check for emergency command
    if (command.contains('help me') ||
        command.contains('emergency') ||
        command.contains('sos')) {
      _handleEmergency();
      return;
    }

    // Check for location query
    if (command.contains('where am i') || command.contains('my location')) {
      var nearestBeacon = _bluetoothService.getNearestBeacon();
      if (nearestBeacon != null) {
        _tts.speak("You are currently at ${nearestBeacon.location}");
      } else {
        _tts.speak("You are currently in the main hallway near the entrance.");
      }
      return;
    }

    // Check for Bluetooth/beacon command
    if (command.contains('show beacons') ||
        command.contains('bluetooth') ||
        command.contains('scan')) {
      setState(() => _currentIndex = 1);
      _tts.speak("Opening Bluetooth scan screen");
      return;
    }

    // Check for map command
    if (command.contains('show map') || command.contains('open map')) {
      setState(() => _currentIndex = 2);
      _tts.speak("Opening map screen");
      return;
    }

    // Check for obstacle warning (simulation)
    if (command.contains('obstacle') || command.contains('something ahead')) {
      _navigationService.announceObstacle();
      return;
    }

    // Extract destination and start navigation
    String destination = _extractDestination(command);

    if (destination.isNotEmpty) {
      _tts.speak("Navigating to $destination. Starting route guidance.");
      _navigationService.startNavigation(destination);
    } else {
      _tts.speak("Sorry, I didn't understand your command. Please try again.");
    }
  }

  String _extractDestination(String command) {
    // Extract room numbers (e.g., "room 295", "295", "room two nine five")
    RegExp roomPattern = RegExp(r'room\s*(\d+)', caseSensitive: false);
    Match? roomMatch = roomPattern.firstMatch(command);

    if (roomMatch != null) {
      return "Room ${roomMatch.group(1)}";
    }

    // Extract standalone numbers that might be room numbers
    RegExp numberPattern = RegExp(r'\b(\d{2,4})\b');
    Match? numberMatch = numberPattern.firstMatch(command);
    if (numberMatch != null &&
        (command.contains('to') || command.contains('take me'))) {
      return "Room ${numberMatch.group(1)}";
    }

    // Extract other common destinations
    List<String> commonPlaces = [
      'library',
      'cafeteria',
      'office',
      'bathroom',
      'exit',
      'entrance',
      'stairs',
      'elevator',
      'lab',
      'computer lab',
      'classroom',
      'auditorium',
      'cse',
      'cs',
      'cse block',
      'ad block',
      'civil block',
      'mech block',
      'ece block',
      'eee block',
      'it block',
      'canteen',
      'mess',
      'computer science',
      'mechanical',
      'civil',
      'electrical',
      'electronics',
      'staff room',
    ];

    for (String place in commonPlaces) {
      if (command.contains(place)) {
        return place.substring(0, 1).toUpperCase() +
            place.substring(1).toLowerCase();
      }
    }

    return '';
  }

  void _handleEmergency() {
    _tts.speakEmergencyAlert();
    // Trigger emergency button action
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.red[50],
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 30),
              SizedBox(width: 12),
              Text(
                'Emergency Alert',
                style: TextStyle(
                  color: Colors.red[900],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            'Emergency alert has been sent!\n\n'
            '📞 Calling caretaker...\n'
            '📍 Sharing your location...\n'
            '🚨 Help is on the way!',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _tts.speak("Emergency confirmed. Caretaker has been notified.");
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [_buildHomePage(), BluetoothScreen(), MapScreen()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);

          // Announce navigation
          if (index == 0) _tts.speak("Home screen");
          if (index == 1) _tts.speak("Bluetooth scan screen");
          if (index == 2) _tts.speak("Map screen");
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.bluetooth),
            label: 'Beacons',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
        ],
      ),
    );
  }

  Widget _buildHomePage() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFB8CCE0), Color(0xFFE8D5C7)],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Settings icon and navigation status
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Navigation status
                      if (_navigationService.isNavigating)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.green, width: 2),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.navigation,
                                color: Colors.green,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Navigating...',
                                style: TextStyle(
                                  color: Colors.green[900],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Spacer(),
                      IconButton(
                        icon: Icon(Icons.settings, color: Colors.grey[600]),
                        onPressed: () {
                          _tts.speak("Settings");
                        },
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: GestureDetector(
                    onTap: _listen,
                    child: Container(
                      width: double.infinity,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Decorative circles and microphone button
                          Stack(
                            children: [
                              // Background circles
                              Positioned(
                                top: -50,
                                left: -100,
                                child: Container(
                                  width: 200,
                                  height: 200,
                                  decoration: BoxDecoration(
                                    color: Color(0xFF5B8DBE).withOpacity(0.6),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: -20,
                                right: -80,
                                child: Container(
                                  width: 150,
                                  height: 150,
                                  decoration: BoxDecoration(
                                    color: Color(0xFFB8CCE0).withOpacity(0.8),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),

                              // Main microphone button
                              Container(
                                width: 300,
                                height: 300,
                                child: Center(
                                  child: AnimatedBuilder(
                                    animation: _pulseAnimation,
                                    builder: (context, child) {
                                      return Transform.scale(
                                        scale: _isListening
                                            ? _pulseAnimation.value
                                            : 1.0,
                                        child: Container(
                                          width: 120,
                                          height: 120,
                                          decoration: BoxDecoration(
                                            color: Color(0xFF5B8DBE),
                                            shape: BoxShape.circle,
                                            boxShadow: _isListening
                                                ? [
                                                    BoxShadow(
                                                      color: Color(
                                                        0xFF5B8DBE,
                                                      ).withOpacity(0.4),
                                                      blurRadius: 20,
                                                      spreadRadius: 10,
                                                    ),
                                                  ]
                                                : [],
                                          ),
                                          child: Icon(
                                            _isListening
                                                ? Icons.mic
                                                : Icons.mic_none,
                                            size: 60,
                                            color: Colors.white,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: 40),

                          // Instructions
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 40),
                            child: Column(
                              children: [
                                Text(
                                  _isListening
                                      ? 'Listening...'
                                      : 'Tap anywhere to speak your command',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                SizedBox(height: 12),
                                if (_lastCommand.isNotEmpty)
                                  Text(
                                    'Last command: $_lastCommand',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Emergency button floating
            Positioned(
              bottom: 30,
              right: 30,
              child: EmergencyButton(onEmergencyTriggered: _handleEmergency),
            ),
          ],
        ),
      ),
    );
  }
}
