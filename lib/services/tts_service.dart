
// Conditionally import flutter_tts only for non-Windows platforms
// For Windows, we use a stub implementation due to CMake issues
import 'tts_service_stub.dart' if (dart.library.io) 'tts_service_impl.dart';

/// Text-to-Speech service for voice feedback
abstract class TtsService {
  static TtsService? _instance;
  
  // Singleton
  static TtsService get instance {
    _instance ??= createTtsService();
    return _instance!;
  }
  
  bool get isSpeaking;
  String get currentLanguage;
  
  Future<void> initialize();
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> setSpeechRate(double rate);
  Future<void> setLanguage(String language);
}
