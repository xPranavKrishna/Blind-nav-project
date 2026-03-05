import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'connection_page.dart';
import 'package:flutter/services.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';
import '../services/navigation_demo_service.dart';
import '../beacon_service.dart';
import '../services/emergency_service.dart';
import '../services/console_service.dart';

const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String DISTANCE_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
const String DETECTED_UUID = "1c95d5e3-d8f7-413a-bf3d-7d3d14a81bf0";
const String TIMESTAMP_UUID = "d8f7125f-b267-4e20-bee0-1a951a1ac307";
const String PREF_BONDED_DEVICE_ID = "bonded_device_id";

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final SpeechService _speechService = SpeechService();
  final TtsService _ttsService = TtsService();
  final NavigationDemoService _navigationService = NavigationDemoService();
  final BeaconNavigationService _beaconService = BeaconNavigationService();
  // final ObstacleRealService _obstacleService = ObstacleRealService(); // Deprecated
  final EmergencyService _emergencyService = EmergencyService();

  String _currentAction = "Ready";
  String _currentDescription = "Say a destination";
  String _statusText = "Initializing...";
  String _directionIcon = "up"; // up, left, right, stop
  bool _isNavigating = false;
  bool _isObstacle = false;
  
  // BLE State
  BluetoothDevice? _connectedDevice;
  String _connectionStatus = "Disconnected";
  bool _isConnected = false;
  int _distance = 0;
  DateTime _lastAlertTime = DateTime.fromMillisecondsSinceEpoch(0);
  
  StreamSubscription? _commandSubscription;
  StreamSubscription? _navigationSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<int>>? _distanceSubscription;
  StreamSubscription<List<int>>? _detectedSubscription;
  StreamSubscription<List<int>>? _timestampSubscription;
  
  Timer? _reconnectionTimer;
  bool _isConnecting = false;

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

    // Start indoor beacon scanning for navigation
    _beaconService.startScanning();

    // Auto-connect to BLE
    _checkPermissionsAndAutoConnect();


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
    // Request all required permissions aggressively at launch
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.phone,
      Permission.location,
      if (Platform.isAndroid) ...[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ]
    ].request();

    bool anyDenied = statuses.values.any((status) => status.isDenied || status.isPermanentlyDenied);

    if (anyDenied) {
      ConsoleService().log("Some permissions were denied. App may not function perfectly.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please grant all permissions for Voice and Bluetooth to work properly.'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _checkPermissionsAndAutoConnect() async {
    // Permissions are now fully handled in _requestPermissions().
    // We just proceed to try auto-connecting.
    
    // Auto-reconnect
    final prefs = await SharedPreferences.getInstance();
    final String? bondedDeviceId = prefs.getString(PREF_BONDED_DEVICE_ID);

    if (bondedDeviceId != null) {
      ConsoleService().log("Found saved device ID: $bondedDeviceId");
      _startReconnectionLoop(bondedDeviceId);
    }
  }

  void _startReconnectionLoop(String deviceId) {
    _reconnectionTimer?.cancel();
    _reconnectionTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_isConnected || _isConnecting) return;

      ConsoleService().log("Aggressive Reconnect: Trying to connect...");
      try {
        // Try to find in bonded list first (most reliable)
        List<BluetoothDevice> bondedDevices = await FlutterBluePlus.bondedDevices;
        try {
          BluetoothDevice device = bondedDevices.firstWhere((d) => d.remoteId.str == deviceId);
          // Use isAutoConnect: false. This forces it to block and time out normally,
          // instead of returning immediately and spamming the loop.
          await _connectToDevice(device, isAutoConnect: false);
        } catch (e) {
           // Fallback
           BluetoothDevice device = BluetoothDevice.fromId(deviceId);
           await _connectToDevice(device, isAutoConnect: false);
        }
      } catch (e) {
        ConsoleService().log("Reconnection loop error: $e");
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device, {bool isAutoConnect = false}) async {
    if (_isConnecting) return;
    
    // Cancel any existing subscription to prevent memory leaks and duplicate states
    _connectionStateSubscription?.cancel();

    setState(() {
      _connectionStatus = "Connecting...";
      _isConnecting = true;
    });
    ConsoleService().log("Connecting to ${device.platformName} (Auto: $isAutoConnect)...");

    try {
      // Connect
      // autoConnect: true allows background reconnection on Android
      await device.connect(autoConnect: isAutoConnect); 
      
      if (!isAutoConnect) {
        // Only wait if manual connection, otherwise let it happen in background
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Check Bond State
      if (Platform.isAndroid) {
        var bondState = await device.bondState.first;
        if (bondState == BluetoothBondState.bonded) {
           ConsoleService().log("Device already bonded.");
        } else {
           ConsoleService().log("Device not bonded. Attempting to bond...");
           try {
             await device.createBond();
           } catch (e) {
             ConsoleService().log("Bonding failed/skipped: $e");
           }
        }
      }

      _connectionStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          setState(() {
            _isConnected = true;
            _connectionStatus = "Connected";
            _connectedDevice = device;
          });
          _saveBondedDevice(device.remoteId.str);
          _discoverServices(device);
          _speak("Device connected");
        } else if (state == BluetoothConnectionState.disconnected) {
          setState(() {
            _isConnected = false;
            _connectionStatus = "Disconnected";
            _connectedDevice = null;
          });
          _speak("Device disconnected");
        }
      });

    } catch (e) {
      setState(() {
        _connectionStatus = "Failed";
        _isConnecting = false;
      });
      ConsoleService().log("Connection failed: $e");
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();
      BluetoothService? targetService;
      try {
        targetService = services.firstWhere((s) => s.uuid.toString() == SERVICE_UUID);
      } catch (e) {
        ConsoleService().log("Service $SERVICE_UUID not found");
        return;
      }

      // Cancel old subscriptions if any
      _distanceSubscription?.cancel();
      _detectedSubscription?.cancel();

      for (BluetoothCharacteristic c in targetService.characteristics) {
        if (c.uuid.toString() == DISTANCE_UUID) {
          if (c.properties.notify || c.properties.indicate) {
             await c.setNotifyValue(true);
             _distanceSubscription = c.onValueReceived.listen((value) {
               _processDistance(value);
             });
          }
        } else if (c.uuid.toString() == DETECTED_UUID) {
          if (c.properties.notify || c.properties.indicate) {
             await c.setNotifyValue(true);
             _detectedSubscription = c.onValueReceived.listen((value) {
               _processDetected(value);
             });
          }
        }
      }
    } catch (e) {
      ConsoleService().log("Discovery failed: $e");
    }
  }

  void _processDistance(List<int> value) {
    if (value.length >= 4) {
      ByteData byteData = ByteData.sublistView(Uint8List.fromList(value));
      int dist = byteData.getInt32(0, Endian.little);
      setState(() {
        _distance = dist;
      });
      // Alert logic is handled in _processDetected or _handleAlerts
    }
  }

  void _processDetected(List<int> value) {
    if (value.isNotEmpty) {
      bool newDetection = value[0] == 1;
      if (newDetection && !_isObstacle) {
         _handleObstacle();
      } else if (!newDetection && _isObstacle) {
         setState(() {
           _isObstacle = false;
         });
         _speak("Path clear");
      }
    }
  }

  Future<void> _saveBondedDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PREF_BONDED_DEVICE_ID, id);
  }

  Future<void> _scanAndConnect() async {
    final BluetoothDevice? device = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ConnectionPage()),
    );

    if (device != null) {
      // Device is already connected by ConnectionPage
      setState(() {
        _isConnected = true;
        _connectionStatus = "Connected";
        _connectedDevice = device;
      });
      _discoverServices(device);
      _speak("Device connected");
      _saveBondedDevice(device.remoteId.str); // Ensure saved
      _startReconnectionLoop(device.remoteId.str); // Start loop for future
      
      // Listen to disconnection
      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
           _handleDisconnection();
        }
      });
    }
  }

  void _handleDisconnection() {
    setState(() {
      _isConnected = false;
      _connectionStatus = "Disconnected";
      _connectedDevice = null;
    });
    _speak("Device disconnected");
  }

  Future<void> _disconnect() async {
    _reconnectionTimer?.cancel(); // Stop aggressive reconnect on manual disconnect
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
    }
  }

  Future<void> _forgetDevice() async {
    _reconnectionTimer?.cancel();
    await _disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PREF_BONDED_DEVICE_ID);
    
    // Try to remove bond if possible (Android only)
    if (Platform.isAndroid && _connectedDevice != null) {
      try {
        await _connectedDevice!.removeBond();
      } catch (e) {
        ConsoleService().log("Could not remove bond: $e");
      }
    }
    
    setState(() {
      _connectedDevice = null;
      _isConnected = false;
      _connectionStatus = "Disconnected";
    });
    _speak("Device forgotten");
  }

  // Wrapper to handle TTS and STT coordination
  Future<void> _speak(String text) async {
    _speechService.pauseListening(); // Stop listening while speaking
    await _ttsService.speak(text);
    // Do NOT auto-resume listening. User must tap.
  }

  Future<void> _speakPrioritized(String text) async {
    _speechService.pauseListening();
    await _ttsService.speakPrioritized(text);
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
    } else if (command.contains("room 1") || command.contains("room1")) {
      // Natural language detect for Room 1
      _startNavigation("Room1");
    } else if (command.contains("hallway")) {
      // Natural language detect for Hallway
      _startNavigation("Hallway");
    } else if (command.contains("entrance")) {
      // Natural language detect for Entrance
      _startNavigation("Entrance");
    } else if (command.contains("go to") || command.contains("navigate to") || command.contains("take me to")) {
      // Fallback for older block commands to not break existing flow
      String destination = command.replaceAll("go to", "").replaceAll("navigate to", "").replaceAll("take me to", "").trim();
      if (destination.isNotEmpty) {
        _startNavigation(destination);
      } else {
        _speak("Sorry, I didn't understand. Please say Go to Room1, Hallway or Entrance");
      }
    } else {
      _speak("Sorry, I didn't understand. Please say Go to Room1, Hallway or Entrance");
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

    // Route to new beacon service if it's an indoor room, else default to demo
    final destLower = destination.toLowerCase();
    final isIndoor = ["entrance", "hallway", "room 1", "room1"].any((r) => destLower.contains(r));

    final navStream = isIndoor 
        ? _beaconService.startNavigation(destination)
        : _navigationService.startNavigation(destination);

    _navigationSubscription = navStream.listen((step) {
      if (_isObstacle) return; // Pause updates if obstacle

      setState(() {
        _currentAction = step['action'];
        _currentDescription = step['description'];
        _directionIcon = step['direction'];
      });
      // Speech might have been interrupted by obstacle. We check _isObstacle above.
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
    _beaconService.stopNavigation();
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
    if (DateTime.now().difference(_lastAlertTime).inMilliseconds < 2000) return;
    
    ConsoleService().log("Obstacle Detected! Distance: $_distance cm");
    setState(() {
      _isObstacle = true;
    });
    
    // STOP Navigation speech immediately and announce obstacle
    _speakPrioritized("Obstacle ahead at $_distance centimeters.");
    
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator ?? false) {
      Vibration.vibrate(duration: 500);
    }
    _lastAlertTime = DateTime.now();
  }

  @override
  void dispose() {
    _speechService.dispose();
    _beaconService.stopScanning();
    // _obstacleService.dispose();
    _commandSubscription?.cancel();
    _navigationSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _distanceSubscription?.cancel();
    _detectedSubscription?.cancel();
    _timestampSubscription?.cancel();
    _reconnectionTimer?.cancel();
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
          // Connection Status Icon
          IconButton(
            icon: Icon(
              _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: _isConnected ? Colors.blue : Colors.grey,
            ),
            onPressed: _isConnected ? _disconnect : _scanAndConnect,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == "connect") {
                _isConnected ? _disconnect() : _scanAndConnect();
              } else if (value == "forget") {
                _forgetDevice();
              } else if (value == "destination") {
                _showDestinationSelector();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: "connect", 
                child: Text(_isConnected ? "Disconnect" : "Connect Device")
              ),
              const PopupMenuItem(
                value: "destination",
                child: Text("Select Destination (Indoor)")
              ),
              const PopupMenuItem(value: "settings", child: Text("Settings")),
              const PopupMenuItem(value: "forget", child: Text("Forget Device")),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Debug Console", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.blueAccent),
                        onPressed: () {
                          final allLogs = logs.join('\n');
                          Clipboard.setData(ClipboardData(text: allLogs));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Logs copied to clipboard'), duration: Duration(seconds: 1)),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.grey),
                  Expanded(
                    child: ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          // Adding SelectableText so users can manually select parts of the log
                          child: SelectableText(logs[index], style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'Courier')),
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

  void _showDestinationSelector() {
    final destinations = _beaconService.availableRooms;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text("Select Destination", style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: destinations.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(destinations[index], style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _startNavigation(destinations[index]);
                  },
                );
              },
            ),
          ),
        );
      }
    );
  }
}
