import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/vision_strings.dart';
import '../../services/detection_models.dart';
import '../widgets/detection_list_tile.dart';

/// Vision Demo screen — live camera → YOLOv11n → native bbox overlay + list.
///
/// Built on the official Ultralytics `ultralytics_yolo` plugin.  The
/// native (Kotlin/CameraX) side owns the camera, frame rotation,
/// preprocessing, inference, NMS and box overlay — all the pieces that a
/// pure-Dart pipeline gets wrong or does too slowly (sensor-rotated
/// frames fed to the model sideways, per-pixel YUV→RGB on the UI
/// isolate).  Flutter receives only the decoded results and metrics.
///
/// The thesis quantization study is preserved: the FP16/INT8 toggle
/// switches models in place by changing [YOLOView.modelPath], and the
/// CPU/GPU toggle rebuilds the view with a different `useGpu` flag.
/// Latency/FPS come from the plugin's own [YOLOPerformanceMetrics].
class VisionDemoScreen extends StatefulWidget {
  const VisionDemoScreen({super.key});

  @override
  State<VisionDemoScreen> createState() => _VisionDemoScreenState();
}

class _VisionDemoScreenState extends State<VisionDemoScreen> {
  /// Mirrors [ObjectDetectionService]'s old thresholds so results stay
  /// comparable across the thesis' before/after pipeline measurements.
  static const double _confidenceThreshold = 0.25;
  static const double _iouThreshold = 0.45;

  final YOLOViewController _controller = YOLOViewController();

  bool _checkingPermission = true;
  bool _permissionDenied = false;

  ModelVariant _variant = ModelVariant.fp16;
  InferenceDelegate _delegate = InferenceDelegate.gpu;

  /// Set while a model switch is in flight (variant toggled, native
  /// `setModel` not yet settled) so the toggles can't be re-tapped
  /// mid-swap.  Cleared by [_onModelLoad] / [_onModelError].
  bool _switchingModel = false;

  /// Last model load/switch failure surfaced as a banner.  Set from
  /// [YOLOView.onModelError] (e.g. tapping INT8 when the INT8 .tflite
  /// isn't bundled), cleared on the next successful load.
  String? _modelError;

  List<Detection> _detections = const [];
  double _fps = 0;
  double _latencyMs = 0;

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _checkingPermission = false;
      _permissionDenied = !status.isGranted;
    });
  }

  String _assetPathFor(ModelVariant v) => 'assets/models/${v.assetFile}';

  // ── Plugin callbacks ──────────────────────────────────────────────────

  void _onResult(List<YOLOResult> results) {
    if (!mounted) return;
    setState(() {
      _detections = results
          .map(
            (r) => Detection(
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
          )
          .toList(growable: false);
    });
  }

  void _onMetrics(YOLOPerformanceMetrics metrics) {
    if (!mounted) return;
    setState(() {
      _fps = metrics.fps;
      _latencyMs = metrics.processingTimeMs;
    });
  }

  void _onModelLoad(String modelPath, YOLOTask? task) {
    if (!mounted) return;
    setState(() {
      _switchingModel = false;
      _modelError = null;
    });
  }

  void _onModelError(Object error, String modelPath, YOLOTask? task) {
    debugPrint('VisionDemoScreen: model load failed ($modelPath) — $error');
    if (!mounted) return;
    setState(() {
      _switchingModel = false;
      _modelError = '$error';
      // If a variant switch failed, fall back to FP16 (the bundled,
      // known-good model).  YOLOView keeps the previous model running
      // natively on a failed in-place switch, so this realigns the
      // toggle with what's actually loaded.
      if (modelPath == _assetPathFor(ModelVariant.int8)) {
        _variant = ModelVariant.fp16;
      }
    });
  }

  // ── Toggle handlers ───────────────────────────────────────────────────

  /// Model switching in `ultralytics_yolo` 0.6.x is declarative: setting a
  /// new [YOLOView.modelPath] triggers an in-place native switch (the
  /// widget serialises overlapping requests internally).  Outcome arrives
  /// via [_onModelLoad] / [_onModelError].
  void _onVariantChanged(ModelVariant v) {
    if (_switchingModel || v == _variant) return;
    setState(() {
      _switchingModel = true;
      _variant = v;
      _modelError = null;
    });
  }

  void _onDelegateChanged(InferenceDelegate d) {
    if (_switchingModel || d == _delegate) return;
    // `useGpu` is a construction-time flag on the platform view, so a
    // delegate change rebuilds YOLOView via the ValueKey below.
    setState(() {
      _delegate = d;
      _modelError = null;
      _detections = const [];
      _fps = 0;
      _latencyMs = 0;
    });
  }

  // ── UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          label: VisionStrings.screenSemantic,
          child: const Text(VisionStrings.screenTitle),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_checkingPermission) return _buildLoadingView();
    if (_permissionDenied) return _buildPermissionDeniedView();
    return Column(
      children: [
        if (_modelError != null) _buildModelErrorBanner(_modelError!),
        _buildToggleRow(),
        Expanded(flex: 3, child: _buildCameraView()),
        const Divider(height: 1),
        Expanded(flex: 2, child: _buildDetectionsList()),
      ],
    );
  }

  Widget _buildCameraView() {
    return YOLOView(
      // Rebuild the platform view when the delegate flips — `useGpu` can't
      // change on a live native view.
      key: ValueKey('yolo-${_delegate.name}'),
      modelPath: _assetPathFor(_variant),
      task: YOLOTask.detect,
      controller: _controller,
      useGpu: _delegate == InferenceDelegate.gpu,
      confidenceThreshold: _confidenceThreshold,
      iouThreshold: _iouThreshold,
      onResult: _onResult,
      onPerformanceMetrics: _onMetrics,
      onModelLoad: _onModelLoad,
      onModelError: _onModelError,
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          SizedBox(height: AppConstants.spacingL),
          const Text(VisionStrings.loadingModel),
        ],
      ),
    );
  }

  Widget _buildPermissionDeniedView() {
    return Padding(
      padding: EdgeInsets.all(AppConstants.spacingL),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined, size: 64, color: AppColors.warning),
            SizedBox(height: AppConstants.spacingL),
            Text(
              VisionStrings.permissionDenied,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: AppConstants.spacingL),
            ElevatedButton.icon(
              onPressed: openAppSettings,
              icon: const Icon(Icons.settings),
              label: const Text(VisionStrings.openSettings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelErrorBanner(String msg) {
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
              '${VisionStrings.modelMissing} $msg',
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

  Widget _buildToggleRow() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppConstants.spacingM,
        vertical: AppConstants.spacingS,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<ModelVariant>(
                  segments: const [
                    ButtonSegment(
                      value: ModelVariant.fp16,
                      label: Text('FP16'),
                    ),
                    ButtonSegment(
                      value: ModelVariant.int8,
                      label: Text('INT8'),
                    ),
                  ],
                  selected: {_variant},
                  onSelectionChanged: _switchingModel
                      ? null
                      : (s) => _onVariantChanged(s.first),
                ),
              ),
              SizedBox(width: AppConstants.spacingS),
              Expanded(
                child: SegmentedButton<InferenceDelegate>(
                  segments: const [
                    ButtonSegment(
                      value: InferenceDelegate.cpu,
                      label: Text('CPU'),
                    ),
                    ButtonSegment(
                      value: InferenceDelegate.gpu,
                      label: Text('GPU'),
                    ),
                  ],
                  selected: {_delegate},
                  onSelectionChanged: _switchingModel
                      ? null
                      : (s) => _onDelegateChanged(s.first),
                ),
              ),
            ],
          ),
          SizedBox(height: AppConstants.spacingS),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricChip(
                VisionStrings.latencyLabel,
                '${_latencyMs.toStringAsFixed(0)} ms',
              ),
              _buildMetricChip(VisionStrings.fpsLabel, _fps.toStringAsFixed(1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, String value) {
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
