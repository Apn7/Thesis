/// Per-class detection reliability + severity tier, calibrated from the
/// SafeWalkBD validation confusion matrix
/// (`runs/detect/runs_safewalkbd/yolo11n_ft/confusion_matrix*.png`).
///
/// These are PRIORS, not magic numbers: the *relative ordering* — which is what
/// actually drives behaviour — is robust, and the absolute values can be
/// refined later from in-app detection logs WITHOUT any retraining. See
/// `FUSION_REDESIGN.md` §4.3.
class ClassProfile {
  /// `P(detect | present)` — diagonal of the normalized confusion matrix.
  final double recall;

  /// `P(detect | absent)` — background→class FP count ÷ 1059 test images.
  final double fpRate;

  /// Log-odds added on a detection: `ln(recall / fpRate)` (> 0). Large when a
  /// detection is rare-when-absent (Pothole) → one sighting can confirm.
  final double lHit;

  /// Log-odds added on a miss: `ln((1 - recall) / (1 - fpRate))` (< 0). Small
  /// magnitude when the class is missed-often-when-present (Pothole) → a
  /// confirmed cell lingers instead of being voted out.
  final double lMiss;

  /// 1 = eager hazard, 2 = proximity-gated, 3 = context/on-demand.
  final int tier;

  const ClassProfile(
    this.recall,
    this.fpRate,
    this.lHit,
    this.lMiss,
    this.tier,
  );
}

/// Keys are lowercased model labels (match `SensorFusionService._bnLabels`).
/// `lHit = ln(recall/fpRate)`, `lMiss = ln((1-recall)/(1-fpRate))`.
const Map<String, ClassProfile> kClassProfiles = {
  // Tier 1 — eager hazards (announce on strong first evidence).
  'pothole': ClassProfile(
    0.30,
    0.031,
    2.27,
    -0.33,
    1,
  ), // barely seen, ~never faked
  'stairs': ClassProfile(
    0.47,
    0.037,
    2.54,
    -0.60,
    1,
  ), // fall hazard, low recall
  'obstacle': ClassProfile(0.62, 0.236, 0.97, -0.70, 1),
  'road-barrier': ClassProfile(0.85, 0.019, 3.80, -1.88, 1),
  'train': ClassProfile(0.83, 0.029, 3.35, -1.74, 1),
  'animal': ClassProfile(0.78, 0.094, 2.12, -1.42, 1),
  'pole': ClassProfile(
    0.83,
    0.548,
    0.42,
    -0.98,
    1,
  ), // high recall BUT 580 FPs → must persist
  'vehicle': ClassProfile(
    0.78,
    0.606,
    0.25,
    -0.58,
    1,
  ), // 642 FPs → persist; TTC rescues real ones
  // Tier 2 — proximity-gated.
  'tree': ClassProfile(0.80, 0.167, 1.57, -1.43, 2),
  'person': ClassProfile(
    0.76,
    0.256,
    1.09,
    -1.13,
    2,
  ), // very common → gate on closeness
  'over-bridge': ClassProfile(0.85, 0.009, 4.51, -1.89, 2),
  'railway': ClassProfile(0.85, 0.028, 3.41, -1.87, 2),
  // Tier 3 — context / on-demand (confirmed but kept near-silent by Layer 2).
  'sidewalk': ClassProfile(0.73, 0.063, 2.45, -1.24, 3),
  'crosswalk': ClassProfile(0.92, 0.008, 4.80, -2.52, 3),
  'traffic-light': ClassProfile(0.89, 0.016, 4.02, -2.19, 3),
  'traffic-sign': ClassProfile(0.79, 0.010, 4.37, -1.55, 3),
};

/// Defensive fallback for any unmapped label: neutral evidence, mid severity.
const ClassProfile kDefaultProfile = ClassProfile(0.70, 0.10, 1.95, -1.18, 2);

/// Profile for a model label (case-insensitive), or [kDefaultProfile].
ClassProfile profileFor(String label) =>
    kClassProfiles[label.toLowerCase()] ?? kDefaultProfile;
