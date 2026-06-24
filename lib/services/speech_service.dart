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
  String? _resolvedBengaliLocale;

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

  /// True between [startListening] and [stopListening]/[cancelListening].
  /// While set, the Android recognizer is restarted transparently on any
  /// transient error (cold-start race, silence timeout, no-match) so that
  /// "hold to talk" actually waits for the user to speak.
  bool _pttHoldActive = false;

  /// Set inside the global [SpeechToText] error handler when a transient
  /// failure fires during PTT — picked up by the listen loop to decide
  /// whether to silently restart the recognizer instead of bubbling up.
  bool _retryRequested = false;

  /// Errors that the Android speech recognizer raises for "nothing was said"
  /// or "service wasn't ready" — these are normal in push-to-talk and must
  /// not abort the user's hold.  Anything outside this set is surfaced as a
  /// real error.
  static const Set<String> _retryableErrors = {
    'error_no_match',
    'error_speech_timeout',
    'error_client',
    'error_recognizer_busy',
  };

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
  String get _platformLocaleId {
    if (_currentLocaleId == 'en') return 'en_US';
    return _resolvedBengaliLocale ?? 'bn_BD';
  }

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

        // Locale pack missing — retry this session over the online recognizer.
        if ((error.errorMsg == 'error_language_unavailable' ||
                error.errorMsg == 'error_language_not_supported') &&
            _useOnDevice) {
          debugPrint(
            'AndroidSTT: on-device pack unavailable, retrying online.',
          );
          _useOnDevice = false;
          _languageUnavailableRetry = true;
          _completeAndroidStt();
          return;
        }

        // Transparent retry while the user is still holding the PTT button:
        // covers the cold-start race (error_client) and the no-speech-yet
        // case (error_no_match / error_speech_timeout).
        if (_pttHoldActive && _retryableErrors.contains(error.errorMsg)) {
          debugPrint(
            'AndroidSTT: transient "${error.errorMsg}" while PTT held — '
            'silent retry',
          );
          _retryRequested = true;
          _completeAndroidStt();
          return;
        }

        // Anything else is a real error — bubble up a clean spoken sentence.
        // Keep the raw Android code in the log only; TTS would otherwise try
        // to pronounce strings like "error_audio_error" literally.
        debugPrint('AndroidSTT: real error ${error.errorMsg}');
        onError?.call(
          'ভয়েস শোনা যায়নি, আবার চেষ্টা করুন। '
          "Couldn't hear you. Please try again.",
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
          // Only mark the session done from a status event when we are NOT
          // mid-PTT-retry — otherwise the retry would race against the
          // session teardown.
          if (!_retryRequested) _isListening = false;
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

    try {
      final locales = await _androidStt.locales();
      for (final locale in locales) {
        if (locale.localeId.startsWith('bn')) {
          _resolvedBengaliLocale = locale.localeId;
          debugPrint(
            'SpeechService: Found Bengali locale -> ${locale.localeId}',
          );
          break; // Prefer the first one found (e.g., bn_BD, bn_IN)
        }
      }
    } catch (e) {
      debugPrint('SpeechService: Failed to fetch locales: $e');
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
    _pttHoldActive = true;

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
  /// Loops the recognizer transparently for two reasons:
  ///   1. **Cold-start race** — the very first `listen()` after process
  ///      launch sometimes fails with `error_client` because the system
  ///      `SpeechRecognizer` service hasn't fully bound yet.  A second
  ///      attempt almost always succeeds.
  ///   2. **Push-to-talk semantics** — if the user holds the button without
  ///      speaking, Android raises `error_no_match` /
  ///      `error_speech_timeout`.  We restart the recognizer silently so
  ///      that "hold to talk" really waits for speech.
  ///
  /// The loop exits when:
  ///   - a final transcription result arrives,
  ///   - the user releases the button ([_pttHoldActive] becomes false),
  ///   - or a non-retryable error occurs.
  ///
  /// `error_language_unavailable` is also handled here — once, by flipping
  /// to the online recognizer and retrying.
  Future<void> _startAndroidListening() async {
    _languageUnavailableRetry = false;
    bool gotFinalResult = false;

    onStatus?.call('listening');

    while (true) {
      _retryRequested = false;
      final completer = Completer<void>();
      _androidSttCompleter = completer;

      await _androidStt.listen(
        onResult: (SpeechRecognitionResult result) {
          onResult?.call(result.recognizedWords, result.finalResult);
          if (result.finalResult) {
            gotFinalResult = true;
            _lastRecognizedWords = result.recognizedWords;
            _completeAndroidStt();
          }
        },
        // Long windows on purpose — the PTT button controls when listening
        // stops, not these timeouts.  They only act as a hard ceiling.
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 30),
        localeId: _platformLocaleId,
        listenOptions: SpeechListenOptions(
          cancelOnError: true,
          partialResults: true,
          onDevice: _useOnDevice,
        ),
      );

      await completer.future;

      // (a) On-device pack missing → retry online (one-shot, then sticky).
      if (_languageUnavailableRetry) {
        _languageUnavailableRetry = false;
        debugPrint('AndroidSTT: retrying with onDevice=false');
        continue;
      }

      // (b) User got their result → done.
      if (gotFinalResult) break;

      // (c) Transient error while PTT still held → silent restart.
      if (_pttHoldActive && _retryRequested) {
        // Tiny delay — Android needs a moment to release the recognizer
        // before we can rebind it.
        await Future<void>.delayed(const Duration(milliseconds: 80));
        continue;
      }

      // (d) Released button or unrecoverable error → exit.
      break;
    }

    if (!gotFinalResult) {
      onResult?.call(_lastRecognizedWords, true);
    }

    onStatus?.call('done');
    _isListening = false;
    _pttHoldActive = false;
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

    // PTT released → break the retry loop in _startAndroidListening so the
    // recognizer doesn't auto-restart after stop().
    _pttHoldActive = false;

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

    _pttHoldActive = false;
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
