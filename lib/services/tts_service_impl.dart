import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'tts_service.dart';

TtsService createTtsService() {
  if (Platform.isWindows) {
    return TtsServiceWindowsStub();
  }
  return TtsServiceMobile();
}

// ── Android / mobile implementation ──────────────────────────────────────────

class TtsServiceMobile extends TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  String _currentLanguage = 'bn-BD';

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  String get currentLanguage => _currentLanguage;

  @override
  Future<void> initialize() async {
    await _tts.setLanguage(_currentLanguage);
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    // Make speak() await actual completion, so the agent's `speaking` state is
    // accurate and a barge-in (stop()) resolves the in-flight speak() at once.
    await _tts.awaitSpeakCompletion(true);

    _tts.setStartHandler(() => _isSpeaking = true);
    _tts.setCompletionHandler(() => _isSpeaking = false);
    _tts.setCancelHandler(() => _isSpeaking = false);
    _tts.setErrorHandler((msg) {
      _isSpeaking = false;
      debugPrint('[TTS] Error: $msg');
    });

    debugPrint('[TTS] Initialized (Android, language: $_currentLanguage)');
  }

  @override
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    // Stop any ongoing speech before starting new one so alerts never queue up.
    await _tts.stop();
    await _tts.speak(text);
    debugPrint('[TTS] 🔊 "$text"');
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  @override
  Future<void> setLanguage(String language) async {
    _currentLanguage = language;
    await _tts.setLanguage(language);
  }
}

// ── Windows stub (flutter_tts CMake unsupported on Windows) ──────────────────

class TtsServiceWindowsStub extends TtsService {
  bool _isSpeaking = false;
  String _currentLanguage = 'bn-BD';

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  String get currentLanguage => _currentLanguage;

  @override
  Future<void> initialize() async {
    debugPrint('[TTS] Initialized (Windows stub — audio disabled)');
  }

  @override
  Future<void> speak(String text) async {
    debugPrint('[TTS] 🔊 "$text"');
    _isSpeaking = true;
    final duration = (text.length * 50).clamp(500, 5000);
    await Future.delayed(Duration(milliseconds: duration));
    _isSpeaking = false;
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
  }

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> setLanguage(String language) async {
    _currentLanguage = language;
  }
}
