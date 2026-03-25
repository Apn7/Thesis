import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:whisper_ggml/whisper_ggml.dart';

import 'stt_engine.dart';

/// Whisper-based STT engine using the whisper_ggml package.
///
/// Uses [WhisperModel.base] with a Q5_1-quantised GGML binary for
/// a good accuracy-vs-size trade-off (~57 MB).
class WhisperEngine implements SttEngine {
  final WhisperController _controller = WhisperController();
  bool _isInitialized = false;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      await _ensureModelCopied();
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('WhisperEngine init error: $e');
      return false;
    }
  }

  /// Copy the bundled GGML model from assets to the app-support directory
  /// (the location whisper_ggml expects).
  Future<void> _ensureModelCopied() async {
    final modelName = WhisperModel.base.modelName;
    final fileName = 'ggml-$modelName.bin';
    final supportDir = await WhisperController.getModelDir();
    final target = File('$supportDir/$fileName');

    if (await target.exists()) {
      debugPrint('WhisperEngine: model already at ${target.path}');
      return;
    }

    debugPrint('WhisperEngine: copying $fileName to ${target.path}…');
    final byteData = await rootBundle.load('assets/models/$fileName');
    await target.writeAsBytes(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
      flush: true,
    );
    debugPrint('WhisperEngine: model copied.');
  }

  @override
  Future<String> transcribe(String audioPath) async {
    try {
      final result = await _controller.transcribe(
        model: WhisperModel.base,
        audioPath: audioPath,
        lang: 'en',
      );

      if (result != null && result.transcription.text.isNotEmpty) {
        final text = result.transcription.text.trim();
        debugPrint('WhisperEngine transcribed: $text');
        return text;
      }

      return '';
    } catch (e) {
      debugPrint('WhisperEngine transcribe error: $e');
      return '';
    }
  }

  @override
  void dispose() {
    _isInitialized = false;
  }
}
