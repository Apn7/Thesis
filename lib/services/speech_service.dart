import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'stt/stt_engine_factory.dart';

/// Orchestrates audio recording, voice-activity detection (VAD),
/// and speech-to-text via a pluggable [SttEngine].
///
/// Bengali → [SherpaEngine], English → [WhisperEngine].
/// Silence detection auto-stops recording after [_silenceDuration]
/// of quiet below [_silenceThresholdDb].
class SpeechService {
  static SpeechService? _instance;

  // ─── Recording ────────────────────────────────────────────────────
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _recordFilePath;

  // ─── State ────────────────────────────────────────────────────────
  bool _isInitialized = false;
  bool _isListening = false;
  String _lastRecognizedWords = '';
  String _currentLocaleId = 'bn';

  // ─── VAD constants ────────────────────────────────────────────────
  static const double _silenceThresholdDb = -35.0;
  static const Duration _silenceDuration = Duration(milliseconds: 1500);
  static const Duration _warmupSkip = Duration(seconds: 1);
  static const Duration _maxRecordDuration = Duration(seconds: 20);

  // ─── VAD runtime state ────────────────────────────────────────────
  Timer? _amplitudePoller;
  Timer? _silenceTimer;
  Timer? _maxDurationTimer;
  DateTime? _recordingStart;

  // ─── Callbacks ────────────────────────────────────────────────────
  Function(String text, bool isFinal)? onResult;
  Function(String status)? onStatus;
  Function(String error)? onError;

  // ─── Singleton ────────────────────────────────────────────────────
  static SpeechService get instance {
    _instance ??= SpeechService._();
    return _instance!;
  }

  SpeechService._();

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;
  String get lastWords => _lastRecognizedWords;

  // ─── Initialisation ───────────────────────────────────────────────

  /// Prepare the microphone permission and the STT engine for the
  /// current locale.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      if (!await _audioRecorder.hasPermission()) {
        onError?.call('Microphone permission not granted');
        return false;
      }

      // Pre-warm the engine for the active locale.
      final engine = SttEngineFactory.getEngine(_currentLocaleId);
      await engine.initialize();

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('SpeechService init error: $e');
      onError?.call('Failed to initialize speech recognition: $e');
      return false;
    }
  }

  // ─── Recording + VAD ──────────────────────────────────────────────

  /// Begin recording with automatic silence detection.
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

      // 16 kHz mono WAV – required by both Whisper and sherpa-onnx.
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _recordFilePath!,
      );

      _startVad();
    } catch (e) {
      _isListening = false;
      onError?.call('Failed to start recording: $e');
    }
  }

  /// Stop recording, run transcription, and deliver the result.
  Future<void> stopListening() async {
    if (!_isListening) return;

    _isListening = false;
    _disposeVadResources();
    onStatus?.call('processing');

    try {
      final path = await _audioRecorder.stop();
      if (path == null || !File(path).existsSync()) {
        onResult?.call('', true);
        onStatus?.call('done');
        return;
      }

      debugPrint('SpeechService: recording saved → transcribing ($path)');

      // Primary engine for the active locale.
      final engine = SttEngineFactory.getEngine(_currentLocaleId);
      if (!engine.isInitialized) await engine.initialize();
      var text = await engine.transcribe(path);

      // Fallback: if primary returned nothing, try the other engine.
      if (text.isEmpty) {
        debugPrint('SpeechService: primary engine empty, trying fallback.');
        final fallback = SttEngineFactory.fallbackEngine;
        if (!fallback.isInitialized) await fallback.initialize();
        text = await fallback.transcribe(path);
      }

      _lastRecognizedWords = text;
      debugPrint('SpeechService recognised: $text');
      onResult?.call(text, true);
    } catch (e) {
      debugPrint('SpeechService transcription error: $e');
      onError?.call('Transcription error: $e');
    } finally {
      onStatus?.call('done');
    }
  }

  /// Cancel recording without transcribing.
  Future<void> cancelListening() async {
    if (!_isListening) return;

    _disposeVadResources();
    await _audioRecorder.stop();
    _isListening = false;
    _lastRecognizedWords = '';
    onStatus?.call('notListening');
  }

  // ─── VAD helpers ──────────────────────────────────────────────────

  void _startVad() {
    _recordingStart = DateTime.now();

    // Poll amplitude every 200 ms (record v6 exposes getAmplitude() as a
    // one-shot Future rather than a continuous stream).
    _amplitudePoller = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _checkAmplitude(),
    );

    // Hard safety cap – stop recording regardless after max duration.
    _maxDurationTimer = Timer(_maxRecordDuration, () {
      if (_isListening) stopListening();
    });
  }

  Future<void> _checkAmplitude() async {
    if (!_isListening) return;
    final elapsed = DateTime.now().difference(_recordingStart!);
    // Ignore the first second – mic warm-up often produces a burst.
    if (elapsed < _warmupSkip) return;

    try {
      final amp = await _audioRecorder.getAmplitude();
      debugPrint(
        'VAD: ${amp.current.toStringAsFixed(1)} dB '
        '(threshold $_silenceThresholdDb) '
        'silent=${amp.current < _silenceThresholdDb}',
      );
      if (amp.current < _silenceThresholdDb) {
        // Silence detected – start / keep the countdown.
        _silenceTimer ??= Timer(_silenceDuration, () {
          if (_isListening) stopListening();
        });
      } else {
        // Voice detected – reset the countdown.
        _silenceTimer?.cancel();
        _silenceTimer = null;
      }
    } catch (e) {
      debugPrint('VAD amplitude error: $e');
    }
  }

  void _disposeVadResources() {
    _amplitudePoller?.cancel();
    _amplitudePoller = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
  }

  // ─── Locale ───────────────────────────────────────────────────────

  /// Switch the active locale.  The matching engine will be lazily
  /// initialised on the next transcription.
  void setLocale(String localeId) {
    _currentLocaleId = localeId;
  }

  /// Available locale identifiers.
  Future<List<String>> getAvailableLocales() async => ['bn', 'en'];
}
