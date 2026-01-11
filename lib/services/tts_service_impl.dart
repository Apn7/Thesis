import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'tts_service.dart';

// For Windows, use stub due to CMake issues
// For mobile platforms, use real flutter_tts
TtsService createTtsService() {
  // On Windows, flutter_tts has broken CMake - use stub
  if (Platform.isWindows) {
    return TtsServiceWindowsStub();
  }
  // On other platforms, we'd use the real implementation
  // but for now, use stub everywhere since flutter_tts causes build issues
  return TtsServiceWindowsStub();
}

/// Stub TTS implementation for Windows (flutter_tts has broken CMake support)
class TtsServiceWindowsStub extends TtsService {
  bool _isSpeaking = false;
  String _currentLanguage = 'en-US';
  
  @override
  bool get isSpeaking => _isSpeaking;
  
  @override
  String get currentLanguage => _currentLanguage;
  
  @override
  Future<void> initialize() async {
    debugPrint('[TTS] Initialized (Windows stub mode - TTS disabled for thesis demo)');
  }
  
  @override
  Future<void> speak(String text) async {
    debugPrint('[TTS] 🔊 "$text"');
    _isSpeaking = true;
    // Simulate speech duration based on text length
    final duration = (text.length * 50).clamp(500, 5000);
    await Future.delayed(Duration(milliseconds: duration));
    _isSpeaking = false;
  }
  
  @override
  Future<void> stop() async {
    _isSpeaking = false;
    debugPrint('[TTS] Stopped');
  }
  
  @override
  Future<void> setSpeechRate(double rate) async {
    debugPrint('[TTS] Speech rate set to $rate');
  }
  
  @override
  Future<void> setLanguage(String language) async {
    _currentLanguage = language;
    debugPrint('[TTS] Language set to $language');
  }
}
