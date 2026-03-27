import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'model_asset_manager.dart';
import 'sherpa_model_config.dart';
import 'stt_engine.dart';

/// Streaming speech-to-text engine backed by sherpa-onnx.
///
/// Uses an [OnlineRecognizer] (streaming transducer) so audio chunks are
/// decoded incrementally as they arrive — no need to buffer the full clip
/// before transcription begins.
///
/// The same class serves both Bengali and English (or any future language)
/// via the injected [SherpaModelConfig].
class SherpaEngine implements SttEngine {
  final SherpaModelConfig config;

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _activeStream;
  String? _modelDir;
  bool _isInitialized = false;

  SherpaEngine(this.config);

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _modelDir = await ModelAssetManager.ensureSherpaModel(config);
      _createRecognizer();
      _isInitialized = true;
      debugPrint('SherpaEngine[${config.language}]: initialised.');
      return true;
    } catch (e) {
      debugPrint('SherpaEngine[${config.language}] init error: $e');
      return false;
    }
  }

  void _createRecognizer() {
    final dir = _modelDir!;

    final transducerConfig = sherpa.OnlineTransducerModelConfig(
      encoder: '$dir/${config.encoderFile}',
      decoder: '$dir/${config.decoderFile}',
      joiner: '$dir/${config.joinerFile}',
    );

    final modelConfig = sherpa.OnlineModelConfig(
      transducer: transducerConfig,
      tokens: '$dir/tokens.txt',
      numThreads: config.numThreads,
      debug: false,
    );

    final recognizerConfig = sherpa.OnlineRecognizerConfig(
      model: modelConfig,
      decodingMethod: 'greedy_search',
      maxActivePaths: 4,
    );

    _recognizer = sherpa.OnlineRecognizer(recognizerConfig);
  }

  // ─── Streaming API ────────────────────────────────────────────────

  @override
  void resetStream() {
    if (_recognizer == null) return;
    _activeStream?.free();
    _activeStream = _recognizer!.createStream();
  }

  @override
  void acceptSamples(Float32List samples, int sampleRate) {
    final stream = _activeStream;
    final recognizer = _recognizer;
    if (stream == null || recognizer == null) return;

    stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
  }

  @override
  String getPartialResult() {
    final stream = _activeStream;
    final recognizer = _recognizer;
    if (stream == null || recognizer == null) return '';
    return recognizer.getResult(stream).text.trim().toLowerCase();
  }

  @override
  String finalizeStream() {
    final stream = _activeStream;
    final recognizer = _recognizer;
    if (stream == null || recognizer == null) return '';

    stream.inputFinished();
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }

    // The English model emits uppercase grapheme tokens; normalise to lowercase.
    // Bengali text is unaffected by toLowerCase().
    final text = recognizer.getResult(stream).text.trim().toLowerCase();
    stream.free();
    _activeStream = null;

    debugPrint('SherpaEngine[${config.language}] final: "$text"');
    return text;
  }

  // ─── Lifecycle ────────────────────────────────────────────────────

  @override
  void dispose() {
    _activeStream?.free();
    _activeStream = null;
    _recognizer?.free();
    _recognizer = null;
    _isInitialized = false;
  }
}
