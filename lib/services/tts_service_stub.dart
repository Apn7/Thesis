import 'package:flutter/material.dart';
import 'tts_service.dart';

/// Stub TTS implementation for web/platforms without TTS support
TtsService createTtsService() => TtsServiceStub();

class TtsServiceStub extends TtsService {
  bool _isSpeaking = false;
  String _currentLanguage = 'en-US';
  
  @override
  bool get isSpeaking => _isSpeaking;
  
  @override
  String get currentLanguage => _currentLanguage;
  
  @override
  Future<void> initialize() async {
    debugPrint('[TTS Stub] Initialized - TTS not available on this platform');
  }
  
  @override
  Future<void> speak(String text) async {
    debugPrint('[TTS Stub] Would speak: "$text"');
    _isSpeaking = true;
    // Simulate speech duration
    await Future.delayed(const Duration(milliseconds: 500));
    _isSpeaking = false;
  }
  
  @override
  Future<void> stop() async {
    _isSpeaking = false;
    debugPrint('[TTS Stub] Stopped');
  }
  
  @override
  Future<void> setSpeechRate(double rate) async {
    debugPrint('[TTS Stub] Speech rate set to $rate');
  }
  
  @override
  Future<void> setLanguage(String language) async {
    _currentLanguage = language;
    debugPrint('[TTS Stub] Language set to $language');
  }
}
