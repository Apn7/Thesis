/// Abstract interface for speech-to-text engines.
///
/// Implementations must be safe to call from any isolate context.
/// Callers are responsible for calling [dispose] when the engine
/// is no longer needed to free native resources.
abstract class SttEngine {
  /// Prepare the engine: load or download model files, allocate native
  /// resources.  Returns `true` on success.
  Future<bool> initialize();

  /// Transcribe a 16 kHz mono WAV file at [audioPath].
  /// Returns the recognised text, or an empty string on failure.
  Future<String> transcribe(String audioPath);

  /// Whether [initialize] has completed successfully.
  bool get isInitialized;

  /// Release all native resources held by this engine.
  void dispose();
}
