/// Bilingual Bangla/English strings for the Vision Demo screen.
///
/// Pattern mirrors [AccessibilityLabels] in `accessibility_helper.dart`:
/// two parallel constants per concept (Bangla + English) so callers can
/// pick by [SettingsService.languageMode] or render both for sighted dev
/// use.
class VisionStrings {
  // Screen title
  static const String screenTitleBn = 'ভিশন ডেমো';
  static const String screenTitleEn = 'Vision Demo';

  // Permission flow
  static const String permissionDeniedBn = 'ক্যামেরা অনুমতি প্রয়োজন।';
  static const String permissionDeniedEn = 'Camera permission required.';

  static const String openSettingsBn = 'সেটিংস খুলুন';
  static const String openSettingsEn = 'Open Settings';

  // Loading / model state
  static const String loadingModelBn = 'মডেল লোড হচ্ছে...';
  static const String loadingModelEn = 'Loading model...';

  static const String modelMissingBn =
      'মডেল ফাইল পাওয়া যায়নি। ডকুমেন্টেশন দেখুন।';
  static const String modelMissingEn =
      'Model file not found. See documentation.';

  // Toggles
  static const String modelLabelBn = 'মডেল';
  static const String modelLabelEn = 'Model';

  static const String delegateLabelBn = 'ডেলিগেট';
  static const String delegateLabelEn = 'Delegate';

  // Metrics
  static const String latencyLabelBn = 'লেটেন্সি';
  static const String latencyLabelEn = 'Latency';

  static const String fpsLabelBn = 'এফপিএস';
  static const String fpsLabelEn = 'FPS';

  // Detection list
  static const String detectionsHeaderBn = 'সনাক্তকরণ';
  static const String detectionsHeaderEn = 'Detections';

  static const String noDetectionsBn = 'কিছু সনাক্ত হয়নি।';
  static const String noDetectionsEn = 'Nothing detected.';

  // Semantics
  static const String screenSemanticBn =
      'ভিশন ডেমো স্ক্রীন। লাইভ ক্যামেরা ফিড থেকে অবজেক্ট সনাক্ত করা হচ্ছে।';
  static const String screenSemanticEn =
      'Vision demo screen. Detecting objects from the live camera feed.';

  // Home-screen entry tile
  static const String tileLabelBn = 'ভিশন';
  static const String tileLabelEn = 'Vision';
  static const String tileHintBn = 'লাইভ ক্যামেরা থেকে অবজেক্ট সনাক্তকরণ ডেমো।';

  // ── Pi Zero vision (frames streamed from the cane camera) ──────────────
  static const String piScreenTitleBn = 'কেন ক্যামেরা';
  static const String piScreenTitleEn = 'Cane Camera';

  static const String piScreenSemanticBn =
      'কেন ক্যামেরা স্ক্রীন। লাঠির ক্যামেরা থেকে অবজেক্ট সনাক্ত করা হচ্ছে।';
  static const String piScreenSemanticEn =
      'Cane camera screen. Detecting objects from the cane-mounted camera.';

  // Connection states
  static const String piWaitingBn = 'ক্যামেরার সংযোগের অপেক্ষায়...';
  static const String piWaitingEn = 'Waiting for camera to connect...';

  static const String piWaitingHintBn =
      'নিশ্চিত করুন রাস্পবেরি পাই চালু আছে এবং একই ওয়াইফাইতে যুক্ত।';
  static const String piWaitingHintEn =
      'Make sure the Raspberry Pi is powered on and on the same Wi-Fi.';

  static const String piServerErrorBn = 'ক্যামেরা সার্ভার চালু করা যায়নি।';
  static const String piServerErrorEn = 'Could not start the camera server.';

  // Home-screen entry tile
  static const String piTileLabelBn = 'কেন ক্যাম';
  static const String piTileLabelEn = 'Cane Cam';
  static const String piTileHintBn = 'লাঠির ক্যামেরা থেকে অবজেক্ট সনাক্তকরণ।';
}
