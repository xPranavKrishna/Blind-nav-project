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

// ─── Design Tokens ────────────────────────────────────────────────────────────
const Color _kBackground    = Color(0xFFF5F5F0);   // warm off-white
const Color _kSurface       = Color(0xFFFFFFFF);
const Color _kAccent        = Color(0xFFFFBF00);   // deep amber — WCAG AA on white
const Color _kAccentDark    = Color(0xFFCC9900);
const Color _kTextPrimary   = Color(0xFF1A1A1A);
const Color _kTextSecondary = Color(0xFF555550);
const Color _kDanger        = Color(0xFFD32F2F);
const Color _kSuccess       = Color(0xFF1B7B4B);
const Color _kBlueBLE       = Color(0xFF1565C0);
const Color _kBorder        = Color(0xFFDDDDD8);

// ─────────────────────────────────────────────────────────────────────────────

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final SpeechService _speechService = SpeechService();
  final TtsService _ttsService = TtsService();
  final NavigationDemoService _navigationService = NavigationDemoService();
  final BeaconNavigationService _beaconService = BeaconNavigationService();
  final EmergencyService _emergencyService = EmergencyService();

  String _currentAction = "Ready";
  String _currentDescription = "Say a destination";
  String _statusText = "Initializing...";
  String _directionIcon = "up";
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

  Timer? _uiUpdateTimer;
  Timer? _reconnectionTimer;
  bool _isConnecting = false;
  String? _currentTarget;
  String _lastSpokenRoom = "";
  String _lastSpokenStep = "";

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _directionController;
  late AnimationController _obstacleFlashController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _directionScaleAnim;
  late Animation<double> _obstacleOpacity;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initServices();
  }

  void _initAnimations() {
    // Mic pulse
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Direction icon entrance
    _directionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _directionScaleAnim = CurvedAnimation(
      parent: _directionController,
      curve: Curves.elasticOut,
    );

    // Obstacle flash
    _obstacleFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _obstacleOpacity = Tween<double>(begin: 0.5, end: 1.0).animate(
      _obstacleFlashController,
    );
  }

  // ── ALL LOGIC BELOW IS UNCHANGED FROM ORIGINAL ─────────────────────────────

  Future<void> _initServices() async {
    await _requestPermissions();
    await _ttsService.init();
    bool available = await _speechService.init();

    if (available) {
      setState(() { _statusText = "Tap to Speak"; });
    } else {
      setState(() { _statusText = "Microphone not available"; });
    }

    _beaconService.startScanning();
    _checkPermissionsAndAutoConnect();

    _commandSubscription = _speechService.commandStream.listen(_handleCommand);
    _speechService.listeningStream.listen((isListening) {
      if (mounted) {
        setState(() {
          _statusText = isListening ? "Listening..." : "Tap to Speak";
        });
        if (isListening) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
          _pulseController.reset();
        }
      }
    });

    Future.delayed(Duration(seconds: 1), () async {
      await _speak(
        "Welcome to Vazhikaatti. Tap the screen and say a destination like Library or Admin Block.",
      );
      _speechService.startListening();
    });

    _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
        if (_isNavigating && !_isObstacle && _beaconService.currentRoom != null) {
          String currentRoom = _beaconService.currentRoom!;
          if (currentRoom != _lastSpokenRoom && currentRoom != "Searching...") {
            _lastSpokenRoom = currentRoom;
            _speak("Entered $currentRoom");
          }
        }
      }
    });
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.phone,
      Permission.location,
      Permission.activityRecognition,
      if (Platform.isAndroid) ...[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ]
    ].request();

    bool anyDenied = statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);
    if (anyDenied) {
      ConsoleService().log("Some permissions were denied.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please grant all permissions for Voice and Bluetooth.'),
            action: SnackBarAction(label: 'Settings', onPressed: () => openAppSettings()),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _checkPermissionsAndAutoConnect() async {
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
        List<BluetoothDevice> bondedDevices = await FlutterBluePlus.bondedDevices;
        try {
          BluetoothDevice device = bondedDevices.firstWhere((d) => d.remoteId.str == deviceId);
          await _connectToDevice(device, isAutoConnect: false);
        } catch (e) {
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
    _connectionStateSubscription?.cancel();
    setState(() { _connectionStatus = "Connecting..."; _isConnecting = true; });
    ConsoleService().log("Connecting to ${device.platformName}...");
    try {
      await device.connect(autoConnect: isAutoConnect);
      if (!isAutoConnect) await Future.delayed(const Duration(milliseconds: 500));
      if (Platform.isAndroid) {
        var bondState = await device.bondState.first;
        if (bondState != BluetoothBondState.bonded) {
          try { await device.createBond(); } catch (e) { ConsoleService().log("Bonding failed: $e"); }
        }
      }
      _connectionStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          setState(() { _isConnected = true; _connectionStatus = "Connected"; _connectedDevice = device; });
          _saveBondedDevice(device.remoteId.str);
          _discoverServices(device);
          _speak("Device connected");
        } else if (state == BluetoothConnectionState.disconnected) {
          setState(() { _isConnected = false; _connectionStatus = "Disconnected"; _connectedDevice = null; });
          _speak("Device disconnected");
        }
      });
    } catch (e) {
      setState(() { _connectionStatus = "Failed"; _isConnecting = false; });
      ConsoleService().log("Connection failed: $e");
    } finally {
      setState(() { _isConnecting = false; });
    }
  }

  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();
      BluetoothService? targetService;
      try { targetService = services.firstWhere((s) => s.uuid.toString() == SERVICE_UUID); }
      catch (e) { ConsoleService().log("Service $SERVICE_UUID not found"); return; }
      _distanceSubscription?.cancel();
      _detectedSubscription?.cancel();
      for (BluetoothCharacteristic c in targetService.characteristics) {
        if (c.uuid.toString() == DISTANCE_UUID) {
          if (c.properties.notify || c.properties.indicate) {
            await c.setNotifyValue(true);
            _distanceSubscription = c.onValueReceived.listen(_processDistance);
          }
        } else if (c.uuid.toString() == DETECTED_UUID) {
          if (c.properties.notify || c.properties.indicate) {
            await c.setNotifyValue(true);
            _detectedSubscription = c.onValueReceived.listen(_processDetected);
          }
        }
      }
    } catch (e) { ConsoleService().log("Discovery failed: $e"); }
  }

  void _processDistance(List<int> value) {
    if (value.length >= 4) {
      ByteData byteData = ByteData.sublistView(Uint8List.fromList(value));
      int dist = byteData.getInt32(0, Endian.little);
      setState(() { _distance = dist; });
    }
  }

  void _processDetected(List<int> value) {
    if (value.isNotEmpty) {
      bool newDetection = value[0] == 1;
      if (newDetection && !_isObstacle) {
        _handleObstacle();
      } else if (!newDetection && _isObstacle) {
        setState(() { _isObstacle = false; });
        _speakPrioritized("Path clear. Resuming navigation.").then((_) {
          if (_isNavigating && _lastSpokenStep.isNotEmpty) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted && !_isObstacle) _speakPrioritized(_lastSpokenStep);
            });
          }
        });
      }
    }
  }

  Future<void> _saveBondedDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PREF_BONDED_DEVICE_ID, id);
  }

  Future<void> _scanAndConnect() async {
    final BluetoothDevice? device = await Navigator.push(
      context, MaterialPageRoute(builder: (context) => const ConnectionPage()),
    );
    if (device != null) {
      setState(() { _isConnected = true; _connectionStatus = "Connected"; _connectedDevice = device; });
      _discoverServices(device);
      _speak("Device connected");
      _saveBondedDevice(device.remoteId.str);
      _startReconnectionLoop(device.remoteId.str);
      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) _handleDisconnection();
      });
    }
  }

  void _handleDisconnection() {
    setState(() { _isConnected = false; _connectionStatus = "Disconnected"; _connectedDevice = null; });
    _speak("Device disconnected");
  }

  Future<void> _disconnect() async {
    _reconnectionTimer?.cancel();
    if (_connectedDevice != null) await _connectedDevice!.disconnect();
  }

  Future<void> _forgetDevice() async {
    _reconnectionTimer?.cancel();
    await _disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PREF_BONDED_DEVICE_ID);
    if (Platform.isAndroid && _connectedDevice != null) {
      try { await _connectedDevice!.removeBond(); } catch (e) { ConsoleService().log("Could not remove bond: $e"); }
    }
    setState(() { _connectedDevice = null; _isConnected = false; _connectionStatus = "Disconnected"; });
    _speak("Device forgotten");
  }

  Future<void> _speak(String text) async {
    _speechService.pauseListening();
    await _ttsService.speak(text);
  }

  Future<void> _speakPrioritized(String text) async {
    _speechService.pauseListening();
    await _ttsService.speakPrioritized(text);
  }

  void _handleCommand(String command) async {
    print("Command received: $command");
    String cmdLower = command.toLowerCase();

    // ==================== EMERGENCY CALL ====================
    if (cmdLower.contains("emergency") ||
        cmdLower.contains("sos") ||
        cmdLower.contains("caretaker") ||
        cmdLower.contains("care taker") ||
        (cmdLower.contains("call") && (
            cmdLower.contains("help") ||
            cmdLower.contains("caretaker") ||
            cmdLower.contains("care") ||
            cmdLower.contains("sos")
        )) ||
        (cmdLower.contains("help") && !_isValidDestination(cmdLower))) {
      
      bool success = await _emergencyService.makeEmergencyCall();
      
      if (success) {
        _speak("Calling caretaker...");
      } else {
        _speak("No caretaker number saved. Please save one in settings.");
      }
      return;   // Important: Stop further processing
    }
    // =======================================================

    // ── Stop navigation ──────────────────────────────────────────────────────
    if (cmdLower.contains("stop") ||
        cmdLower.contains("cancel") ||
        cmdLower.contains("cancel route") ||
        cmdLower.contains("end navigation") ||
        cmdLower.contains("quit")) {
      _stopNavigation();

    // ── Connect device ───────────────────────────────────────────────────────
    } else if (cmdLower.contains("connect") ||
               cmdLower.contains("connect device") ||
               cmdLower.contains("connect to device") ||
               cmdLower.contains("pair device")) {
      if (_isConnected) {
        _speak("Device is already connected");
      } else {
        _speak("Opening device connection");
        _scanAndConnect();
      }

    // ── Repeat last instruction ──────────────────────────────────────────────
    } else if (cmdLower.contains("repeat") ||
               cmdLower.contains("say again") ||
               cmdLower.contains("what was that")) {
      if (_lastSpokenStep.isNotEmpty) {
        _speakPrioritized(_lastSpokenStep);
      } else {
        _speakPrioritized("No navigation step to repeat");
      }

    // ── Navigate to destination ──────────────────────────────────────────────
    } else {
      String? target;
      List<String> validTargets = [
        "room1", "room 1", "room2", "room 2",
        "hallway", "entrance",
        "library", "admin", "cs01", "newblock", "cse", "adblock"
      ];

      bool matched = false;
      for (String v in validTargets) {
        if (cmdLower.contains(v)) {
          matched = true;
          if (v == "room1" || v == "room 1") target = "Room1";
          else if (v == "room2" || v == "room 2") target = "Room2";
          else if (v == "hallway") target = "Hallway";
          else if (v == "entrance") target = "Entrance";
          else target = command
              .replaceAll(
                RegExp(r'(go to|navigate to|take me to|find)',
                    caseSensitive: false),
                "")
              .trim();
          break;
        }
      }

      if (matched && target != null && target.isNotEmpty) {
        _startNavigation(target);
      } else {
        _speak("Sorry, I didn't understand. Say a destination or say help.");
      }
    }
  }

  void _startNavigation(String destination) {
    _navigationService.stopNavigation();
    _beaconService.stopNavigation();
    _navigationSubscription?.cancel();
    setState(() {
      _currentTarget = destination;
      _lastSpokenRoom = "";
      _lastSpokenStep = "";
      _isNavigating = true;
      _statusText = "Navigating...";
    });
    _speak("Starting navigation to $destination");
    _directionController.forward(from: 0);

    final destLower = destination.toLowerCase();
    final isIndoor = ["entrance","hallway","room 1","room1"].any((r) => destLower.contains(r));
    final navStream = isIndoor
        ? _beaconService.startNavigation(destination)
        : _navigationService.startNavigation(destination);

    _navigationSubscription = navStream.listen((step) {
      if (_isObstacle) return;
      if (step['action'] == 'WAITING') {
        setState(() { _currentAction = 'WAITING'; _currentDescription = step['description']; _directionIcon = 'stop'; });
        _speakPrioritized("Locating you, please walk a few steps");
        return;
      }
      String newDescription = step['description'];
      setState(() {
        _currentAction = step['action'];
        _currentDescription = newDescription;
        _directionIcon = step['direction'];
      });
      _directionController.forward(from: 0);

      if (newDescription.isNotEmpty && newDescription != "Recalculating...") {
        if (_lastSpokenStep != newDescription) {
          _lastSpokenStep = newDescription;
          _speakPrioritized(newDescription);
        }
      }
    }, onDone: () {
      if (mounted) {
        setState(() {
          _isNavigating = false;
          _statusText = "Arrived";
          _directionIcon = "stop";
          _currentAction = "ARRIVED";
          _currentDescription = "You have reached $destination";
        });
      }
      _speak("You have reached $destination");
    });
  }

  void _stopNavigation() {
    _navigationService.stopNavigation();
    _beaconService.stopNavigation();
    _navigationSubscription?.cancel();
    setState(() {
      _isNavigating = false;
      _statusText = "Tap to Speak";
      _currentAction = "Ready";
      _currentDescription = "Tap to say a destination";
      _directionIcon = "stop";
      _currentTarget = null;
    });
    _speak("Navigation stopped");
  }

  void _handleObstacle() async {
    if (DateTime.now().difference(_lastAlertTime).inMilliseconds < 2000) return;

    ConsoleService().log("Obstacle Detected! Distance: $_distance cm");

    await _ttsService.stop(); // stop current speech first

    setState(() { _isObstacle = true; });

    final distText = _distance > 0 ? "at $_distance centimeters" : "detected";
    _speakPrioritized("Obstacle $distText. Stop and wait.");

    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator ?? false) Vibration.vibrate(duration: 500);
    _lastAlertTime = DateTime.now();

    // Auto-clear if BLE drops
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isObstacle) {
        setState(() { _isObstacle = false; });
        _speakPrioritized("Obstacle timeout. Proceed with caution.").then((_) {
          if (_isNavigating && _lastSpokenStep.isNotEmpty) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted && !_isObstacle) _speakPrioritized(_lastSpokenStep);
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _directionController.dispose();
    _obstacleFlashController.dispose();
    _uiUpdateTimer?.cancel();
    _speechService.dispose();
    _beaconService.stopScanning();
    _commandSubscription?.cancel();
    _navigationSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _distanceSubscription?.cancel();
    _detectedSubscription?.cancel();
    _timestampSubscription?.cancel();
    _reconnectionTimer?.cancel();
    super.dispose();
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
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

  // ── HEADER ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder, width: 1.5)),
      ),
      child: Row(
        children: [
          // Logo circle
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _kAccent,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.navigation_rounded, color: Colors.black, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Vazhikaatti",
                style: TextStyle(
                  color: _kTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                "Indoor Navigation",
                style: TextStyle(
                  color: _kTextSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const Spacer(),
          // BLE badge
          Semantics(
            label: _isConnected ? "Bluetooth connected" : "Bluetooth disconnected. Tap to connect.",
            button: true,
            child: GestureDetector(
              onTap: _isConnected ? _disconnect : _scanAndConnect,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _isConnected ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isConnected ? _kSuccess : _kBorder,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isConnected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_disabled_rounded,
                      size: 16,
                      color: _isConnected ? _kSuccess : _kTextSecondary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isConnected ? "Live" : "Off",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _isConnected ? _kSuccess : _kTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: _kTextSecondary, size: 22),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            color: _kSurface,
            onSelected: (value) {
              if (value == "connect") { _isConnected ? _disconnect() : _scanAndConnect(); }
              else if (value == "forget") { _forgetDevice(); }
              else if (value == "destination") { _showDestinationSelector(); }
              else if (value == "caretaker") { _showCaretakerSetup(); }
            },
            itemBuilder: (context) => [
              _menuItem(Icons.phone_rounded, "Add Caretaker", "caretaker"),
              _menuItem(Icons.bluetooth_rounded, _isConnected ? "Disconnect" : "Connect Device", "connect"),
              _menuItem(Icons.place_rounded, "Select Destination", "destination"),
              _menuItem(Icons.delete_outline_rounded, "Forget Device", "forget"),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(IconData icon, String label, String value) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: _kTextSecondary),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 15, color: _kTextPrimary)),
        ],
      ),
    );
  }

  // ── IDLE UI ────────────────────────────────────────────────────────────────

  Widget _buildIdleUI() {
    final bool isListening = _speechService.isListening;

    return Semantics(
      label: isListening
          ? "Listening. Speak your destination."
          : "Tap anywhere to speak your destination.",
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.mediumImpact();
          if (!_speechService.isListening) {
            _speechService.resumeListening();
          }
        },
        child: Container(
          color: _kBackground,
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ── Mic orb ─────────────────────────────────────────────────
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: isListening ? _pulseAnimation.value : 1.0,
                    child: child,
                  );
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // outer ring (listening glow)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isListening
                            ? _kAccent.withOpacity(0.15)
                            : _kBorder.withOpacity(0.4),
                      ),
                    ),
                    // inner circle
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isListening ? _kAccent : _kSurface,
                        border: Border.all(
                          color: isListening ? _kAccentDark : _kBorder,
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isListening
                                ? _kAccent.withOpacity(0.35)
                                : Colors.black.withOpacity(0.06),
                            blurRadius: isListening ? 32 : 12,
                            spreadRadius: isListening ? 4 : 0,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.mic_rounded,
                        size: 64,
                        color: isListening ? Colors.black : _kTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // ── Status label ─────────────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  isListening ? "Listening..." : "Tap to Speak",
                  key: ValueKey(isListening),
                  style: TextStyle(
                    color: _kTextPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Text(
                "Say a destination like \"Library\" or \"Admin Block\"",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _kTextSecondary,
                  fontSize: 17,
                  height: 1.5,
                ),
              ),

              const Spacer(flex: 2),

              // ── Hint chips ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    _hintChip("Library"),
                    _hintChip("Admin Block"),
                    _hintChip("Hallway"),
                    _hintChip("Entrance"),
                    _hintChip("Room 1"),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hintChip(String label) {
    return Semantics(
      label: "Navigate to $label",
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _startNavigation(label);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: _kBorder, width: 1.5),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: _kTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // ── NAVIGATION UI ──────────────────────────────────────────────────────────

  String _getFullPathStr(String start, String target) {
    String s = start.toLowerCase();
    String t = target.toLowerCase();
    if (s == t) return start;
    if (s == "entrance" && t == "room1") return "Entrance → Hallway → Room1";
    if (s == "room1" && t == "entrance") return "Room1 → Hallway → Entrance";
    if (s == "entrance" && t == "hallway") return "Entrance → Hallway";
    if (s == "hallway" && t == "entrance") return "Hallway → Entrance";
    if (s == "hallway" && t == "room1") return "Hallway → Room1";
    if (s == "room1" && t == "hallway") return "Room1 → Hallway";
    return "$start → $target";
  }

  Widget _buildNavigationUI() {
    String currentRoom = _beaconService.currentRoom ?? "Searching...";
    String fullPath = "";
    if (_currentTarget != null && _beaconService.currentRoom != null) {
      fullPath = _getFullPathStr(_beaconService.currentRoom!, _currentTarget!);
    }
    String displayDescription = _currentDescription.isNotEmpty ? _currentDescription : "Recalculating...";

    return Semantics(
      label: "$displayDescription. Current location: $currentRoom. Tap to give a voice command.",
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          HapticFeedback.mediumImpact();
          await _ttsService.stop();
          if (!_speechService.isListening) _speechService.resumeListening();
        },
        child: Container(
          color: _kBackground,
          child: Column(
            children: [
              // ── Obstacle banner ────────────────────────────────────────
              if (_isObstacle) _buildObstacleBanner(),

              // ── Top card ───────────────────────────────────────────────
              _buildNavigationCard(currentRoom, displayDescription, fullPath),

              // ── Big direction icon ─────────────────────────────────────
              Expanded(
                child: Center(
                  child: ScaleTransition(
                    scale: _directionScaleAnim,
                    child: _buildDirectionIcon(),
                  ),
                ),
              ),

              // ── Bottom stats row ───────────────────────────────────────
              _buildStatsRow(),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildObstacleBanner() {
    return AnimatedBuilder(
      animation: _obstacleOpacity,
      builder: (context, child) {
        return Opacity(
          opacity: _obstacleOpacity.value,
          child: child,
        );
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: _kDanger,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "OBSTACLE AHEAD",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
                  Text(
                    "$_distance cm away • Stop and wait",
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationCard(String currentRoom, String description, String fullPath) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current location row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _kAccent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_on_rounded, size: 18, color: _kAccentDark),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("You are here", style: TextStyle(color: _kTextSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    Text(currentRoom, style: const TextStyle(color: _kTextPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              if (_currentTarget != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F0EC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.flag_rounded, size: 14, color: _kTextSecondary),
                      const SizedBox(width: 5),
                      Text(_currentTarget!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kTextPrimary)),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),
          Container(height: 1, color: _kBorder),
          const SizedBox(height: 16),

          // Next step
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kAccent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kAccent.withOpacity(0.3), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "NEXT STEP",
                  style: TextStyle(color: _kAccentDark, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(color: _kTextPrimary, fontSize: 22, fontWeight: FontWeight.w800, height: 1.3),
                ),
              ],
            ),
          ),

          if (fullPath.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.route_rounded, size: 14, color: _kTextSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fullPath,
                    style: TextStyle(color: _kTextSecondary, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDirectionIcon() {
    final IconData icon = _getIconForDirection(_directionIcon);
    final Color iconColor = _isObstacle ? _kDanger : _kTextPrimary;

    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: _isObstacle ? _kDanger.withOpacity(0.08) : _kAccent.withOpacity(0.10),
        shape: BoxShape.circle,
        border: Border.all(
          color: _isObstacle ? _kDanger.withOpacity(0.3) : _kAccent.withOpacity(0.4),
          width: 2,
        ),
      ),
      child: Icon(icon, size: 90, color: iconColor),
    );
  }

  Widget _buildStatsRow() {
    final double? navDist = _beaconService.distanceToNextWaypoint;

    // If nothing real to show, hide the row entirely
    if (navDist == null && !_isConnected) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Real: distance to next waypoint from beacon service
          if (navDist != null) ...[
            Expanded(
              child: _statCard(
                Icons.directions_walk_rounded,
                "To Waypoint",
                "${navDist.toStringAsFixed(1)} m",
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Real: live obstacle sensor distance from ESP32
          if (_isConnected)
            Expanded(
              child: _statCard(
                Icons.sensors_rounded,
                "Obstacle",
                _distance > 0 ? "$_distance cm" : "Clear",
              ),
            ),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder, width: 1.5),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: _kTextSecondary),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: _kTextPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          Text(label, style: TextStyle(color: _kTextSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  // ── FOOTER ─────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border(top: BorderSide(color: _kBorder, width: 1.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _statusText,
              style: TextStyle(color: _kTextSecondary, fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Console
          Semantics(
            label: "Debug console",
            button: true,
            child: IconButton(
              icon: const Icon(Icons.terminal_rounded, color: _kTextSecondary, size: 22),
              onPressed: _showConsole,
            ),
          ),
          const SizedBox(width: 8),
          // Stop nav button (only when navigating)
          if (_isNavigating)
            Semantics(
              label: "Stop navigation",
              button: true,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.heavyImpact();
                  _stopNavigation();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kBorder, width: 1.5),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stop_rounded, color: _kTextPrimary, size: 18),
                      SizedBox(width: 6),
                      Text("Stop", style: TextStyle(color: _kTextPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
          // Emergency button
          Semantics(
            label: "Emergency call to caretaker",
            button: true,
            child: GestureDetector(
              onTap: () async {
                HapticFeedback.heavyImpact();
                final called = await _emergencyService.makeEmergencyCall();
                if (called) {
                  _speak("Calling caretaker");
                } else {
                  _speak("No caretaker number saved. Please add one in settings.");
                  _showCaretakerSetup(); // opens setup dialog
                }
              },
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _kDanger,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: _kDanger.withOpacity(0.35), blurRadius: 12, spreadRadius: 2),
                  ],
                ),
                child: const Icon(Icons.phone_rounded, color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── CONSOLE ────────────────────────────────────────────────────────────────

  void _showConsole() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return ValueListenableBuilder<List<String>>(
          valueListenable: ConsoleService().logs,
          builder: (context, logs, child) {
            return Container(
              padding: const EdgeInsets.all(20),
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Debug Console",
                        style: TextStyle(color: _kTextPrimary, fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: logs.join('\n')));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Logs copied'), duration: Duration(seconds: 1)),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text("Copy"),
                        style: TextButton.styleFrom(foregroundColor: _kBlueBLE),
                      ),
                    ],
                  ),
                  Container(height: 1, color: _kBorder),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListView.builder(
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: SelectableText(
                              logs[index],
                              style: const TextStyle(color: Color(0xFF4AFF91), fontSize: 12, fontFamily: 'Courier'),
                            ),
                          );
                        },
                      ),
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

  // ── HELPERS ────────────────────────────────────────────────────────────────

  IconData _getIconForDirection(String direction) {
    switch (direction) {
      case 'up':    return Icons.arrow_upward_rounded;
      case 'left':  return Icons.turn_left_rounded;
      case 'right': return Icons.turn_right_rounded;
      case 'stop':  return Icons.stop_circle_rounded;
      default:      return Icons.navigation_rounded;
    }
  }

  void _showCaretakerSetup() async {
    // Load existing number
    final existing = await _emergencyService.getCaretakerNumber();
    final TextEditingController controller =
        TextEditingController(text: existing ?? "");

    showModalBottomSheet(
      context: context,
      backgroundColor: _kSurface,
      isScrollControlled: true, // allows keyboard to push sheet up
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return Padding(
          // Push sheet above keyboard
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  const Text(
                    "Caretaker Number",
                    style: TextStyle(
                      color: _kTextPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "This number will be called in emergencies",
                    style: TextStyle(color: _kTextSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  // Phone input
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    style: const TextStyle(
                      color: _kTextPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                    decoration: InputDecoration(
                      hintText: "+91 98765 43210",
                      hintStyle: TextStyle(color: _kTextSecondary.withOpacity(0.5), fontSize: 18),
                      prefixIcon: const Icon(Icons.phone_rounded, color: _kAccentDark),
                      filled: true,
                      fillColor: const Color(0xFFF8F8F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _kBorder, width: 1.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _kBorder, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _kAccent, width: 2),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final number = controller.text.trim();
                        if (number.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Please enter a phone number")),
                          );
                          return;
                        }
                        await _emergencyService.saveCaretakerNumber(number);
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Caretaker number saved ✓")),
                          );
                          _speak("Caretaker number saved");
                        }
                      },
                      icon: const Icon(Icons.save_rounded),
                      label: const Text(
                        "Save Number",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),

                  // Delete button (only show if number exists)
                  if (existing != null && existing.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _emergencyService.deleteCaretakerNumber();
                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Caretaker number deleted")),
                            );
                            _speak("Caretaker number deleted");
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded, color: _kDanger),
                        label: const Text(
                          "Delete Number",
                          style: TextStyle(
                            color: _kDanger,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: _kDanger.withOpacity(0.4), width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDestinationSelector() {
    final destinations = _beaconService.availableRooms;
    showModalBottomSheet(
      context: context,
      backgroundColor: _kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Select Destination",
                  style: TextStyle(color: _kTextPrimary, fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  "Tap a room to start navigation",
                  style: TextStyle(color: _kTextSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                ...destinations.map((dest) => Semantics(
                  label: "Navigate to $dest",
                  button: true,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context);
                      _startNavigation(dest);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F8F5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kBorder, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _kAccent.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.room_rounded, size: 18, color: _kAccentDark),
                          ),
                          const SizedBox(width: 14),
                          Text(dest, style: const TextStyle(color: _kTextPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          const Icon(Icons.chevron_right_rounded, color: _kTextSecondary),
                        ],
                      ),
                    ),
                  ),
                )),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isValidDestination(String cmd) {
    const destinations = [
      "room1", "room 1", "room2", "room 2",
      "hallway", "entrance", "library", "admin",
      "cs01", "newblock", "cse", "adblock"
    ];
    return destinations.any((d) => cmd.contains(d));
  }
}