import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';

/// Information card with icon and bilingual content
class InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String titleEn;
  final String value;
  final Color? color;
  final VoidCallback? onTap;
  final String? semanticLabel;
  
  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.titleEn,
    required this.value,
    this.color,
    this.onTap,
    this.semanticLabel,
  });
  
  @override
  Widget build(BuildContext context) {
    final cardColor = color ?? AppColors.primary;
    
    return Semantics(
      label: semanticLabel ?? '$title, $titleEn: $value',
      button: onTap != null,
      child: Card(
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          child: Padding(
            padding: EdgeInsets.all(AppConstants.spacingL),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(AppConstants.spacingM),
                  decoration: BoxDecoration(
                    color: cardColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                  ),
                  child: Icon(
                    icon,
                    size: AppConstants.iconL,
                    color: cardColor,
                  ),
                ),
                SizedBox(width: AppConstants.spacingL),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SizedBox(height: AppConstants.spacingXs),
                      Text(
                        titleEn,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: AppConstants.spacingS),
                      Text(
                        value,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.arrow_forward_ios,
                    size: AppConstants.iconS,
                    color: AppColors.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
