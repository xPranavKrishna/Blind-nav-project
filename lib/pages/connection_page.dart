import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/console_service.dart';

const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String PREF_BONDED_DEVICE_ID = "bonded_device_id";

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> with SingleTickerProviderStateMixin {
  List<ScanResult> _scanResults = [];
  List<BluetoothDevice> _systemDevices = [];
  bool _isScanning = false;
  
  late AnimationController _animationController;
  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _startScan();
  }

  @override
  void dispose() {
    _stopScan();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _scanResults = [];
      _systemDevices = [];
    });
    _animationController.repeat();

    try {
      // 1. Get system devices (bonded)
      if (Platform.isAndroid) {
        try {
          // Get ALL bonded devices, not just those with the service UUID
          // This fixes the issue where the device doesn't show up if not advertising the service
          _systemDevices = await FlutterBluePlus.bondedDevices;
        } catch (e) {
          ConsoleService().log("Error getting system devices: $e");
        }
        setState(() {});
      }

      // 2. Start Scan
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          _scanResults = results;
          _scanResults.sort((a, b) => b.rssi.compareTo(a.rssi));
        });
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      
      await Future.delayed(const Duration(seconds: 15));
      if (mounted) {
        _stopScan();
      }
    } catch (e) {
      ConsoleService().log("Scan failed: $e");
      _stopScan();
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) { /* ignore */ }
    
    _scanSubscription?.cancel();
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
      _animationController.stop();
      _animationController.reset();
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    await _stopScan();
    
    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    try {
      ConsoleService().log("Connecting to ${device.remoteId}...");
      await device.connect(autoConnect: false);
      
      // Wait for stack
      await Future.delayed(const Duration(seconds: 1));
      
      // Bond if needed (Android only)
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

      // Save ID
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PREF_BONDED_DEVICE_ID, device.remoteId.str);

      if (mounted) {
        Navigator.pop(context); // Close dialog
        Navigator.pop(context, device); // Return device to Home
      }
    } catch (e) {
      ConsoleService().log("Connection failed: $e");
      if (mounted) {
        Navigator.pop(context); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Connection failed: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [Color(0xFF222222), Colors.black],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildScanner(),
              const SizedBox(height: 20),
              Expanded(child: _buildDeviceList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Text(
            "Connect Device",
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _isScanning ? _stopScan : _startScan,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_isScanning)
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.5 * (1 - _animationController.value)),
                            width: 2,
                          ),
                        ),
                      );
                    },
                  ),
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[900],
                    boxShadow: [
                      BoxShadow(
                        color: _isScanning ? Colors.blue.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                        blurRadius: _isScanning ? 20 : 10,
                        spreadRadius: _isScanning ? 5 : 1,
                      ),
                    ],
                    border: Border.all(
                      color: _isScanning ? Colors.blue : Colors.grey[800]!,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      _isScanning ? Icons.bluetooth_searching : Icons.bluetooth,
                      size: 50,
                      color: _isScanning ? Colors.blue : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _isScanning ? "Scanning for devices..." : "Tap to Scan",
            style: TextStyle(
              color: _isScanning ? Colors.blueAccent : Colors.grey,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    if (_systemDevices.isEmpty && _scanResults.isEmpty) {
      return Center(
        child: Text(
          _isScanning ? "Looking for nearby devices..." : "No devices found.",
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (_systemDevices.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text("PAIRED DEVICES", style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),
          ..._systemDevices.map((d) => _buildDeviceTile(d)),
          const SizedBox(height: 16),
        ],
        if (_scanResults.isNotEmpty) ...[
           const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text("AVAILABLE DEVICES", style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),
           ..._scanResults.map((r) => _buildDeviceTile(r.device, rssi: r.rssi)),
        ]
      ],
    );
  }

  Widget _buildDeviceTile(BluetoothDevice device, {int? rssi}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.bluetooth, color: Colors.blue),
        ),
        title: Text(
          device.platformName.isNotEmpty ? device.platformName : "Unknown Device",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(device.remoteId.str, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            if (rssi != null)
              Text("Signal: $rssi dBm", style: TextStyle(color: _getSignalColor(rssi), fontSize: 12)),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () => _connect(device),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: const Text("Connect"),
        ),
      ),
    );
  }

  Color _getSignalColor(int rssi) {
    if (rssi > -60) return Colors.green;
    if (rssi > -70) return Colors.yellow;
    return Colors.red;
  }
}
