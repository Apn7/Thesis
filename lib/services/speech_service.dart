import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'stt/audio_pipeline.dart';
import 'stt/stt_engine_factory.dart';

/// Orchestrates speech-to-text with two back-ends:
///
/// - **Bengali (`'bn'`):** offline streaming via [AudioPipeline] → sherpa-onnx
///   zipformer. Full streaming partial results, no network required.
///
/// - **English (`'en'`):** Android's built-in speech recognizer via the
///   `speech_to_text` package. Uses the on-device (offline) English model that
///   ships with most Android phones. No model bundling needed.
///
/// The active back-end is selected by [setLocale].  Switch happens on the next
/// [startListening] call — no app restart required.
///
/// Partial transcription results are emitted via [onResult] with
/// `isFinal = false`; the final result is emitted with `isFinal = true`.
class SpeechService {
  static SpeechService? _instance;

  // ─── State ────────────────────────────────────────────────────────
  bool _isInitialized = false;
  bool _isListening = false;
  String _lastRecognizedWords = '';
  String _currentLocaleId = 'bn'; // Bengali is the default

  // ─── Bengali back-end ─────────────────────────────────────────────
  final AudioPipeline _pipeline = AudioPipeline();

  // ─── English back-end ─────────────────────────────────────────────
  final SpeechToText _androidStt = SpeechToText();
  bool _androidSttAvailable = false;

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
    _pipeline.onStatus = (status) => onStatus?.call(status);
    _pipeline.onError = (error) => onError?.call(error);
    _pipeline.onPartialResult = (text) => onResult?.call(text, false);
  }

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;
  String get lastWords => _lastRecognizedWords;

  // ─── Initialisation ───────────────────────────────────────────────

  /// Prepare the active back-end for listening.
  ///
  /// Must succeed before [startListening] is called; called automatically
  /// if skipped.  Returns `false` and fires [onError] on failure.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      if (_currentLocaleId == 'en') {
        return await _initAndroidStt();
      } else {
        if (!await _pipeline.hasPermission()) {
          onError?.call(
            'মাইক্রোফোনের অনুমতি দেওয়া হয়নি / Microphone permission not granted',
          );
          return false;
        }
        await SttEngineFactory.getEngine('bn').initialize();
        _isInitialized = true;
        return true;
      }
    } catch (e) {
      debugPrint('SpeechService init error: $e');
      onError?.call(
        'ভয়েস রিকগনিশন শুরু করতে ব্যর্থ / Failed to initialize speech recognition: $e',
      );
      return false;
    }
  }

  /// Initialize the Android built-in STT back-end.
  ///
  /// Sets global [onError]/[onStatus] callbacks on the [SpeechToText]
  /// instance — these fire for every session, not just initialization.
  Future<bool> _initAndroidStt() async {
    _androidSttAvailable = await _androidStt.initialize(
      onError: (SpeechRecognitionError error) {
        debugPrint(
          'AndroidSTT error: ${error.errorMsg} (permanent=${error.permanent})',
        );
        onError?.call(
          'ইংরেজি ভয়েস রিকগনিশন ত্রুটি / English STT error: ${error.errorMsg}',
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
        'এই ডিভাইসে ইংরেজি ভয়েস রিকগনিশন সমর্থিত নয়।\n'
        'সেটিংস থেকে বাংলা মোড ব্যবহার করুন।\n\n'
        'English speech recognition is not available on this device.\n'
        'Please switch to Bangla mode in Settings.',
      );
      return false;
    }

    _isInitialized = true;
    debugPrint('SpeechService: Android STT initialized.');
    return true;
  }

  // ─── Recording + Transcription ────────────────────────────────────

  /// Begin listening for speech.
  ///
  /// For Bengali: streams PCM audio through the sherpa-onnx pipeline.
  /// For English: delegates to Android's built-in speech recognizer.
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

    if (_currentLocaleId == 'en') {
      await _startAndroidListening();
    } else {
      try {
        final text = await _pipeline.run();
        _lastRecognizedWords = text;
        onResult?.call(text, true);
      } catch (e) {
        debugPrint('SpeechService Bengali error: $e');
        onError?.call('ট্রান্সক্রিপশন ত্রুটি / Transcription error: $e');
      } finally {
        _isListening = false;
      }
    }
  }

  /// Start an Android STT session and wait for it to complete.
  Future<void> _startAndroidListening() async {
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
      localeId: 'en_US',
      listenOptions: SpeechListenOptions(
        cancelOnError: true,
        partialResults: true,
        onDevice: false, // offline English pack rarely installed; allow online
      ),
    );

    // Block until the session ends (final result, silence, timeout, or cancel).
    await completer.future;

    // If the session timed out with no speech, emit empty final result so
    // VoiceNavigationService can handle it gracefully.
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

    if (_currentLocaleId == 'en') {
      // stop() asks the recognizer for a final result; callbacks handle cleanup.
      await _androidStt.stop();
    } else {
      await _pipeline.cancel();
      _isListening = false;
      onStatus?.call('done');
    }
  }

  /// Cancel recording without delivering a result.
  Future<void> cancelListening() async {
    if (!_isListening) return;

    if (_currentLocaleId == 'en') {
      await _androidStt.cancel();
      _completeAndroidStt();
    } else {
      await _pipeline.cancel();
    }

    _isListening = false;
    _lastRecognizedWords = '';
    onStatus?.call('notListening');
  }

  // ─── Locale ───────────────────────────────────────────────────────

  /// Switch the active back-end to [localeId] (`'bn'` or `'en'`).
  ///
  /// Cancels any active session, disposes the current engine, and resets
  /// initialisation so the new back-end is prepared on the next
  /// [startListening] call.
  Future<void> setLocale(String localeId) async {
    assert(
      localeId == 'bn' || localeId == 'en',
      'setLocale: localeId must be bn or en',
    );
    if (localeId == _currentLocaleId) return;

    if (_isListening) await cancelListening();

    // Dispose the Bengali engine if we're leaving that path.
    if (_currentLocaleId == 'bn') {
      SttEngineFactory.disposeEngine('bn');
    }
    // Android STT doesn't hold persistent resources between sessions.

    _currentLocaleId = localeId;
    _isInitialized = false;
    _androidSttAvailable = false;
    debugPrint('SpeechService: locale set to $localeId');
  }

  /// Available locale identifiers.
  Future<List<String>> getAvailableLocales() async => ['bn', 'en'];
}
