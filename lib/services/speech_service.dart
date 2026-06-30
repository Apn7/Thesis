import 'dart:async';

import 'package:flutter/material.dart';

import 'stt/audio_pipeline.dart';
import 'stt/stt_engine_factory.dart';

/// Speech-to-text orchestrator — **offline Bengali only**.
///
/// All recognition runs on-device through the sherpa-onnx streaming Zipformer
/// (Bangla) via [AudioPipeline] → [SherpaEngine]. The platform/Google
/// `speech_to_text` recognizer is intentionally NOT used: it routes audio to
/// the cloud and gives no offline guarantee. This service owns the microphone
/// → VAD → streaming transcription path end-to-end.
///
/// Push-to-talk contract (unchanged for callers):
///   * [startListening] begins capture; partial transcripts arrive via
///     `onResult(text, false)`.
///   * Releasing the button calls [stopListening], which finalizes the stream;
///     the final transcript arrives via `onResult(text, true)`.
///   * Voice-activity detection also auto-finalizes on a short pause, so a user
///     who speaks then stops gets a result without holding forever.
class SpeechService {
  static SpeechService? _instance;

  // ─── State ────────────────────────────────────────────────────────
  bool _isInitialized = false;
  bool _isListening = false; // a capture session (run) is in flight
  bool _cancelled = false; // current session's result should be suppressed
  String _lastRecognizedWords = '';

  /// Completes when the current session's [run] has fully torn down. A new
  /// [startListening] awaits this after aborting the old session, so we never
  /// end up with two recorders / overlapping runs (rapid re-press, barge-in
  /// during the tail-drain).
  Completer<void>? _sessionDone;

  // ─── Offline Bengali sherpa-onnx back-end ─────────────────────────
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
    _pipeline.onPartialResult = (text) => onResult?.call(text, false);
    _pipeline.onError = (error) {
      // Keep the raw cause in the log; speak a clean Bengali sentence.
      debugPrint('SpeechService pipeline error: $error');
      onError?.call('শুনতে পারিনি। আবার চেষ্টা করুন।');
    };
  }

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;
  String get lastWords => _lastRecognizedWords;

  // ─── Initialisation ───────────────────────────────────────────────

  /// Prepare the offline Bengali recognizer for listening.
  ///
  /// On first call this copies the bundled ~91 MB model out of assets and loads
  /// the sherpa-onnx recognizer — slow, so it's best triggered at app startup
  /// (see `main.dart`'s pre-warm) rather than on the first push-to-talk.
  /// Also requests microphone permission. Returns `false` and fires [onError]
  /// on failure.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      if (!await _pipeline.hasPermission()) {
        onError?.call('মাইক্রোফোন অনুমতি প্রয়োজন।');
        return false;
      }

      final engine = SttEngineFactory.getEngine('bn');
      final ready = engine.isInitialized || await engine.initialize();
      if (!ready) {
        onError?.call('ভয়েস মডেল লোড করা যায়নি।');
        return false;
      }

      _isInitialized = true;
      debugPrint('SpeechService: offline Bengali STT initialized.');
      return true;
    } catch (e) {
      debugPrint('SpeechService init error: $e');
      onError?.call('ভয়েস সিস্টেম চালু করা যায়নি।');
      return false;
    }
  }

  // ─── Recording + Transcription ────────────────────────────────────

  /// Begin listening for Bengali speech.
  ///
  /// Awaiting this blocks until the session completes (VAD pause, max duration,
  /// or [stopListening]/[cancelListening]). Partial transcripts stream via
  /// `onResult(text, false)`; the final transcript via `onResult(text, true)`.
  Future<void> startListening() async {
    // Barge-in / rapid re-press: abort any in-flight session and wait for it to
    // fully tear down before starting a new one, so two recorders never overlap
    // and the old (abandoned) transcript is suppressed.
    if (_isListening) {
      _cancelled = true;
      await _pipeline.cancel();
      await _sessionDone?.future;
    }

    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return;
    }

    _lastRecognizedWords = '';
    _cancelled = false;
    _isListening = true;
    final done = Completer<void>();
    _sessionDone = done;

    try {
      // Pure push-to-talk: the volume button delimits the utterance, so VAD
      // silence auto-stop is disabled — a user who pauses mid-sentence or
      // speaks softly is never cut off. Release ([stopListening]) ends it.
      final text = await _pipeline.run(autoStopOnSilence: false);
      if (_cancelled) return; // superseded by a newer session — drop result
      _lastRecognizedWords = text;
      onResult?.call(text, true);
      onStatus?.call('done');
    } catch (e) {
      debugPrint('SpeechService: session error — $e');
      if (!_cancelled) {
        // Deliver an empty final so the agent resets to idle (never hangs).
        onResult?.call('', true);
      }
    } finally {
      _isListening = false;
      if (!done.isCompleted) done.complete();
    }
  }

  /// Stop recording and finalize — the in-flight [startListening] resolves with
  /// the final transcript. Called on push-to-talk release.
  ///
  /// Uses [AudioPipeline.finish] (not [AudioPipeline.cancel]) so the mic keeps
  /// capturing for a short tail window: the audio still buffered upstream (the
  /// user's last word) drains into the recognizer before we finalize, instead
  /// of being clipped the instant the button is released.
  Future<void> stopListening() async {
    if (!_isListening) return;
    await _pipeline.finish(); // tail-drain → completes run() → finalize → text
  }

  /// Cancel recording and discard the result (no final `onResult`).
  Future<void> cancelListening() async {
    if (!_isListening) return;
    _cancelled = true;
    await _pipeline.cancel();
    _lastRecognizedWords = '';
  }

  // ─── Locale (compat shims — the app is Bengali-only) ──────────────

  /// No-op — recognition is fixed to offline Bengali. Kept for call-site
  /// compatibility.
  Future<void> setLocale(String localeId) async {
    if (_isListening) await cancelListening();
    debugPrint('SpeechService: locale fixed at bn (setLocale ignored)');
  }

  /// Available locale identifiers — Bengali only.
  Future<List<String>> getAvailableLocales() async => ['bn'];
}
