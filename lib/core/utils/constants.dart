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

  // BLE (Bluetooth Low Energy) - must match Pi GATT server UUIDs
  static const String bleServiceUuid = '12345678-1234-5678-1234-56789abcdef0';
  static const String bleAlertCharUuid = '12345678-1234-5678-1234-56789abcdef1';
  static const String bleBatteryCharUuid =
      '12345678-1234-5678-1234-56789abcdef2';
  static const String bleDeviceName = 'SmartCane';
  static const Duration bleScanTimeout = Duration(seconds: 10);
  static const Duration bleReconnectDelay = Duration(seconds: 3);

  // ESP32 BLE — must match smart_cane_ble.ino
  static const String espBleServiceUuid =
      'a1b2c3d4-0001-1000-8000-00805f9b34fb';
  static const String espBleDistanceCharUuid =
      'a1b2c3d4-0002-1000-8000-00805f9b34fb';
  static const String espBleDeviceName = 'SmartCane_ESP';

  // Verdict thresholds (cm) — distance < threshold triggers that level
  static const double espCriticalCm = 50.0;
  static const double espWarningCm = 100.0;
  static const double espCautionCm = 200.0;

  // Feature flags — flip to detach/reattach without removing code
  static const bool enablePiBle = false;
  static const bool enableEspBle = true;
  static const bool enableLlm =
      true; // routes voice commands through GroqService (cloud LLaMA)
}
