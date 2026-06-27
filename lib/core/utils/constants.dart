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
  // ESP32 BLE path — superseded by the Pi HC-SR04 over WiFi (`enablePiDistance`
  // below). Kept dormant (like the legacy `enablePiBle` path) as a fallback.
  static const bool enableEspBle = false;
  static const bool enableLlm =
      true; // routes voice commands through GroqService (cloud LLaMA)

  // ── Pi Zero vision (camera frames over WiFi) ──────────────────────────
  // The Raspberry Pi Zero 2 W + IMX519 camera streams JPEG frames to the
  // phone, which runs them through the bundled YOLO via YOLO.predict().
  // See Thesis_pi_zero/PI_ZERO_VISION_PLAN.md. Gate mirrors enableEspBle.
  static const bool enablePiVision = true;

  /// TCP port the app's frame server listens on. The Pi *dials* the phone
  /// (the hotspot gateway) here. Must match the Pi's `--port` / config.
  static const int piFramePort = 8765;

  /// Upper bound on a single frame's byte length. A length prefix larger
  /// than this means the stream desynced or is corrupt — we drop the
  /// connection rather than allocate a huge buffer (anti-OOM guard).
  static const int piMaxFrameBytes = 4 * 1024 * 1024; // 4 MB

  /// Wire framing: each frame is a 4-byte big-endian unsigned length
  /// prefix followed by that many JPEG bytes.
  static const int piFrameHeaderBytes = 4;

  // ── Pi Zero distance (HC-SR04 over WiFi) ──────────────────────────────
  // Replaces the ESP32 ultrasonic path. The Pi reads the HC-SR04 and dials
  // the phone here, pushing newline-delimited centimetre readings; the app
  // applies the SAME esp*Cm thresholds. A distinct port from the camera frame
  // stream so the two never block each other. `PiDistanceService` mirrors
  // `EspBleService`, so flipping these flags swaps the cane's distance
  // hardware with no other app changes.
  //
  // The two distance sources are mutually exclusive — when `enablePiDistance`
  // is true it takes precedence over `enableEspBle` (see home_screen.dart).
  // To run on the Pi: set enablePiDistance = true, enableEspBle = false.
  static const bool enablePiDistance = true;

  /// TCP port the app's distance server listens on. The Pi *dials* the phone
  /// here. Must equal Thesis_pi_zero/pi_vision/config.py `SONAR_PORT`.
  static const int piDistancePort = 8766;

  /// A distance line should be a handful of ASCII chars (e.g. "1234.5\n"). A
  /// line longer than this means the stream desynced or is garbage, so we drop
  /// the connection and let the Pi redial rather than buffer unboundedly.
  static const int piDistanceMaxLineBytes = 64;
}
