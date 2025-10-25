// lib/services/bluetooth_service.dart

import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/beacon_model.dart';
import 'dart:math' as math;

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  final StreamController<List<BeaconModel>> _beaconsController =
      StreamController<List<BeaconModel>>.broadcast();
  Stream<List<BeaconModel>> get beaconsStream => _beaconsController.stream;

  List<BeaconModel> _detectedBeacons = [];
  bool _isScanning = false;
  Timer? _scanTimer;
  bool _useSimulation = false;

  // Simulated beacon data
  final List<Map<String, dynamic>> _simulatedBeacons = [
    {'name': 'Beacon_Entrance', 'location': 'Main Entrance', 'rssi': -65},
    {'name': 'Beacon_Lab', 'location': 'Computer Lab', 'rssi': -72},
    {'name': 'Beacon_Library', 'location': 'Library', 'rssi': -78},
    {'name': 'Beacon_StaffRoom', 'location': 'Staff Room', 'rssi': -85},
  ];

  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  Future<void> startScanning() async {
    if (_isScanning) return;

    // Request permissions
    bool permissionsGranted = await requestPermissions();
    if (!permissionsGranted) {
      print('Bluetooth permissions not granted, using simulation mode');
      _useSimulation = true;
      _startSimulatedScanning();
      return;
    }

    try {
      // Check if Bluetooth is available
      bool isAvailable = await FlutterBluePlus.isAvailable;
      if (!isAvailable) {
        print('Bluetooth not available, using simulation mode');
        _useSimulation = true;
        _startSimulatedScanning();
        return;
      }

      // Check if Bluetooth is on
      var state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        print('Bluetooth is off, using simulation mode');
        _useSimulation = true;
        _startSimulatedScanning();
        return;
      }

      _isScanning = true;
      _useSimulation = false;

      // Start scanning for real devices
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 4));

      // Listen to scan results
      FlutterBluePlus.scanResults.listen((results) {
        _detectedBeacons.clear();

        for (ScanResult result in results) {
          String name = result.device.name.isNotEmpty
              ? result.device.name
              : result.device.id.toString();

          _detectedBeacons.add(
            BeaconModel(
              id: result.device.id.toString(),
              name: name,
              rssi: result.rssi,
              location: _getLocationFromName(name),
              isSimulated: false,
            ),
          );
        }

        // If no devices found after 5 seconds, switch to simulation
        if (_detectedBeacons.isEmpty) {
          _scanTimer ??= Timer(Duration(seconds: 5), () {
            if (_detectedBeacons.isEmpty) {
              _useSimulation = true;
              _startSimulatedScanning();
            }
          });
        } else {
          _beaconsController.add(_detectedBeacons);
        }
      });
    } catch (e) {
      print('Error starting Bluetooth scan: $e');
      _useSimulation = true;
      _startSimulatedScanning();
    }
  }

  void _startSimulatedScanning() {
    _isScanning = true;
    _detectedBeacons.clear();

    // Add simulated beacons
    for (var beacon in _simulatedBeacons) {
      _detectedBeacons.add(
        BeaconModel(
          id: 'sim_${beacon['name']}',
          name: beacon['name'],
          rssi: beacon['rssi'] + math.Random().nextInt(10) - 5, // Add variance
          location: beacon['location'],
          isSimulated: true,
        ),
      );
    }

    _beaconsController.add(_detectedBeacons);

    // Update simulated beacons periodically
    Timer.periodic(Duration(seconds: 3), (timer) {
      if (!_isScanning || !_useSimulation) {
        timer.cancel();
        return;
      }

      _detectedBeacons.clear();
      for (var beacon in _simulatedBeacons) {
        _detectedBeacons.add(
          BeaconModel(
            id: 'sim_${beacon['name']}',
            name: beacon['name'],
            rssi: beacon['rssi'] + math.Random().nextInt(10) - 5,
            location: beacon['location'],
            isSimulated: true,
          ),
        );
      }

      _beaconsController.add(_detectedBeacons);
    });
  }

  Future<void> stopScanning() async {
    _isScanning = false;
    _scanTimer?.cancel();
    _scanTimer = null;

    if (!_useSimulation) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (e) {
        print('Error stopping scan: $e');
      }
    }
  }

  String _getLocationFromName(String name) {
    // Map beacon names to locations
    if (name.toLowerCase().contains('entrance')) return 'Main Entrance';
    if (name.toLowerCase().contains('lab')) return 'Computer Lab';
    if (name.toLowerCase().contains('library')) return 'Library';
    if (name.toLowerCase().contains('staff')) return 'Staff Room';
    return 'Unknown Location';
  }

  BeaconModel? getNearestBeacon() {
    if (_detectedBeacons.isEmpty) return null;

    // Sort by RSSI (highest/closest first)
    _detectedBeacons.sort((a, b) => b.rssi.compareTo(a.rssi));
    return _detectedBeacons.first;
  }

  bool get isSimulationMode => _useSimulation;

  List<BeaconModel> get currentBeacons => _detectedBeacons;

  void dispose() {
    stopScanning();
    _beaconsController.close();
  }
}
