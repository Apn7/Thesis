# Handoff: Sliding-Window Fusion — is it still algorithmically correct after the model change?

**Purpose:** continue this discussion in a fresh Claude session. This is an *open design question*, not a bug. Nothing below has been changed in code yet.

## Context in 30 seconds

Smart-cane assistive app for visually-impaired users in Bangladesh. On-device YOLOv11n detects obstacles from a cane-mounted Pi camera; `SensorFusionService` turns detections + ultrasonic distance into spoken bilingual (Bangla/English) alerts. Runs headless on HomeScreen.

**What just changed:** the detector was swapped from stock **COCO yolo11n (80 common classes)** to a **SafeWalkBD fine-tuned yolo11n (16 BD classes)**: `Animal, Crosswalk, Obstacle, Over-bridge, Person, Pole, Pothole, Railway, Road-barrier, Sidewalk, Stairs, Traffic-light, Traffic-sign, Train, Tree, Vehicle`. Model val metrics: mAP@50 0.761, recall ≈ 0.70.

## The current fusion algorithm (unchanged)

File: `lib/services/sensor_fusion_service.dart`. Key tunables in `lib/core/utils/constants.dart`:
- `fusionWindowSize = 5` — sliding window of last 5 frames (~0.6 s at 8–9 fps)
- `fusionMajorityThreshold = 3` — an object is *confirmed* only if it appears in ≥3 of the last 5 frames, counted once per frame per `(label, zone)`
- `fusionCooldownMs = 3000` — per-`(zone,label)` re-announce cooldown
- `fusionSonarMaxAssignCm = 400`

Logic (`onNewFrame`, ~line 265): build per-(label,zone) counts (`_buildCounts` ~427) → center = largest-bbox confirmed object, gets sonar distance (`_selectCenter` ~447); left/right = highest-count confirmed object, name only (`_bestConfirmed` ~463) → announce only zones whose confirmed label **changed** → merge into one TTS utterance → 3 s cooldown. Silent while sonar verdict = CRITICAL (HomeScreen alarm owns audio). Sonar fallback: camera blind + sonar in range ⇒ "obstacle ahead, X m".

## The concern

The 3-of-5 majority vote was a **temporal denoiser** built on two assumptions: (1) a real object persists across consecutive frames, (2) false positives are sporadic. These held for COCO's big, central, easy classes. The new BD classes may break them:

- **Low per-frame recall hazards flicker** (thin Pole, distant Pothole). Binomial: at per-frame recall p=0.5, a *truly present* object clears 3/5 only ~50% of the time; p=0.6 → ~68%; p=0.7 → ~84%. So real hazards can be **silently voted out as noise** → false negatives.
- **Failure mode flips from false-positive to false-negative.** For a cane, *missing a pole is worse than a phantom pole* — so the algorithm's conservative "suppress unless confirmed" bias may now be the wrong objective.
- **Over-frequent classes spam.** `Sidewalk`/`Crosswalk` appear nearly every frame → over-confirm (5/5) → announced constantly while adding little nav value.
- **Window vs dwell time.** 5 frames ≈ 0.6 s; a thin object the user walks past may never stay in-frame for 3 frames → can't confirm.
- **Distance-assignment heuristic** ("largest center bbox gets sonar distance") can misfire now: a big `Tree`/`Sidewalk` region stealing distance from a small foreground `Pole`.

**Partial mitigation already present:** the **sonar fallback** catches thin obstacles the camera vote drops (announces "obstacle ahead"), so *collision-safety* degrades gracefully even when *identification* fails. Worth emphasizing.

## Levers to discuss (none implemented)

1. **Per-class thresholds** instead of global 3/5: hazards (Pole, Pothole, Stairs, Road-barrier, Tree) → lower bar (2/5 or announce-on-first-confident); context (Sidewalk, Crosswalk) → whitelist out or raise bar.
2. **Window size / threshold** retune for the recall/latency/false-alarm trade.
3. **Lower inference confidence (currently 0.25)** to raise recall and let the temporal vote filter the extra FPs.
4. **Smarter distance assignment** (prefer hazard classes, or lowest/nearest-to-ground bbox).

**Still unambiguously fine, no rethink:** state-change-only + cooldown, CRITICAL priority-silence, sonar fallback.

## Recommended next step

**Don't tune blind — measure per-class, per-frame recall** (from the held-out SafeWalkBD test split of 1,059 images, or by logging live detections). That converts "I think the window is off" into a data-driven tuning section for the thesis: which classes flicker (→ lower threshold) and which spam (→ whitelist).

## Pointers
- Fusion service: `lib/services/sensor_fusion_service.dart`
- Tunables: `lib/core/utils/constants.dart` (the `fusion*` block)
- Full fine-tune details: `SAFEWALKBD_FINETUNE.md`
- Overall thesis state: `../../context.md`
