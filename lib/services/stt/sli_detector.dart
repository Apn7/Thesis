import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'model_asset_manager.dart';
import 'sherpa_model_config.dart';

/// Detects the spoken language from a PCM audio buffer.
///
/// Uses sherpa-onnx [SpokenLanguageIdentification] with the whisper-tiny
/// int8 model.  The model is downloaded as a tarball on first use.
class SliDetector {
  final SliModelConfig config;

  sherpa.SpokenLanguageIdentification? _sli;
  String? _modelDir;
  bool _isInitialized = false;

  SliDetector({this.config = kSliWhisperTinyConfig});

  bool get isInitialized => _isInitialized;

  /// Copy model from bundled assets if needed, then create the identifier.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _modelDir = await ModelAssetManager.ensureSliModel(config);
      _createIdentifier();
      _isInitialized = true;
      debugPrint('SliDetector: initialised successfully.');
      return true;
    } catch (e) {
      debugPrint('SliDetector init error: $e');
      return false;
    }
  }

  // ─── Identifier lifecycle ──────────────────────────────────────────

  void _createIdentifier() {
    final dir = _modelDir!;

    final sliConfig = sherpa.SpokenLanguageIdentificationConfig(
      whisper: sherpa.SpokenLanguageIdentificationWhisperConfig(
        encoder: '$dir/${config.encoderFile}',
        decoder: '$dir/${config.decoderFile}',
      ),
      numThreads: config.numThreads,
      debug: false,
    );

    _sli = sherpa.SpokenLanguageIdentification(sliConfig);
  }

  // ─── Detection ─────────────────────────────────────────────────────

  /// Detect the spoken language from raw PCM [samples] at [sampleRate].
  ///
  /// Returns a BCP-47 language tag (e.g. `'bn'`, `'en'`).
  /// Returns `'bn'` (Bengali default) on failure or low confidence.
  String detect(Float32List samples, int sampleRate) {
    if (!_isInitialized || _sli == null) {
      debugPrint('SliDetector: not initialised, defaulting to bn.');
      return 'bn';
    }

    try {
      final stream = _sli!.createStream();
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      final result = _sli!.compute(stream);
      stream.free();

      final lang = result.lang;
      debugPrint('SliDetector: detected language = $lang');

      // Whisper-tiny frequently misidentifies Bengali as neighbouring South
      // Asian languages (hi, ur, ne, si) and Bangladeshi-accented English as
      // Southeast-Asian ones (id, ms, ta, ml).  Give each language a fair
      // "territory" and fall back to Bengali when undecided.
      //
      // Bengali territory: bn + South Asian siblings
      const bnLike = {'bn', 'hi', 'ur', 'ne', 'si', 'sd', 'pa'};
      // English territory: en + common Bangladeshi-English misidentifications
      const enLike = {'en', 'id', 'ms', 'ta', 'ml', 'jv'};

      if (bnLike.contains(lang)) return 'bn';
      if (enLike.contains(lang)) return 'en';
      return 'bn'; // default to Bengali when undecided
    } catch (e) {
      debugPrint('SliDetector: detection error – $e, defaulting to bn.');
      return 'bn';
    }
  }

  void dispose() {
    _sli?.free();
    _sli = null;
    _isInitialized = false;
  }
}
