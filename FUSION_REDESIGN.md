# Fusion Redesign: From a Majority Vote to a Calibrated Bayesian Announcer

**Status:** design spec, nothing implemented yet. Supersedes the open question in
`FUSION_SLIDING_WINDOW_HANDOFF.md`. Target file: `lib/services/sensor_fusion_service.dart`
+ a new `lib/services/fusion/` folder + the `fusion*` block in `lib/core/utils/constants.dart`.

**Hard constraint (by request):** **no machine learning of any kind.** No retraining, no
re-export, no running `best.pt`, no Python. Every number in this document is derived from the
**already-existing** SafeWalkBD validation confusion matrix on disk
(`runs/detect/runs_safewalkbd/yolo11n_ft/confusion_matrix*.png`) plus first-principles math.
Any future refinement is done by **logging detections inside the running Flutter app** (pure
Dart) — never by an ML pipeline. This is an *algorithms + code + math* change, end to end.

---

## 1. The problem, stated precisely

The current fusion layer confirms an object only when it appears in **≥3 of the last 5 frames**
(`fusionMajorityThreshold = 3`, `fusionWindowSize = 5`), counted once per `(label, zone)`. This
is — exactly, not metaphorically — the **"M-of-N" track-confirmation rule** from radar tracking
(M=3, N=5 are the canonical textbook values). It rests on two assumptions:

1. a real object is detected in *most* consecutive frames (high per-frame recall), and
2. false positives are sporadic and uncorrelated.

Both held for stock COCO's big, central classes. The SafeWalkBD fine-tune **breaks both**, and we
can prove it from the model's own confusion matrix. M-of-N has one fatal limitation: it treats
every detection as identical evidence and every *gap* as identical evidence. It cannot know that a
Pothole is hard to see but never hallucinated, while a Pole is easy to see but hallucinated
constantly. That single blind spot is the entire bug.

### 1.1 The data (read off the confusion matrix — no new ML)

`recall` = diagonal of the **normalized** matrix. `FP/frame` ≈ (background→class count in the
**raw** matrix) ÷ 1059 test images — a per-frame spurious-detection rate. `P(3-of-5)` = binomial
`P(X≥3), X~Bin(5, recall)` — the probability the *current* vote confirms a *truly present* object.

| Class | recall | FP/frame | **P(3-of-5 confirms a real object)** | Tier |
|---|---|---|---|---|
| Pothole | **0.30** | 0.031 | **0.16** ☠ | 1 |
| Stairs | **0.47** | 0.037 | **0.44** ☠ | 1 |
| Obstacle | 0.62 | 0.236 | 0.72 | 1 |
| Sidewalk | 0.73 | 0.063 | 0.85 | 3 |
| Person | 0.76 | 0.256 | 0.90 | 2 |
| Animal | 0.78 | 0.094 | 0.91 | 1 |
| Vehicle | 0.78 | **0.606** | 0.91 | 1 |
| Traffic-sign | 0.79 | 0.010 | 0.91 | 3 |
| Tree | 0.80 | 0.167 | 0.92 | 2 |
| Pole | 0.83 | **0.548** | 0.95 | 1 |
| Train | 0.83 | 0.029 | 0.95 | 1 |
| Railway | 0.85 | 0.028 | 0.96 | 2 |
| Road-barrier | 0.85 | 0.019 | 0.96 | 1 |
| Over-bridge | 0.85 | 0.009 | 0.96 | 2 |
| Traffic-light | 0.89 | 0.016 | 0.98 | 3 |
| Crosswalk | 0.92 | 0.008 | 0.99 | 3 |

Two facts jump out, and they point in **opposite** directions:

- **Pothole and Stairs — the fall hazards — are silently voted out.** A real pothole clears the
  3-of-5 bar only **16%** of the time; stairs **44%**. For a cane, *a missed hazard is far worse
  than a phantom one*, so the vote is optimizing the wrong objective for exactly the classes that
  matter most. (And these are *optimistic* upper bounds: live per-frame recall under motion blur is
  lower than test-set per-image recall.)
- **Pole and Vehicle are detected reliably but hallucinated constantly** (580 and 642 background
  FPs). So the naive fix — "lower the bar for hazards" — would turn Pole (a hazard!) into a spam
  cannon. **No single global threshold can serve both groups.** The lever has to be per-class, and
  it has to weigh recall *and* precision together.

### 1.2 Two separate jobs, currently tangled

The fusion layer is really doing two different jobs that the current code conflates:

- **Perception** — "*Is X actually there?*" Today: the 3-of-5 vote. This is where the false
  negatives happen.
- **Communication** — "*Should I say it, and when?*" Today: state-change + 3 s cooldown. This is
  where the spam/irritation happens (Sidewalk/Crosswalk at 5/5, constant "person ahead").

Separating these cleanly is the backbone of the redesign. Layer 1 owns perception; Layer 2 owns
communication; they share a clean interface (a list of confirmed tracks with existence
probabilities).

---

## 2. The reframe (and why it's defensible, not invented)

Both jobs have a textbook-correct upgrade:

- **Perception:** M-of-N's known successor is the **Sequential Probability Ratio Test (SPRT,
  Wald 1945)** / **recursive Bayesian existence estimation**. Instead of *counting* hits, you
  *accumulate log-likelihood evidence* and decide when it crosses a threshold. Implemented in
  **log-odds** form it's the same one-addition-per-update math as a **Bayesian occupancy grid**
  (Thrun/Burgard/Fox). The decisive feature: the evidence weight of a hit and of a miss are
  **derived from the sensor's own error model** — here, your confusion matrix.
- **Communication:** the assistive-navigation literature converged on treating the user's hearing
  as a **bandwidth-limited channel** — "multipriority audio," "suppress secondary cues,"
  event-triggered announcement to bound cognitive load. So Layer 2 is a **utility-ranked,
  rate-limited scheduler**, not a per-zone change detector.

This is a genuine, citable systems contribution ("a per-class Bayesian existence estimator
calibrated from the detector's confusion matrix, feeding a perception-bandwidth-constrained
announcement scheduler"), and the current 3-of-5 vote is recoverable as the **degenerate special
case** (every `L_hit=+1`, every `L_miss=0`, threshold `=3`). You lose nothing and gain a framework.

---

## 3. Architecture

```
 raw Detections (per frame, from YOLO.predict)
        │
        ▼
┌───────────────────────────────────────────────┐
│ LAYER 1 — Bayesian existence grid (PERCEPTION) │  replaces the 5-frame Queue + _buildCounts + vote
│  one log-odds score ℓ per (class, zone) cell   │
│  ℓ += L_hit  on detection, ℓ += L_miss on gap  │  weights from confusion matrix (§4)
│  confirm at ℓ≥ℓ_high, drop at ℓ≤ℓ_low (hyst.)  │
└───────────────────────────────────────────────┘
        │  confirmed tracks {label, zone, P(exist), bbox, area-trend}
        ▼
┌───────────────────────────────────────────────┐
│ LAYER 3 — distance + looming (CONTEXT)         │  replaces "largest center bbox gets distance"
│  assign sonar to nearest-ground hazard track   │
│  estimate time-to-contact from bbox growth     │
└───────────────────────────────────────────────┘
        │  enriched tracks {…, distance?, ttc?}
        ▼
┌───────────────────────────────────────────────┐
│ LAYER 2 — announcement scheduler (COMMUNICATE) │  replaces state-change + binary cooldown
│  U = severity·proximity·novelty·conf·looming   │
│  token-bucket rate limit, Tier-1 preempts      │
│  emit ≤1 merged utterance per window           │
└───────────────────────────────────────────────┘
        │
        ▼   TtsService.speak(...)   (CRITICAL-silence + bilingual phrasing unchanged)
```

**Efficiency note (this is also a *performance* win, not just a quality one):** the existence grid
is **O(detections + cells)** per frame with a single float add per cell, and it **deletes the
`Queue<List<Detection>>` window entirely** — you keep one scalar per cell instead of 5 frames of
boxed detections, and you stop rebuilding the count map from scratch every frame
(`_buildCounts` is O(window×detections) today). All of Layer 1–3 is negligible next to the ~90 ms
YOLO inference.

---

## 4. Layer 1 — Per-class Bayesian existence filter

### 4.1 The math

Model each `(class, zone)` cell as a binary state: object **present** (`E`) or **absent** (`¬E`).
Track the **log-odds** of existence:

```
ℓ = ln( P(E) / P(¬E) )            ℓ=0 ⇔ P=0.5 ;  ℓ=+0.85 ⇔ P≈0.70 ;  ℓ=-0.85 ⇔ P≈0.30
```

Bayes' rule in log-odds form turns each frame's observation into one **addition**:

```
ℓ ← ℓ + Δ            where  Δ = ln( P(obs | E) / P(obs | ¬E) )
```

There are two observations per cell per frame — "detected" or "not detected" — so two constants:

```
detection this frame:   L_hit(c)  = ln(  recall_c      /  fpRate_c      )   (> 0)
no detection:           L_miss(c) = ln( (1 - recall_c) / (1 - fpRate_c) )   (< 0)
```

- `recall_c   = P(detect | present)` → confusion-matrix diagonal.
- `fpRate_c   = P(detect | absent)`  → background→class FP rate per frame.

That's the whole derivation. The intuition each term encodes:

- **`L_hit` is large when detections are rare-when-absent.** A Pothole detection is *strong*
  evidence (potholes are almost never hallucinated), so one sighting can confirm. A Pole detection
  is *weak* evidence (poles are hallucinated constantly), so it takes several.
- **`L_miss` is small-magnitude when the class is missed-often-when-present.** A Pothole *gap* is
  weak evidence of absence (we miss 70% of real ones anyway), so a confirmed pothole *lingers*. A
  Pole gap is strong evidence of absence (we usually see real poles), so a phantom pole *evaporates*.

### 4.2 Confirmation, hysteresis, bounded memory

```
confirmed  ⇔ ℓ ≥ ℓ_high   (default +0.85, P≈0.70)
dropped    ⇔ ℓ ≤ ℓ_low    (default -0.85, P≈0.30)
ℓ clamped to [ℓ_min, ℓ_max] (default ±3.0) — bounds how long stale evidence persists
```

The **two thresholds** (not one) give **hysteresis**: a cell hovering near the boundary can't
chatter confirmed/dropped/confirmed — it must travel the whole gap to flip. This is the principled
version of "denoising." The clamp `ℓ_max` sets the **memory length**: after a single +2.27 Pothole
hit (clamped toward +3.0), with `L_miss=-0.33` the cell stays confirmed for ~`3.0/0.33 ≈ 9` frames
(~1 s at 8–9 fps) of pure misses — enough dwell time to speak, not so long it goes stale.

### 4.3 The calibration table (computed here, frozen into constants — this is the "no-ML" payload)

Every value below is `ln(recall/fp)` and `ln((1-recall)/(1-fp))` from §1.1. **These are priors:**
the *relative ordering* (Pothole eager, Pole cautious) is robust and is what drives behavior; the
absolute values can later be nudged from in-app logs (§7) without retraining anything.

```dart
// lib/services/fusion/class_profiles.dart
//
// Calibrated from the SafeWalkBD validation confusion matrix
// (runs/detect/runs_safewalkbd/yolo11n_ft/confusion_matrix*.png).
// recall = normalized-matrix diagonal; fpRate = raw background→class / 1059 imgs.
// lHit = ln(recall/fpRate);  lMiss = ln((1-recall)/(1-fpRate)).
// tier: 1 = eager hazard, 2 = proximity-gated, 3 = context/on-demand.
class ClassProfile {
  final double recall, fpRate, lHit, lMiss;
  final int tier;
  const ClassProfile(this.recall, this.fpRate, this.lHit, this.lMiss, this.tier);
}

// keys are lowercased model labels (match _bnLabels)
const Map<String, ClassProfile> kClassProfiles = {
  'pothole':       ClassProfile(0.30, 0.031, 2.27, -0.33, 1), // eager: barely seen, ~never faked
  'stairs':        ClassProfile(0.47, 0.037, 2.54, -0.60, 1), // eager: fall hazard, low recall
  'obstacle':      ClassProfile(0.62, 0.236, 0.97, -0.70, 1),
  'road-barrier':  ClassProfile(0.85, 0.019, 3.80, -1.88, 1),
  'train':         ClassProfile(0.83, 0.029, 3.35, -1.74, 1),
  'animal':        ClassProfile(0.78, 0.094, 2.12, -1.42, 1),
  'pole':          ClassProfile(0.83, 0.548, 0.42, -0.98, 1), // cautious: high recall BUT 580 FPs
  'vehicle':       ClassProfile(0.78, 0.606, 0.25, -0.58, 1), // cautious: 642 FPs; rescued by TTC
  'tree':          ClassProfile(0.80, 0.167, 1.57, -1.43, 2),
  'person':        ClassProfile(0.76, 0.256, 1.09, -1.13, 2), // common → Tier 2, proximity-gated
  'over-bridge':   ClassProfile(0.85, 0.009, 4.51, -1.89, 2),
  'railway':       ClassProfile(0.85, 0.028, 3.41, -1.87, 2),
  'sidewalk':      ClassProfile(0.73, 0.063, 2.45, -1.24, 3), // context: announce on transition only
  'crosswalk':     ClassProfile(0.92, 0.008, 4.80, -2.52, 3),
  'traffic-light': ClassProfile(0.89, 0.016, 4.02, -2.19, 3),
  'traffic-sign':  ClassProfile(0.79, 0.010, 4.37, -1.55, 3),
};

// Fallback for any unmapped label (defensive): neutral evidence, mid severity.
const ClassProfile kDefaultProfile = ClassProfile(0.70, 0.10, 1.95, -1.18, 2);
```

### 4.4 Worked behavior (what the table *does*, vs the old vote)

| Class | +L_hit | −L_miss | New behavior (ℓ_high=+0.85) | Old 3-of-5 |
|---|---|---|---|---|
| **Pothole** | +2.27 | −0.33 | **confirms on the 1st confident sight**, lingers ~9 frames | confirmed **16%** of the time → usually **silent** ☠ |
| **Stairs** | +2.54 | −0.60 | **confirms on 1st sight**, lingers ~5 frames | confirmed 44% of the time ☠ |
| **Pole** | +0.42 | −0.98 | needs **~3 consistent hits**; a phantom dies in **1 miss** | every flicker counts equally → 580 FPs leak through |
| **Vehicle** | +0.25 | −0.58 | needs ~4 hits (kills 642 FPs); real approach saved by §6 | same FP leakage |
| **Tree** | +1.57 | −1.43 | confirms in 1–2 hits, decays fast | fine already |

The headline for the thesis: **a pothole announces instantly and a phantom pole stays silent from
the *same* update rule, with zero hand-tuning** — the asymmetry is computed from the detector's own
error profile. That is the sentence that makes this look like engineering rather than knob-twiddling.

### 4.5 Code sketch

```dart
// lib/services/fusion/existence_grid.dart
import 'dart:math' as math;
import '../detection_models.dart';
import 'class_profiles.dart';

/// One (label, zone) existence cell — a binary Bayes filter in log-odds.
class _Cell {
  double logOdds = 0.0;
  bool confirmed = false;
  BBox? lastBox;        // for Layer 3 looming / distance assignment
  double areaEma = 0.0; // EMA of bbox area, for looming
  DateTime lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
}

class ExistenceGrid {
  static const double lHigh = 0.85, lLow = -0.85, lClamp = 3.0;
  static const double _areaAlpha = 0.5; // EMA weight for looming
  final Map<String, _Cell> _cells = {}; // key: "label:zone"

  /// Feed one frame. Returns the set of currently-confirmed tracks.
  List<Track> update(List<Detection> dets) {
    // 1) which (label,zone) cells were detected this frame, keep the biggest box
    final seen = <String, Detection>{};
    for (final d in dets) {
      final k = '${d.label}:${d.position}';
      final cur = seen[k];
      if (cur == null || d.bbox.area > cur.bbox.area) seen[k] = d;
    }
    // 2) every cell that COULD exist gets an update: hit if seen, miss if not.
    //    (union of existing cells and freshly-seen ones)
    final keys = {..._cells.keys, ...seen.keys};
    final out = <Track>[];
    for (final k in keys) {
      final label = k.substring(0, k.lastIndexOf(':'));
      final prof = kClassProfiles[label.toLowerCase()] ?? kDefaultProfile;
      final cell = _cells.putIfAbsent(k, () => _Cell());
      final hit = seen[k];
      if (hit != null) {
        cell.logOdds += prof.lHit;
        cell.lastBox = hit.bbox;
        cell.areaEma = cell.areaEma == 0
            ? hit.bbox.area
            : _areaAlpha * hit.bbox.area + (1 - _areaAlpha) * cell.areaEma;
        cell.lastSeen = DateTime.now();
      } else {
        cell.logOdds += prof.lMiss;
      }
      cell.logOdds = cell.logOdds.clamp(-lClamp, lClamp);

      // hysteresis
      if (!cell.confirmed && cell.logOdds >= lHigh) cell.confirmed = true;
      if (cell.confirmed && cell.logOdds <= lLow)  cell.confirmed = false;

      if (cell.confirmed && hit != null) {
        out.add(Track(
          label: label,
          zone: hit.position,
          existence: _sigmoid(cell.logOdds),
          box: hit.bbox,
          areaTrend: cell.areaEma == 0 ? 0 : (hit.bbox.area - cell.areaEma) / cell.areaEma,
          tier: prof.tier,
        ));
      }
      // GC fully-decayed cells so the map can't grow unbounded
      if (cell.logOdds <= -lClamp + 0.01 && !cell.confirmed) _cells.remove(k);
    }
    return out;
  }

  static double _sigmoid(double x) => 1 / (1 + math.exp(-x));
}
```

> **Note on confirmed-but-not-seen-this-frame:** the sketch only emits a `Track` when the cell is
> *also* detected in the current frame (so we have a fresh box for distance/phrasing). A confirmed
> cell with no current box still *exists* in the grid and keeps its place — it simply isn't a fresh
> announce candidate that frame, which is the behavior we want (lingering memory, but we speak about
> things we can currently localize). The lingering matters for **not re-announcing** in Layer 2.

**Known limitation (carried over, not introduced): zone hand-off.** An object crossing
left→center is two cells, so its evidence doesn't transfer. The old vote had the identical issue.
Cheap mitigation if it bites in field test: on a zone transition for the same label, seed the new
cell with a fraction of the old cell's `ℓ`. In practice high-`L_hit` classes re-confirm in the new
zone within 1–2 frames, so this is a *nice-to-have*, listed as a tunable, not a blocker.

---

## 5. Layer 2 — Perception-bandwidth scheduler

### 5.1 The model

A blind user can absorb roughly **one short phrase per ~2–3 s** before speech becomes noise. So the
scheduler's job is: *given all confirmed tracks, say the single most useful thing — or stay quiet.*
Each confirmed track gets a **utility** in `[0, ∞)`:

```
U(track) = severity(class) · proximity · novelty · confidence · looming
```

| Factor | Range | Meaning / source |
|---|---|---|
| `severity` | tier weight | Tier 1 = 1.0, Tier 2 = 0.5, Tier 3 = 0.15 (from `kClassProfiles`) |
| `proximity` | 0..1 | from sonar distance if assigned (§6), else bbox size/bottom-edge proxy; closer → 1 |
| `novelty` | 0..1 | 0 right after announcing this (label,zone), ramps to 1 over `refractoryMs`; **replaces the binary cooldown** |
| `confidence` | 0..1 | the existence probability `σ(ℓ)` from Layer 1 |
| `looming` | ≥1 | `1 + k·max(0, areaTrend)` — approaching objects get boosted (§6) |

### 5.2 Severity tiers (the spam fix, made explicit — your "12 actionable classes")

- **Tier 1 — announce eagerly** (trip / fall / collision): Pothole, Stairs, Pole, Road-barrier,
  Vehicle, Train, Animal, Obstacle.
- **Tier 2 — only when near or approaching**: Tree, Person, Over-bridge, Railway. *(Person is the
  single biggest spam risk — extremely frequent — so it lives here, gated hard on proximity/looming.)*
- **Tier 3 — context, on-transition / on-demand only**: Sidewalk, Crosswalk, Traffic-light,
  Traffic-sign. These are *confirmed* by Layer 1 (they really are there) but their low severity +
  novelty decay keeps them near-silent — surfacing on a **transition** (e.g. "sidewalk ending") or
  when the user asks "what's ahead?". **This is the direct cure for the Sidewalk/Crosswalk 5/5 spam.**

Tier 1 ∪ Tier 2-collision = your ~**12 actionable classes**; the 4 Tier-3 are the context cues you
said you don't want nagging the user. Layer 1 = *perception* (know everything), Layer 2 = *policy*
(say little).

### 5.3 The arbiter (rate-limit + preemption)

```dart
// lib/services/fusion/announcement_scheduler.dart
class AnnouncementScheduler {
  final Map<String, DateTime> _lastSpoken = {}; // "label:zone" -> when
  DateTime _bucketRefill = DateTime.fromMillisecondsSinceEpoch(0);

  static const _minGapMs = 2500;       // normal cadence (token bucket, capacity 1)
  static const _preemptGapMs = 800;    // hard floor even for preempting Tier-1
  static const _refractoryMs = 6000;   // novelty fully recovers after this
  static const _utilityFloor = 0.20;   // below this, say nothing

  /// Returns the labels to merge into one utterance this cycle (≤2), or [].
  List<Track> select(List<Track> confirmed, {required bool critical}) {
    if (critical) return const []; // HomeScreen alarm owns audio — unchanged
    final now = DateTime.now();

    final scored = confirmed
        .map((t) => (t, _utility(t, now)))
        .where((e) => e.$2 >= _utilityFloor)
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    if (scored.isEmpty) return const [];

    final top = scored.first.$1;
    final preempting = top.tier == 1 && scored.first.$2 >= 0.8;
    final sinceRefill = now.difference(_bucketRefill).inMilliseconds;
    final allowed = sinceRefill >= _minGapMs ||
        (preempting && sinceRefill >= _preemptGapMs);
    if (!allowed) return const [];

    _bucketRefill = now;
    // Merge the top hazard with at most one more *different-zone* item (center-first),
    // so the user still gets a compact picture without a paragraph.
    final picks = <Track>[top];
    for (final e in scored.skip(1)) {
      if (e.$1.zone != top.zone && picks.length < 2) { picks.add(e.$1); break; }
    }
    for (final p in picks) _lastSpoken['${p.label}:${p.zone}'] = now;
    return picks;
  }

  double _utility(Track t, DateTime now) {
    final sev = switch (t.tier) { 1 => 1.0, 2 => 0.5, _ => 0.15 };
    final prox = t.proximity;            // 0..1, set by Layer 3 (default 0.4 if unknown)
    final last = _lastSpoken['${t.label}:${t.zone}'];
    final nov = last == null
        ? 1.0
        : (now.difference(last).inMilliseconds / _refractoryMs).clamp(0.0, 1.0);
    final loom = 1.0 + 1.5 * (t.areaTrend > 0 ? t.areaTrend : 0.0);
    return sev * prox * nov * t.existence * loom;
  }
}
```

What this buys, concretely:
- **Bounded load:** at most one utterance per `_minGapMs`, *always the most useful one*. The user is
  never flooded, even when 6 things are confirmed.
- **Smooth re-announce:** `novelty` replaces the hard 3 s cooldown — something only repeats once it's
  meaningfully fresh again (or has become urgent via proximity/looming).
- **Safety preemption:** a close Tier-1 hazard (pothole right ahead) can jump the queue at the 800 ms
  floor instead of waiting out the 2.5 s cadence — without ever stuttering.
- **Context goes quiet:** Sidewalk/Crosswalk score `0.15 · …` and almost never win the arbiter.

---

## 6. Layer 3 — Distance assignment + time-to-contact

### 6.1 Fix the distance theft

Today the sonar reading goes to the **largest** center bbox — so a big background Tree or Sidewalk
region can steal the distance from a small foreground Pole. The cane camera sees near hazards **low
in the frame**, so use **ground contact**, weighted by severity:

```dart
// among confirmed center-zone tracks, pick the nearest ground-contacting hazard
Track? assignDistanceTarget(List<Track> centerTracks) {
  Track? best; double bestScore = -1;
  for (final t in centerTracks) {
    final ground = t.box.y2;                     // lower edge; larger = closer to bottom = nearer
    final sev = switch (t.tier) { 1 => 1.0, 2 => 0.6, _ => 0.2 };
    final score = ground * sev;                  // nearest-ground hazard wins the sonar reading
    if (score > bestScore) { bestScore = score; best = t; }
  }
  return best;
}
```

The HC-SR04 has a wide cone and returns one number, so this is a heuristic either way — but
"nearest ground-contacting hazard" is a strictly better prior than "biggest box" for a cane.

### 6.2 Looming = a cheap time-to-contact signal (Lee's τ)

The optical variable **τ** (Lee 1976) — inverse relative expansion rate of an object's image —
approximates time-to-contact, and bounding-box **area growth** is a discrete estimate of it. Layer 1
already maintains `areaEma`, so `areaTrend = (area_now − areaEma)/areaEma` is free. A *growing* box
means *approaching*:

- feeds `looming` in the utility (a vehicle bearing down beats a parked one), and
- **rescues the high-FP Vehicle/Pole classes**: a real approaching vehicle *looms* and earns
  urgency; a one-frame phantom doesn't loom and is filtered by Layer 1 anyway. This is the missing
  third axis that makes trusting these classes safe despite their FP counts.

Optional phrase upgrade: when `areaTrend` is strongly positive on a Tier-1 track, switch wording to
the approaching form ("vehicle approaching" / "গাড়ি এগিয়ে আসছে") instead of static "vehicle ahead".

---

## 7. What stays exactly as-is

These were correctly flagged "unambiguously fine" and are untouched:

- **CRITICAL priority-silence** — fusion stays mute while sonar verdict = CRITICAL (HomeScreen alarm
  owns audio).
- **Sonar-only fallback** — camera blind + sonar in range ⇒ "obstacle ahead, X m" (glass/thin poles).
  Still the graceful-degradation safety net.
- **One merged utterance per cycle**, center-first (TtsService interrupts on every `speak`).
- **All bilingual phrasing** (`_centerPhrase`/`_sidePhrase`/`_obstaclePhrase`, `_bnLabels`, Bangla digits).
- **The inference pipeline** (`_maybeProcess`, single-inflight `_busy`, frame-id dedupe) and the
  **debug surface** (`latestDetections`, `confirmedCenter/Left/Right`, `latestProcessedJpeg`, fps/latency).
  `confirmed*` getters now report the existence-confirmed labels instead of vote-confirmed ones.

`onNewFrame(List<Detection>)` keeps its signature, so the existing unit-testability is preserved.

---

## 8. Constants changes (additive — keep the old ones for A/B)

```dart
// lib/core/utils/constants.dart  — keep fusionWindowSize/fusionMajorityThreshold so the OLD
// algorithm stays runnable for the thesis A/B comparison; add:

// Layer 1 — existence filter
static const double fusionConfirmLogOdds  = 0.85;   // ℓ_high  (P≈0.70)
static const double fusionDropLogOdds     = -0.85;  // ℓ_low   (P≈0.30)
static const double fusionLogOddsClamp    = 3.0;    // ±memory bound
// Layer 2 — scheduler
static const int    fusionMinGapMs        = 2500;   // token-bucket cadence
static const int    fusionPreemptGapMs    = 800;    // Tier-1 preemption floor
static const int    fusionRefractoryMs    = 6000;   // novelty recovery
static const double fusionUtilityFloor    = 0.20;   // silence below this
// master toggle so you can flip OLD↔NEW at runtime for the thesis
static const bool   fusionUseBayesian     = true;
```

Suggested new files (keeps `sensor_fusion_service.dart` readable; or inline if you prefer):
`lib/services/fusion/class_profiles.dart`, `existence_grid.dart`, `announcement_scheduler.dart`,
`track.dart`.

---

## 9. Validation & thesis measurement — **all in-app, zero ML**

The point is a *measured* before/after, produced without any training/validation pipeline:

1. **Structured diagnostics** (mirror `IntentMatcher.MatchDiagnostics`): per frame, emit a
   `FusionDiagnostics.toJson()` with each confirmed cell's `ℓ`, confirm/drop events, and the
   scheduler's candidate utilities + what was spoken vs suppressed. Pure `debugPrint`/JSON.
2. **Record once, replay offline.** `onNewFrame` is a pure function of (detections, distance). Dump a
   real session's detection+distance stream to a JSON fixture (just run the app on the cane and log).
   Then a **Dart unit test** replays that *same* stream through the OLD vote and the NEW pipeline and
   prints both metric sets. No camera, no Pi, no Python needed for the comparison.
3. **Metrics** (all computable from the logs):
   - **Time-to-first-announce** per hazard appearance (lower = safer).
   - **Missed-hazard proxy:** object present in raw detections ≥k frames but never announced
     (this is where the old vote's Pothole/Stairs failures show up as a hard number).
   - **Announcement load:** utterances/minute, and Tier-3 share of utterances (spam indicator).
   - **Re-announce rate** for the same object (irritation indicator).
4. **Tunables for the thesis sweep** (each a single constant, no retrain): `ℓ_high/ℓ_low` (recall vs
   false-alarm), `ℓ_clamp` (memory/dwell), `minGap/refractory` (load), tier weights.

Expected story in the write-up: **the Bayesian announcer recovers the Pothole/Stairs hazards the
3-of-5 vote dropped (time-to-first-announce goes from "never" to ~1 frame) while *cutting* total
utterances/minute and Tier-3 spam** — i.e. simultaneously safer *and* quieter, which a single global
threshold provably cannot achieve.

---

## 10. Phased rollout (each phase ships and is measurable on its own)

- **Phase 1 — Layer 1 (existence grid).** Drop-in for `_buildCounts`/`_selectCenter`/`_bestConfirmed`;
  everything downstream keeps working. **Fixes the safety problem (false negatives).** Smallest,
  highest-value, fully unit-testable via `onNewFrame`. *Recommended first.*
- **Phase 2 — Layer 2 (scheduler).** Replace state-change+cooldown with utility+token-bucket+tiers.
  **Fixes the irritation problem.**
- **Phase 3 — Layer 3 (distance + looming).** Ground-contact distance assignment + TTC urgency +
  "approaching" phrasing.

Phases 1 and 2 are independent enough that either can land first; Layer 3 enriches both but neither
depends on it.

---

## 11. References

- A. Wald, *Sequential Analysis*, 1947 (the SPRT — the optimal sequential test M-of-N approximates).
- S. Blackman & R. Popoli, *Design and Analysis of Modern Tracking Systems*, 1999 (M-of-N track
  confirmation; SPRT-based confirmation/rejection).
- S. Thrun, W. Burgard, D. Fox, *Probabilistic Robotics*, 2005 (binary Bayes filter / occupancy
  grids in log-odds form — the existence-filter math).
- D. N. Lee, "A theory of visual control of braking based on information about time-to-collision,"
  *Perception*, 1976 (τ / looming → time-to-contact).
- Recent assistive-nav framing of audio as a bandwidth-limited channel (multipriority announcement,
  cognitive-load minimization): MDPI Sensors 24(11):3572, 2024; "Less is More" (arXiv:2511.00945).
- Source data: SafeWalkBD validation confusion matrix, this repo,
  `runs/detect/runs_safewalkbd/yolo11n_ft/confusion_matrix*.png` (Kabir et al. 2024 dataset).
```
