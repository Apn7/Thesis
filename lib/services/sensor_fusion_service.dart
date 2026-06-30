import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../core/utils/constants.dart';
import 'detection_models.dart';
import 'distance_alert_source.dart';
import 'fusion/announcement_scheduler.dart';
import 'fusion/existence_grid.dart';
import 'fusion/track.dart';
import 'pi_distance_service.dart';
import 'pi_frame_server.dart';
import 'tts_service.dart';

/// The fusion "brain": combines the Pi camera's YOLO detections with the
/// HC-SR04 sonar distance into meaningful, non-overwhelming spoken alerts.
///
/// **It owns its own inference pipeline.** It subscribes to the shared
/// [PiFrameServer] singleton, runs each frame through its own [YOLO] instance,
/// and reads the latest sonar reading from the [PiDistanceService] singleton
/// (which `HomeScreen` already drives — fusion only *reads* it, never
/// re-initialises it). The blind user lives on `HomeScreen`; they never have
/// to open the Cane Cam debug screen for this to work.
///
/// **Design provenance** (see the research validation doc):
///  * 5-frame sliding window + majority vote — detection stabilisation.
///  * Center → object + sonar distance; sides → object only.
///  * Sonar-sees / camera-blind → "obstacle ahead" fallback (glass, poles).
///  * State-change-only announcements with a per-object cooldown (ISANA /
///    GlAccess) so the user isn't talked at every frame.
///  * **Priority layer:** while the sonar verdict is CRITICAL, the
///    `HomeScreen` proximity alarm ("Stop" + tone + heavy haptics) owns the
///    audio channel, so fusion stays silent rather than talking over a
///    safety-critical warning.
///
/// It is additive: it never touches the existing distance-alert haptics/tone
/// flow in `HomeScreen`.
class SensorFusionService extends ChangeNotifier {
  static SensorFusionService? _instance;
  static SensorFusionService get instance =>
      _instance ??= SensorFusionService._();
  SensorFusionService._();

  // Kept identical to the vision screens so detections stay comparable.
  static const double _confidenceThreshold = 0.25;
  static const double _iouThreshold = 0.45;

  final PiFrameServer _frames = PiFrameServer.instance;
  final PiDistanceService _distance = PiDistanceService.instance;
  final TtsService _tts = TtsService.instance;

  // ── Inference state ───────────────────────────────────────────────────
  YOLO? _yolo;
  bool _modelReady = false;
  bool _running = false;

  /// Single-inflight guard: the frame server can deliver faster than YOLO
  /// runs, so we process one frame at a time and let the rest be superseded.
  bool _busy = false;

  /// [PiFrameServer.frameId] we last *attempted* (success or failure), so we
  /// never reprocess the same frame.
  int _lastProcessedId = -1;

  // ── Sliding window of the last N frames' detections ───────────────────
  // Used by the legacy majority-vote path and by getSceneDescription().
  final Queue<List<Detection>> _window = Queue<List<Detection>>();

  // ── Fusion v2 (active when AppConstants.fusionUseBayesian) ─────────────
  // Layer 1 perception + Layer 2 communication. See FUSION_REDESIGN.md.
  final ExistenceGrid _grid = ExistenceGrid();
  final AnnouncementScheduler _scheduler = AnnouncementScheduler();

  // ── Last-announced state per zone (for state-change detection) ─────────
  String? _lastCenter;
  String? _lastLeft;
  String? _lastRight;

  /// Per-(zone:label) last-announced timestamps for the cooldown.
  final Map<String, DateTime> _cooldowns = {};

  // ── Debug / UI snapshot (drives the on-screen fusion panel) ────────────
  // Updated every processed frame and published via notifyListeners() so a
  // debug widget can render exactly what the fusion layer is "seeing" and
  // why it spoke (or stayed silent). None of this affects the audio logic.
  List<Detection> _latestDetections = const [];
  String? _confirmedCenter; // raw English label, or '__obstacle__', or null
  String? _confirmedLeft;
  String? _confirmedRight;

  /// v2 debug snapshot: every confirmed [Track] this frame (fresh ones carry
  /// proximity/distance/looming; lingering ones are flagged via
  /// [Track.seenThisFrame]). Drives the Bayesian fusion debug panel. Empty on
  /// the legacy vote path.
  List<Track> _confirmedTracks = const [];
  String _lastAnnouncement = '';
  double _latencyMs = 0;
  double _fps = 0;
  int _framesProcessed = 0;
  int _lastDoneAtMs = 0;

  /// The exact JPEG bytes fusion last ran inference on, plus that frame's id.
  /// Published so the Cane Cam viewer renders the *same* frame that
  /// [latestDetections] belong to — drawing the live server frame against these
  /// detections would misalign, since inference lags the newest frame. This is
  /// the received JPEG held by reference (~16 KB); fusion never decodes it.
  Uint8List? _latestProcessedJpeg;
  int _latestProcessedFrameId = -1;

  bool get isRunning => _running;
  bool get modelReady => _modelReady;

  /// Most recent frame's raw detections (pre-confirmation).
  List<Detection> get latestDetections => _latestDetections;

  /// The JPEG bytes [latestDetections] were computed from, and that frame's id,
  /// so a viewer can render an aligned frame+boxes pair.
  Uint8List? get latestProcessedJpeg => _latestProcessedJpeg;
  int get latestProcessedFrameId => _latestProcessedFrameId;

  /// The confirmed (majority-vote) object label per zone, or null if none.
  /// Center may be the sentinel `__obstacle__` for the sonar-only fallback.
  String? get confirmedCenter => _confirmedCenter;
  String? get confirmedLeft => _confirmedLeft;
  String? get confirmedRight => _confirmedRight;

  /// v2: the confirmed tracks the existence filter is currently holding, with
  /// their enrichment (existence, tier, proximity, looming, distance). For the
  /// Bayesian debug panel. Empty when on the legacy vote path.
  List<Track> get confirmedTracks => _confirmedTracks;

  /// v2 debug: the scheduler's utility score for [t] this cycle (0 if it wasn't
  /// a candidate — e.g. a lingering, not-seen-this-frame track).
  double utilityFor(Track t) =>
      _scheduler.lastUtilities['${t.label}:${t.zone.index}'] ?? 0.0;

  /// v2 debug: whether [t] was one of the tracks the scheduler chose to speak
  /// this cycle (i.e. it won the perception-bandwidth channel).
  bool wasPicked(Track t) =>
      _scheduler.lastPicks.any((p) => p.label == t.label && p.zone == t.zone);

  /// True when the active fusion path is the v2 Bayesian existence filter.
  bool get usingBayesian => AppConstants.fusionUseBayesian;

  /// The last utterance fused-speech actually sent to TTS (for debugging).
  String get lastAnnouncement => _lastAnnouncement;

  /// Live sonar distance (cm) and its verdict, read from [PiDistanceService].
  double? get latestDistanceCm => _distance.latestDistance;
  ObstacleVerdict get verdict => verdictForDistanceCm(_distance.latestDistance);

  /// Inference timing for the debug panel.
  double get latencyMs => _latencyMs;
  double get fps => _fps;
  int get framesProcessed => _framesProcessed;

  /// How full the sliding window is, 0..[AppConstants.fusionWindowSize].
  int get windowFill => _window.length;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  /// Starts the fusion pipeline: loads the model, subscribes to the shared
  /// frame server, and begins inference. Idempotent.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    debugPrint('SensorFusionService: starting');

    // Own YOLO instance on its own channel so it never collides with the
    // PiVisionScreen / VisionDemoScreen instances if those happen to be alive.
    _yolo = YOLO(
      modelPath: 'assets/models/${ModelVariant.fp16.assetFile}',
      task: YOLOTask.detect,
      useGpu: true,
      useMultiInstance: true,
    );
    try {
      _modelReady = await _yolo!.loadModel();
      if (!_modelReady) {
        debugPrint('SensorFusionService: model failed to load');
      }
    } on Object catch (e) {
      _modelReady = false;
      debugPrint('SensorFusionService: model load error — $e');
    }

    // Bail out if the caller stopped us during the async load.
    if (!_running) {
      _yolo?.dispose();
      _yolo = null;
      return;
    }

    _frames.addListener(_onFrameUpdate);
    await _frames.start(); // reference-counted; shared with PiVisionScreen
    unawaited(_maybeProcess()); // a frame may already be waiting
  }

  /// Stops the pipeline and releases the model + frame-server reference.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    debugPrint('SensorFusionService: stopping');
    _frames.removeListener(_onFrameUpdate);
    await _frames.stop();
    _yolo?.dispose();
    _yolo = null;
    _modelReady = false;
    _busy = false;
    _lastProcessedId = -1;
    _window.clear();
    _grid.reset();
    _scheduler.reset();
    _resetAnnouncementState();
    _latestDetections = const [];
    _latestProcessedJpeg = null;
    _latestProcessedFrameId = -1;
    _confirmedCenter = _confirmedLeft = _confirmedRight = null;
    _confirmedTracks = const [];
    _lastAnnouncement = '';
    _latencyMs = 0;
    _fps = 0;
    _framesProcessed = 0;
    _lastDoneAtMs = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    // Singleton, but honour the contract.
    stop();
    super.dispose();
  }

  // ── Frame pipeline ────────────────────────────────────────────────────

  void _onFrameUpdate() => unawaited(_maybeProcess());

  Future<void> _maybeProcess() async {
    if (!_running || _busy || !_modelReady || _yolo == null) return;
    if (_frames.frameId == _lastProcessedId) return; // nothing new
    final frame = _frames.latestFrame;
    if (frame == null) return;

    _busy = true;
    // Mark attempted up-front so a frame that fails to infer isn't retried in
    // a tight loop — we move on when the next frame arrives.
    _lastProcessedId = _frames.frameId;

    try {
      final sw = Stopwatch()..start();
      final result = await _yolo!.predict(
        frame,
        confidenceThreshold: _confidenceThreshold,
        iouThreshold: _iouThreshold,
      );
      sw.stop();
      if (!_running) return;

      // Inference timing for the debug panel (light EMA so it doesn't jitter).
      _latencyMs = sw.elapsedMilliseconds.toDouble();
      final now = DateTime.now().millisecondsSinceEpoch;
      final dt = _lastDoneAtMs == 0 ? 0 : now - _lastDoneAtMs;
      _lastDoneAtMs = now;
      if (dt > 0) {
        final inst = 1000.0 / dt;
        _fps = _fps == 0 ? inst : (_fps * 0.7 + inst * 0.3);
      }
      _framesProcessed++;

      // Publish the exact frame these detections came from so the Cane Cam
      // viewer renders an aligned frame+boxes pair (it lags the live server
      // frame otherwise). Reference only — no copy, no decode.
      _latestProcessedJpeg = frame;
      _latestProcessedFrameId = _lastProcessedId;
      onNewFrame(_parseDetections(result));
    } on Object catch (e) {
      debugPrint('SensorFusionService: inference failed — $e');
    } finally {
      _busy = false;
      // A newer frame may have landed mid-inference — pick it up. Microtask
      // avoids unbounded recursion on a fast stream.
      if (_running && _frames.frameId != _lastProcessedId) {
        scheduleMicrotask(_maybeProcess);
      }
    }
  }

  List<Detection> _parseDetections(Map<String, dynamic> result) {
    final raw = result['detections'];
    if (raw is! List) return const [];
    final out = <Detection>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final r = YOLOResult.fromMap(item);
      out.add(
        Detection(
          classId: r.classIndex,
          label: r.className,
          confidence: r.confidence,
          bbox: BBox(
            r.normalizedBox.left,
            r.normalizedBox.top,
            r.normalizedBox.right,
            r.normalizedBox.bottom,
          ),
        ),
      );
    }
    return out;
  }

  // ── Fusion core ───────────────────────────────────────────────────────

  /// Feeds one frame's detections into the sliding window and, once the window
  /// is full, decides what (if anything) to announce. Public so it can be
  /// unit-tested without a live YOLO/socket.
  void onNewFrame(List<Detection> detections) {
    // Publish raw detections for the debug panel even before the window fills.
    _latestDetections = detections;

    _window.addLast(detections);
    while (_window.length > AppConstants.fusionWindowSize) {
      _window.removeFirst();
    }

    // v2 path: per-class Bayesian existence filter + scheduler (FUSION_REDESIGN.md).
    if (AppConstants.fusionUseBayesian) {
      _onFrameBayesian(detections);
      return;
    }

    // ── Legacy 3-of-5 majority-vote path (kept for A/B comparison) ──
    if (_window.length < AppConstants.fusionWindowSize) {
      notifyListeners(); // window still warming up — show live detections
      return;
    }

    // Count map: label → zone → number of frames it appeared in.
    final counts = _buildCounts(_window);
    final current = _window.last;

    final distCm = _distance.latestDistance;
    final verdict = verdictForDistanceCm(distCm);

    // PRIORITY LAYER: at CRITICAL range the HomeScreen proximity alarm owns
    // the audio channel. Stay silent (and forget our announce state so the
    // scene is re-announced fresh once the danger clears) rather than talk
    // over a safety-critical "stop now" warning.
    if (verdict == ObstacleVerdict.critical) {
      _resetAnnouncementState();
      _confirmedCenter = _confirmedLeft = _confirmedRight = null;
      notifyListeners();
      return;
    }

    final inRange =
        distCm != null && distCm <= AppConstants.fusionSonarMaxAssignCm;

    // ── Center: largest confirmed bbox gets the sonar distance ──────────
    // The largest box in the center zone is (by apparent size) the closest
    // object there, so the single sonar reading is most likely measuring it.
    final centerObj = _selectCenter(counts, current);
    String? centerLabel;
    String centerCooldownKey = '';
    String? centerPhrase;
    if (centerObj != null) {
      centerLabel = centerObj.label;
      centerCooldownKey = centerLabel;
      centerPhrase = _centerPhrase(centerLabel, inRange ? distCm : null);
    } else if (inRange) {
      // Sonar fallback: the camera sees nothing ahead but the sonar does —
      // glass, a thin pole, an unrecognised object. Worth a heads-up.
      centerLabel = '__obstacle__';
      centerCooldownKey = '__obstacle__';
      centerPhrase = _obstaclePhrase(distCm);
    }

    // ── Sides: highest-count confirmed object, object name only ─────────
    final leftLabel = _bestConfirmed(counts, PositionZone.left);
    final rightLabel = _bestConfirmed(counts, PositionZone.right);

    // Publish the confirmed picture for the debug panel.
    _confirmedCenter = centerLabel;
    _confirmedLeft = leftLabel;
    _confirmedRight = rightLabel;

    // Build one combined utterance from the zones that CHANGED (TtsService
    // interrupts on every speak(), so three separate calls would cut each
    // other off — we say it all in one breath, center first).
    final parts = <String>[];

    if (centerLabel != _lastCenter) {
      if (centerPhrase != null && _canAnnounce('center', centerCooldownKey)) {
        parts.add(centerPhrase);
        _recordAnnouncement('center', centerCooldownKey);
      }
      _lastCenter = centerLabel;
    }
    if (leftLabel != _lastLeft) {
      if (leftLabel != null && _canAnnounce('left', leftLabel)) {
        parts.add(_sidePhrase(leftLabel, PositionZone.left));
        _recordAnnouncement('left', leftLabel);
      }
      _lastLeft = leftLabel;
    }
    if (rightLabel != _lastRight) {
      if (rightLabel != null && _canAnnounce('right', rightLabel)) {
        parts.add(_sidePhrase(rightLabel, PositionZone.right));
        _recordAnnouncement('right', rightLabel);
      }
      _lastRight = rightLabel;
    }

    if (parts.isNotEmpty) {
      final utterance = parts.join('. ');
      _lastAnnouncement = utterance;
      _tts.speak(utterance);
    }

    notifyListeners();
  }

  // ── Fusion core v2 (Bayesian existence filter + scheduler) ─────────────
  // Layer 1 = ExistenceGrid (perception); Layer 3 = distance/looming
  // enrichment here; Layer 2 = AnnouncementScheduler. See FUSION_REDESIGN.md.

  void _onFrameBayesian(List<Detection> detections) {
    final now = DateTime.now();
    final confirmed = _grid.update(detections); // all currently-confirmed cells

    final distCm = _distance.latestDistance;
    final verdict = verdictForDistanceCm(distCm);
    final inRange =
        distCm != null && distCm <= AppConstants.fusionSonarMaxAssignCm;

    // Fresh = confirmed AND detected this frame (have a current box). Only these
    // are announce/distance candidates; lingering cells just keep the picture
    // stable and suppress re-announcement.
    final fresh = confirmed.where((t) => t.seenThisFrame).toList();

    // Layer 3: give the single sonar reading to the nearest ground-contacting
    // hazard, and score proximity for every fresh track.
    _assignDistanceAndProximity(fresh, distCm, inRange);

    // Sonar-only fallback: nothing recognised dead ahead but the sonar sees
    // something (glass, a thin pole) — worth a heads-up.
    final hasCenter = fresh.any((t) => t.zone == PositionZone.center);
    if (!hasCenter && inRange) {
      fresh.add(_obstacleTrack(distCm));
    }

    _publishConfirmedSnapshot(confirmed, fresh);

    // PRIORITY LAYER: while sonar verdict is CRITICAL, HomeScreen's proximity
    // alarm owns the audio channel. Stay silent and forget scheduler state so
    // the scene re-announces fresh once the danger clears.
    if (verdict == ObstacleVerdict.critical) {
      _scheduler.reset();
      notifyListeners();
      return;
    }

    // Layer 2: at most one short utterance (≤2 zones), center-first.
    final picks = _scheduler.select(fresh, now: now);
    if (picks.isNotEmpty) {
      _orderForUtterance(picks);
      final utterance = picks.map((t) => _phraseFor(t)).join('. ');
      _lastAnnouncement = utterance;
      _tts.speak(utterance);
    }

    notifyListeners();
  }

  /// Layer 3 — assign the one sonar reading to the nearest ground-contacting
  /// hazard in the center (not merely the biggest box, which a background tree
  /// could win), then score proximity for every fresh track (0..1, closer ⇒ 1).
  void _assignDistanceAndProximity(
    List<Track> fresh,
    double? distCm,
    bool inRange,
  ) {
    if (inRange && distCm != null) {
      Track? target;
      double bestScore = -1;
      for (final t in fresh) {
        if (t.zone != PositionZone.center) continue;
        final sev = t.tier == 1
            ? 1.0
            : t.tier == 2
            ? 0.6
            : 0.2;
        final score = t.box.y2 * sev; // lower edge ⇒ nearer the ground/user
        if (score > bestScore) {
          bestScore = score;
          target = t;
        }
      }
      target?.distanceCm = distCm;
    }

    const maxA = AppConstants.fusionSonarMaxAssignCm;
    const crit = AppConstants.espCriticalCm;
    for (final t in fresh) {
      final d = t.distanceCm;
      if (d != null) {
        t.proximity = ((maxA - d) / (maxA - crit)).clamp(0.0, 1.0);
      } else {
        // No sonar on this track: a lower / bigger box is likely closer.
        // Capped so a camera-only guess can't outrank a sonar-confirmed hazard.
        t.proximity = (0.3 + 0.5 * t.box.y2).clamp(0.0, 0.85);
      }
    }
  }

  /// Synthetic "something ahead" track for the sonar-only fallback.
  Track _obstacleTrack(double distCm) {
    const maxA = AppConstants.fusionSonarMaxAssignCm;
    const crit = AppConstants.espCriticalCm;
    return Track(
      label: '__obstacle__',
      zone: PositionZone.center,
      existence: 1.0,
      box: const BBox(0.34, 0.5, 0.66, 1.0),
      areaTrend: 0,
      tier: 1,
      seenThisFrame: true,
      distanceCm: distCm,
      proximity: ((maxA - distCm) / (maxA - crit)).clamp(0.0, 1.0),
    );
  }

  /// Publish the confirmed per-zone picture for the debug panel / Cane Cam.
  void _publishConfirmedSnapshot(List<Track> confirmed, List<Track> fresh) {
    String? center, left, right;
    double cBest = -1, lBest = -1, rBest = -1;
    // The sonar-only obstacle, when present, owns the center slot.
    if (fresh.any((t) => t.label == '__obstacle__')) {
      center = '__obstacle__';
      cBest = 2;
    }
    for (final t in confirmed) {
      if (t.zone == PositionZone.center) {
        if (t.existence > cBest) {
          cBest = t.existence;
          center = t.label;
        }
      } else if (t.zone == PositionZone.left) {
        if (t.existence > lBest) {
          lBest = t.existence;
          left = t.label;
        }
      } else {
        if (t.existence > rBest) {
          rBest = t.existence;
          right = t.label;
        }
      }
    }
    _confirmedCenter = center;
    _confirmedLeft = left;
    _confirmedRight = right;

    // Full track snapshot for the debug panel: every confirmed cell plus the
    // synthetic sonar-only obstacle (which lives in [fresh], not [confirmed]).
    // Fresh-this-frame tracks first, then by existence — so the panel reads
    // top-down from "what's live right now" to "what's lingering in memory".
    final snap = <Track>[
      ...confirmed,
      ...fresh.where((t) => t.label == '__obstacle__'),
    ];
    snap.sort((a, b) {
      if (a.seenThisFrame != b.seenThisFrame) return a.seenThisFrame ? -1 : 1;
      return b.existence.compareTo(a.existence);
    });
    _confirmedTracks = snap;
  }

  /// Order picks center → left → right for a natural single utterance.
  void _orderForUtterance(List<Track> picks) {
    int rank(PositionZone z) =>
        z == PositionZone.center ? 0 : (z == PositionZone.left ? 1 : 2);
    picks.sort((a, b) => rank(a.zone).compareTo(rank(b.zone)));
  }

  String _phraseFor(Track t) {
    if (t.label == '__obstacle__') {
      return _obstaclePhrase(t.distanceCm ?? 0);
    }
    if (t.zone == PositionZone.center) {
      final approaching = t.tier == 1 && t.seenThisFrame && t.areaTrend > 0.15;
      return _centerPhrase(t.label, t.distanceCm, approaching: approaching);
    }
    return _sidePhrase(t.label, t.zone);
  }

  /// Stores the latest sonar reading. Kept for API symmetry with the plan /
  /// for callers that want to push readings; the live path reads
  /// [PiDistanceService] directly each frame, so this is optional.
  void onNewDistance(double cm) {
    // No-op by design: distance is read live from PiDistanceService in
    // onNewFrame so the freshest reading is always used.
  }

  // ── On-demand scene description ───────────────────────────────────────

  /// Answers "what's in front of me?" from the current window: the top-N most
  /// consistently-seen objects, plus the nearest sonar distance if in range.
  String getSceneDescription() {
    if (_window.length < AppConstants.fusionWindowSize) {
      return 'এখনও যথেষ্ট তথ্য নেই।';
    }

    final totals = <String, int>{};
    for (final snap in _window) {
      for (final d in snap) {
        totals[d.label] = (totals[d.label] ?? 0) + 1;
      }
    }

    final distCm = _distance.latestDistance;
    final inRange =
        distCm != null && distCm <= AppConstants.fusionSonarMaxAssignCm;

    if (totals.isEmpty) {
      if (inRange) {
        return 'সামনে কিছু চিনতে পারিনি, তবে ${_metersStr(distCm)} মিটার দূরে একটি বাধা আছে।';
      }
      return 'সামনে কিছু সনাক্ত হয়নি।';
    }

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted
        .take(AppConstants.fusionOnDemandTopN)
        .map((e) => _labelFor(e.key))
        .toList();
    final list = top.join(', ');

    final buf = StringBuffer();
    buf.write('সামনে $list আছে।');
    if (inRange) {
      buf.write(' নিকটতম বাধা ${_metersStr(distCm)} মিটার দূরে।');
    }
    return buf.toString();
  }

  // ── Window analysis helpers ───────────────────────────────────────────

  Map<String, Map<PositionZone, int>> _buildCounts(
    Queue<List<Detection>> window,
  ) {
    final counts = <String, Map<PositionZone, int>>{};
    for (final snap in window) {
      // Count each (label, zone) at most once per frame so a frame with two
      // chairs on the left doesn't over-count toward the majority vote.
      final seen = <String>{};
      for (final d in snap) {
        final key = '${d.label}:${d.position}';
        if (!seen.add(key)) continue;
        final zoneMap = counts.putIfAbsent(d.label, () => {});
        zoneMap[d.position] = (zoneMap[d.position] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// The largest-bbox center-zone detection in [current] whose label is
  /// *confirmed* (seen in a majority of the window). Null if none qualifies.
  Detection? _selectCenter(
    Map<String, Map<PositionZone, int>> counts,
    List<Detection> current,
  ) {
    Detection? best;
    for (final d in current) {
      if (d.position != PositionZone.center) continue;
      final c = counts[d.label]?[PositionZone.center] ?? 0;
      if (c < AppConstants.fusionMajorityThreshold) continue; // unconfirmed
      if (best == null || d.bbox.area > best.bbox.area) best = d;
    }
    return best;
  }

  /// Highest-count confirmed object label in [zone], or null if none reach the
  /// majority threshold.
  String? _bestConfirmed(
    Map<String, Map<PositionZone, int>> counts,
    PositionZone zone,
  ) {
    String? best;
    int bestCount = 0;
    counts.forEach((label, zoneMap) {
      final c = zoneMap[zone] ?? 0;
      if (c >= AppConstants.fusionMajorityThreshold && c > bestCount) {
        bestCount = c;
        best = label;
      }
    });
    return best;
  }

  // ── Cooldown ──────────────────────────────────────────────────────────

  bool _canAnnounce(String zone, String label) {
    final last = _cooldowns['$zone:$label'];
    if (last == null) return true;
    return DateTime.now().difference(last).inMilliseconds >
        AppConstants.fusionCooldownMs;
  }

  void _recordAnnouncement(String zone, String label) {
    _cooldowns['$zone:$label'] = DateTime.now();
  }

  void _resetAnnouncementState() {
    _lastCenter = null;
    _lastLeft = null;
    _lastRight = null;
  }

  // ── Phrasing (Bengali) ────────────────────────────────────────────────

  String _centerPhrase(
    String label,
    double? distCm, {
    bool approaching = false,
  }) {
    final name = _labelFor(label);
    if (approaching) {
      // Looming cue (Layer 3): the bbox is growing ⇒ the hazard is closing in.
      if (distCm == null) return '$name এগিয়ে আসছে';
      return '$name এগিয়ে আসছে, ${_metersStr(distCm)} মিটার';
    }
    if (distCm == null) return 'সামনে $name';
    return '$name, ${_metersStr(distCm)} মিটার';
  }

  String _obstaclePhrase(double distCm) =>
      'সামনে বাধা, ${_metersStr(distCm)} মিটার';

  String _sidePhrase(String label, PositionZone zone) =>
      '${zone.bn} দিকে ${_labelFor(label)}';

  /// Distance in metres, one decimal place, in Bengali numerals.
  String _metersStr(double cm) => _toBnDigits((cm / 100.0).toStringAsFixed(1));

  static String _toBnDigits(String s) {
    const bn = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    final out = StringBuffer();
    for (final ch in s.split('')) {
      final code = ch.codeUnitAt(0);
      if (code >= 0x30 && code <= 0x39) {
        out.write(bn[code - 0x30]);
      } else {
        out.write(ch); // keep the decimal point
      }
    }
    return out.toString();
  }

  /// Bengali name for a class label, falling back to the English label for
  /// anything unmapped.
  String _labelFor(String en) => _bnLabels[en.toLowerCase()] ?? en;

  /// The 16 SafeWalkBD classes → Bengali. Keys are lowercased to match the
  /// model's class names (e.g. "Over-bridge" → "over-bridge"). Unmapped labels
  /// fall back to English.
  static const Map<String, String> _bnLabels = {
    'animal': 'প্রাণী',
    'crosswalk': 'পারাপার',
    'obstacle': 'বাধা',
    'over-bridge': 'ওভারব্রিজ',
    'person': 'মানুষ',
    'pole': 'খুঁটি',
    'pothole': 'গর্ত',
    'railway': 'রেললাইন',
    'road-barrier': 'রোড ব্যারিয়ার',
    'sidewalk': 'ফুটপাত',
    'stairs': 'সিঁড়ি',
    'traffic-light': 'ট্রাফিক লাইট',
    'traffic-sign': 'ট্রাফিক সাইন',
    'train': 'ট্রেন',
    'tree': 'গাছ',
    'vehicle': 'যানবাহন',
  };
}
