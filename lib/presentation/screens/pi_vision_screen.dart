import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/vision_strings.dart';
import '../../services/detection_models.dart';
import '../../services/pi_frame_server.dart';
import '../../services/sensor_fusion_service.dart';
import '../widgets/detection_list_tile.dart';

/// Cane-camera vision debug view — a **pure viewer of [SensorFusionService]**.
///
/// Fusion is the single, always-on inference pipeline (it runs on `HomeScreen`
/// so the blind user never has to open this screen). This screen used to run a
/// *second* [YOLO] instance of its own, which meant two models loaded and two
/// inferences per frame whenever Cane Cam was open — double the GPU work and
/// halved FPS. It now renders exactly what fusion already computed: fusion
/// publishes the JPEG it ran inference on plus that frame's detections, and we
/// decode + overlay that aligned pair. One pipeline, one source of truth — the
/// numbers here match the on-screen fusion debug panel.
///
/// We never run inference and never touch the frame socket (fusion owns the
/// [PiFrameServer] reference). The phone-camera [VisionDemoScreen] is unrelated
/// and left untouched.
class PiVisionScreen extends StatefulWidget {
  const PiVisionScreen({super.key});

  @override
  State<PiVisionScreen> createState() => _PiVisionScreenState();
}

class _PiVisionScreenState extends State<PiVisionScreen>
    with WidgetsBindingObserver {
  final SensorFusionService _fusion = SensorFusionService.instance;

  /// Current render frame: decoded image + the detections that belong to it,
  /// captured together so the boxes always line up with the pixels.
  ui.Image? _renderImage;
  List<Detection> _detections = const [];

  /// Single-inflight decode guard: fusion can publish faster than a JPEG
  /// decodes, so we decode one frame at a time and let the rest be superseded
  /// (newest-frame-wins) — never building a backlog.
  bool _decoding = false;

  /// Suspended while the app is backgrounded — we just stop *decoding for
  /// display*; fusion keeps running underneath on HomeScreen.
  bool _paused = false;

  /// Fusion frame id we last decoded, so we never redo the same frame.
  int _lastDecodedId = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fusion.addListener(_onFusionUpdate);
    // Fusion may already be mid-stream — render the current frame immediately.
    _maybeDecode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fusion.removeListener(_onFusionUpdate);
    // Never dispose the fusion singleton — HomeScreen owns its lifecycle.
    _renderImage?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final paused =
        state != AppLifecycleState.resumed &&
        state != AppLifecycleState.inactive;
    if (paused == _paused) return;
    _paused = paused;
    if (!_paused) _maybeDecode(); // resume rendering
  }

  // ── Render pipeline (decode only — NO inference here) ──────────────────

  void _onFusionUpdate() {
    if (!mounted) return;
    // Refresh metrics/connection state every notify (cheap), and decode the
    // newly-published frame for the overlay (async, single-inflight).
    setState(() {});
    _maybeDecode();
  }

  Future<void> _maybeDecode() async {
    if (!mounted || _paused || _decoding) return;
    final fid = _fusion.latestProcessedFrameId;
    if (fid == _lastDecodedId) return; // nothing new
    final jpeg = _fusion.latestProcessedJpeg;
    if (jpeg == null) return;
    // Snapshot the detections synchronously with the jpeg/id above (no await
    // between these reads, so they're a consistent same-frame pair).
    final dets = _fusion.latestDetections;

    _decoding = true;
    _lastDecodedId = fid;
    try {
      final image = await _decode(jpeg);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _renderImage?.dispose();
        _renderImage = image;
        _detections = dets;
      });
    } on Object catch (e) {
      debugPrint('PiVisionScreen: frame decode failed — $e');
    } finally {
      _decoding = false;
      // A newer frame may have arrived mid-decode — pick it up. Microtask
      // avoids unbounded recursion on a fast stream.
      if (mounted &&
          !_paused &&
          _fusion.latestProcessedFrameId != _lastDecodedId) {
        scheduleMicrotask(_maybeDecode);
      }
    }
  }

  Future<ui.Image> _decode(Uint8List jpeg) async {
    final codec = await ui.instantiateImageCodec(jpeg);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          label: VisionStrings.piScreenSemantic,
          child: const Text(VisionStrings.piScreenTitle),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildMetricsRow(),
          Expanded(flex: 3, child: _buildViewport()),
          const Divider(height: 1),
          Expanded(flex: 2, child: _buildDetectionsList()),
        ],
      ),
    );
  }

  Widget _buildViewport() {
    // Fusion is the source of truth; if it isn't running there's nothing to
    // show. In our system fusion is always on, so this is a safety net.
    if (!AppConstants.enableSensorFusion || !_fusion.isRunning) {
      return _buildStatusView(
        icon: Icons.sensors_off,
        color: AppColors.warning,
        title: VisionStrings.piFusionOff,
        detail: VisionStrings.piFusionOffHint,
      );
    }
    if (PiFrameServer.instance.state == PiServerState.error) {
      return _buildStatusView(
        icon: Icons.wifi_off,
        color: AppColors.error,
        title: VisionStrings.piServerError,
        detail: PiFrameServer.instance.errorMessage,
      );
    }
    final image = _renderImage;
    if (image == null) {
      // Fusion running but no frame decoded yet — still connecting/warming up.
      return _buildStatusView(
        icon: Icons.videocam_outlined,
        color: AppColors.textSecondary,
        title: VisionStrings.piWaiting,
        detail: VisionStrings.piWaitingHint,
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
    // These come straight from fusion, so they match the fusion debug panel.
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppConstants.spacingM,
        vertical: AppConstants.spacingS,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _chip(
            VisionStrings.latencyLabel,
            '${_fusion.latencyMs.toStringAsFixed(0)} ms',
          ),
          _chip(VisionStrings.fpsLabel, _fusion.fps.toStringAsFixed(1)),
          _chip('ফ্রেম', '${_fusion.framesProcessed}'),
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
    required String title,
    String? detail,
    bool showSpinner = false,
  }) {
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
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          if (detail != null) ...[
            SizedBox(height: AppConstants.spacingS),
            Text(
              detail,
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

  Widget _buildDetectionsList() {
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
            VisionStrings.detectionsHeader,
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
                    VisionStrings.noDetections,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: dets.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => DetectionListTile(detection: dets[i]),
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
    final dst = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
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
        .clamp(
          bounds.left,
          (bounds.right - tp.width).clamp(bounds.left, bounds.right),
        )
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
