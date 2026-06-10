/// A single object detected by the YOLO model.
///
/// [bbox] is normalised to the source frame (0..1 in both axes), xyxy
/// format with `x2 >= x1` and `y2 >= y1`.  Mapped from the Ultralytics
/// plugin's `YOLOResult.normalizedBox` in the Vision Demo screen.
class Detection {
  final int classId;
  final String label;
  final double confidence;
  final BBox bbox;

  const Detection({
    required this.classId,
    required this.label,
    required this.confidence,
    required this.bbox,
  });

  /// Coarse horizontal position relative to the frame — used in the spoken
  /// alert ("person, center") and the on-screen chip in the detection list.
  PositionZone get position {
    final cx = (bbox.x1 + bbox.x2) / 2;
    if (cx < 0.33) return PositionZone.left;
    if (cx > 0.67) return PositionZone.right;
    return PositionZone.center;
  }
}

/// Normalised bounding box, top-left to bottom-right.
class BBox {
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const BBox(this.x1, this.y1, this.x2, this.y2);

  double get width => x2 - x1;
  double get height => y2 - y1;
  double get area => width * height;
}

enum PositionZone {
  left('বাম', 'left'),
  center('মাঝে', 'center'),
  right('ডান', 'right');

  final String bn;
  final String en;
  const PositionZone(this.bn, this.en);
}

/// Which quantised TFLite model file to load.  Bundled at build time;
/// toggled at runtime from the Vision Demo screen so the thesis can compare
/// latency and accuracy head-to-head without rebuilding.
enum ModelVariant {
  fp16('yolo11n_float16.tflite', 'FP16'),
  int8('yolo11n_int8.tflite', 'INT8');

  final String assetFile;
  final String label;
  const ModelVariant(this.assetFile, this.label);
}

/// Which delegate the native interpreter should use.  Exposed as a runtime
/// toggle so the thesis can compare CPU vs GPU latency on the same model.
/// Maps to the Ultralytics plugin's `useGpu` flag.
enum InferenceDelegate {
  cpu('CPU'),
  gpu('GPU');

  final String label;
  const InferenceDelegate(this.label);
}
