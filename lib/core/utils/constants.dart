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

  /// Credentials of the access point the **Pi itself hosts** (fallback-AP
  /// provisioning, comitup-style). The app joins it with Android's
  /// WifiNetworkSpecifier — an app-scoped, local-only link that never becomes
  /// the default route, so the phone's internet (Groq, geocoding) stays on
  /// mobile data. Must match the Pi's `smartcane-ap` NetworkManager profile.
  static const String piApSsid = 'SmartCane-Cam';
  static const String piApPsk = 'smartcane123';

  /// Auto-join the cane's AP hands-free when the sensor pipeline starts
  /// (HomeScreen), instead of requiring the Cane Cam screen's debug button.
  /// First-ever join on a phone shows the one-time system consent dialog;
  /// after that every launch connects silently.
  static const bool enablePiAutoJoin = true;

  /// Stuck-join escalation cadence (seconds). While the specifier request
  /// sits unfulfilled in `requesting`, PiWifiService re-files it natively at
  /// this interval. Why re-file at all: on Android 12/13 the OS *revokes* the
  /// remembered silent approval whenever the phone is already associated to
  /// another WiFi (home/campus) and the radio can't host a second station
  /// interface — it then wants to re-show the consent dialog, but only
  /// re-evaluates all of this for a *freshly filed* request. Re-filing also
  /// restarts the platform's 10 s request scans with an immediate sweep.
  /// Long enough for a TalkBack user to find and press Connect on a consent
  /// window before it is replaced; short enough that the cane keeps winning
  /// the radio back from home WiFi within a minute of app entry.
  static const int piWifiRefileSeconds = 45;

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

  /// The sonar streams at ~5 Hz; if no reading arrives within this window the
  /// stream is stalled (WiFi hiccup, Pi hang, half-open TCP) and the last
  /// reading is a lie. The service then reverts to `noData` so the user is
  /// never alarmed — or falsely reassured — by a frozen distance.
  static const int sonarStaleMs = 2500;

  /// De-escalation hysteresis for the distance verdict. A reading hovering on
  /// a threshold (cane swinging at ~50 cm) would otherwise flap
  /// CRITICAL↔WARNING every reading, restarting the alarm tone and vibration
  /// burst each time. Escalation is instant (safety); de-escalation must clear
  /// the boundary by this margin.
  static const double verdictHysteresisCm = 10.0;

  // ── Sensor Fusion (camera detections + sonar distance) ────────────────
  // Combines the Pi camera's YOLO detections with the HC-SR04 sonar distance
  // into meaningful, non-overwhelming spoken alerts for the blind user. Runs
  // on HomeScreen (the user never has to open the Cane Cam debug screen).
  // Research provenance (see compass_artifact validation doc): ISANA, GlAccess
  // (state-change-only announcements + priority layer), Bai et al. (sonar
  // fallback for glass/poles). Additive — it never alters the existing
  // distance-alert haptics/tone flow in HomeScreen.
  //
  // Master switch — flip to false to fully detach the fusion layer.
  static const bool enableSensorFusion = true;

  /// Sliding-window frame count. An object is only *confirmed* (and eligible
  /// to be announced) once it appears in a majority of the last N frames —
  /// this stabilises flickery single-frame detections. At the Pi path's
  /// ~10 fps, 5 frames ≈ 0.5 s of evidence (acceptable latency).
  static const int fusionWindowSize = 5;

  /// Minimum frames (out of [fusionWindowSize]) an object must appear in to
  /// be confirmed. 3/5 = simple majority vote.
  static const int fusionMajorityThreshold = 3;

  /// Per-(zone,label) re-announcement cooldown. A confirmed object that stays
  /// put is not re-announced within this window, so the user isn't nagged.
  static const int fusionCooldownMs = 3000;

  /// Top-N objects included in an on-demand "what's in front of me?" reply.
  static const int fusionOnDemandTopN = 3;

  /// The sonar distance is only assigned to a detection / spoken as a fallback
  /// when it is within range. Beyond this (≈ HC-SR04 max range) the reading is
  /// "no obstacle", not a measurement, so we don't announce a distance.
  static const double fusionSonarMaxAssignCm = 400.0;

  // ── Sensor Fusion v2: Bayesian existence filter + scheduler ───────────
  // Replaces the 3-of-5 majority vote above (kept for A/B) with a per-class
  // recursive Bayesian existence estimate (Layer 1) feeding a bandwidth-limited
  // announcement scheduler (Layer 2), plus distance/looming enrichment (Layer
  // 3). Full rationale, math and per-class calibration: FUSION_REDESIGN.md.
  //
  // `final` (not const) so the legacy vote stays live code for analysis/A-B and
  // so the algorithm can be toggled without a dead-code branch.
  static final bool fusionUseBayesian = true;

  // Layer 1 — existence filter (log-odds). Confirm/drop use hysteresis so a
  // cell never chatters on the boundary; the clamp bounds dwell/memory length.
  static const double fusionConfirmLogOdds = 0.85; // ℓ_high ≈ P(exist) 0.70
  static const double fusionDropLogOdds = -0.85; // ℓ_low  ≈ P(exist) 0.30
  static const double fusionLogOddsClamp =
      3.0; // ± bound on accumulated evidence

  // Layer 2 — announcement scheduler (perception-bandwidth model).
  static const int fusionMinGapMs = 2500; // token-bucket cadence at normal load
  static const int fusionPreemptGapMs =
      800; // floor a Tier-1 hazard may preempt to
  static const int fusionRefractoryMs =
      6000; // novelty fully recovers after this
  static const double fusionUtilityFloor =
      0.20; // stay silent below this utility

  /// "What's in front of me?" freshness bound. If fusion hasn't successfully
  /// processed a frame within this window (Pi camera down, stream stalled),
  /// the answer would come from stale frames — say the camera is unavailable
  /// instead of describing a scene that may no longer exist.
  static const int fusionSceneStaleMs = 3000;

  // ── Emergency SOS (direct SMS) ────────────────────────────────────────
  // A zero-tap, hands-free panic alert: the app fetches GPS, builds a bilingual
  // message + a Google Maps link, and sends it as a direct SMS (via a Kotlin
  // SmsManager MethodChannel) to every saved emergency contact at once — no app
  // to open and no send button to find, which is the whole point for a blind
  // user. SMS is chosen over data channels because it reaches any handset and
  // can be sent programmatically; the per-message SIM cost is negligible for a
  // rarely-fired emergency. Android-only (no SMS on Windows desktop).
  //
  // Master switch — flip to false to detach the SOS feature entirely.
  static const bool enableSos = true;

  /// Eyes-free safety countdown before the SMS is sent, so an accidental
  /// trigger can be cancelled. Spoken down by the SOS screen.
  static const int sosCountdownSeconds = 5;

  /// Upper bound on saved emergency contacts.
  static const int sosMaxContacts = 5;

  /// Default dialling code prepended to a locally-entered number that has no
  /// country code. Bangladesh (880); stored without '+' or separators.
  static const String sosDefaultCountryCode = '880';
}
