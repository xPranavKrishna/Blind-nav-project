import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(NaviAiApp());
}

class NaviAiApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NAVI-AI Indoor Navigation',
      theme: ThemeData(
        primaryColor: Color(0xFF5B8DBE),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late stt.SpeechToText _speech;
  late FlutterTts _flutterTts;
  bool _isListening = false;
  String _recognizedText = '';
  String _lastCommand = '';
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _flutterTts = FlutterTts();
    _initializeSpeech();
    _initializeTts();

    // Initialize pulse animation for microphone
    _pulseController = AnimationController(
      duration: Duration(seconds: 1),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

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
    _flutterTts.stop();
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

  void _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  void _speakWelcomeMessage() async {
    await _flutterTts.speak(
      "Welcome to NAVI-AI. Tap anywhere on the screen to speak. "
      "You can say things like: Take me to Room 295, Where am I, or Go to Library.",
    );
  }

  void _listen() async {
    // Stop any ongoing speech when user taps to listen
    await _flutterTts.stop();

    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        // Say "Listening" when starting to listen
        await _flutterTts.speak("Listening");

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

    // Extract room number or destination
    String destination = _extractDestination(command);

    if (destination.isNotEmpty) {
      _speak("Navigating to $destination. Please wait for directions.");
      _simulateNavigation(destination);
    } else if (command.contains('where am i') ||
        command.contains('my location')) {
      _speak("You are currently in the main hallway near the entrance.");
    } else {
      _speak("Sorry, I didn't understand your command. Please try again.");
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
    if (numberMatch != null && command.contains('to')) {
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
    ];

    for (String place in commonPlaces) {
      if (command.contains(place)) {
        return place.substring(0, 1).toUpperCase() +
            place.substring(1).toLowerCase();
      }
    }

    return '';
  }

  void _speak(String text) async {
    if (mounted) {
      await _flutterTts.speak(text);
    }
  }

  void _simulateNavigation(String destination) {
    // Simulate navigation instructions
    Future.delayed(Duration(seconds: 2), () {
      if (mounted) {
        _speak("Walk straight for 10 meters, then turn right.");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [_buildHomePage(), _buildMapPage()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
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
        child: Column(
          children: [
            // Settings icon
            Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(Icons.settings, color: Colors.grey[600]),
                    onPressed: () {
                      // Settings functionality can be added here
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
                      // Decorative circles (matching your design)
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
                          Positioned(
                            bottom: -100,
                            left: -50,
                            child: Container(
                              width: 180,
                              height: 180,
                              decoration: BoxDecoration(
                                color: Color(0xFFB8CCE0).withOpacity(0.7),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: -80,
                            right: -70,
                            child: Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                color: Color(0xFF5B8DBE).withOpacity(0.5),
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
                                  : 'Tap anywhere to speak',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Say things like:\n"Take me to Room 295"\n"Where am I?"\n"Go to Library"',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
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
      ),
    );
  }

  Widget _buildMapPage() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFB8CCE0), Color(0xFFE8D5C7)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Campus Map',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
            ),
            Expanded(
              child: Container(
                margin: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Placeholder for map
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.map_outlined,
                            size: 80,
                            color: Colors.grey[400],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Map will be displayed here',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                        ],
                      ),
                    ),

                    // User position indicator (example)
                    Positioned(
                      top: 100,
                      left: 100,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
