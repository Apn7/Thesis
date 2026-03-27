import 'package:flutter/material.dart';

import 'stt/audio_pipeline.dart';
import 'stt/stt_engine_factory.dart';

/// Orchestrates audio recording, voice-activity detection (VAD),
/// language detection (SLI), and speech-to-text via streaming
/// [SherpaEngine] instances.
///
/// Delegates all recording + transcription work to [AudioPipeline].
/// Partial transcription results are emitted via [onResult] with
/// `isFinal = false`; the final result is emitted with `isFinal = true`.
class SpeechService {
  static SpeechService? _instance;

  // ─── State ────────────────────────────────────────────────────────
  bool _isInitialized = false;
  bool _isListening = false;
  String _lastRecognizedWords = '';
  String _currentLocaleId = 'both';

  final AudioPipeline _pipeline = AudioPipeline();

  // ─── Callbacks ────────────────────────────────────────────────────
  Function(String text, bool isFinal)? onResult;
  Function(String status)? onStatus;
  Function(String error)? onError;

  // ─── Singleton ────────────────────────────────────────────────────
  static SpeechService get instance {
    _instance ??= SpeechService._();
    return _instance!;
  }

  SpeechService._() {
    _pipeline.onStatus = (status) => onStatus?.call(status);
    _pipeline.onError = (error) => onError?.call(error);
    _pipeline.onPartialResult = (text) => onResult?.call(text, false);
  }

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;
  String get lastWords => _lastRecognizedWords;

  // ─── Initialisation ───────────────────────────────────────────────

  /// Prepare microphone permission and pre-warm engines for the current locale.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      if (!await _pipeline.hasPermission()) {
        onError?.call('Microphone permission not granted');
        return false;
      }

      if (_currentLocaleId == 'both') {
        // Pre-warm both engines in parallel so SLI can switch instantly.
        final bn = SttEngineFactory.getEngine('bn');
        final en = SttEngineFactory.getEngine('en');
        await Future.wait([bn.initialize(), en.initialize()]);
        await SttEngineFactory.initSliDetector();
      } else {
        await SttEngineFactory.getEngine(_currentLocaleId).initialize();
      }

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('SpeechService init error: $e');
      onError?.call('Failed to initialize speech recognition: $e');
      return false;
    }
  }

  // ─── Recording + Transcription ────────────────────────────────────

  /// Begin streaming recording with automatic silence detection.
  /// Partial results arrive via [onResult] with `isFinal = false`.
  Future<void> startListening() async {
    if (!_isInitialized) {
      final success = await initialize();
      if (!success) return;
    }
    if (_isListening) return;

    _lastRecognizedWords = '';
    _isListening = true;

    try {
      final text = await _pipeline.run(locale: _currentLocaleId);
      _lastRecognizedWords = text;
      onResult?.call(text, true);
    } catch (e) {
      debugPrint('SpeechService error: $e');
      onError?.call('Transcription error: $e');
    } finally {
      _isListening = false;
    }
  }

  /// Stop recording and deliver the final result.
  Future<void> stopListening() async {
    if (!_isListening) return;
    await _pipeline.cancel();
    _isListening = false;
    onStatus?.call('done');
  }

  /// Cancel recording without delivering a result.
  Future<void> cancelListening() async {
    if (!_isListening) return;
    await _pipeline.cancel();
    _isListening = false;
    _lastRecognizedWords = '';
    onStatus?.call('notListening');
  }

  // ─── Locale ───────────────────────────────────────────────────────

  /// Switch the active locale (`'bn'`, `'en'`, or `'both'`).
  ///
  /// Cancels any active recording, disposes engines no longer needed,
  /// and resets initialisation so the correct engine is pre-warmed on
  /// the next [startListening] call.
  Future<void> setLocale(String localeId) async {
    if (localeId == _currentLocaleId) return;

    if (_isListening) await cancelListening();

    for (final locale in ['bn', 'en']) {
      if (localeId != 'both' && localeId != locale) {
        SttEngineFactory.disposeEngine(locale);
      }
    }

    if (localeId == 'both') {
      await SttEngineFactory.initSliDetector();
    } else {
      SttEngineFactory.disposeSli();
    }

    _currentLocaleId = localeId;
    _isInitialized = false;
    debugPrint('SpeechService: locale set to $localeId');
  }

  /// Available locale identifiers.
  Future<List<String>> getAvailableLocales() async => ['bn', 'en', 'both'];
}
