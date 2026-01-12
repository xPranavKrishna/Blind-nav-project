import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';
import '../services/navigation_demo_service.dart';
import '../services/obstacle_real_service.dart';
import '../services/emergency_service.dart';
import '../services/console_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final SpeechService _speechService = SpeechService();
  final TtsService _ttsService = TtsService();
  final NavigationDemoService _navigationService = NavigationDemoService();
  final ObstacleRealService _obstacleService = ObstacleRealService();
  final EmergencyService _emergencyService = EmergencyService();

  String _currentAction = "Ready";
  String _currentDescription = "Say a destination";
  String _statusText = "Initializing...";
  String _directionIcon = "up"; // up, left, right, stop
  bool _isNavigating = false;
  bool _isObstacle = false;
  
  StreamSubscription? _commandSubscription;
  StreamSubscription? _navigationSubscription;
  StreamSubscription? _obstacleSubscription;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    await _requestPermissions();
    await _ttsService.init();
    bool available = await _speechService.init();
    
    if (available) {
      setState(() {
        _statusText = "Tap to Speak";
      });
    } else {
      setState(() {
        _statusText = "Microphone not available";
      });
    }

    _obstacleSubscription = _obstacleService.obstacleStream.listen((isObstacle) {
      if (isObstacle) {
        // Only alert if we weren't already in obstacle state
        if (!_isObstacle) {
          _handleObstacle();
        }
      } else {
        // Only clear if we were in obstacle state
        if (_isObstacle) {
           _isObstacle = false;
           _speak("Obstacle cleared. Resuming.");
           setState(() {});
        }
      }
    });
    
    // Start listening immediately for "Always On" detection
    _obstacleService.startListening();

    _commandSubscription = _speechService.commandStream.listen(_handleCommand);
    _speechService.listeningStream.listen((isListening) {
      if (mounted) {
        setState(() {
          _statusText = isListening ? "Listening..." : "Tap to Speak";
        });
      }
    });

    // Initial Welcome Message & Listen
    Future.delayed(Duration(seconds: 1), () async {
      await _speak(
        "Welcome to Vazhikaatti. Tap the screen and say a destination like Library or Admin Block."
      );
      // Optional: Listen once at startup if desired, or just wait for tap
      _speechService.startListening();
    });
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.microphone,
      Permission.phone,
      Permission.location, // For future use
    ].request();
  }

  // Wrapper to handle TTS and STT coordination
  Future<void> _speak(String text) async {
    _speechService.pauseListening(); // Stop listening while speaking
    await _ttsService.speak(text);
    // Do NOT auto-resume listening. User must tap.
  }

  void _handleCommand(String command) {
    print("Command received: $command");
    command = command.toLowerCase();

    if (command.contains("stop")) {
      _stopNavigation();
    } else if (command.contains("emergency")) {
      _emergencyService.makeEmergencyCall();
      _speak("Calling caretaker");
    } else if (command.contains("repeat") || command.contains("say again")) {
      _speak(_currentDescription);
    } else if (command.contains("go to") || command.contains("navigate to") || command.contains("take me to")) {
      String destination = command.replaceAll("go to", "").replaceAll("navigate to", "").replaceAll("take me to", "").trim();
      _startNavigation(destination);
    } else {
      _speak("I didn't catch that. Please tap and try again.");
    }
  }

  void _startNavigation(String destination) {
    _stopNavigation(); // Clear previous
    setState(() {
      _isNavigating = true;
      _statusText = "Navigating...";
    });
    
    _speak("Starting navigation to $destination");
    // _obstacleService.startListening(); // Already listening globally

    _navigationSubscription = _navigationService.startNavigation(destination).listen((step) {
      if (_isObstacle) return; // Pause updates if obstacle

      setState(() {
        _currentAction = step['action'];
        _currentDescription = step['description'];
        _directionIcon = step['direction'];
      });
      _speak(step['description']);
    }, onDone: () {
      setState(() {
        _isNavigating = false;
        _statusText = "Arrived";
        _directionIcon = "stop";
        _currentAction = "ARRIVED";
        _currentDescription = "You have reached $destination";
      });
      _speak("You have reached $destination");
      // _obstacleService.stopListening(); // Keep listening globally
    });
  }

  void _stopNavigation() {
    _navigationService.stopNavigation();
    _navigationSubscription?.cancel();
    // _obstacleService.stopListening(); // Keep listening globally
    setState(() {
      _isNavigating = false;
      _statusText = "Tap to Speak";
      _currentAction = "Ready";
      _currentDescription = "Tap to say a destination";
      _directionIcon = "stop";
    });
    _speak("Navigation stopped.");
  }

  void _handleObstacle() async {
    ConsoleService().log("Obstacle Detected! triggering Alert & Vibration");
    _isObstacle = true;
    setState(() {});
    _speak("Obstacle ahead. Please stop.");
    
    bool? hasVibrator = await Vibration.hasVibrator();
    ConsoleService().log("Device has vibrator? $hasVibrator");
    
    if (hasVibrator ?? false) {
      ConsoleService().log("Vibrating now...");
      Vibration.vibrate(duration: 1000); // Vibrate for 1 second
    } else {
      ConsoleService().log("Vibration NOT supported/available");
    }
  }

  @override
  void dispose() {
    _speechService.dispose();
    _obstacleService.dispose();
    _commandSubscription?.cancel();
    _navigationSubscription?.cancel();
    _obstacleSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isNavigating ? _buildNavigationUI() : _buildIdleUI(),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Image.asset('assets/images/logo.png', height: 40),
          const SizedBox(width: 12),
          const Text(
            "Vazhikaatti",
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              // Handle menu
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: "settings", child: Text("Settings")),
              const PopupMenuItem(value: "caretaker", child: Text("Add Caretaker")),
              const PopupMenuItem(value: "about", child: Text("About")),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIdleUI() {
    return InkWell(
      onTap: () {
        print("Tap detected on Idle UI");
        if (!_speechService.isListening) {
          print("Starting listening from tap...");
          _speechService.resumeListening();
        } else {
          print("Already listening");
        }
      },
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pulsing Mic Animation (Visual cue)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _speechService.isListening ? Colors.yellowAccent.withOpacity(0.2) : Colors.grey[800],
                border: Border.all(
                  color: _speechService.isListening ? Colors.yellowAccent : Colors.grey,
                  width: 4,
                ),
                boxShadow: _speechService.isListening
                    ? [BoxShadow(color: Colors.yellowAccent.withOpacity(0.4), blurRadius: 30, spreadRadius: 10)]
                    : [],
              ),
              child: Icon(
                Icons.mic,
                size: 80,
                color: _speechService.isListening ? Colors.yellowAccent : Colors.grey,
              ),
            ),
            const SizedBox(height: 50),
            Text(
              _speechService.isListening ? "Listening..." : "Tap to Speak",
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              "Try \"Library\" or \"Admin Block\"",
              style: TextStyle(color: Colors.grey[400], fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationUI() {
    return InkWell(
      onTap: () {
         // Allow tapping during navigation to issue commands like "Stop"
         if (!_speechService.isListening) {
          _speechService.startListening();
        }
      },
      child: Column(
        children: [
          // Top Instruction Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _isObstacle ? Colors.red[900] : Colors.grey[850],
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 5)),
              ],
            ),
            child: Column(
              children: [
                if (_isObstacle)
                  const Text(
                    "OBSTACLE DETECTED",
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                Text(
                  _currentAction,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.yellowAccent, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                ),
                const SizedBox(height: 10),
                Text(
                  _currentDescription,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
              ],
            ),
          ),
          
          // Direction Icon
          Expanded(
            child: Center(
              child: Icon(
                _getIconForDirection(_directionIcon),
                size: 200,
                color: _isObstacle ? Colors.red : Colors.white,
              ),
            ),
          ),
  
          // Bottom Info Card (Simulated)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoItem(Icons.timer, "2 min"),
                _buildInfoItem(Icons.directions_walk, "50 m"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey, size: 20),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Status Text
          Expanded(
            child: Text(
              _statusText,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Console Button
          IconButton(
            icon: const Icon(Icons.terminal, color: Colors.blue),
            onPressed: _showConsole,
          ),
          // Emergency Button
          FloatingActionButton(
            onPressed: () {
              _emergencyService.makeEmergencyCall();
              _speak("Calling caretaker");
            },
            backgroundColor: Colors.red,
            mini: true,
            child: const Icon(Icons.phone, color: Colors.white),
          ),
        ],
      ),
    );
  }

  void _showConsole() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) {
        return ValueListenableBuilder<List<String>>(
          valueListenable: ConsoleService().logs,
          builder: (context, logs, child) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Debug Console", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.grey),
                  Expanded(
                    child: ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(logs[index], style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'Courier')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  IconData _getIconForDirection(String direction) {
    switch (direction) {
      case 'up': return Icons.arrow_upward;
      case 'left': return Icons.turn_left;
      case 'right': return Icons.turn_right;
      case 'stop': return Icons.stop_circle;
      default: return Icons.navigation;
    }
  }
}
