"""Export YOLOv11n to two TFLite variants for the Vision Demo screen.

Produces:
  assets/models/yolo11n_float16.tflite  (FP16, ~5 MB)
  assets/models/yolo11n_int8.tflite     (INT8 PTQ, ~2.5 MB)

The thesis quantization chapter A/B-tests these head-to-head from the
Vision Demo screen.  See assets/models/README.md for the why.

Run from this directory:
    pip install ultralytics
    python export_yolo_models.py
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

try:
    from ultralytics import YOLO
except ImportError:
    sys.stderr.write(
        "Ultralytics is not installed.\n"
        "    pip install ultralytics\n"
    )
    sys.exit(1)

PROJECT_DIR = Path(__file__).resolve().parent
ASSETS_DIR = PROJECT_DIR / "assets" / "models"
ASSETS_DIR.mkdir(parents=True, exist_ok=True)

INPUT_SIZE = 640  # must match ObjectDetectionService.inputSize on the Dart side
CALIBRATION_DATA = "coco128.yaml"  # ~7 MB auto-download, 128 images


def find_tflite(saved_model_dir: Path, must_contain: str) -> Path:
    """Locate the right .tflite inside Ultralytics' saved_model output.

    Ultralytics names files like 'yolo11n_float16.tflite' or
    'yolo11n_full_integer_quant.tflite' depending on the export flags
    and library version.  Match on the fragment we care about.
    """
    candidates = list(saved_model_dir.glob(f"*{must_contain}*.tflite"))
    if not candidates:
        raise FileNotFoundError(
            f"No .tflite containing '{must_contain}' found under "
            f"{saved_model_dir}.  Inspect the directory manually."
        )
    if len(candidates) > 1:
        print(
            f"!! Multiple candidates for '{must_contain}', using first: "
            f"{candidates}",
            file=sys.stderr,
        )
    return candidates[0]


def main() -> None:
    print(">> Loading pretrained YOLOv11n (COCO)...")
    model = YOLO("yolo11n.pt")

    print(">> Exporting FP16 TFLite...")
    fp16_export = model.export(format="tflite", half=True, imgsz=INPUT_SIZE)
    fp16_src = Path(fp16_export)
    if not fp16_src.exists():
        fp16_src = find_tflite(fp16_src.parent, "float16")
    fp16_dst = ASSETS_DIR / "yolo11n_float16.tflite"
    shutil.copy(fp16_src, fp16_dst)
    print(f"   wrote {fp16_dst}  ({fp16_dst.stat().st_size / 1e6:.2f} MB)")

    print(">> Exporting INT8 TFLite (PTQ with COCO128 calibration)...")
    # batch=16 keeps calibration RAM usage ~80 MB instead of ~630 MB —
    # plenty for PTQ scale/zero-point estimation, and it sidesteps the
    # `torch.cat` OOM that fires on machines with constrained memory or
    # a tight Windows pagefile.
    int8_export = model.export(
        format="tflite",
        int8=True,
        data=CALIBRATION_DATA,
        imgsz=INPUT_SIZE,
        batch=16,
    )
    int8_src = Path(int8_export)
    if not int8_src.exists():
        # PTQ exports sometimes land as 'yolo11n_full_integer_quant.tflite'
        int8_src = find_tflite(int8_src.parent, "int8")
    int8_dst = ASSETS_DIR / "yolo11n_int8.tflite"
    shutil.copy(int8_src, int8_dst)
    print(f"   wrote {int8_dst}  ({int8_dst.stat().st_size / 1e6:.2f} MB)")

    print()
    print(">> Done.  Next:")
    print("   flutter pub get")
    print("   flutter run -d <android-device-id>")


if __name__ == "__main__":
    main()
