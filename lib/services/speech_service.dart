import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Service for offline speech-to-text functionality via Whisper GGML
class SpeechService {
  static SpeechService? _instance;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final WhisperController _whisperController = WhisperController();

  bool _isInitialized = false;
  bool _isListening = false;
  String _lastRecognizedWords = '';
  String _currentLocaleId = 'bn'; // Bengali Bangladesh

  String? _recordFilePath;

  // Callbacks
  Function(String text, bool isFinal)? onResult;
  Function(String status)? onStatus;
  Function(String error)? onError;

  // Singleton
  static SpeechService get instance {
    _instance ??= SpeechService._();
    return _instance!;
  }

  SpeechService._();

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;
  String get lastWords => _lastRecognizedWords;

  /// Initialize speech recognition
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // 1. Check microphone permission
      if (!await _audioRecorder.hasPermission()) {
        onError?.call('Microphone permission not granted');
        return false;
      }

      // 2. Setup Whisper model from assets
      await _setupWhisperModel();

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Speech init error: $e');
      onError?.call('Failed to initialize speech recognition: $e');
      return false;
    }
  }

  Future<void> _setupWhisperModel() async {
    final modelName = WhisperModel.tiny.modelName; // Usually "tiny"
    final modelFileName = 'ggml-$modelName.bin';

    // The whisper_ggml package expects the model in the app support directory
    final supportDir = await WhisperController.getModelDir();
    final targetPath = '$supportDir/$modelFileName';
    final targetFile = File(targetPath);

    if (!await targetFile.exists()) {
      debugPrint('Copying Whisper model to $targetPath...');
      try {
        final byteData = await rootBundle.load('assets/models/$modelFileName');
        await targetFile.writeAsBytes(
          byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          ),
          flush: true,
        );
        debugPrint('Model copied successfully.');
      } catch (e) {
        debugPrint('Error copying model: $e');
        // Let WhisperController download it if asset copying fails
      }
    } else {
      debugPrint('Model already exists at $targetPath');
    }
  }

  /// Start listening for speech
  Future<void> startListening() async {
    if (!_isInitialized) {
      final success = await initialize();
      if (!success) return;
    }

    if (_isListening) return;

    _lastRecognizedWords = '';
    _isListening = true;
    onStatus?.call('listening');

    try {
      final tempDir = await getTemporaryDirectory();
      _recordFilePath = '${tempDir.path}/recording.wav';

      // whisper_ggml uses 16kHz, mono, 16-bit PCM wav files.
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _recordFilePath!,
      );
    } catch (e) {
      _isListening = false;
      onError?.call('Failed to start recording: $e');
    }
  }

  /// Stop listening and transcribe
  Future<void> stopListening() async {
    if (!_isListening) return;

    _isListening = false;
    onStatus?.call('processing'); // Tell UI we are now thinking

    try {
      final path = await _audioRecorder.stop();
      if (path != null && File(path).existsSync()) {
        debugPrint('Recording saved to $path, transcribing offline...');

        final result = await _whisperController.transcribe(
          model: WhisperModel.tiny,
          audioPath: path,
          lang: _currentLocaleId,
        );

        if (result != null && result.transcription.text.isNotEmpty) {
          _lastRecognizedWords = result.transcription.text.trim();
          debugPrint('Recognized offline: $_lastRecognizedWords');
          onResult?.call(_lastRecognizedWords, true);
        } else {
          onResult?.call('', true); // empty result
        }
      }
    } catch (e) {
      debugPrint('Error transcribing: $e');
      onError?.call('Transcription error: $e');
    } finally {
      onStatus?.call('done');
    }
  }

  /// Cancel listening
  Future<void> cancelListening() async {
    if (!_isListening) return;

    await _audioRecorder.stop();
    _isListening = false;
    _lastRecognizedWords = '';
    onStatus?.call('notListening');
  }

  /// Switch locale (Bengali/English)
  void setLocale(String localeId) {
    _currentLocaleId = localeId;
  }

  /// Get available locales
  Future<List<String>> getAvailableLocales() async {
    // whisper_ggml supports multiple languages built-in
    return ['bn', 'en'];
  }
}
