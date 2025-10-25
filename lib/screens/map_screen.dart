// lib/screens/map_screen.dart

import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../models/beacon_model.dart';

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final BluetoothService _bluetoothService = BluetoothService();

  // Define room positions on the map (as percentages of screen size)
  final Map<String, Offset> _roomPositions = {
    'Main Entrance': Offset(0.5, 0.2),
    'Computer Lab': Offset(0.3, 0.4),
    'Library': Offset(0.7, 0.5),
    'Staff Room': Offset(0.5, 0.7),
  };

  String _currentLocation = 'Main Entrance';

  @override
  void initState() {
    super.initState();
    _listenToBeacons();
  }

  void _listenToBeacons() {
    _bluetoothService.beaconsStream.listen((beacons) {
      if (beacons.isNotEmpty && mounted) {
        BeaconModel? nearest = _bluetoothService.getNearestBeacon();
        if (nearest != null) {
          setState(() {
            _currentLocation = nearest.location;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Department Map'),
        backgroundColor: Color(0xFF5B8DBE),
        actions: [
          IconButton(
            icon: Icon(Icons.my_location),
            onPressed: () {
              // Center on current location
              setState(() {});
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
            // Current Location Banner
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              color: Colors.blue.withOpacity(0.2),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: Colors.blue[700]),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Location',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          _currentLocation,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Map Container
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          // Background map image placeholder
                          Container(
                            width: double.infinity,
                            height: double.infinity,
                            color: Colors.grey[100],
                            child: CustomPaint(painter: MapPainter()),
                          ),

                          // Room markers
                          ..._buildRoomMarkers(constraints),

                          // Current location indicator
                          _buildCurrentLocationMarker(constraints),

                          // Legend
                          Positioned(
                            bottom: 16,
                            left: 16,
                            child: _buildLegend(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),

            // Instructions
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Your location updates automatically based on nearby beacons',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRoomMarkers(BoxConstraints constraints) {
    return _roomPositions.entries.map((entry) {
      bool isCurrentLocation = entry.key == _currentLocation;

      return Positioned(
        left: entry.value.dx * constraints.maxWidth - 25,
        top: entry.value.dy * constraints.maxHeight - 25,
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isCurrentLocation
                    ? Colors.blue.withOpacity(0.2)
                    : Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCurrentLocation ? Colors.blue : Colors.grey,
                  width: 2,
                ),
              ),
              child: Icon(
                _getIconForRoom(entry.key),
                color: isCurrentLocation ? Colors.blue : Colors.grey[600],
                size: 24,
              ),
            ),
            SizedBox(height: 4),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Text(
                entry.key.split(' ').last, // Show last word only
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isCurrentLocation
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: isCurrentLocation ? Colors.blue : Colors.grey[700],
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildCurrentLocationMarker(BoxConstraints constraints) {
    Offset? position = _roomPositions[_currentLocation];
    if (position == null) return SizedBox.shrink();

    return Positioned(
      left: position.dx * constraints.maxWidth - 15,
      top: position.dy * constraints.maxHeight - 15,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 3,
            ),
          ],
        ),
        child: Icon(Icons.person, color: Colors.white, size: 16),
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Legend',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          SizedBox(height: 8),
          _buildLegendItem(Colors.blue, 'Your Location'),
          _buildLegendItem(Colors.grey, 'Room'),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  IconData _getIconForRoom(String roomName) {
    if (roomName.contains('Entrance')) return Icons.meeting_room;
    if (roomName.contains('Lab')) return Icons.computer;
    if (roomName.contains('Library')) return Icons.local_library;
    if (roomName.contains('Staff')) return Icons.people;
    return Icons.room;
  }
}

// Custom painter for the map background
class MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw grid
    for (double i = 0; i < size.width; i += 50) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i, size.height),
        paint..color = Colors.grey[200]!,
      );
    }
    for (double i = 0; i < size.height; i += 50) {
      canvas.drawLine(
        Offset(0, i),
        Offset(size.width, i),
        paint..color = Colors.grey[200]!,
      );
    }

    // Draw building outline
    paint.color = Colors.grey[400]!;
    paint.strokeWidth = 3;
    canvas.drawRect(
      Rect.fromLTWH(20, 20, size.width - 40, size.height - 40),
      paint,
    );

    // Draw corridors
    paint.color = Colors.grey[350]!;
    paint.strokeWidth = 20;
    canvas.drawLine(
      Offset(size.width / 2, 20),
      Offset(size.width / 2, size.height - 20),
      paint,
    );
    canvas.drawLine(
      Offset(20, size.height / 2),
      Offset(size.width - 20, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
