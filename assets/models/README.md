# Vision Demo Models — YOLOv11n PTQ Variants

The Vision Demo screen expects **two** TFLite files in this directory:

| File | Purpose | Approx size |
|---|---|---|
| `yolo11n_float16.tflite` | FP16-quantized baseline. Default model loaded on screen entry. | ~5 MB |
| `yolo11n_int8.tflite` | INT8 post-training-quantization (PTQ) variant. Toggled at runtime for the thesis comparison. | ~2.5 MB |

`flutter build apk` will fail until both files exist, because both are referenced in `pubspec.yaml` under `flutter: assets:`. This is intentional — the demo is not useful without them.

## How to generate them

**Important — two footguns:**

1. Ultralytics' TFLite export needs TensorFlow, which currently has **no Python 3.13 wheel**. If you're on Python 3.13 (Windows users on a fresh Python install often are), the local script will fail with `ModuleNotFoundError: No module named 'tensorflow'` followed by `Could not find a version that satisfies the requirement tensorflow...`. Pick one of the two paths below.

2. **INT8 export is memory-hungry.** On a machine with limited free RAM or a constrained Windows pagefile, the INT8 calibration step OOMs either inside `torch.cat(images, ...)` (Ultralytics concatenating calibration images into one tensor) or during `import tensorflow` itself. We mitigate the first by passing `batch=16` in the script, but the second is environmental. If INT8 export fails:
   - Close other RAM-heavy apps and retry, or
   - Increase your Windows pagefile / swap, or
   - Ship FP16 only for now. The `yolo11n_int8.tflite` asset is **commented out** in `pubspec.yaml` for that reason — uncomment that line once the INT8 file exists.

### Path 1 — Google Colab (recommended, ~5 min)

Colab runs Python 3.10 with TF pre-installed. No local setup.

1. Open https://colab.research.google.com → **New notebook**.
2. Paste and run:
   ```python
   !pip install -q ultralytics
   from ultralytics import YOLO
   m = YOLO("yolo11n.pt")
   m.export(format="tflite", half=True, imgsz=640)
   m.export(format="tflite", int8=True, data="coco128.yaml", imgsz=640)
   !ls -lh yolo11n_saved_model/*.tflite
   ```
3. In the file browser, download `yolo11n_float16.tflite` **and** `yolo11n_full_integer_quant.tflite` from the `yolo11n_saved_model/` folder.
4. Place them in `Test_app/test_app_1/assets/models/`, **renaming** `yolo11n_full_integer_quant.tflite` → `yolo11n_int8.tflite`.

### Path 2 — Local with Python 3.12

1. Install Python 3.12 from https://www.python.org/downloads/windows/ (alongside your existing 3.13 is fine).
2. From this project's root (`Test_app/test_app_1/`):
   ```powershell
   py -3.12 -m pip install ultralytics
   py -3.12 export_yolo_models.py
   ```
3. The script copies + renames into `assets/models/` automatically.

The script logic, in either path:

1. Download the pretrained YOLOv11n COCO weights (`yolo11n.pt`, ~5 MB) — auto-fetched by Ultralytics on first call.
2. Export FP16 TFLite.
3. Auto-download the **COCO128** calibration set (~7 MB, 128 images) for INT8 PTQ.
4. Export INT8 TFLite using that calibration set.

Total one-time cost: ~30 MB download, 1–3 minutes runtime on a CPU machine.

## Why both models

This is the experimental instrument for the thesis quantization chapter:

- **FP16** is the accuracy baseline. Negligible mAP drop vs FP32, ~2× speed up vs FP32, half the model size.
- **INT8 PTQ** is the deployment-leaning variant. Reported in the literature to lose 1–3 mAP@50 on YOLOv8n COCO; faster on NNAPI/Hexagon hardware, half the size again.

The Vision Demo lets the user A/B them on the same camera frames in real time, producing the latency-vs-quality data the thesis writeup needs.

## Re-export at a different input size

If you change `ObjectDetectionService.inputSize` from 640, re-export with the matching `imgsz=` flag, otherwise the input tensor shape mismatches and inference will throw.

## What's *not* in scope here

- **Custom Bangladesh classes.** The exported models classify the standard 80 COCO classes (see `coco_labels.txt`). Custom training is documented as future work in the thesis scope, not v1.
- **Quantization-aware training (QAT).** Heavier route; only revisit if PTQ accuracy turns out worse than the literature predicts on your target device.
- **iOS / Windows builds.** Vision Demo is Android-only for v1 — the `camera` plugin's `startImageStream` is the limiting factor.
