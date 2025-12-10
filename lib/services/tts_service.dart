import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-Speech service for voice feedback
class TtsService {
  static TtsService? _instance;
  final FlutterTts _tts = FlutterTts();
  
  bool _isInitialized = false;
  bool _isSpeaking = false;
  String _currentLanguage = 'bn-BD';
  
  // Singleton
  static TtsService get instance {
    _instance ??= TtsService._();
    return _instance!;
  }
  
  TtsService._();
  
  bool get isSpeaking => _isSpeaking;
  
  /// Initialize TTS
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Configure TTS
    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.5); // Slower for clarity
    await _tts.setPitch(1.0);
    
    // Try Bengali first
    final languages = await _tts.getLanguages;
    debugPrint('Available TTS languages: $languages');
    
    if (languages.contains('bn-BD') || languages.contains('bn_BD')) {
      await _tts.setLanguage('bn-BD');
      _currentLanguage = 'bn-BD';
    } else if (languages.contains('bn-IN') || languages.contains('bn_IN')) {
      await _tts.setLanguage('bn-IN');
      _currentLanguage = 'bn-IN';
    } else {
      await _tts.setLanguage('en-US');
      _currentLanguage = 'en-US';
      debugPrint('Bengali TTS not available, using English');
    }
    
    // Set handlers
    _tts.setStartHandler(() {
      _isSpeaking = true;
    });
    
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });
    
    _tts.setErrorHandler((error) {
      debugPrint('TTS error: $error');
      _isSpeaking = false;
    });
    
    _isInitialized = true;
  }
  
  /// Speak text
  Future<void> speak(String text) async {
    if (!_isInitialized) await initialize();
    
    // Stop any current speech
    if (_isSpeaking) {
      await stop();
    }
    
    await _tts.speak(text);
  }
  
  /// Stop speaking
  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }
  
  /// Set speech rate (0.0 - 1.0)
  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
  }
  
  /// Set language
  Future<void> setLanguage(String language) async {
    await _tts.setLanguage(language);
    _currentLanguage = language;
  }
  
  String get currentLanguage => _currentLanguage;
}
