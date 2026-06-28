import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../core/utils/constants.dart';
import 'detection_models.dart';
import 'distance_alert_source.dart';
import 'pi_distance_service.dart';
import 'pi_frame_server.dart';
import 'settings_service.dart';
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
///    `HomeScreen` proximity alarm ("থামুন" + tone + heavy haptics) owns the
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
  final Queue<List<Detection>> _window = Queue<List<Detection>>();

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
  String _lastAnnouncement = '';
  double _latencyMs = 0;
  double _fps = 0;
  int _framesProcessed = 0;
  int _lastDoneAtMs = 0;

  bool get isRunning => _running;
  bool get modelReady => _modelReady;

  /// Most recent frame's raw detections (pre-confirmation).
  List<Detection> get latestDetections => _latestDetections;

  /// The confirmed (majority-vote) object label per zone, or null if none.
  /// Center may be the sentinel `__obstacle__` for the sonar-only fallback.
  String? get confirmedCenter => _confirmedCenter;
  String? get confirmedLeft => _confirmedLeft;
  String? get confirmedRight => _confirmedRight;

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
    _resetAnnouncementState();
    _latestDetections = const [];
    _confirmedCenter = _confirmedLeft = _confirmedRight = null;
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

    final bn = SettingsService.instance.languageMode == 'bn';
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
      centerPhrase = _centerPhrase(centerLabel, inRange ? distCm : null, bn);
    } else if (inRange) {
      // Sonar fallback: the camera sees nothing ahead but the sonar does —
      // glass, a thin pole, an unrecognised object. Worth a heads-up.
      centerLabel = '__obstacle__';
      centerCooldownKey = '__obstacle__';
      centerPhrase = _obstaclePhrase(distCm, bn);
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
        parts.add(_sidePhrase(leftLabel, PositionZone.left, bn));
        _recordAnnouncement('left', leftLabel);
      }
      _lastLeft = leftLabel;
    }
    if (rightLabel != _lastRight) {
      if (rightLabel != null && _canAnnounce('right', rightLabel)) {
        parts.add(_sidePhrase(rightLabel, PositionZone.right, bn));
        _recordAnnouncement('right', rightLabel);
      }
      _lastRight = rightLabel;
    }

    if (parts.isNotEmpty) {
      final utterance = parts.join(bn ? '। ' : '. ');
      _lastAnnouncement = utterance;
      _tts.speak(utterance);
    }

    notifyListeners();
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
  String getSceneDescription(String lang) {
    final bn = lang == 'bn';
    if (_window.length < AppConstants.fusionWindowSize) {
      return bn ? 'এখনও যথেষ্ট তথ্য নেই।' : 'Not enough information yet.';
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
        return bn
            ? 'সামনে কিছু চিনতে পারিনি, তবে ${_metersStr(distCm, bn)} মিটার দূরে একটি বাধা আছে।'
            : "I can't identify anything ahead, but there's an obstacle ${_metersStr(distCm, bn)} meters away.";
      }
      return bn ? 'সামনে কিছু সনাক্ত হয়নি।' : 'Nothing detected ahead.';
    }

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted
        .take(AppConstants.fusionOnDemandTopN)
        .map((e) => _labelFor(e.key, bn))
        .toList();
    final list = top.join(bn ? ', ' : ', ');

    final buf = StringBuffer();
    if (bn) {
      buf.write('সামনে $list আছে।');
      if (inRange) {
        buf.write(' নিকটতম বাধা ${_metersStr(distCm, bn)} মিটার দূরে।');
      }
    } else {
      buf.write('Ahead I can see $list.');
      if (inRange) {
        buf.write(' Nearest obstacle ${_metersStr(distCm, bn)} meters away.');
      }
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

  // ── Phrasing (bilingual) ──────────────────────────────────────────────

  String _centerPhrase(String label, double? distCm, bool bn) {
    final name = _labelFor(label, bn);
    if (distCm == null) {
      return bn ? 'সামনে $name' : '$name ahead';
    }
    final m = _metersStr(distCm, bn);
    return bn ? '$name, $m মিটার' : '$name, $m meters';
  }

  String _obstaclePhrase(double distCm, bool bn) {
    final m = _metersStr(distCm, bn);
    return bn ? 'সামনে বাধা, $m মিটার' : 'Obstacle ahead, $m meters';
  }

  String _sidePhrase(String label, PositionZone zone, bool bn) {
    final name = _labelFor(label, bn);
    return bn ? '${zone.bn} দিকে $name' : '$name on your ${zone.en}';
  }

  /// Distance in metres, one decimal, with Bangla digits when [bn].
  String _metersStr(double cm, bool bn) {
    final s = (cm / 100.0).toStringAsFixed(1);
    return bn ? _toBnDigits(s) : s;
  }

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

  /// Bangla name for a COCO class label, falling back to the English label
  /// for anything unmapped. English mode always returns the YOLO label as-is.
  String _labelFor(String en, bool bn) {
    if (!bn) return en;
    return _bnLabels[en.toLowerCase()] ?? en;
  }

  /// Common COCO classes → Bangla. Unmapped labels fall back to English.
  static const Map<String, String> _bnLabels = {
    'person': 'মানুষ',
    'bicycle': 'সাইকেল',
    'car': 'গাড়ি',
    'motorcycle': 'মোটরসাইকেল',
    'bus': 'বাস',
    'train': 'ট্রেন',
    'truck': 'ট্রাক',
    'traffic light': 'ট্রাফিক লাইট',
    'fire hydrant': 'হাইড্রেন্ট',
    'stop sign': 'স্টপ সাইন',
    'bench': 'বেঞ্চ',
    'bird': 'পাখি',
    'cat': 'বিড়াল',
    'dog': 'কুকুর',
    'cow': 'গরু',
    'backpack': 'ব্যাগ',
    'umbrella': 'ছাতা',
    'handbag': 'হাতব্যাগ',
    'bottle': 'বোতল',
    'cup': 'কাপ',
    'chair': 'চেয়ার',
    'couch': 'সোফা',
    'potted plant': 'গাছ',
    'bed': 'বিছানা',
    'dining table': 'টেবিল',
    'toilet': 'টয়লেট',
    'tv': 'টিভি',
    'laptop': 'ল্যাপটপ',
    'cell phone': 'মোবাইল',
    'book': 'বই',
    'clock': 'ঘড়ি',
  };
}
