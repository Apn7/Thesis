import 'dart:math' as math;

import '../../core/utils/constants.dart';
import '../detection_models.dart';
import 'class_profiles.dart';
import 'track.dart';

/// One `(class, zone)` existence cell — a binary Bayes filter in log-odds.
class _Cell {
  double logOdds = 0.0;
  bool confirmed = false;
  BBox? lastBox;
  double areaEma = 0.0;
}

/// **Layer 1 — Bayesian existence grid (perception).**
///
/// A coarse semantic occupancy grid: one recursive binary Bayes filter per
/// `(class, zone)` cell, tracked in **log-odds** so each frame is a single
/// addition. Replaces the 3-of-5 majority vote.
///
/// Each frame, every cell that *could* exist is updated: `+lHit` if the class
/// was detected in that zone, `+lMiss` if not. Because the per-class `lHit` /
/// `lMiss` come from the detector's own confusion matrix (see
/// [class_profiles.dart]), the right behaviour emerges from one rule with no
/// hand-tuning: flickery-but-rarely-faked hazards (Pothole, Stairs) confirm on
/// first sight, while reliably-seen-but-often-faked classes (Pole, Vehicle)
/// must persist. Confirm/drop use **hysteresis** (two thresholds) to kill
/// boundary chatter, and the score is clamped to bound how long stale evidence
/// lingers. See `FUSION_REDESIGN.md` §4.
class ExistenceGrid {
  static const double _areaAlpha = 0.5; // EMA weight for the looming estimate
  final Map<String, _Cell> _cells = {}; // key: "label:zoneIndex"

  /// Feed one frame of detections. Returns every currently-**confirmed** cell
  /// as a [Track] (fresh-boxed ones flagged via [Track.seenThisFrame]).
  List<Track> update(List<Detection> detections) {
    // Keep the largest box per (label, zone) seen this frame — one observation
    // per cell, so two poles on the left don't double-count.
    final seen = <String, Detection>{};
    for (final d in detections) {
      final k = '${d.label}:${d.position.index}';
      final cur = seen[k];
      if (cur == null || d.bbox.area > cur.bbox.area) seen[k] = d;
    }

    final clamp = AppConstants.fusionLogOddsClamp;
    final keys = <String>{..._cells.keys, ...seen.keys};
    final out = <Track>[];

    for (final k in keys) {
      final sep = k.lastIndexOf(':');
      final label = k.substring(0, sep);
      final zone = PositionZone.values[int.parse(k.substring(sep + 1))];
      final prof = profileFor(label);
      final cell = _cells.putIfAbsent(k, () => _Cell());
      final hit = seen[k];

      double areaTrend = 0.0;
      if (hit != null) {
        final a = hit.bbox.area;
        final prev = cell.areaEma;
        areaTrend = prev > 0 ? (a - prev) / prev : 0.0;
        cell.areaEma = prev == 0 ? a : _areaAlpha * a + (1 - _areaAlpha) * prev;
        cell.lastBox = hit.bbox;
        cell.logOdds += prof.lHit;
      } else {
        cell.logOdds += prof.lMiss;
      }
      cell.logOdds = cell.logOdds.clamp(-clamp, clamp);

      // Hysteresis: confirm high, drop low — never flip on the boundary.
      if (!cell.confirmed &&
          cell.logOdds >= AppConstants.fusionConfirmLogOdds) {
        cell.confirmed = true;
      } else if (cell.confirmed &&
          cell.logOdds <= AppConstants.fusionDropLogOdds) {
        cell.confirmed = false;
      }

      if (cell.confirmed && cell.lastBox != null) {
        out.add(
          Track(
            label: label,
            zone: zone,
            existence: _sigmoid(cell.logOdds),
            box: cell.lastBox!,
            areaTrend: areaTrend,
            tier: prof.tier,
            seenThisFrame: hit != null,
          ),
        );
      }

      // Garbage-collect fully-decayed unconfirmed cells so the map can't grow.
      if (!cell.confirmed && cell.logOdds <= -clamp + 0.01) {
        _cells.remove(k);
      }
    }
    return out;
  }

  /// Forget all evidence (on stop / teardown).
  void reset() => _cells.clear();

  static double _sigmoid(double x) => 1 / (1 + math.exp(-x));
}
