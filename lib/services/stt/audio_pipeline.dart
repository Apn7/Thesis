import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'stt_engine_factory.dart';

/// Coordinates streaming audio capture, VAD, and Bengali sherpa-onnx
/// transcription into a single pipeline.
///
/// Audio chunks are fed to the recognizer **as they arrive** from the
/// microphone, so partial results are available in real-time and the
/// streaming nature of the zipformer model is fully exploited.
///
/// This pipeline handles the Bengali ('bn') path only.
/// English STT uses the Android built-in recognizer (see [SpeechService]).
///
/// Usage:
/// ```dart
/// final pipeline = AudioPipeline();
/// pipeline.onPartialResult = (text) => print('partial: $text');
/// final text = await pipeline.run();
/// ```
class AudioPipeline {
  // ─── VAD constants (only used when autoStopOnSilence is true) ─────────
  static const double _silenceThresholdDb = -26.0;
  static const Duration _silenceDuration = Duration(milliseconds: 1500);
  static const Duration _warmupSkip = Duration(seconds: 1);
  static const Duration _amplitudePollInterval = Duration(milliseconds: 200);

  /// Hard safety ceiling: even in pure push-to-talk a stuck-held button (or a
  /// dropped key-up event) must not record forever. Generous so it never
  /// truncates a real, deliberately long command.
  static const Duration _maxRecordDuration = Duration(seconds: 30);

  /// After the push-to-talk button is released we keep capturing for this long
  /// before finalizing, so the audio still buffered upstream (OS capture buffer
  /// + Dart stream queue) — i.e. the user's *final word* — drains into the
  /// recognizer. Without it, releasing the button instantly kills the mic and
  /// the tail of the utterance is lost. Sized just above typical Android
  /// capture latency.
  static const Duration _tailDrainDuration = Duration(milliseconds: 500);

  // ─── Callbacks ────────────────────────────────────────────────────
  Function(String status)? onStatus;
  Function(String error)? onError;

  /// Called with each new partial transcript during recording.
  Function(String text)? onPartialResult;

  final AudioRecorder _recorder = AudioRecorder();
  Completer<void>? _stopCompleter;

  // ─── Public API ───────────────────────────────────────────────────

  /// Run the full pipeline: record → stream to Bengali STT → return final text.
  ///
  /// Audio chunks are fed into the streaming recognizer incrementally.
  /// [onPartialResult] fires whenever the partial transcript changes.
  /// Returns the final transcript, or an empty string on failure.
  ///
  /// [autoStopOnSilence]: when true, a [_silenceDuration] pause auto-ends the
  /// utterance (hands-free). For **push-to-talk** the caller passes `false`:
  /// the physical button delimits the utterance ([cancel] on release), so a
  /// blind user who pauses mid-sentence or speaks softly is never cut off. The
  /// only automatic stop in that mode is the [_maxRecordDuration] safety
  /// ceiling.
  Future<String> run({bool autoStopOnSilence = true}) async {
    onStatus?.call('listening');

    try {
      final engine = SttEngineFactory.getEngine('bn');
      if (!engine.isInitialized) await engine.initialize();
      engine.resetStream();

      final pcmStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      final completer = Completer<void>();
      _stopCompleter = completer;

      // ── VAD state + listener (only wired when autoStopOnSilence) ──
      DateTime? recordingStart;
      bool heardSpeech = false;
      Timer? silenceTimer;
      StreamSubscription<Amplitude>? ampSubscription;

      if (autoStopOnSilence) {
        ampSubscription = _recorder
            .onAmplitudeChanged(_amplitudePollInterval)
            .listen((amp) {
              recordingStart ??= DateTime.now();
              final elapsed = DateTime.now().difference(recordingStart!);
              if (elapsed < _warmupSkip) return;

              if (amp.current < _silenceThresholdDb) {
                if (heardSpeech) {
                  silenceTimer ??= Timer(_silenceDuration, () {
                    if (!completer.isCompleted) completer.complete();
                  });
                }
              } else {
                heardSpeech = true;
                silenceTimer?.cancel();
                silenceTimer = null;
              }
            });
      }

      // Hard safety ceiling — a stuck button can never record forever.
      final maxTimer = Timer(_maxRecordDuration, () {
        if (!completer.isCompleted) completer.complete();
      });

      // ── PCM streaming listener ──
      String lastPartial = '';
      final pcmSubscription = pcmStream.listen((rawChunk) {
        final samples = _convertChunk(rawChunk);
        if (samples.isEmpty) return;

        engine.acceptSamples(samples, 16000);
        final partial = engine.getPartialResult();
        if (partial != lastPartial) {
          lastPartial = partial;
          onPartialResult?.call(partial);
        }
      });

      // ── Wait for button release ([cancel]), the safety ceiling, or (in
      //    hands-free mode) a VAD silence gap ──
      await completer.future;
      _stopCompleter = null;

      silenceTimer?.cancel();
      maxTimer.cancel();
      await ampSubscription?.cancel();
      await pcmSubscription.cancel();
      try {
        await _recorder.stop();
      } catch (_) {}

      // ── Finalize transcription ──
      onStatus?.call('processing');
      // Instrumentation: how long the final flush/decode takes after the tail
      // has drained. If this is consistently small (<~150ms) the recognizer is
      // keeping up in real time and any remaining lag is capture latency (tune
      // the tail); if it's large (>~300ms) decode is backlogged and we should
      // raise numThreads / confirm the int8 encoder. See SherpaModelConfig.
      final sw = Stopwatch()..start();
      final finalText = engine.finalizeStream();
      sw.stop();
      debugPrint(
        'AudioPipeline: finalizeStream took ${sw.elapsedMilliseconds}ms '
        '→ "$finalText"',
      );
      onStatus?.call('done');
      return finalText;
    } catch (e) {
      debugPrint('AudioPipeline error: $e');
      onError?.call('শুনতে সমস্যা হয়েছে।');
      try {
        await _recorder.stop();
      } catch (_) {}
      onStatus?.call('done');
      return '';
    }
  }

  /// Whether microphone permission has been granted.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Finish a push-to-talk utterance cleanly (button released, keep the result).
  ///
  /// Unlike [cancel], this does NOT stop the mic immediately. It keeps the
  /// recorder running for [tail] so the audio already buffered upstream (the
  /// user's last word) keeps flowing into the recognizer, then signals [run] to
  /// finalize. This is what stops words from being clipped at release.
  Future<void> finish({Duration tail = _tailDrainDuration}) async {
    final completer = _stopCompleter;
    if (completer == null || completer.isCompleted) return;
    // Reflect "released → wrapping up" immediately, even though we keep
    // capturing the tail for another [tail] ms underneath.
    onStatus?.call('processing');
    await Future<void>.delayed(tail); // let the tail drain into acceptSamples()
    if (!completer.isCompleted) completer.complete();
  }

  /// Abort an in-progress run and **discard** the result (mic stops at once).
  /// Used for explicit cancellation, not for normal button release — see
  /// [finish] for that.
  Future<void> cancel() async {
    if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
      _stopCompleter!.complete();
    }
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  // ─── PCM helpers ──────────────────────────────────────────────────

  /// Convert a raw PCM Int16LE [chunk] to Float32 normalised to ±1.0.
  ///
  /// Copies into a fresh aligned buffer first to avoid the
  /// `Int16List.view` offset-must-be-multiple-of-2 crash that occurs
  /// when the `record` package delivers views at odd byte offsets.
  Float32List _convertChunk(Uint8List chunk) {
    final evenLen = chunk.length & ~1;
    if (evenLen == 0) return Float32List(0);
    final buf = Uint8List(evenLen);
    buf.setRange(0, evenLen, chunk);
    final numSamples = evenLen ~/ 2;
    final int16View = Int16List.view(buf.buffer, 0, numSamples);
    final result = Float32List(numSamples);
    for (int i = 0; i < numSamples; i++) {
      result[i] = int16View[i] / 32768.0;
    }
    return result;
  }
}
