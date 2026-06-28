import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../services/detection_models.dart';
import '../../services/distance_alert_source.dart';
import '../../services/sensor_fusion_service.dart';

/// On-screen debug panel for the [SensorFusionService]: shows exactly what the
/// fusion layer is detecting, what it has *confirmed* per zone, the live sonar
/// distance/verdict, and the last utterance it spoke.
///
/// This is a developer aid (the blind user relies on voice). It rebuilds at the
/// fusion frame rate, so it's wrapped in its own [ListenableBuilder] and kept
/// out of the main HomeScreen rebuild path.
class FusionDebugCard extends StatelessWidget {
  const FusionDebugCard({super.key});

  @override
  Widget build(BuildContext context) {
    final fusion = SensorFusionService.instance;
    return ListenableBuilder(
      listenable: fusion,
      builder: (context, _) {
        final dets = fusion.latestDetections;
        final distCm = fusion.latestDistanceCm;
        final verdict = fusion.verdict;

        return Card(
          elevation: 4,
          color: AppColors.primary.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusM),
            side: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(AppConstants.spacingM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, fusion),
                const Divider(height: 16),
                _metricsRow(context, fusion),
                SizedBox(height: AppConstants.spacingS),
                _distanceRow(context, distCm, verdict),
                SizedBox(height: AppConstants.spacingS),
                _confirmedZones(context, fusion, distCm),
                SizedBox(height: AppConstants.spacingS),
                _lastAnnouncement(context, fusion),
                const Divider(height: 16),
                _rawDetections(context, dets),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Sections ────────────────────────────────────────────────────────────

  Widget _header(BuildContext context, SensorFusionService fusion) {
    final ok = fusion.isRunning && fusion.modelReady;
    return Row(
      children: [
        Icon(
          ok ? Icons.hub : Icons.hub_outlined,
          size: AppConstants.iconM,
          color: ok ? AppColors.success : AppColors.warning,
        ),
        SizedBox(width: AppConstants.spacingS),
        Expanded(
          child: Text(
            'ফিউশন ডিবাগ / Fusion Debug',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        _pill(
          fusion.modelReady ? 'MODEL OK' : 'MODEL…',
          fusion.modelReady ? AppColors.success : AppColors.warning,
        ),
      ],
    );
  }

  Widget _metricsRow(BuildContext context, SensorFusionService fusion) {
    return Wrap(
      spacing: AppConstants.spacingS,
      runSpacing: AppConstants.spacingXs,
      children: [
        _stat('FPS', fusion.fps.toStringAsFixed(1)),
        _stat('Latency', '${fusion.latencyMs.toStringAsFixed(0)} ms'),
        _stat('Frames', '${fusion.framesProcessed}'),
        _stat(
          'Window',
          '${fusion.windowFill}/${AppConstants.fusionWindowSize}',
        ),
      ],
    );
  }

  Widget _distanceRow(BuildContext context, double? distCm, ObstacleVerdict v) {
    final color = _verdictColor(v);
    return Row(
      children: [
        Icon(Icons.straighten, size: AppConstants.iconS, color: color),
        SizedBox(width: AppConstants.spacingS),
        Text('Sonar: ', style: Theme.of(context).textTheme.bodyMedium),
        Text(
          distCm == null ? '— cm' : '${distCm.toStringAsFixed(1)} cm',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        SizedBox(width: AppConstants.spacingS),
        _pill(v.label, color),
      ],
    );
  }

  Widget _confirmedZones(
    BuildContext context,
    SensorFusionService fusion,
    double? distCm,
  ) {
    String centerText;
    final c = fusion.confirmedCenter;
    if (c == null) {
      centerText = '—';
    } else if (c == '__obstacle__') {
      centerText = 'obstacle (sonar)';
    } else {
      centerText = distCm != null
          ? '$c @ ${(distCm / 100).toStringAsFixed(1)} m'
          : c;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Confirmed (≥${AppConstants.fusionMajorityThreshold}/${AppConstants.fusionWindowSize})',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
        ),
        SizedBox(height: AppConstants.spacingXs),
        _zoneRow(context, 'Left', fusion.confirmedLeft ?? '—'),
        _zoneRow(context, 'Center', centerText, emphasise: true),
        _zoneRow(context, 'Right', fusion.confirmedRight ?? '—'),
      ],
    );
  }

  Widget _zoneRow(
    BuildContext context,
    String zone,
    String value, {
    bool emphasise = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppConstants.spacingXs / 2),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              zone,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: emphasise ? FontWeight.bold : FontWeight.normal,
                color: value == '—' ? AppColors.textSecondary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lastAnnouncement(BuildContext context, SensorFusionService fusion) {
    final text = fusion.lastAnnouncement.isEmpty
        ? '—'
        : fusion.lastAnnouncement;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.volume_up,
          size: AppConstants.iconS,
          color: AppColors.accent,
        ),
        SizedBox(width: AppConstants.spacingS),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }

  Widget _rawDetections(BuildContext context, List<Detection> dets) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Raw detections (${dets.length})',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
        ),
        SizedBox(height: AppConstants.spacingXs),
        if (dets.isEmpty)
          Text(
            'none',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          )
        else
          ...dets.map(
            (d) => Padding(
              padding: EdgeInsets.symmetric(
                vertical: AppConstants.spacingXs / 2,
              ),
              child: Row(
                children: [
                  _zoneTag(d.position),
                  SizedBox(width: AppConstants.spacingS),
                  Expanded(
                    child: Text(
                      d.label,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${(d.confidence * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Small helpers ─────────────────────────────────────────────────────

  Widget _zoneTag(PositionZone zone) {
    final color = switch (zone) {
      PositionZone.left => AppColors.info,
      PositionZone.center => AppColors.accent,
      PositionZone.right => AppColors.primary,
    };
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppConstants.radiusS),
      ),
      child: Text(
        zone.en,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Builder(
      builder: (context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppConstants.spacingS,
          vertical: AppConstants.spacingXs,
        ),
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(AppConstants.radiusS),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label ',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Color _verdictColor(ObstacleVerdict v) {
    switch (v) {
      case ObstacleVerdict.critical:
        return AppColors.error;
      case ObstacleVerdict.warning:
        return AppColors.warning;
      case ObstacleVerdict.caution:
        return AppColors.accent;
      case ObstacleVerdict.safe:
        return AppColors.success;
      case ObstacleVerdict.noData:
        return AppColors.textSecondary;
    }
  }
}
