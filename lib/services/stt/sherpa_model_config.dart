/// Immutable configuration for a sherpa-onnx streaming transducer model.
///
/// Carries everything needed to copy from bundled assets, validate, and
/// construct an [OnlineRecognizer]: directory name, expected files with
/// minimum sizes, and the recognizer-specific file names.
class SherpaModelConfig {
  final String language;
  final String modelDirName;

  /// Keys = filenames; values = min byte sizes (80% check for corruption).
  final Map<String, int> modelFiles;

  /// File names used when constructing OnlineTransducerModelConfig.
  final String encoderFile;
  final String decoderFile;
  final String joinerFile;
  final int numThreads;

  const SherpaModelConfig({
    required this.language,
    required this.modelDirName,
    required this.modelFiles,
    this.encoderFile = 'encoder.onnx',
    this.decoderFile = 'decoder.onnx',
    this.joinerFile = 'joiner.onnx',
    this.numThreads = 2,
  });
}

/// Bengali streaming zipformer transducer (~90 MB).
const kBengaliSherpaConfig = SherpaModelConfig(
  language: 'bn',
  modelDirName: 'sherpa-onnx-streaming-zipformer-bn-vosk-2026-02-09',
  modelFiles: {
    'encoder.onnx': 87000000,
    'decoder.onnx': 2000000,
    'joiner.onnx': 1000000,
    'tokens.txt': 5000,
  },
);
