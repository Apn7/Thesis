import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../services/detection_models.dart';

/// One row of the live-detection list shown under the camera preview.
///
/// Renders the COCO class label, a confidence bar, and a position chip
/// (left/center/right) computed from the bbox centre.
class DetectionListTile extends StatelessWidget {
  final Detection detection;

  const DetectionListTile({
    super.key,
    required this.detection,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (detection.confidence * 100).clamp(0, 100).toStringAsFixed(0);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppConstants.spacingM,
        vertical: AppConstants.spacingS,
      ),
      child: Row(
        children: [
          Icon(
            Icons.crop_square,
            size: AppConstants.iconS,
            color: AppColors.primary,
          ),
          SizedBox(width: AppConstants.spacingM),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detection.label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: AppConstants.spacingXs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: detection.confidence.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: AppConstants.spacingM),
          SizedBox(
            width: 44,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: AppConstants.spacingS),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppConstants.radiusS),
            ),
            child: Text(
              detection.position.bn,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
