import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';

/// Large, accessible action button for voice-first navigation
class AccessibleActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String labelEn;
  final String? semanticHint;
  final VoidCallback onPressed;
  final Color? color;
  final bool isLarge;
  
  const AccessibleActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.labelEn,
    required this.onPressed,
    this.semanticHint,
    this.color,
    this.isLarge = false,
  });
  
  @override
  Widget build(BuildContext context) {
    final buttonColor = color ?? AppColors.primary;
    final size = isLarge ? AppConstants.largeTouchTargetSize : AppConstants.minTouchTargetSize;
    
    return Semantics(
      button: true,
      label: '$label. $labelEn',
      hint: semanticHint,
      enabled: true,
      child: Material(
        color: buttonColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppConstants.radiusL),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppConstants.radiusL),
          child: Container(
            padding: EdgeInsets.all(AppConstants.spacingL),
            constraints: BoxConstraints(
              minHeight: size * 2,
              minWidth: size * 2,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(AppConstants.spacingL),
                  decoration: BoxDecoration(
                    color: buttonColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: isLarge ? AppConstants.iconXxl : AppConstants.iconXl,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: AppConstants.spacingM),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: buttonColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppConstants.spacingXs),
                Text(
                  labelEn,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
