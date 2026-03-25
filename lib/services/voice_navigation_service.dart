import 'package:flutter/material.dart';
import 'groq_service.dart';
import 'speech_service.dart';
import 'tts_service.dart';

/// Navigation actions that can be triggered by voice
enum VoiceAction {
  navigateHome,
  navigateLocation,
  navigateSettings,
  navigateHelp,
  speakBattery,
  speakTime,
  none,
}

/// Orchestrates speech recognition, Groq AI, and navigation
class VoiceNavigationService extends ChangeNotifier {
  static VoiceNavigationService? _instance;

  final GroqService _groq = GroqService.instance;
  final SpeechService _speech = SpeechService.instance;
  final TtsService _tts = TtsService.instance;

  bool _isListening = false;
  bool _isProcessing = false;
  String _currentTranscript = '';
  String _lastResponse = '';
  String _error = '';

  // Navigation callback
  Function(VoiceAction action)? onNavigationAction;

  // Singleton
  static VoiceNavigationService get instance {
    _instance ??= VoiceNavigationService._();
    return _instance!;
  }

  VoiceNavigationService._() {
    _setupSpeechCallbacks();
  }

  // Getters
  bool get isListening => _isListening;
  bool get isProcessing => _isProcessing;
  String get currentTranscript => _currentTranscript;
  String get lastResponse => _lastResponse;
  String get error => _error;

  /// Initialize all services
  Future<void> initialize() async {
    // Groq service doesn't need initialization

    try {
      await _speech.initialize();
    } catch (e) {
      debugPrint('Speech init error: $e');
    }

    try {
      await _tts.initialize();
    } catch (e) {
      debugPrint('TTS init error: $e');
    }
  }

  /// Setup speech recognition callbacks
  void _setupSpeechCallbacks() {
    _speech.onResult = (text, isFinal) {
      _currentTranscript = text;
      notifyListeners();

      if (isFinal && text.isNotEmpty) {
        _processCommand(text);
      }
    };

    _speech.onStatus = (status) {
      if (status == 'processing') {
        _isProcessing = true;
        notifyListeners();
      } else if (status == 'done' || status == 'notListening') {
        _isListening = false;
        notifyListeners();
      }
    };

    _speech.onError = (error) {
      _error = error;
      _isListening = false;
      notifyListeners();
    };
  }

  /// Start listening for voice commands
  Future<void> startListening() async {
    if (_isListening || _isProcessing) return;

    _error = '';
    _currentTranscript = '';
    _isListening = true;
    notifyListeners();

    await _speech.startListening();
  }

  /// Stop listening
  Future<void> stopListening() async {
    await _speech.stopListening();
    _isListening = false;
    notifyListeners();
  }

  /// Process the voice command through Groq LLaMA
  Future<void> _processCommand(String text) async {
    if (text.isEmpty) return;

    _isProcessing = true;
    _isListening = false;
    notifyListeners();

    try {
      final response = await _groq.processCommand(text);
      _lastResponse = response.spokenResponse;

      // Speak the response
      await _tts.speak(response.spokenResponse);

      // Trigger navigation action
      final action = _parseAction(response.action);
      if (action != VoiceAction.none) {
        onNavigationAction?.call(action);
      }
    } catch (e) {
      _error = 'Processing error: $e';
      await _tts.speak(
        'দুঃখিত, একটি সমস্যা হয়েছে। Sorry, there was an error.',
      );
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Parse action string to enum
  VoiceAction _parseAction(String actionStr) {
    switch (actionStr.toLowerCase()) {
      case 'navigate_home':
        return VoiceAction.navigateHome;
      case 'navigate_location':
        return VoiceAction.navigateLocation;
      case 'navigate_settings':
        return VoiceAction.navigateSettings;
      case 'navigate_help':
        return VoiceAction.navigateHelp;
      case 'speak_battery':
        return VoiceAction.speakBattery;
      case 'speak_time':
        return VoiceAction.speakTime;
      default:
        return VoiceAction.none;
    }
  }

  /// Speak a message directly
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  /// Send a text command directly (for testing)
  Future<void> sendTextCommand(String text) async {
    _currentTranscript = text;
    notifyListeners();
    await _processCommand(text);
  }
}
