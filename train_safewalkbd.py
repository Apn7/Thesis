"""Fine-tune YOLOv11n on the SafeWalkBD roadside-obstacle dataset.

SafeWalkBD (Kabir et al., 2024, CC BY 4.0) is a Bangladesh-specific roadside
object dataset for visually-impaired navigation — 16 classes including Tree,
Pole, Pothole, Stairs, Sidewalk, Vehicle, etc. COCO (the stock yolo11n weights)
covers none of these footpath hazards, which is why the phone-camera path could
not name a tree.

We start from the COCO-pretrained yolo11n.pt (transfer learning) so this
converges fast on a small laptop GPU. The resulting best.pt is then handed to
export_yolo_models.py to produce the FP16/INT8 .tflite the app ships.

Run from this directory (with the training venv active):
    python train_safewalkbd.py
"""
from __future__ import annotations

from ultralytics import YOLO

# Path to the Roboflow-exported dataset (data.yaml was edited to use an
# absolute `path:` so it resolves regardless of CWD).
DATA_YAML = r"D:/Download/SafeWalkBD.v9i.yolov11/data.yaml"

# Tuned for a 4 GB RTX 3050 Laptop GPU. yolo11n is tiny, so batch=8 @ 640px
# fits comfortably; drop to batch=4 if you ever hit a CUDA out-of-memory.
CONFIG = dict(
    data=DATA_YAML,
    epochs=80,
    imgsz=640,
    batch=8,
    device=0,            # the RTX 3050
    workers=4,           # Windows: keep modest to avoid dataloader stalls
    patience=20,         # early-stop if val mAP plateaus for 20 epochs
    project="runs_safewalkbd",
    name="yolo11n_ft",
    plots=True,          # writes confusion matrix / PR curves for the thesis
)


def main() -> None:
    model = YOLO("yolo11n.pt")  # COCO-pretrained starting point (auto-downloads)
    model.train(**CONFIG)
    print(">> Done. Best weights: runs_safewalkbd/yolo11n_ft/weights/best.pt")


if __name__ == "__main__":
    main()
