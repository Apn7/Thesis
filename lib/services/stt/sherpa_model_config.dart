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

/// English streaming zipformer transducer, int8-quantised (~70 MB).
///
/// Trained on LibriSpeech; significantly more accurate than the 20 M model.
const kEnglishSherpaConfig = SherpaModelConfig(
  language: 'en',
  modelDirName: 'sherpa-onnx-streaming-zipformer-en-2023-06-26',
  modelFiles: {
    'encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx': 70000000,
    'decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx': 500000,
    'joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx': 200000,
    'tokens.txt': 5000,
  },
  encoderFile: 'encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
  decoderFile: 'decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
  joinerFile: 'joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
);

/// Configuration for the SLI (Spoken Language Identification) whisper-tiny model.
class SliModelConfig {
  final String modelDirName;

  /// Keys = filenames; values = min byte sizes (80% check for corruption).
  final Map<String, int> modelFiles;

  final String encoderFile;
  final String decoderFile;
  final int numThreads;

  const SliModelConfig({
    required this.modelDirName,
    required this.modelFiles,
    this.encoderFile = 'encoder.int8.onnx',
    this.decoderFile = 'decoder.int8.onnx',
    this.numThreads = 1,
  });
}

/// Whisper-tiny int8 multilingual model for spoken language identification (~100 MB).
const kSliWhisperTinyConfig = SliModelConfig(
  modelDirName: 'sherpa-onnx-whisper-tiny',
  modelFiles: {
    'tiny-encoder.int8.onnx': 12000000,
    'tiny-decoder.int8.onnx': 85000000,
    'tiny-tokens.txt': 500000,
  },
  encoderFile: 'tiny-encoder.int8.onnx',
  decoderFile: 'tiny-decoder.int8.onnx',
);
