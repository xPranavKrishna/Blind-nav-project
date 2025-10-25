// lib/screens/bluetooth_screen.dart

import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../services/tts_service.dart';
import '../models/beacon_model.dart';

class BluetoothScreen extends StatefulWidget {
  @override
  _BluetoothScreenState createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  final BluetoothService _bluetoothService = BluetoothService();
  final TtsService _tts = TtsService();
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _startScanning();
  }

  Future<void> _startScanning() async {
    setState(() => _isScanning = true);
    await _bluetoothService.startScanning();

    // Announce scanning status
    Future.delayed(Duration(seconds: 2), () {
      if (_bluetoothService.isSimulationMode) {
        _tts.speakBluetoothStatus(
          "No Bluetooth beacons detected. Running in simulation mode.",
        );
      } else {
        _tts.speakBluetoothStatus("Scanning for nearby beacons");
      }
    });
  }

  @override
  void dispose() {
    _bluetoothService.stopScanning();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bluetooth Beacons'),
        backgroundColor: Color(0xFF5B8DBE),
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.refresh),
            onPressed: () {
              if (_isScanning) {
                _bluetoothService.stopScanning();
                setState(() => _isScanning = false);
              } else {
                _startScanning();
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB8CCE0), Color(0xFFE8D5C7)],
          ),
        ),
        child: Column(
          children: [
            // Status Banner
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              color: _bluetoothService.isSimulationMode
                  ? Colors.orange.withOpacity(0.2)
                  : Colors.blue.withOpacity(0.2),
              child: Row(
                children: [
                  Icon(
                    _bluetoothService.isSimulationMode
                        ? Icons.warning_amber
                        : Icons.bluetooth_searching,
                    color: _bluetoothService.isSimulationMode
                        ? Colors.orange[700]
                        : Colors.blue[700],
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _bluetoothService.isSimulationMode
                          ? 'Simulation Mode - Demo Beacons'
                          : 'Scanning for Beacons...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Beacon List
            Expanded(
              child: StreamBuilder<List<BeaconModel>>(
                stream: _bluetoothService.beaconsStream,
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF5B8DBE)),
                          SizedBox(height: 20),
                          Text(
                            'Searching for beacons...',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  List<BeaconModel> beacons = snapshot.data!;

                  return ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: beacons.length,
                    itemBuilder: (context, index) {
                      BeaconModel beacon = beacons[index];
                      return _buildBeaconCard(beacon);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBeaconCard(BeaconModel beacon) {
    Color signalColor;
    if (beacon.rssi > -60) {
      signalColor = Colors.green;
    } else if (beacon.rssi > -75) {
      signalColor = Colors.orange;
    } else {
      signalColor = Colors.red;
    }

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          _tts.speak(
            "${beacon.name} detected at ${beacon.location}. "
            "Signal strength: ${beacon.proximityLevel}",
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Signal Strength Indicator
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: signalColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.bluetooth, color: signalColor, size: 30),
                  ),
                  SizedBox(width: 16),

                  // Beacon Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                beacon.name,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                            if (beacon.isSimulated)
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange[100],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'DEMO',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange[700],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          beacon.location,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              SizedBox(height: 12),
              Divider(height: 1),
              SizedBox(height: 12),

              // Signal Details
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildInfoChip('RSSI', '${beacon.rssi} dBm', signalColor),
                  _buildInfoChip(
                    'Distance',
                    '~${beacon.estimatedDistance.toStringAsFixed(1)}m',
                    Colors.blue,
                  ),
                  _buildInfoChip(
                    'Proximity',
                    beacon.proximityLevel,
                    Colors.purple,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
