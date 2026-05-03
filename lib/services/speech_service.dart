import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

// Sherpa-onnx offline Bengali STT — currently disabled.  The pipeline files
// remain in lib/services/stt/ so this can be re-enabled later without
// rewriting anything.  See the commented blocks below for the original
// dual-engine implementation.
// import 'stt/audio_pipeline.dart';
// import 'stt/stt_engine_factory.dart';

/// Speech-to-text orchestrator.
///
/// Currently both `'bn'` (Bengali) and `'en'` (English) route through the
/// platform/Google built-in speech recognizer via the `speech_to_text`
/// package.  Bengali uses locale `bn-BD` and falls back to the online
/// recognizer if the on-device pack isn't installed; English uses `en_US`.
///
/// The original offline Bengali back-end (sherpa-onnx Zipformer) is kept in
/// commented-out form below so it can be re-attached without rebuilding from
/// scratch.
class SpeechService {
  static SpeechService? _instance;

  // ─── State ────────────────────────────────────────────────────────
  bool _isInitialized = false;
  bool _isListening = false;
  String _lastRecognizedWords = '';
  String _currentLocaleId = 'bn'; // Bengali is the default

  // ─── Sherpa offline Bengali back-end (DISABLED) ───────────────────
  // final AudioPipeline _pipeline = AudioPipeline();

  // ─── Google / Android built-in STT ────────────────────────────────
  final SpeechToText _androidStt = SpeechToText();
  bool _androidSttAvailable = false;

  /// Whether to request on-device recognition.  Starts true; flipped to false
  /// permanently after the first [error_language_unavailable] so subsequent
  /// sessions fall back to the online recognizer automatically.
  bool _useOnDevice = true;

  /// Set when [error_language_unavailable] fires mid-session so
  /// [_startAndroidListening] can retry with onDevice:false.
  bool _languageUnavailableRetry = false;

  /// Completer used to block [startListening] until the Android STT session
  /// finishes (either a final result, silence timeout, or cancellation).
  Completer<void>? _androidSttCompleter;

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
    // Sherpa pipeline wiring — disabled along with the Bengali offline engine.
    // _pipeline.onStatus = (status) => onStatus?.call(status);
    // _pipeline.onError = (error) => onError?.call(error);
    // _pipeline.onPartialResult = (text) => onResult?.call(text, false);
  }

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;
  String get lastWords => _lastRecognizedWords;

  /// Resolve the platform STT locale for the active app locale.
  String get _platformLocaleId =>
      _currentLocaleId == 'en' ? 'en_US' : 'bn-BD';

  // ─── Initialisation ───────────────────────────────────────────────

  /// Prepare the Google/Android speech recognizer for listening.
  ///
  /// Returns `false` and fires [onError] on failure.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      return await _initAndroidStt();

      // Sherpa offline Bengali path — disabled.
      // if (_currentLocaleId == 'bn') {
      //   if (!await _pipeline.hasPermission()) {
      //     onError?.call(
      //       'মাইক্রোফোনের অনুমতি দেওয়া হয়নি / Microphone permission not granted',
      //     );
      //     return false;
      //   }
      //   await SttEngineFactory.getEngine('bn').initialize();
      //   _isInitialized = true;
      //   return true;
      // }
    } catch (e) {
      debugPrint('SpeechService init error: $e');
      onError?.call(
        'ভয়েস রিকগনিশন শুরু করতে ব্যর্থ / Failed to initialize speech recognition: $e',
      );
      return false;
    }
  }

  /// Initialize the Android/Google built-in STT back-end.
  ///
  /// Sets global [onError]/[onStatus] callbacks on the [SpeechToText]
  /// instance — these fire for every session, not just initialization.
  Future<bool> _initAndroidStt() async {
    _androidSttAvailable = await _androidStt.initialize(
      onError: (SpeechRecognitionError error) {
        debugPrint(
          'AndroidSTT error: ${error.errorMsg} (permanent=${error.permanent})',
        );
        if (error.errorMsg == 'error_language_unavailable' && _useOnDevice) {
          // On-device pack not installed — retry this session without it.
          debugPrint('AndroidSTT: on-device pack unavailable, will retry online.');
          _useOnDevice = false;
          _languageUnavailableRetry = true;
          _completeAndroidStt();
          return;
        }
        onError?.call(
          'ভয়েস রিকগনিশন ত্রুটি / STT error: ${error.errorMsg}',
        );
        _isListening = false;
        _completeAndroidStt();
      },
      onStatus: (String status) {
        debugPrint('AndroidSTT status: $status');
        if (status == SpeechToText.listeningStatus) {
          onStatus?.call('listening');
        } else if (status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus) {
          _isListening = false;
          _completeAndroidStt();
        }
      },
    );

    if (!_androidSttAvailable) {
      onError?.call(
        'এই ডিভাইসে ভয়েস রিকগনিশন সমর্থিত নয়।\n'
        'Speech recognition is not available on this device.',
      );
      return false;
    }

    _isInitialized = true;
    debugPrint('SpeechService: Android STT initialized.');
    return true;
  }

  // ─── Recording + Transcription ────────────────────────────────────

  /// Begin listening for speech via Google/Android STT.
  ///
  /// Partial results arrive via [onResult](text, false).
  /// Final result arrives via [onResult](text, true).
  /// Awaiting this method blocks until the full session is complete.
  Future<void> startListening() async {
    if (!_isInitialized) {
      final success = await initialize();
      if (!success) return;
    }
    if (_isListening) return;

    _lastRecognizedWords = '';
    _isListening = true;

    await _startAndroidListening();

    // Sherpa offline Bengali path — disabled.
    // if (_currentLocaleId == 'bn') {
    //   try {
    //     final text = await _pipeline.run();
    //     _lastRecognizedWords = text;
    //     onResult?.call(text, true);
    //   } catch (e) {
    //     debugPrint('SpeechService Bengali error: $e');
    //     onError?.call('ট্রান্সক্রিপশন ত্রুটি / Transcription error: $e');
    //   } finally {
    //     _isListening = false;
    //   }
    // }
  }

  /// Start an Android STT session and wait for it to complete.
  ///
  /// If [error_language_unavailable] fires (on-device pack not installed),
  /// the session retries once with [onDevice:false] (online recognizer).
  /// After the first retry [_useOnDevice] stays false for all future sessions.
  Future<void> _startAndroidListening() async {
    _languageUnavailableRetry = false;

    final completer = Completer<void>();
    _androidSttCompleter = completer;
    bool gotFinalResult = false;

    onStatus?.call('listening');

    await _androidStt.listen(
      onResult: (SpeechRecognitionResult result) {
        onResult?.call(result.recognizedWords, result.finalResult);
        if (result.finalResult) {
          gotFinalResult = true;
          _lastRecognizedWords = result.recognizedWords;
          _completeAndroidStt();
        }
      },
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 2),
      localeId: _platformLocaleId,
      listenOptions: SpeechListenOptions(
        cancelOnError: true,
        partialResults: true,
        onDevice: _useOnDevice,
      ),
    );

    await completer.future;

    // On-device pack unavailable — retry transparently with online recognizer.
    if (_languageUnavailableRetry) {
      _languageUnavailableRetry = false;
      debugPrint('AndroidSTT: retrying with onDevice=false');
      await _startAndroidListening();
      return;
    }

    if (!gotFinalResult) {
      onResult?.call(_lastRecognizedWords, true);
    }

    onStatus?.call('done');
    _isListening = false;
  }

  /// Complete (or no-op if already done) the active Android STT completer.
  void _completeAndroidStt() {
    final c = _androidSttCompleter;
    _androidSttCompleter = null;
    if (!(c?.isCompleted ?? true)) c!.complete();
  }

  /// Stop recording and request the final result.
  Future<void> stopListening() async {
    if (!_isListening) return;

    // stop() asks the recognizer for a final result; callbacks handle cleanup.
    await _androidStt.stop();

    // Sherpa offline path — disabled.
    // if (_currentLocaleId == 'bn') {
    //   await _pipeline.cancel();
    //   _isListening = false;
    //   onStatus?.call('done');
    // }
  }

  /// Cancel recording without delivering a result.
  Future<void> cancelListening() async {
    if (!_isListening) return;

    await _androidStt.cancel();
    _completeAndroidStt();

    // Sherpa offline path — disabled.
    // if (_currentLocaleId == 'bn') {
    //   await _pipeline.cancel();
    // }

    _isListening = false;
    _lastRecognizedWords = '';
    onStatus?.call('notListening');
  }

  // ─── Locale ───────────────────────────────────────────────────────

  /// Switch the active locale to [localeId] (`'bn'` or `'en'`).
  ///
  /// Cancels any active session.  Both locales share the Android STT
  /// recognizer, so we do not need to dispose engines — just reset the flag
  /// so the next [startListening] reconfigures with the new locale.
  Future<void> setLocale(String localeId) async {
    assert(
      localeId == 'bn' || localeId == 'en',
      'setLocale: localeId must be bn or en',
    );
    if (localeId == _currentLocaleId) return;

    if (_isListening) await cancelListening();

    // Sherpa engine disposal — disabled along with the Bengali offline path.
    // if (_currentLocaleId == 'bn') {
    //   SttEngineFactory.disposeEngine('bn');
    // }

    _currentLocaleId = localeId;
    debugPrint('SpeechService: locale set to $localeId');
  }

  /// Available locale identifiers.
  Future<List<String>> getAvailableLocales() async => ['bn', 'en'];
}
