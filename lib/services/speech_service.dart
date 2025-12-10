import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

/// Service for speech-to-text functionality
class SpeechService {
  static SpeechService? _instance;
  final SpeechToText _speechToText = SpeechToText();
  
  bool _isInitialized = false;
  bool _isListening = false;
  String _lastRecognizedWords = '';
  String _currentLocaleId = 'bn_BD'; // Bengali Bangladesh
  
  // Callbacks
  Function(String text, bool isFinal)? onResult;
  Function(String status)? onStatus;
  Function(String error)? onError;
  
  // Singleton
  static SpeechService get instance {
    _instance ??= SpeechService._();
    return _instance!;
  }
  
  SpeechService._();
  
  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;
  String get lastWords => _lastRecognizedWords;
  
  /// Initialize speech recognition
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      _isInitialized = await _speechToText.initialize(
        onError: (error) {
          debugPrint('Speech error: ${error.errorMsg}');
          onError?.call(error.errorMsg);
        },
        onStatus: (status) {
          debugPrint('Speech status: $status');
          onStatus?.call(status);
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
          }
        },
      );
      
      if (_isInitialized) {
        // Check available locales
        final locales = await _speechToText.locales();
        debugPrint('Available locales: ${locales.map((l) => l.localeId).join(', ')}');
        
        // Try to find Bengali, fallback to English
        final hasBengali = locales.any((l) => l.localeId.startsWith('bn'));
        if (hasBengali) {
          _currentLocaleId = 'bn_BD';
        } else {
          _currentLocaleId = 'en_US';
          debugPrint('Bengali not available, using English');
        }
      }
      
      return _isInitialized;
    } catch (e) {
      debugPrint('Speech init error: $e');
      onError?.call('Failed to initialize speech recognition');
      return false;
    }
  }
  
  /// Start listening for speech
  Future<void> startListening() async {
    if (!_isInitialized) {
      final success = await initialize();
      if (!success) return;
    }
    
    if (_isListening) return;
    
    _lastRecognizedWords = '';
    _isListening = true;
    
    await _speechToText.listen(
      onResult: _onSpeechResult,
      localeId: _currentLocaleId,
      cancelOnError: true,
      partialResults: true,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }
  
  /// Stop listening
  Future<void> stopListening() async {
    if (!_isListening) return;
    
    await _speechToText.stop();
    _isListening = false;
  }
  
  /// Cancel listening
  Future<void> cancelListening() async {
    await _speechToText.cancel();
    _isListening = false;
    _lastRecognizedWords = '';
  }
  
  /// Handle speech result
  void _onSpeechResult(SpeechRecognitionResult result) {
    _lastRecognizedWords = result.recognizedWords;
    onResult?.call(result.recognizedWords, result.finalResult);
    
    debugPrint('Recognized: ${result.recognizedWords} (final: ${result.finalResult})');
  }
  
  /// Switch locale (Bengali/English)
  void setLocale(String localeId) {
    _currentLocaleId = localeId;
  }
  
  /// Get available locales
  Future<List<String>> getAvailableLocales() async {
    if (!_isInitialized) await initialize();
    final locales = await _speechToText.locales();
    return locales.map((l) => l.localeId).toList();
  }
}
