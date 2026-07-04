/// Bengali strings for the Vision Demo and Cane Camera screens.
class VisionStrings {
  // Screen title
  static const String screenTitle = 'ভিশন ডেমো';

  // Permission flow
  static const String permissionDenied = 'ক্যামেরা অনুমতি প্রয়োজন।';
  static const String openSettings = 'সেটিংস খুলুন';

  // Loading / model state
  static const String loadingModel = 'মডেল লোড হচ্ছে...';
  static const String modelMissing =
      'মডেল ফাইল পাওয়া যায়নি। ডকুমেন্টেশন দেখুন।';

  // Toggles
  static const String modelLabel = 'মডেল';
  static const String delegateLabel = 'ডেলিগেট';

  // Metrics
  static const String latencyLabel = 'লেটেন্সি';
  static const String fpsLabel = 'এফপিএস';

  // Detection list
  static const String detectionsHeader = 'সনাক্তকরণ';
  static const String noDetections = 'কিছু সনাক্ত হয়নি।';

  // Semantics
  static const String screenSemantic =
      'ভিশন ডেমো স্ক্রীন। লাইভ ক্যামেরা ফিড থেকে অবজেক্ট সনাক্ত করা হচ্ছে।';

  // Home-screen entry tile
  static const String tileLabel = 'ভিশন';
  static const String tileHint = 'লাইভ ক্যামেরা থেকে অবজেক্ট সনাক্তকরণ ডেমো।';

  // ── Pi Zero vision (frames streamed from the cane camera) ──────────────
  static const String piScreenTitle = 'কেইন ক্যামেরা';
  static const String piScreenSemantic =
      'কেইন ক্যামেরা স্ক্রীন। লাঠির ক্যামেরা থেকে অবজেক্ট সনাক্ত করা হচ্ছে।';

  // Connection states
  static const String piWaiting = 'ক্যামেরার সংযোগের অপেক্ষায়...';
  static const String piWaitingHint =
      'নিশ্চিত করুন রাস্পবেরি পাই চালু আছে এবং একই ওয়াইফাইতে যুক্ত।';
  static const String piServerError = 'ক্যামেরা সার্ভার চালু করা যায়নি।';

  // Fusion-off state
  static const String piFusionOff = 'সেন্সর ফিউশন বন্ধ আছে।';
  static const String piFusionOffHint =
      'কেইন ক্যাম ফিউশন থেকে ফ্রেম দেখায়; ফিউশন চালু থাকা প্রয়োজন।';

  // Home-screen entry tile
  static const String piTileLabel = 'কেইন ক্যাম';
  static const String piTileHint = 'লাঠির ক্যামেরা থেকে অবজেক্ট সনাক্তকরণ।';

  // Pi AP join (WifiNetworkSpecifier — joining the camera's own WiFi)
  static const String piWifiConnect = 'ক্যামেরার ওয়াইফাই যুক্ত করুন';
  static const String piWifiSearching =
      'ক্যামেরা খোঁজা হচ্ছে... চালু হলে নিজে থেকেই যুক্ত হবে।';
  static const String piWifiConnected = 'ক্যামেরার ওয়াইফাই যুক্ত হয়েছে।';
  static const String piWifiFailed =
      'ওয়াইফাই যুক্ত করা যায়নি। পাই চালু আছে কিনা দেখুন।';
  static const String piWifiLost = 'ক্যামেরার ওয়াইফাই সংযোগ বিচ্ছিন্ন হয়েছে।';
}
