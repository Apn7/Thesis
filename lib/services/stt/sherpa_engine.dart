import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'stt_engine.dart';

/// Bengali speech-to-text engine backed by sherpa-onnx.
///
/// Uses the streaming zipformer-bn-vosk transducer model (~90 MB total).
/// The model is downloaded as a tarball on first launch to the app-support
/// directory and extracted there. Subsequent launches reuse local files.
class SherpaEngine implements SttEngine {
  static const String _modelDirName =
      'sherpa-onnx-streaming-zipformer-bn-vosk-2026-02-09';

  static const String _tarballUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
      '$_modelDirName.tar.bz2';

  /// Required files and their minimum expected sizes (80 % check).
  static const Map<String, int> _modelFiles = {
    'encoder.onnx': 87000000,
    'decoder.onnx': 2000000,
    'joiner.onnx': 1000000,
    'tokens.txt': 5000,
  };

  sherpa.OnlineRecognizer? _recognizer;
  String? _modelDir;
  bool _isInitialized = false;

  /// Optional progress callback: (bytesDownloaded, totalBytes).
  void Function(int downloaded, int total)? onDownloadProgress;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final appDir = await getApplicationSupportDirectory();
      _modelDir = '${appDir.path}/$_modelDirName';
      await Directory(_modelDir!).create(recursive: true);

      final allReady = await _ensureModelFiles();
      if (!allReady) {
        debugPrint('SherpaEngine: model files incomplete – cannot initialise.');
        return false;
      }

      _createRecognizer();
      _isInitialized = true;
      debugPrint('SherpaEngine: initialised successfully.');
      return true;
    } catch (e) {
      debugPrint('SherpaEngine init error: $e');
      return false;
    }
  }

  // ─── Model download ───────────────────────────────────────────────

  Future<bool> _ensureModelFiles() async {
    bool allPresent = true;
    for (final entry in _modelFiles.entries) {
      final file = File('${_modelDir!}/${entry.key}');
      if (!await file.exists()) {
        allPresent = false;
        break;
      }
      final size = await file.length();
      if (size < entry.value * 0.8) {
        debugPrint(
          'SherpaEngine: ${entry.key} looks corrupt '
          '(${size}B vs expected ~${entry.value}B). Re-downloading.',
        );
        allPresent = false;
        break;
      }
    }

    if (allPresent) {
      debugPrint('SherpaEngine: all model files present.');
      return true;
    }

    return await _downloadAndExtract();
  }

  Future<bool> _downloadAndExtract() async {
    final tempDir = await getTemporaryDirectory();
    final tarball = File('${tempDir.path}/$_modelDirName.tar.bz2');

    debugPrint('SherpaEngine: downloading tarball…');

    try {
      final request = http.Request('GET', Uri.parse(_tarballUrl));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        debugPrint('SherpaEngine: HTTP ${response.statusCode} for tarball');
        return false;
      }

      final totalBytes = response.contentLength ?? 0;
      final sink = tarball.openWrite();
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onDownloadProgress?.call(received, totalBytes);
      }
      await sink.flush();
      await sink.close();
      debugPrint('SherpaEngine: tarball downloaded (${received}B). Extracting…');

      // Extract: decompress bz2, then decode tar.
      final inputStream = InputFileStream(tarball.path);
      final decompressed = BZip2Decoder().decodeBuffer(inputStream);
      final archive = TarDecoder().decodeBuffer(InputStream(decompressed));

      for (final file in archive) {
        if (!file.isFile) continue;
        // Archive entries are like "sherpa-.../encoder.onnx" – use only basename.
        final baseName = file.name.split('/').last;
        if (!_modelFiles.containsKey(baseName)) continue;

        final target = File('${_modelDir!}/$baseName');
        await target.writeAsBytes(file.content as List<int>);
        debugPrint('SherpaEngine: extracted $baseName (${target.lengthSync()}B)');
      }

      await tarball.delete();
      debugPrint('SherpaEngine: extraction complete.');
      return true;
    } catch (e) {
      debugPrint('SherpaEngine: download/extract failed – $e');
      if (await tarball.exists()) await tarball.delete();
      return false;
    }
  }

  // ─── Recognizer lifecycle ─────────────────────────────────────────

  void _createRecognizer() {
    final dir = _modelDir!;

    final transducerConfig = sherpa.OnlineTransducerModelConfig(
      encoder: '$dir/encoder.onnx',
      decoder: '$dir/decoder.onnx',
      joiner: '$dir/joiner.onnx',
    );

    final modelConfig = sherpa.OnlineModelConfig(
      transducer: transducerConfig,
      tokens: '$dir/tokens.txt',
      numThreads: 2,
      debug: false,
    );

    final config = sherpa.OnlineRecognizerConfig(
      model: modelConfig,
      decodingMethod: 'greedy_search',
      maxActivePaths: 4,
    );

    _recognizer = sherpa.OnlineRecognizer(config);
  }

  // ─── Transcription ────────────────────────────────────────────────

  @override
  Future<String> transcribe(String audioPath) async {
    if (!_isInitialized || _recognizer == null) {
      debugPrint('SherpaEngine: not initialised, cannot transcribe.');
      return '';
    }

    try {
      final waveData = sherpa.readWave(audioPath);
      final stream = _recognizer!.createStream();

      stream.acceptWaveform(
        samples: waveData.samples,
        sampleRate: waveData.sampleRate,
      );

      // Signal end-of-audio to flush the decoder.
      stream.inputFinished();

      while (_recognizer!.isReady(stream)) {
        _recognizer!.decode(stream);
      }

      final result = _recognizer!.getResult(stream);
      stream.free();

      final text = result.text.trim();
      debugPrint('SherpaEngine transcribed: $text');
      return text;
    } catch (e) {
      debugPrint('SherpaEngine transcribe error: $e');
      return '';
    }
  }

  @override
  void dispose() {
    _recognizer?.free();
    _recognizer = null;
    _isInitialized = false;
  }
}
