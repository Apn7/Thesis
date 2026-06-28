"""Export the SafeWalkBD-fine-tuned YOLOv11n to the app's TFLite variants.

Mirrors export_yolo_models.py, but:
  * loads our fine-tuned best.pt (16 BD classes) instead of stock COCO yolo11n.pt
  * calibrates the INT8 PTQ on SafeWalkBD images (not COCO128) so the 8-bit
    scales are tuned to the actual deployment distribution.

Output filenames are kept identical to the COCO ones so the Flutter side needs
no model-path change — only the class labels differ (handled in Dart).

Produces:
  assets/models/yolo11n_float16.tflite  (FP16)
  assets/models/yolo11n_int8.tflite     (INT8 PTQ)

Run from this directory (training venv active):
    python export_safewalkbd.py
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

from ultralytics import YOLO

PROJECT_DIR = Path(__file__).resolve().parent
ASSETS_DIR = PROJECT_DIR / "assets" / "models"
ASSETS_DIR.mkdir(parents=True, exist_ok=True)

BEST_PT = PROJECT_DIR / "runs" / "detect" / "runs_safewalkbd" / "yolo11n_ft" / "weights" / "best.pt"
INPUT_SIZE = 640  # must match the Dart side's input size
# INT8 calibration on the real deployment distribution (SafeWalkBD val split).
CALIBRATION_DATA = r"D:/Download/SafeWalkBD.v9i.yolov11/data.yaml"


def find_tflite(saved_model_dir: Path, must_contain: str) -> Path:
    candidates = list(saved_model_dir.glob(f"*{must_contain}*.tflite"))
    if not candidates:
        raise FileNotFoundError(
            f"No .tflite containing '{must_contain}' under {saved_model_dir}."
        )
    if len(candidates) > 1:
        print(f"!! Multiple '{must_contain}' candidates, using first: {candidates}",
              file=sys.stderr)
    return candidates[0]


def main() -> None:
    if not BEST_PT.exists():
        sys.exit(f"best.pt not found at {BEST_PT}")
    print(f">> Loading fine-tuned model: {BEST_PT}")
    model = YOLO(str(BEST_PT))
    print(f">> Classes ({len(model.names)}): {list(model.names.values())}")

    fp16_dst = ASSETS_DIR / "yolo11n_float16.tflite"
    if fp16_dst.exists():
        print(f">> FP16 already exported ({fp16_dst.stat().st_size / 1e6:.2f} MB) — skipping.")
    else:
        print(">> Exporting FP16 TFLite...")
        fp16_export = model.export(format="tflite", half=True, imgsz=INPUT_SIZE)
        fp16_src = Path(fp16_export)
        if not fp16_src.exists():
            fp16_src = find_tflite(fp16_src.parent, "float16")
        shutil.copy(fp16_src, fp16_dst)
        print(f"   wrote {fp16_dst}  ({fp16_dst.stat().st_size / 1e6:.2f} MB)")

    print(">> Exporting INT8 TFLite (PTQ, SafeWalkBD calibration)...")
    # fraction=0.1 -> ~200 calibration images (the full val split is ~9.75 GB
    # of float tensors at once and OOMs). 200 is ample for PTQ scale estimation.
    int8_export = model.export(
        format="tflite", int8=True, data=CALIBRATION_DATA,
        imgsz=INPUT_SIZE, batch=16, fraction=0.1,
    )
    int8_src = Path(int8_export)
    if not int8_src.exists():
        int8_src = find_tflite(int8_src.parent, "int8")
    int8_dst = ASSETS_DIR / "yolo11n_int8.tflite"
    shutil.copy(int8_src, int8_dst)
    print(f"   wrote {int8_dst}  ({int8_dst.stat().st_size / 1e6:.2f} MB)")

    print("\n>> Done. Next: update Dart class labels, then flutter run.")


if __name__ == "__main__":
    main()
