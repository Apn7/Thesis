import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../services/detection_models.dart';
import '../../services/distance_alert_source.dart';
import '../../services/fusion/track.dart';
import '../../services/sensor_fusion_service.dart';

/// On-screen debug panel for the [SensorFusionService]: shows exactly what the
/// fusion layer is detecting, what it has *confirmed*, the live sonar
/// distance/verdict, and the last utterance it spoke.
///
/// It renders one of two layouts depending on the active fusion path:
///  * **Bayesian (v2, default):** per-track existence probability, severity
///    tier, proximity, looming and the scheduler's utility score — i.e. *why*
///    each track did or didn't earn the audio channel (FUSION_REDESIGN.md).
///  * **Legacy vote:** the old 3-of-5 sliding-window confirmed-per-zone view,
///    kept for A/B comparison when `fusionUseBayesian` is false.
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
        final bayes = fusion.usingBayesian;

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
                bayes ? _metricsRowV2(context, fusion) : _metricsRow(fusion),
                SizedBox(height: AppConstants.spacingS),
                _distanceRow(context, distCm, verdict),
                SizedBox(height: AppConstants.spacingS),
                if (bayes)
                  _tracksList(context, fusion)
                else
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
            'ফিউশন ডিবাগ',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        // Which fusion brain is live, so the panel is never read against the
        // wrong mental model.
        _pill(
          fusion.usingBayesian ? 'BAYES' : 'VOTE',
          fusion.usingBayesian ? AppColors.primary : AppColors.textSecondary,
        ),
        SizedBox(width: AppConstants.spacingXs),
        _pill(
          fusion.modelReady ? 'MODEL OK' : 'MODEL…',
          fusion.modelReady ? AppColors.success : AppColors.warning,
        ),
      ],
    );
  }

  // ── v2 (Bayesian) metrics + track list ────────────────────────────────

  Widget _metricsRowV2(BuildContext context, SensorFusionService fusion) {
    return Wrap(
      spacing: AppConstants.spacingS,
      runSpacing: AppConstants.spacingXs,
      children: [
        _stat('FPS', fusion.fps.toStringAsFixed(1)),
        _stat('Latency', '${fusion.latencyMs.toStringAsFixed(0)} ms'),
        _stat('ফ্রেম', '${fusion.framesProcessed}'),
        _stat('ট্র্যাক', '${fusion.confirmedTracks.length}'),
      ],
    );
  }

  Widget _tracksList(BuildContext context, SensorFusionService fusion) {
    final tracks = fusion.confirmedTracks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Confirmed tracks · P(exists) ≥ ${_sigmoid(AppConstants.fusionConfirmLogOdds).toStringAsFixed(2)}',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
        ),
        SizedBox(height: AppConstants.spacingXs),
        if (tracks.isEmpty)
          Text(
            'কিছু নিশ্চিত হয়নি',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          )
        else
          ...tracks.map((t) => _trackRow(context, fusion, t)),
      ],
    );
  }

  Widget _trackRow(BuildContext context, SensorFusionService fusion, Track t) {
    final picked = fusion.wasPicked(t);
    final utility = fusion.utilityFor(t);
    final looming = t.areaTrend > 0.15;
    final live = t.seenThisFrame;
    final name = t.label == '__obstacle__' ? 'বাধা (সোনার)' : t.label;

    // Sub-line: the scheduler inputs that decided whether this track spoke.
    final facts = <String>[
      'P ${(t.existence * 100).toStringAsFixed(0)}%',
      'prox ${t.proximity.toStringAsFixed(2)}',
      if (t.distanceCm != null) '${(t.distanceCm! / 100).toStringAsFixed(1)} m',
      if (looming) '↑ looming',
      'U ${utility.toStringAsFixed(2)}',
    ];

    return Container(
      margin: EdgeInsets.only(bottom: AppConstants.spacingXs),
      padding: EdgeInsets.symmetric(
        horizontal: AppConstants.spacingS,
        vertical: AppConstants.spacingXs,
      ),
      decoration: BoxDecoration(
        color: picked
            ? AppColors.accent.withValues(alpha: 0.14)
            : AppColors.primaryLight.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusS),
        border: picked
            ? Border.all(color: AppColors.accent.withValues(alpha: 0.6))
            : null,
      ),
      child: Opacity(
        // Lingering (not-this-frame) tracks are memory only — dim them.
        opacity: live ? 1.0 : 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _zoneTag(t.zone),
                SizedBox(width: AppConstants.spacingS),
                _tierChip(t.tier),
                SizedBox(width: AppConstants.spacingS),
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (picked)
                  Icon(
                    Icons.volume_up,
                    size: AppConstants.iconS,
                    color: AppColors.accentDark,
                  )
                else if (!live)
                  Text(
                    'mem',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
            SizedBox(height: AppConstants.spacingXs / 2),
            _existenceBar(t.existence, t.tier),
            SizedBox(height: AppConstants.spacingXs / 2),
            Text(
              facts.join('  ·  '),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// A slim existence-probability bar, coloured by severity tier.
  Widget _existenceBar(double p, int tier) {
    final color = _tierColor(tier);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: p.clamp(0.0, 1.0),
        minHeight: 5,
        backgroundColor: color.withValues(alpha: 0.15),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }

  Widget _tierChip(int tier) {
    final color = _tierColor(tier);
    final label = switch (tier) {
      1 => 'T1·hazard',
      2 => 'T2·near',
      _ => 'T3·context',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppConstants.radiusS),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Color _tierColor(int tier) => switch (tier) {
    1 => AppColors.error,
    2 => AppColors.warning,
    _ => AppColors.textSecondary,
  };

  // ── Legacy (vote) metrics + confirmed-per-zone ────────────────────────

  Widget _metricsRow(SensorFusionService fusion) {
    return Wrap(
      spacing: AppConstants.spacingS,
      runSpacing: AppConstants.spacingXs,
      children: [
        _stat('FPS', fusion.fps.toStringAsFixed(1)),
        _stat('Latency', '${fusion.latencyMs.toStringAsFixed(0)} ms'),
        _stat('ফ্রেম', '${fusion.framesProcessed}'),
        _stat(
          'উইন্ডো',
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
        Text('সোনার: ', style: Theme.of(context).textTheme.bodyMedium),
        Text(
          distCm == null ? '— সেমি' : '${distCm.toStringAsFixed(1)} সেমি',
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
      centerText = 'বাধা (সোনার)';
    } else {
      centerText = distCm != null
          ? '$c @ ${(distCm / 100).toStringAsFixed(1)} m'
          : c;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'নিশ্চিত (≥${AppConstants.fusionMajorityThreshold}/${AppConstants.fusionWindowSize})',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
        ),
        SizedBox(height: AppConstants.spacingXs),
        _zoneRow(context, 'বাম', fusion.confirmedLeft ?? '—'),
        _zoneRow(context, 'মাঝে', centerText, emphasise: true),
        _zoneRow(context, 'ডান', fusion.confirmedRight ?? '—'),
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
          'কাঁচা সনাক্তকরণ (${dets.length})',
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

  /// Logistic, to render the confirm threshold as a probability in the header.
  static double _sigmoid(double x) => 1 / (1 + math.exp(-x));
}
