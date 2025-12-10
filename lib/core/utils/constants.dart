/// App-wide constants
class AppConstants {
  // App info
  static const String appName = 'স্মার্ট ক্যান';
  static const String appNameEn = 'Smart Cane';
  static const String appVersion = '1.0.0';
  
  // Touch target sizes (WCAG AAA compliance)
  static const double minTouchTargetSize = 56.0;
  static const double largeTouchTargetSize = 72.0;
  
  // Spacing
  static const double spacingXs = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXl = 32.0;
  static const double spacingXxl = 48.0;
  
  // Border radius
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 16.0;
  static const double radiusXl = 24.0;
  
  // Icon sizes
  static const double iconS = 20.0;
  static const double iconM = 24.0;
  static const double iconL = 32.0;
  static const double iconXl = 48.0;
  static const double iconXxl = 64.0;
  
  // Animation durations
  static const Duration animationFast = Duration(milliseconds: 200);
  static const Duration animationMedium = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);
  
  // Voice feedback delays
  static const Duration voiceFeedbackDelay = Duration(milliseconds: 500);
  static const Duration screenAnnouncementDelay = Duration(milliseconds: 800);
}
