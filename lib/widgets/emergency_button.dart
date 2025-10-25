// lib/widgets/emergency_button.dart

import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../services/tts_service.dart';

class EmergencyButton extends StatefulWidget {
  final VoidCallback? onEmergencyTriggered;

  const EmergencyButton({Key? key, this.onEmergencyTriggered})
    : super(key: key);

  @override
  _EmergencyButtonState createState() => _EmergencyButtonState();
}

class _EmergencyButtonState extends State<EmergencyButton>
    with SingleTickerProviderStateMixin {
  final TtsService _tts = TtsService();
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _triggerEmergency() async {
    setState(() => _isPressed = true);
    _controller.forward();

    // Vibrate
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(duration: 500, amplitude: 255);
    }

    // Speak emergency message
    await _tts.speakEmergencyAlert();

    // Show dialog
    if (mounted) {
      _showEmergencyDialog();
    }

    // Call callback
    widget.onEmergencyTriggered?.call();

    await Future.delayed(Duration(milliseconds: 200));
    _controller.reverse();
    if (mounted) {
      setState(() => _isPressed = false);
    }
  }

  void _showEmergencyDialog() {
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Emergency alert has been sent!',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 12),
              Text(
                '📞 Calling caretaker...\n'
                '📍 Sharing your location...\n'
                '🚨 Help is on the way!',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 16),
              LinearProgressIndicator(
                backgroundColor: Colors.red[100],
                valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _tts.speak("Emergency cancelled");
              },
              child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
            ),
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
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Colors.red[600]!, Colors.red[800]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _triggerEmergency,
                borderRadius: BorderRadius.circular(35),
                child: Center(
                  child: Icon(
                    Icons.crisis_alert,
                    color: Colors.white,
                    size: 35,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
