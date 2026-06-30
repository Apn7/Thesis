import '../../core/utils/constants.dart';
import 'track.dart';

/// **Layer 2 — perception-bandwidth scheduler (communication).**
///
/// Treats the blind user's hearing as a low-bandwidth channel. Each cycle it
/// scores every confirmed track by **utility** and emits at most one short
/// utterance (≤2 zones merged) per cadence window, letting a close Tier-1
/// hazard preempt. Replaces the binary state-change + fixed cooldown, which is
/// why Sidewalk/Crosswalk stop spamming and real hazards still get through.
///
/// ```
/// U = severity(tier) · proximity · novelty · existence · looming
/// ```
///
/// See `FUSION_REDESIGN.md` §5.
class AnnouncementScheduler {
  /// `"label:zoneIndex"` → when it was last spoken (drives the novelty decay).
  final Map<String, DateTime> _lastSpoken = {};
  DateTime _bucketRefill = DateTime.fromMillisecondsSinceEpoch(0);

  /// Debug-only: the utility scored for every candidate this cycle (keyed
  /// `"label:zoneIndex"`), **including** ones below the floor. Lets the on-screen
  /// panel explain why a track did or didn't earn the channel. Not used by the
  /// audio logic.
  final Map<String, double> lastUtilities = {};

  /// Debug-only: the tracks actually selected to speak this cycle (`[]` if the
  /// scheduler stayed silent — rate-limited, below floor, or nothing fresh).
  List<Track> lastPicks = const [];

  void reset() {
    _lastSpoken.clear();
    _bucketRefill = DateTime.fromMillisecondsSinceEpoch(0);
    lastUtilities.clear();
    lastPicks = const [];
  }

  /// The tracks to speak this cycle (caller orders the utterance), or `[]` to
  /// stay silent. [tracks] should be the fresh confirmed tracks.
  List<Track> select(List<Track> tracks, {required DateTime now}) {
    lastUtilities.clear();
    lastPicks = const [];
    final scored = <(Track, double)>[];
    for (final t in tracks) {
      final u = _utility(t, now);
      lastUtilities['${t.label}:${t.zone.index}'] = u;
      if (u >= AppConstants.fusionUtilityFloor) scored.add((t, u));
    }
    if (scored.isEmpty) return const [];
    scored.sort((a, b) => b.$2.compareTo(a.$2));

    final top = scored.first;
    // A close, high-utility Tier-1 hazard may jump the cadence queue (down to a
    // short hard floor) instead of waiting out the normal gap.
    final preempting = top.$1.tier == 1 && top.$2 >= 0.8;
    final sinceMs = now.difference(_bucketRefill).inMilliseconds;
    final allowed =
        sinceMs >= AppConstants.fusionMinGapMs ||
        (preempting && sinceMs >= AppConstants.fusionPreemptGapMs);
    if (!allowed) return const [];

    _bucketRefill = now;
    final picks = <Track>[top.$1];
    // Add at most one more item, from a different zone, to paint a compact
    // picture without turning into a paragraph.
    for (final e in scored.skip(1)) {
      if (picks.length >= 2) break;
      if (e.$1.zone != top.$1.zone) {
        picks.add(e.$1);
        break;
      }
    }
    for (final p in picks) {
      _lastSpoken['${p.label}:${p.zone.index}'] = now;
    }
    lastPicks = picks;
    return picks;
  }

  double _utility(Track t, DateTime now) {
    final severity = t.tier == 1
        ? 1.0
        : t.tier == 2
        ? 0.5
        : 0.15;
    final last = _lastSpoken['${t.label}:${t.zone.index}'];
    final novelty = last == null
        ? 1.0
        : (now.difference(last).inMilliseconds /
                  AppConstants.fusionRefractoryMs)
              .clamp(0.0, 1.0);
    final looming = 1.0 + 1.5 * (t.areaTrend > 0 ? t.areaTrend : 0.0);
    return severity * t.proximity * novelty * t.existence * looming;
  }
}
