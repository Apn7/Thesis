import '../detection_models.dart';

/// One reasoned-about object: a confirmed `(label, zone)` cell of the existence
/// grid (Layer 1), enriched with distance + looming for the scheduler (Layer
/// 2/3). See `FUSION_REDESIGN.md`.
class Track {
  /// Raw model label (e.g. `"Pole"`), or the `'__obstacle__'` sentinel for a
  /// sonar-only "something ahead" with no camera identity.
  final String label;
  final PositionZone zone;

  /// `P(exists)` = `sigmoid(logOdds)`, 0..1 — the cell's existence confidence.
  final double existence;

  /// Most-recent bounding box for this cell (fresh if [seenThisFrame]).
  final BBox box;

  /// `(area − areaEMA) / areaEMA` this frame; `> 0` ⇒ the box is growing ⇒ the
  /// object is approaching (a discrete time-to-contact / looming cue).
  final double areaTrend;

  /// 1 = eager hazard, 2 = proximity-gated, 3 = context (from [profileFor]).
  final int tier;

  /// True if detected in the current frame (has a fresh box) vs. a confirmed
  /// cell merely lingering in memory.
  final bool seenThisFrame;

  /// 0..1 closeness, closer ⇒ 1. Set by the fusion layer (Layer 3) before
  /// scheduling — from the sonar reading if assigned, else a bbox proxy.
  double proximity;

  /// The sonar distance (cm) assigned to this track, if any.
  double? distanceCm;

  Track({
    required this.label,
    required this.zone,
    required this.existence,
    required this.box,
    required this.areaTrend,
    required this.tier,
    required this.seenThisFrame,
    this.proximity = 0.0,
    this.distanceCm,
  });
}
