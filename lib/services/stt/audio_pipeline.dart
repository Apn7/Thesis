import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'stt_engine.dart';
import 'stt_engine_factory.dart';

/// Coordinates streaming audio capture, VAD, SLI language detection,
/// and sherpa-onnx transcription into a single pipeline.
///
/// Audio chunks are fed to the recognizer **as they arrive** from the
/// microphone, so partial results are available in real-time and the
/// streaming nature of the zipformer model is fully exploited.
///
/// Usage:
/// ```dart
/// final pipeline = AudioPipeline();
/// pipeline.onPartialResult = (text) => print('partial: $text');
/// final text = await pipeline.run(locale: 'both');
/// ```
class AudioPipeline {
  // ─── VAD constants ────────────────────────────────────────────────
  static const double _silenceThresholdDb = -26.0;
  static const Duration _silenceDuration = Duration(milliseconds: 1500);
  static const Duration _warmupSkip = Duration(seconds: 1);
  static const Duration _maxRecordDuration = Duration(seconds: 20);
  static const Duration _amplitudePollInterval = Duration(milliseconds: 200);

  /// Samples to buffer before SLI language detection (1 s at 16 kHz).
  static const int _sliMinSamples = 16000;

  // ─── Callbacks ────────────────────────────────────────────────────
  Function(String status)? onStatus;
  Function(String error)? onError;

  /// Called with each new partial transcript during recording.
  Function(String text)? onPartialResult;

  final AudioRecorder _recorder = AudioRecorder();
  Completer<void>? _stopCompleter;

  // ─── Public API ───────────────────────────────────────────────────

  /// Run the full pipeline: record → detect language (if 'both') → transcribe.
  ///
  /// Audio chunks are fed into the streaming recognizer incrementally.
  /// [onPartialResult] fires whenever the partial transcript changes.
  /// Returns the final transcript, or an empty string on failure.
  Future<String> run({required String locale}) async {
    onStatus?.call('listening');

    try {
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

      // ── Streaming state ──
      SttEngine? activeEngine;
      String resolvedLocale = locale == 'both' ? 'bn' : locale;
      bool languageDetected = locale != 'both';
      bool sliTriggered = false;

      // Buffer for SLI + fallback: holds Float32 chunks until engine is ready.
      // Also kept after streaming starts for the 'both'-mode fallback path.
      final preBuffer = <Float32List>[];
      int preBufferSamples = 0;

      // All samples ever recorded — used for 'both'-mode fallback.
      final allSamples = <Float32List>[];

      String lastPartial = '';

      // For single-locale mode: start streaming immediately.
      if (locale != 'both') {
        final engine = SttEngineFactory.getEngine(locale);
        if (!engine.isInitialized) await engine.initialize();
        engine.resetStream();
        activeEngine = engine;
      }

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

        allSamples.add(samples);

        if (languageDetected && activeEngine != null) {
          // ── Fast path: live streaming ──
          activeEngine!.acceptSamples(samples, 16000);
          final partial = activeEngine!.getPartialResult();
          if (partial != lastPartial) {
            lastPartial = partial;
            onPartialResult?.call(partial);
          }
        } else {
          // ── Buffering phase: SLI pending or engine initialising ──
          preBuffer.add(samples);
          preBufferSamples += samples.length;

          if (!sliTriggered && preBufferSamples >= _sliMinSamples) {
            sliTriggered = true;

            // Detect language synchronously from first ~1 s of audio.
            final detector = SttEngineFactory.sliDetector;
            if (detector != null && detector.isInitialized) {
              final sliInput = _mergeFloatChunks(
                preBuffer,
                maxSamples: _sliMinSamples * 2,
              );
              resolvedLocale = detector.detect(sliInput, 16000);
            }
            debugPrint('AudioPipeline: resolved locale → $resolvedLocale');

            final engine = SttEngineFactory.getEngine(resolvedLocale);

            void startStreaming() {
              engine.resetStream();
              for (final c in preBuffer) {
                engine.acceptSamples(c, 16000);
              }
              preBuffer.clear();
              preBufferSamples = 0;
              activeEngine = engine;
              languageDetected = true;

              final partial = engine.getPartialResult();
              if (partial.isNotEmpty) {
                lastPartial = partial;
                onPartialResult?.call(partial);
              }
            }

            if (engine.isInitialized) {
              startStreaming();
            } else {
              // Engine not pre-warmed — initialise asynchronously.
              // New chunks continue accumulating in preBuffer until done.
              engine.initialize().then((_) => startStreaming());
            }
          }
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

      String finalText = '';

      if (activeEngine != null) {
        // Feed any chunks that landed in preBuffer while engine was initialising.
        for (final c in preBuffer) {
          activeEngine!.acceptSamples(c, 16000);
        }
        finalText = activeEngine!.finalizeStream();
      } else if (allSamples.isNotEmpty) {
        // Recording ended before SLI triggered (very short clip).
        final engine = SttEngineFactory.getEngine(resolvedLocale);
        if (!engine.isInitialized) await engine.initialize();
        engine.resetStream();
        for (final c in allSamples) {
          engine.acceptSamples(c, 16000);
        }
        finalText = engine.finalizeStream();
      }

      // ── Fallback: try other language if primary is empty ──
      if (finalText.isEmpty && locale == 'both') {
        final fallbackLocale = resolvedLocale == 'bn' ? 'en' : 'bn';
        debugPrint(
          'AudioPipeline: primary ($resolvedLocale) empty, '
          'trying fallback ($fallbackLocale).',
        );
        final fallback = SttEngineFactory.getEngine(fallbackLocale);
        if (!fallback.isInitialized) await fallback.initialize();
        fallback.resetStream();
        final merged = _mergeFloatChunks(allSamples);
        fallback.acceptSamples(merged, 16000);
        finalText = fallback.finalizeStream();
      }

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

  /// Merge Float32 chunks into a single contiguous array,
  /// optionally capped at [maxSamples].
  Float32List _mergeFloatChunks(
    List<Float32List> chunks, {
    int? maxSamples,
  }) {
    int total = 0;
    for (final c in chunks) {
      total += c.length;
    }
    if (maxSamples != null && maxSamples < total) total = maxSamples;
    final result = Float32List(total);
    int pos = 0;
    for (final c in chunks) {
      final toCopy = (pos + c.length <= total) ? c.length : total - pos;
      result.setRange(pos, pos + toCopy, c);
      pos += toCopy;
      if (pos >= total) break;
    }
    return result;
  }
}
