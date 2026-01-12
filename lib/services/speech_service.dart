import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:async';

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;
  bool _isPaused = false; // New flag to control manual pausing (e.g., during TTS)

  // Stream to broadcast recognized words
  final StreamController<String> _commandController = StreamController<String>.broadcast();
  Stream<String> get commandStream => _commandController.stream;

  // Stream to broadcast listening status
  final StreamController<bool> _listeningController = StreamController<bool>.broadcast();
  Stream<bool> get listeningStream => _listeningController.stream;

  bool get isListening => _isListening;

  Future<bool> init() async {
    _isAvailable = await _speech.initialize(
      onStatus: (status) {
        print('Speech Status: $status');
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          _listeningController.add(false);
        } else if (status == 'listening') {
          _isListening = true;
          _listeningController.add(true);
        }
      },
      onError: (errorNotification) {
        print('Speech Error: $errorNotification');
        _isListening = false;
        _listeningController.add(false);
      },
    );
    return _isAvailable;
  }

  void startListening() {
    print("startListening called. Available: $_isAvailable, Listening: $_isListening, Paused: $_isPaused");
    if (_isAvailable && !_isListening && !_isPaused) {
      _speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            _commandController.add(result.recognizedWords);
          }
        },
        listenFor: Duration(seconds: 10),
        pauseFor: Duration(seconds: 3),



      );
      _isListening = true;
    }
  }

  void stopListening() {
    _isPaused = true; // Prevent auto-restart
    if (_isListening) {
      _speech.stop();
      _isListening = false;
    }
  }
  
  // Pause listening (e.g., when TTS is speaking)
  void pauseListening() {
    _isPaused = true;
    if (_isListening) {
      _speech.stop();
      _isListening = false;
    }
  }

  // Resume listening (e.g., after TTS finishes)
  void resumeListening() {
    _isPaused = false;
    startListening();
  }

  void dispose() {
    _commandController.close();
    _listeningController.close();
  }
}
