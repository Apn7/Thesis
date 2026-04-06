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
  // ─── VAD constants ────────────────────────────────────────────────
  static const double _silenceThresholdDb = -26.0;
  static const Duration _silenceDuration = Duration(milliseconds: 1500);
  static const Duration _warmupSkip = Duration(seconds: 1);
  static const Duration _maxRecordDuration = Duration(seconds: 20);
  static const Duration _amplitudePollInterval = Duration(milliseconds: 200);

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
  Future<String> run() async {
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

      // ── VAD state ──
      DateTime? recordingStart;
      bool heardSpeech = false;
      Timer? silenceTimer;

      String lastPartial = '';

      // ── VAD amplitude listener ──
      final ampSubscription = _recorder
          .onAmplitudeChanged(_amplitudePollInterval)
          .listen((amp) {
            recordingStart ??= DateTime.now();
            final elapsed = DateTime.now().difference(recordingStart!);
            if (elapsed < _warmupSkip) return;

            debugPrint(
              'AudioPipeline VAD: ${amp.current.toStringAsFixed(1)} dB '
              '(threshold $_silenceThresholdDb)',
            );

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

      final maxTimer = Timer(_maxRecordDuration, () {
        if (!completer.isCompleted) completer.complete();
      });

      // ── PCM streaming listener ──
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

      // ── Wait for VAD silence, max duration, or external cancel ──
      await completer.future;
      _stopCompleter = null;

      silenceTimer?.cancel();
      maxTimer.cancel();
      await ampSubscription.cancel();
      await pcmSubscription.cancel();
      try {
        await _recorder.stop();
      } catch (_) {}

      // ── Finalize transcription ──
      onStatus?.call('processing');
      final finalText = engine.finalizeStream();
      onStatus?.call('done');
      return finalText;
    } catch (e) {
      debugPrint('AudioPipeline error: $e');
      onError?.call('Recording/transcription error: $e');
      try {
        await _recorder.stop();
      } catch (_) {}
      onStatus?.call('done');
      return '';
    }
  }

  /// Whether microphone permission has been granted.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Cancel an in-progress pipeline run early.
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
