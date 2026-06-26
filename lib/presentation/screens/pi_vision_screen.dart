import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/vision_strings.dart';
import '../../services/detection_models.dart';
import '../../services/pi_frame_server.dart';
import '../../services/settings_service.dart';
import '../widgets/detection_list_tile.dart';

/// Cane-camera vision: frames arrive from the Raspberry Pi over WiFi (via
/// [PiFrameServer]) and are run through the bundled YOLO using the plugin's
/// still-image [YOLO.predict] API.
///
/// Why not [YOLOView]? That widget is a native CameraX platform view with no
/// external-frame input — it can only see the phone's own camera. The Pi path
/// needs to feed *our* JPEG bytes in, which only `YOLO.predict(bytes)`
/// supports. It's slower than the native camera pipeline, but per the plan a
/// "usable for a blind user" cadence is enough; we don't target a fixed FPS.
///
/// The existing phone-camera [VisionDemoScreen] is intentionally left
/// untouched — this is a parallel screen.
class PiVisionScreen extends StatefulWidget {
  const PiVisionScreen({super.key});

  @override
  State<PiVisionScreen> createState() => _PiVisionScreenState();
}

class _PiVisionScreenState extends State<PiVisionScreen>
    with WidgetsBindingObserver {
  // Kept identical to VisionDemoScreen so detections stay comparable across
  // the phone-camera and cane-camera paths.
  static const double _confidenceThreshold = 0.25;
  static const double _iouThreshold = 0.45;

  late final PiFrameServer _server;
  late final YOLO _yolo;

  bool _modelReady = false;
  String? _modelError;

  /// True while a [YOLO.predict] is in flight. The frame server can deliver
  /// faster than inference runs, so we process one frame at a time and let the
  /// rest be superseded — never building a backlog.
  bool _busy = false;

  /// Suspended while the app is backgrounded (saves battery; the socket stays
  /// open so the Pi doesn't have to redial on a brief switch-away).
  bool _paused = false;

  /// [PiFrameServer.frameId] of the frame we last *attempted* (success or
  /// failure), so we don't reprocess it.
  int _lastProcessedId = -1;

  // Current render frame: decoded image + its detections, painted together so
  // boxes always line up with the pixels they were computed from.
  ui.Image? _renderImage;
  List<Detection> _detections = const [];

  // Metrics
  double _latencyMs = 0;
  double _fps = 0;
  int _lastDoneAtMs = 0;
  int _errorCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _server = PiFrameServer()..addListener(_onServerUpdate);
    _yolo = YOLO(
      modelPath: 'assets/models/${ModelVariant.fp16.assetFile}',
      task: YOLOTask.detect,
      useGpu: true,
      // Own channel so this instance never collides with VisionDemoScreen's
      // default-channel YOLOView if both happen to be alive.
      useMultiInstance: true,
    );
    _init();
  }

  Future<void> _init() async {
    // Load the model and bind the socket in parallel.
    final loadModel = _yolo.loadModel().then((ok) {
      if (!mounted) return;
      setState(() {
        _modelReady = ok;
        if (!ok) _modelError = 'Model failed to load.';
      });
    }).catchError((Object e) {
      debugPrint('PiVisionScreen: model load failed — $e');
      if (mounted) setState(() => _modelError = '$e');
    });
    await Future.wait([loadModel, _server.start()]);
    // A frame may already be waiting if the Pi connected during model load.
    unawaited(_maybeProcess());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _server.removeListener(_onServerUpdate);
    _server.dispose();
    _renderImage?.dispose();
    // YOLO holds native resources; release them.
    _yolo.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final paused =
        state != AppLifecycleState.resumed &&
        state != AppLifecycleState.inactive;
    if (paused == _paused) return;
    _paused = paused;
    if (!_paused) _maybeProcess(); // resume the loop
  }

  // ── Frame pipeline ────────────────────────────────────────────────────

  void _onServerUpdate() {
    if (!mounted) return;
    // Reflect connection-state/error changes in the UI...
    setState(() {});
    // ...and try to process any newly-arrived frame.
    _maybeProcess();
  }

  Future<void> _maybeProcess() async {
    if (!mounted || _paused || _busy || !_modelReady) return;
    if (_server.frameId == _lastProcessedId) return; // nothing new
    final frame = _server.latestFrame;
    if (frame == null) return;

    _busy = true;
    // Mark attempted up-front so a frame that fails to decode/infer isn't
    // retried in a tight loop — we move on when the next frame arrives.
    _lastProcessedId = _server.frameId;

    try {
      final sw = Stopwatch()..start();
      final image = await _decode(frame);
      final result = await _yolo.predict(
        frame,
        confidenceThreshold: _confidenceThreshold,
        iouThreshold: _iouThreshold,
      );
      sw.stop();

      if (!mounted) {
        image.dispose();
        return;
      }

      final dets = _parseDetections(result);
      final now = DateTime.now().millisecondsSinceEpoch;
      final dt = _lastDoneAtMs == 0 ? 0 : now - _lastDoneAtMs;
      _lastDoneAtMs = now;

      setState(() {
        _renderImage?.dispose();
        _renderImage = image;
        _detections = dets;
        _latencyMs = sw.elapsedMilliseconds.toDouble();
        if (dt > 0) {
          final inst = 1000.0 / dt;
          // Light EMA so the readout doesn't jitter.
          _fps = _fps == 0 ? inst : (_fps * 0.7 + inst * 0.3);
        }
      });
    } on Object catch (e) {
      _errorCount++;
      debugPrint('PiVisionScreen: frame inference failed (#$_errorCount) — $e');
    } finally {
      _busy = false;
      // A newer frame may have landed mid-inference — pick it up. Microtask
      // avoids unbounded recursion on a fast stream.
      if (mounted && !_paused && _server.frameId != _lastProcessedId) {
        scheduleMicrotask(_maybeProcess);
      }
    }
  }

  Future<ui.Image> _decode(Uint8List jpeg) async {
    final codec = await ui.instantiateImageCodec(jpeg);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
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
          // normalizedBox is 0..1 relative to the source frame — exactly what
          // BBox and the overlay painter expect.
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

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final useBn = SettingsService.instance.languageMode == 'bn';
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          label: useBn
              ? VisionStrings.piScreenSemanticBn
              : VisionStrings.piScreenSemanticEn,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(VisionStrings.piScreenTitleBn),
              Text(
                VisionStrings.piScreenTitleEn,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (_modelError != null) _buildBanner(_modelError!),
          _buildMetricsRow(),
          Expanded(flex: 3, child: _buildViewport(useBn)),
          const Divider(height: 1),
          Expanded(flex: 2, child: _buildDetectionsList(useBn)),
        ],
      ),
    );
  }

  Widget _buildViewport(bool useBn) {
    if (_server.state == PiServerState.error) {
      return _buildStatusView(
        icon: Icons.wifi_off,
        color: AppColors.error,
        titleBn: VisionStrings.piServerErrorBn,
        titleEn: VisionStrings.piServerErrorEn,
        detail: _server.errorMessage,
      );
    }
    final image = _renderImage;
    if (image == null) {
      // Connected or still waiting — either way nothing to draw yet.
      return _buildStatusView(
        icon: Icons.videocam_outlined,
        color: AppColors.textSecondary,
        titleBn: VisionStrings.piWaitingBn,
        titleEn: VisionStrings.piWaitingEn,
        detailBn: VisionStrings.piWaitingHintBn,
        detailEn: VisionStrings.piWaitingHintEn,
        showSpinner: true,
      );
    }
    return Container(
      color: Colors.black,
      width: double.infinity,
      child: CustomPaint(
        painter: _PiOverlayPainter(image: image, detections: _detections),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildMetricsRow() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppConstants.spacingM,
        vertical: AppConstants.spacingS,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _chip(VisionStrings.latencyLabelEn, '${_latencyMs.toStringAsFixed(0)} ms'),
          _chip(VisionStrings.fpsLabelEn, _fps.toStringAsFixed(1)),
          _chip('Frames', '${_server.framesReceived}'),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppConstants.spacingM,
        vertical: AppConstants.spacingXs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppConstants.radiusS),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
          ),
          SizedBox(width: AppConstants.spacingS),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusView({
    required IconData icon,
    required Color color,
    required String titleBn,
    required String titleEn,
    String? detail,
    String? detailBn,
    String? detailEn,
    bool showSpinner = false,
  }) {
    final useBn = SettingsService.instance.languageMode == 'bn';
    return Container(
      color: Colors.black,
      width: double.infinity,
      padding: EdgeInsets.all(AppConstants.spacingL),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showSpinner) ...[
            const CircularProgressIndicator(),
            SizedBox(height: AppConstants.spacingL),
          ] else ...[
            Icon(icon, size: 56, color: color),
            SizedBox(height: AppConstants.spacingM),
          ],
          Text(
            useBn ? titleBn : titleEn,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          if (detail != null || detailBn != null) ...[
            SizedBox(height: AppConstants.spacingS),
            Text(
              detail ?? (useBn ? detailBn! : detailEn!),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBanner(String msg) {
    return Container(
      width: double.infinity,
      color: AppColors.error.withValues(alpha: 0.12),
      padding: EdgeInsets.symmetric(
        horizontal: AppConstants.spacingM,
        vertical: AppConstants.spacingS,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: AppColors.error, size: 18),
          SizedBox(width: AppConstants.spacingS),
          Expanded(
            child: Text(
              msg,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.error),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionsList(bool useBn) {
    final dets = _detections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppConstants.spacingM,
            AppConstants.spacingS,
            AppConstants.spacingM,
            AppConstants.spacingXs,
          ),
          child: Text(
            useBn
                ? VisionStrings.detectionsHeaderBn
                : VisionStrings.detectionsHeaderEn,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: dets.isEmpty
              ? Center(
                  child: Text(
                    useBn
                        ? VisionStrings.noDetectionsBn
                        : VisionStrings.noDetectionsEn,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: dets.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) =>
                      DetectionListTile(detection: dets[i], useBangla: useBn),
                ),
        ),
      ],
    );
  }
}

/// Draws the received frame letterboxed (BoxFit.contain) and overlays the
/// detection boxes in the *same* fitted rect, so boxes line up regardless of
/// the frame's aspect ratio or the viewport's shape.
class _PiOverlayPainter extends CustomPainter {
  _PiOverlayPainter({required this.image, required this.detections});

  final ui.Image image;
  final List<Detection> detections;

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, imageSize, size);
    final dst = Alignment.center.inscribe(fitted.destination, Offset.zero & size);
    final src = Offset.zero & imageSize;

    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.low,
    );

    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = AppColors.accent;

    for (final d in detections) {
      final rect = Rect.fromLTRB(
        dst.left + d.bbox.x1 * dst.width,
        dst.top + d.bbox.y1 * dst.height,
        dst.left + d.bbox.x2 * dst.width,
        dst.top + d.bbox.y2 * dst.height,
      );
      canvas.drawRect(rect, boxPaint);
      _paintLabel(canvas, rect, d, dst);
    }
  }

  void _paintLabel(Canvas canvas, Rect box, Detection d, Rect bounds) {
    final tp = TextPainter(
      text: TextSpan(
        text: ' ${d.label} ${(d.confidence * 100).toStringAsFixed(0)}% ',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Sit the label above the box; flip below if it would clip the top edge.
    double ly = box.top - tp.height;
    if (ly < bounds.top) ly = box.top;
    final lx = box.left
        .clamp(bounds.left, (bounds.right - tp.width).clamp(bounds.left, bounds.right))
        .toDouble();

    canvas.drawRect(
      Rect.fromLTWH(lx, ly, tp.width, tp.height),
      Paint()..color = AppColors.accent,
    );
    tp.paint(canvas, Offset(lx, ly));
  }

  @override
  bool shouldRepaint(_PiOverlayPainter old) =>
      !identical(old.image, image) || !identical(old.detections, detections);
}
