# Domain Adaptation of On-Device YOLOv11-Nano to Bangladeshi Footpath Hazards via Fine-Tuning on SafeWalkBD

*A methodology record for the Smart Cane assistive-navigation system. This document describes how the deployed obstacle detector was adapted from a generic COCO-pretrained model to the target deployment domain. It is written to be lifted into the thesis as a self-contained chapter/section.*

> **Scope and framing.** The novel contribution of this thesis is the **integrated system** — efficient on-device inference (quantization and the FP16/INT8 study), the camera-plus-sonar sensor-fusion layer, and the bilingual Bangla/English voice interface for a smart cane. The fine-tuning described here is an **engineering step to adapt an existing detector to the deployment domain**; it is *not* claimed as a research contribution in its own right. The dataset (SafeWalkBD) and the benchmarking of YOLOv11 on it were produced by Kabir et al. (2024), and this work neither created the dataset nor attempts to advance the state of the art on it. This document is deliberately explicit about that boundary.

---

## 1. Motivation and Problem Statement

The Smart Cane companion app performs real-time obstacle detection **entirely on-device**, running a YOLOv11-nano (`yolo11n`) detector inside the Flutter application via a bundled TensorFlow Lite model. The detector exists to give a visually impaired pedestrian timely spoken warnings about hazards on the path ahead, in Bangladesh.

The originally shipped model was the **stock COCO-pretrained `yolo11n`**, which recognises the 80 generic COCO object classes (person, car, chair, laptop, etc.). In an outdoor field test (≈ 2026-06-28), this model behaved as its training data predicts: it detected **people reliably**, but **failed to detect a tree directly in the path**. This is not a defect in the model weights — it is a domain mismatch. Trees, utility/electric **poles**, **potholes**, open **drains**, **stairs**, **sidewalks**, **over-bridges**, and **road barriers** are simply **not COCO classes**, so a COCO-trained detector cannot, even in principle, report them.

The broader issue is that the common driving/general-purpose detection benchmarks do not represent the deployment environment:

- **COCO** is a general "things in everyday photos" dataset; its taxonomy is built around indoor and Western-urban objects, not pedestrian path hazards.
- **KITTI** and similar autonomous-driving datasets capture *vehicular* road scenes from a car's viewpoint, not the cluttered, unstructured, pedestrian-eye-level reality of a Bangladeshi footpath (mixed surfaces, encroachments, informal obstacles, open drains, broken pavement).

The conclusion is direct: to be useful as a navigation aid in this environment, the detector must be **adapted to Bangladeshi street/footpath objects**. This motivates fine-tuning the detector on a domain-specific dataset, **SafeWalkBD**, whose class taxonomy was designed for exactly this use case (roadside object detection for visually impaired pedestrians in Bangladesh).

---

## 2. Dataset: SafeWalkBD

### 2.1 Source and licence

SafeWalkBD is a roadside-object detection dataset purpose-built for the visually-impaired-pedestrian use case in Bangladesh, introduced and benchmarked by its authors in an IEEE conference paper. It is publicly hosted on Roboflow Universe.

| Property | Value |
|---|---|
| Dataset | SafeWalkBD |
| Authors | Kabir et al. (2024) |
| Venue | IEEE conference paper, *"SafeWalkBD: A Roadside Object Detection Dataset for Visually Impaired Pedestrians in Bangladesh"* |
| Host | Roboflow Universe |
| Workspace / project | `safewalkbd` / `safewalkbd-l8jbn` |
| Licence | CC BY 4.0 (attribution required — see References) |

### 2.2 Honest note on dataset size: 34,336 (paper) vs 10,241 (version used)

The published **paper reports 34,336 images across 16 classes**. The **publicly released Roboflow version used in this work is version 9 (v9), a curated subset of 10,241 images.** This work was therefore trained on the smaller, publicly available curated release, **not** the full corpus described in the paper. This distinction is stated up front because it directly affects how the results below should be read and compared against the paper (see §4.3).

A related clarification: the Roboflow "versions" v6–v9 are **not different datasets** — they are the *same* underlying dataset re-exported with **different augmentation recipes and curation**. v9 is the latest, curated export; it is smaller than some earlier exports precisely because the augmentation was dialled back / re-curated rather than because images were removed wholesale. v9 was chosen as the most recent curated release.

### 2.3 Split (v9)

| Split | Images | Proportion |
|---|---|---|
| Train | 7,193 | 70% |
| Validation | 1,989 | 19% |
| Test | 1,059 | 10% |
| **Total** | **10,241** | **100%** |

### 2.4 Class taxonomy (16 classes)

SafeWalkBD defines **16 classes** oriented toward pedestrian navigation hazards and cues:

| # | Class | # | Class |
|---|---|---|---|
| 1 | Animal | 9 | Road-barrier |
| 2 | Crosswalk | 10 | Sidewalk |
| 3 | Obstacle | 11 | Stairs |
| 4 | Over-bridge | 12 | Traffic-light |
| 5 | Person | 13 | Traffic-sign |
| 6 | Pole | 14 | Train |
| 7 | Pothole | 15 | Tree |
| 8 | Railway | 16 | Vehicle |

### 2.5 The COCO ↔ Bangladesh-footpath trade-off

Adopting SafeWalkBD's taxonomy is a deliberate **trade**, not a strict upgrade:

**Gained** (the decisive reason to switch): the footpath hazards that COCO cannot express at all — **Tree, Pole, Pothole, Stairs, Sidewalk, Over-bridge, Road-barrier, Crosswalk, Railway**, and a generic **Obstacle** class. These are exactly the objects a cane user must be warned about, and exactly what the COCO model missed in the field.

**Lost** (fine-grained granularity): SafeWalkBD lumps all motorised road users into a single **Vehicle** class (losing COCO's car/bus/truck/motorcycle distinctions) and all animals into a single **Animal** class (losing COCO's dog/cat/etc.).

For a **navigation aid**, this loss is acceptable. The system's job is to announce that a hazard is present and roughly where — *"vehicle ahead"* is operationally sufficient guidance for a pedestrian; the exact make/type of vehicle does not change the required behaviour (stop / steer around). The granularity that matters for safety (is there a tree/pole/pothole in my path?) is precisely what is gained.

---

## 3. Methodology

### 3.1 Approach: transfer learning (fine-tuning)

Rather than training from scratch, the detector was produced by **transfer learning** from the COCO-pretrained checkpoint:

- **Initialisation:** Ultralytics COCO-pretrained `yolo11n.pt` (pretrained on ~118k COCO images).
- **Adaptation:** the convolutional **backbone is reused** (it already encodes useful general low-/mid-level visual features), while the **detection head is rebuilt for 16 classes**. As a consequence the fine-tuned model outputs **only the 16 SafeWalkBD classes** — it no longer predicts the original 80 COCO classes.
- This is the standard, sample-efficient way to retarget a detector to a new domain when the new dataset (here 10,241 images) is far smaller than the source pretraining corpus.

### 3.2 Environment and hardware

| Component | Version / spec |
|---|---|
| Framework | Ultralytics 8.4.81 |
| Deep-learning backend | PyTorch 2.6.0 + CUDA 12.4 (`cu124`) |
| Language runtime | Python 3.13 |
| GPU | Single NVIDIA RTX 3050 Laptop GPU, 4 GB VRAM |
| Platform | Local Windows machine |

This is a deliberately modest, single-laptop-GPU training budget; it is relevant context when interpreting the achieved metrics against the paper's full-scale results (§4.3).

### 3.3 Hyperparameters

All settings were kept close to Ultralytics defaults, with the inference-time thresholds **pinned to the values used in deployment** so that training-time evaluation matches the conditions the model actually runs under on the phone.

| Hyperparameter | Value | Note |
|---|---|---|
| Epochs | 80 | with early stopping |
| Image size (`imgsz`) | 640 | |
| Batch size | 8 | constrained by 4 GB VRAM |
| Dataloader workers | 4 | |
| Optimizer | `auto` (Ultralytics) | |
| Initial learning rate (`lr0`) | 0.01 | |
| Patience (early stop) | 20 | |
| `close_mosaic` | 10 | mosaic disabled for last 10 epochs |
| Augmentation | Ultralytics defaults | |
| Confidence threshold | 0.25 | identical to deployed inference setting |
| IoU / NMS threshold | 0.45 | identical to deployed inference setting |

### 3.4 Training cost

| Metric | Value |
|---|---|
| Time per epoch | ≈ 3.4 minutes |
| Total wall-clock (80 epochs) | ≈ 4.5 hours |
| Peak VRAM | ≈ 1.2–1.8 GB |

### 3.5 Reproducibility

The full configuration is captured in the training script **`train_safewalkbd.py`** (same directory as this document). Re-running it against the SafeWalkBD v9 export reproduces the run. The exact resolved arguments for the recorded run are also stored alongside the run artifacts in `runs/detect/runs_safewalkbd/yolo11n_ft/args.yaml`.

---

## 4. Results

### 4.1 Validation metrics

The best checkpoint was selected at **epoch 69** (early stopping with patience 20 prevented running the full 80 from being the selection point). Validation performance of the best model:

| Metric | Value |
|---|---|
| mAP@50 | **0.761** |
| mAP@50–95 | **0.538** |
| Precision | ≈ 0.80 |
| Recall | ≈ 0.70 |

### 4.2 Training behaviour

Training was **healthy and well-behaved**, with **no signs of overfitting**:

- All **training and validation losses** (box, classification, DFL) decreased smoothly and then flattened.
- Critically, the **validation losses kept dropping** alongside the training losses (they did not diverge upward), which is the signature of a model that is generalising rather than memorising.
- The accuracy/mAP curve shows a **steep climb up to roughly epoch 15**, followed by a **slow crawl to a plateau around mAP@50 ≈ 0.76**.

#### Figures (thesis artifacts)

All artifacts referenced below are in `runs/detect/runs_safewalkbd/yolo11n_ft/` and can be inserted directly as thesis figures:

| Figure file | What it shows |
|---|---|
| `results.png` | Combined training/validation loss curves and metric curves over epochs |
| `confusion_matrix.png` | Raw confusion matrix across the 16 classes |
| `confusion_matrix_normalized.png` | Row-normalised confusion matrix (per-class recall view) |
| `BoxPR_curve.png` | Precision–Recall curve (detection) |
| `BoxF1_curve.png` | F1 vs confidence threshold |
| `BoxP_curve.png` | Precision vs confidence threshold |
| `BoxR_curve.png` | Recall vs confidence threshold |
| `results.csv` | Per-epoch numeric log (for re-plotting / tables) |

### 4.3 Comparison to the SafeWalkBD paper

The dataset authors benchmarked YOLOv11 on the **full** dataset and report the figures below. This comparison is included for context only — **this work does not claim to match or beat the paper**, and the two numbers are not directly comparable because they use different dataset versions, model scales, and training budgets.

| | SafeWalkBD paper (Kabir et al.) | This work (deployment adaptation) |
|---|---|---|
| Dataset used | Full SafeWalkBD | v9 curated subset (10,241 images) |
| Model | YOLOv11 | YOLOv11-**nano** (`yolo11n`) |
| mAP | 81.2% | **76.1%** (mAP@50) |
| Precision | 82.2% | ≈ 80% |
| Recall | 75.2% | ≈ 70% |
| Reported inference time | 3.04 ms/image | (efficiency reported separately, §5) |
| Hardware | (paper's setup) | single RTX 3050 Laptop, 4 GB |

**Why the gap is expected and acceptable.** The roughly 5-point mAP difference is consistent with the differences in the experimental setup, not a deficiency in method:

1. **Fewer images and lighter augmentation** — this work trained on the curated v9 subset (10,241 images), not the paper's full 34,336.
2. **Smallest model variant** — the `nano` model was chosen *deliberately* because it must run on a phone in real time; a larger YOLOv11 variant would be expected to score higher but would not meet the on-device latency budget.
3. **Constrained training budget** — a single 4 GB laptop GPU, batch size 8, ~4.5 hours.

A validation mAP@50 of 0.761 on the curated subset with a nano model on a laptop GPU is a **reasonable, honest result** for the actual goal: a detector that runs on the phone and recognises the right domain classes. The objective here was **domain adaptation for deployment**, not topping a leaderboard.

---

## 5. Deployment and Quantization

The efficiency dimension — getting this detector to run well **on the phone** — is where this work's contribution lies. The fine-tuned PyTorch checkpoint is converted to TensorFlow Lite and quantized.

### 5.1 Export pipeline

`best.pt` (PyTorch, ~5.2 MB) is converted to TensorFlow Lite by the script **`export_safewalkbd.py`** through the chain:

```
PyTorch (.pt)  →  ONNX  →  TensorFlow SavedModel  →  TFLite
```

The conversion requires an additional toolchain beyond the training environment:

| Tool | Version |
|---|---|
| tensorflow | 2.21 |
| onnx2tf | 2.3.15 |
| tf_keras | (paired with TF) |
| ai_edge_litert | (LiteRT runtime) |
| onnx_graphsurgeon | (ONNX graph cleanup) |

### 5.2 Exported variants and the FP16 ↔ INT8 pair

Two quantized variants are exported. Together they form the basis of the thesis's **quantization efficiency study**:

| Variant | File | Size | Quantization | Role |
|---|---|---|---|---|
| FP16 | `yolo11n_float16.tflite` | **5.15 MB** | Float16 | **Production model the app ships** |
| INT8 | `yolo11n_int8.tflite` | **2.87 MB** | Post-training (PTQ), int8 | Retained as a quantization-study artifact |

INT8 PTQ was **calibrated on SafeWalkBD images** using `fraction=0.1` (≈ 200 images). Calibrating on the full validation split was attempted but **ran out of memory** (an attempted ~9.75 GB tensor allocation), so the calibration set was reduced to the 10% fraction — itself a relevant, reportable finding about the practical constraints of on-device quantization.

The app **currently runs the FP16 model**; the INT8 model is kept on hand specifically so that the FP16-vs-INT8 size/accuracy/latency comparison can be reported as the quantization study, rather than being shipped as the default.

---

## 6. Integration into the Application

Replacing the COCO model with the domain-adapted one required almost no application surgery, by design:

- **Class names travel in the model.** The 16 class names are embedded in the `.tflite` **metadata**, so the Ultralytics-based plugin automatically returns human-readable labels (`"Tree"`, `"Pole"`, `"Pothole"`, …). No hard-coded app-side class list had to change.
- **Only one Dart change.** The single required application change was **extending the bilingual Bangla/English label map** to cover the 16 SafeWalkBD classes, so spoken alerts are produced in both languages for the new hazards.
- **Safe rollback.** The previous COCO model was **backed up before replacement**, so the swap is reversible.

The detector therefore drops into the existing voice-navigation and sensor-fusion pipeline unchanged: detections flow into the same announcement logic that the rest of the smart-cane system already uses.

---

## 7. Limitations and Honest Novelty Framing

This section states the boundaries of the work plainly, as a methodology chapter should.

**What is not novel here.** The **dataset is not a contribution of this thesis** — SafeWalkBD was created by Kabir et al. (2024). The **act of fine-tuning a detector** is standard transfer-learning practice, and the dataset authors had **already benchmarked YOLOv11 on SafeWalkBD**. This work neither introduces a new dataset, a new architecture, nor a new training method.

**What this step actually is.** It is **domain adaptation for deployment**: taking an off-the-shelf detector that demonstrably failed on real Bangladeshi footpath hazards and retargeting it to the classes that matter for the actual use case. It is a necessary engineering step that makes the rest of the system meaningful, but it is framed as engineering, not as research novelty.

**Where the thesis novelty genuinely lies.** The contributions are at the **system** level:

1. **On-device inference efficiency** — running detection fully on the phone, and the FP16/INT8 post-training-quantization study built on the exported model pair (§5).
2. **Sensor fusion** — combining the on-device camera detector with cane-mounted sonar distance sensing into a single hazard-alerting layer.
3. **Bilingual voice interaction** — a Bangla/English spoken interface that turns detections into actionable, accessible guidance for a visually impaired user.

**Specific limitations to acknowledge:**

- Trained on the **v9 curated subset (10,241 images)**, not the full 34,336-image corpus; absolute accuracy is correspondingly lower than the paper's full-data figure (§4.3).
- The **nano** model and single-GPU budget cap achievable accuracy; this is an intentional accuracy-for-latency trade dictated by on-phone deployment.
- The taxonomy collapses **all vehicles into one class and all animals into one class**, losing fine-grained type information (judged acceptable for a navigation aid, §2.5).
- INT8 calibration used only **~200 images (10%)** due to a memory limit, which may leave some accuracy on the table relative to full-split calibration.
- Reported detection metrics are from the **validation split**; field robustness (lighting, motion blur, partial occlusion on a moving cane) is governed by the integrated system, not by the offline mAP alone.

---

## 8. Reproduction Steps

1. **Obtain the dataset.** Download SafeWalkBD **version 9** from Roboflow Universe — workspace `safewalkbd`, project `safewalkbd-l8jbn` (CC BY 4.0; cite the authors). Export in YOLO format.
2. **Set up the environment.** Ultralytics 8.4.81, PyTorch 2.6.0 + cu124, Python 3.13. A CUDA GPU with ≥ ~2 GB free VRAM is sufficient (training peaked at ~1.2–1.8 GB).
3. **Fine-tune.** Run `train_safewalkbd.py` (starts from `yolo11n.pt`; epochs 80, imgsz 640, batch 8, workers 4, optimizer auto, lr0 0.01, patience 20, close_mosaic 10, conf 0.25, IoU 0.45). Artifacts are written to `runs/detect/runs_safewalkbd/yolo11n_ft/`; the resolved config is saved to `args.yaml`.
4. **Export and quantize.** Install the export toolchain (tensorflow 2.21, onnx2tf 2.3.15, tf_keras, ai_edge_litert, onnx_graphsurgeon) and run `export_safewalkbd.py` to produce `yolo11n_float16.tflite` and `yolo11n_int8.tflite` (INT8 calibrated with `fraction=0.1`).
5. **Deploy.** Place `yolo11n_float16.tflite` in the app's `assets/models/` (class names are read from the `.tflite` metadata; ensure the bilingual Bangla/English label map covers all 16 classes).

---

## References

1. **SafeWalkBD dataset.** Kabir et al., *"SafeWalkBD: A Roadside Object Detection Dataset for Visually Impaired Pedestrians in Bangladesh,"* IEEE, 2024. Dataset hosted on Roboflow Universe, workspace `safewalkbd`, project `safewalkbd-l8jbn`, version 9. Licence: CC BY 4.0. *(Attribution required by licence.)*

2. **YOLOv11 / Ultralytics.** Ultralytics YOLOv11 (`yolo11n`), Ultralytics framework v8.4.81. COCO-pretrained checkpoint used as the transfer-learning initialisation.

3. **COCO dataset.** Lin et al., *"Microsoft COCO: Common Objects in Context,"* ECCV 2014. *(Source of the original 80-class pretraining and of the domain mismatch motivating this work.)*
