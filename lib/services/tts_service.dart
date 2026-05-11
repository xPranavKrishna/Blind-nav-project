import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TTS SERVICE  –  updated to latest flutter_tts API (Jan 2026)
//
// Key changes from old version:
//  • setStartHandler()      → startHandler = (direct property, modern API)
//  • setCompletionHandler() → completionHandler = (direct property)
//  • setPauseHandler()      → pauseHandler = (direct property)
//  • cancelHandler          → NEW: fires when stop() is called mid-speech
//  • progressHandler        → NEW: word-by-word progress tracking
//  • awaitSpeakCompletion() → makes speak() truly await until finished
//  • setAudioAttributesForNavigation() → NEW: Android audio focus for nav apps
//    (ducking music, routing through navigation audio stream)
// ─────────────────────────────────────────────────────────────────────────────

class TtsService {
  final FlutterTts _tts = FlutterTts();

  // Public state
  bool _isSpeaking = false;
  String _currentWord = "";

  bool get isSpeaking  => _isSpeaking;
  String get currentWord => _currentWord; // useful for UI word highlighting

  // ── INIT ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    // ── Core settings ────────────────────────────────────────────────────────
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.45);  // Slightly slower than default for clarity
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // ── Android: route audio through navigation stream ───────────────────────
    // This is the correct modern way for navigation apps on Android.
    // It ducks music/media volume and uses the navigation audio focus,
    // so the TTS is heard clearly even when music is playing.
    if (Platform.isAndroid) {
      await _tts.setAudioAttributesForNavigation();
    }

    // ── awaitSpeakCompletion ─────────────────────────────────────────────────
    // Makes speak() return a Future that completes ONLY when speech finishes.
    // Without this, speak() returns immediately and you can't await it.
    await _tts.awaitSpeakCompletion(true);

    // ── Handlers (modern direct property assignment) ─────────────────────────
    _tts.startHandler = () {
      _isSpeaking = true;
    };

    _tts.completionHandler = () {
      _isSpeaking = false;
      _currentWord = "";
    };

    // cancelHandler fires when stop() interrupts speech mid-sentence
    _tts.cancelHandler = () {
      _isSpeaking = false;
      _currentWord = "";
    };

    _tts.pauseHandler = () {
      _isSpeaking = false;
    };

    _tts.continueHandler = () {
      _isSpeaking = true;
    };

    // progressHandler: tracks which word is being spoken right now
    // Useful if you want to highlight the current instruction word in UI
    _tts.progressHandler = (String text, int startOffset, int endOffset, String word) {
      _currentWord = word;
    };

    // errorHandler still uses setErrorHandler() method (typed ErrorHandler)
    _tts.setErrorHandler((dynamic msg) {
      _isSpeaking  = false;
      _currentWord = "";
    });
  }

  // ── PUBLIC API ────────────────────────────────────────────────────────────

  /// Normal speak – queues behind any current speech.
  /// Awaitable: returns only after speech completes (because awaitSpeakCompletion = true).
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.speak(text);
  }

  /// Prioritized speak – immediately stops current speech then speaks [text].
  /// Use this for obstacle alerts and turn instructions.
  Future<void> speakPrioritized(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();           // interrupt anything currently speaking
    await _tts.speak(text);      // speak the new instruction
  }

  /// Stop any ongoing speech immediately.
  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking  = false;
    _currentWord = "";
  }

  /// Pause speech (iOS/Android).
  Future<void> pause() async {
    await _tts.pause();
  }

  // ── OPTIONAL HELPERS ─────────────────────────────────────────────────────

  /// Change speech rate at runtime.
  /// [rate] 0.0–1.0  (0.45 = clear navigation pace, 1.0 = fast)
  Future<void> setRate(double rate) async {
    await _tts.setSpeechRate(rate.clamp(0.0, 1.0));
  }

  /// Change pitch at runtime.
  /// [pitch] 0.5–2.0  (1.0 = normal)
  Future<void> setPitch(double pitch) async {
    await _tts.setPitch(pitch.clamp(0.5, 2.0));
  }

  /// Get all available voices on the device (Android/iOS).
  Future<List<dynamic>> getVoices() async {
    return await _tts.getVoices ?? [];
  }

  /// Dispose – call in widget's dispose() if TtsService is widget-scoped.
  Future<void> dispose() async {
    await _tts.stop();
  }
}