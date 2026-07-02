import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:test_app_1/services/detection_models.dart';
import 'package:test_app_1/services/fusion/announcement_scheduler.dart';
import 'package:test_app_1/services/fusion/existence_grid.dart';
import 'package:test_app_1/services/fusion/track.dart';

/// A detection of [label] with a square box of the given [area] centered at
/// horizontal position [cx] (0=left edge .. 1=right edge → drives the zone).
Detection _det(String label, {double cx = 0.5, double area = 0.04}) {
  final half = math.sqrt(area) / 2;
  return Detection(
    classId: 0,
    label: label,
    confidence: 0.6,
    bbox: BBox(cx - half, 0.5 - half, cx + half, 0.5 + half),
  );
}

Track _trk(
  String label, {
  required int tier,
  double existence = 0.9,
  double proximity = 0.7,
  double areaTrend = 0,
  PositionZone zone = PositionZone.center,
}) {
  return Track(
    label: label,
    zone: zone,
    existence: existence,
    box: const BBox(0.4, 0.5, 0.6, 0.9),
    areaTrend: areaTrend,
    tier: tier,
    seenThisFrame: true,
    proximity: proximity,
  );
}

bool _has(List<Track> tracks, String label) =>
    tracks.any((t) => t.label == label);

void main() {
  group('ExistenceGrid (Layer 1 — perception)', () {
    test(
      'Pothole confirms on the FIRST detection (rarely faked ⇒ trust it)',
      () {
        // The bug it fixes: the 3-of-5 vote confirmed a real pothole only ~16%
        // of the time. Here one sighting (lHit=+2.27 ≥ +0.85) is enough.
        final grid = ExistenceGrid();
        expect(_has(grid.update([_det('Pothole')]), 'Pothole'), isTrue);
      },
    );

    test('a lone Pole false-positive NEVER confirms (spam suppression)', () {
      // Pole has 580 background FPs; one hit (lHit=+0.42) must not announce.
      final grid = ExistenceGrid();
      expect(_has(grid.update([_det('Pole')]), 'Pole'), isFalse);
      expect(_has(grid.update(const []), 'Pole'), isFalse);
      expect(_has(grid.update(const []), 'Pole'), isFalse);
    });

    test('a sustained real Pole confirms within a few frames', () {
      final grid = ExistenceGrid();
      grid.update([_det('Pole')]); // +0.42
      grid.update([_det('Pole')]); // +0.84
      expect(_has(grid.update([_det('Pole')]), 'Pole'), isTrue); // +1.26 ≥ 0.85
    });

    test('a confirmed Pole survives a single missed frame (hysteresis)', () {
      final grid = ExistenceGrid();
      grid.update([_det('Pole')]);
      grid.update([_det('Pole')]);
      grid.update([_det('Pole')]); // confirmed (~+1.26)
      final out = grid.update(
        const [],
      ); // miss −0.98 → +0.28, still > drop(−0.85)
      final pole = out.where((t) => t.label == 'Pole').toList();
      expect(pole, hasLength(1), reason: 'still confirmed, just lingering');
      expect(pole.single.seenThisFrame, isFalse);
    });

    test(
      'zones are independent: a left Pole is a different cell from center',
      () {
        final grid = ExistenceGrid();
        final out = grid.update([_det('Tree', cx: 0.1)]); // left
        final tree = out.where((t) => t.label == 'Tree');
        expect(tree, hasLength(1));
        expect(tree.single.zone, PositionZone.left);
      },
    );
  });

  group('AnnouncementScheduler (Layer 2 — communication)', () {
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);

    test('Tier-3 context (Sidewalk) is suppressed while a hazard speaks', () {
      // Sidewalk is perceptually confirmed but must not win the channel.
      final s = AnnouncementScheduler();
      final picks = s.select([
        _trk('Pothole', tier: 1, existence: 0.9, proximity: 0.7),
        _trk('Sidewalk', tier: 3, existence: 0.95, proximity: 0.8),
      ], now: t0);
      expect(_has(picks, 'Pothole'), isTrue);
      expect(_has(picks, 'Sidewalk'), isFalse);
    });

    test('rate-limits within the cadence window, then speaks again', () {
      final s = AnnouncementScheduler();
      expect(
        _has(s.select([_trk('Pothole', tier: 1)], now: t0), 'Pothole'),
        isTrue,
      );
      // 100 ms later: inside the gap + novelty barely recovered ⇒ silent.
      expect(
        s.select([
          _trk('Pothole', tier: 1),
        ], now: t0.add(const Duration(milliseconds: 100))),
        isEmpty,
      );
      // 3 s later: past the gap, novelty recovered ⇒ speaks again.
      expect(
        _has(
          s.select([
            _trk('Pothole', tier: 1),
          ], now: t0.add(const Duration(seconds: 3))),
          'Pothole',
        ),
        isTrue,
      );
    });

    test('a close, looming Tier-1 hazard preempts the cadence', () {
      final s = AnnouncementScheduler();
      s.select([_trk('Vehicle', tier: 1)], now: t0); // consumes the bucket
      // 1 s later (< 2.5 s gap, > 0.8 s floor): a new, close, approaching Pole
      // has utility ≥ 0.8 ⇒ it may jump the queue.
      final picks = s.select([
        _trk('Pole', tier: 1, existence: 1.0, proximity: 1.0, areaTrend: 0.5),
      ], now: t0.add(const Duration(seconds: 1)));
      expect(_has(picks, 'Pole'), isTrue);
    });

    test('nothing is said when every candidate is below the utility floor', () {
      final s = AnnouncementScheduler();
      // A far, low-confidence Tier-2 person: 0.5·0.2·1·0.5 = 0.05 < 0.20.
      final picks = s.select([
        _trk('Person', tier: 2, existence: 0.5, proximity: 0.2),
      ], now: t0);
      expect(picks, isEmpty);
    });

    test('ttsBusy defers an ordinary callout WITHOUT burning novelty', () {
      final s = AnnouncementScheduler();
      // The TTS channel is mid-utterance (e.g. the WARNING escalation speech):
      // a moderate track must wait its turn, not cut the safety speech off.
      final held = s.select(
        [_trk('Tree', tier: 2, existence: 0.9, proximity: 0.6)],
        now: t0,
        ttsBusy: true,
      );
      expect(held, isEmpty);
      // The moment the channel frees up, the SAME callout goes out — novelty
      // was not consumed by the deferral.
      final picks = s.select([
        _trk('Tree', tier: 2, existence: 0.9, proximity: 0.6),
      ], now: t0.add(const Duration(milliseconds: 200)));
      expect(_has(picks, 'Tree'), isTrue);
    });

    test('a close Tier-1 hazard is still allowed to interrupt live TTS', () {
      final s = AnnouncementScheduler();
      // Safety beats sentence completeness: utility ≥ 0.8 Tier-1 preempts.
      final picks = s.select(
        [_trk('Pothole', tier: 1, existence: 1.0, proximity: 1.0)],
        now: t0,
        ttsBusy: true,
      );
      expect(_has(picks, 'Pothole'), isTrue);
    });
  });
}
