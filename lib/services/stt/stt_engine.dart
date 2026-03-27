import 'dart:typed_data';

/// Abstract interface for speech-to-text engines.
///
/// Engines operate in **streaming mode**: audio is fed incrementally as it
/// arrives from the microphone, partial results are available after each
/// [acceptSamples] call, and the final transcript is returned by
/// [finalizeStream].
///
/// Typical call sequence for one recording session:
/// ```dart
/// engine.resetStream();
/// for (final chunk in audioChunks) {
///   engine.acceptSamples(chunk, 16000);
///   final partial = engine.getPartialResult();  // optional live display
/// }
/// final text = engine.finalizeStream();
/// ```
abstract class SttEngine {
  /// Whether [initialize] has completed successfully.
  bool get isInitialized;

  /// Load model files and allocate native resources. Returns `true` on success.
  Future<bool> initialize();

  /// Start (or restart) a new recognition session.
  /// Must be called before [acceptSamples].
  void resetStream();

  /// Feed [samples] (16 kHz mono Float32, range ±1.0) into the active stream
  /// and run an incremental decode step.
  void acceptSamples(Float32List samples, int sampleRate);

  /// Best partial result decoded so far in the current stream.
  /// Returns an empty string if nothing has been recognised yet.
  String getPartialResult();

  /// Signal end-of-audio, flush the decoder, and return the final transcript.
  /// Releases the stream; call [resetStream] before the next recording.
  String finalizeStream();

  /// Release all native resources held by this engine.
  void dispose();
}
