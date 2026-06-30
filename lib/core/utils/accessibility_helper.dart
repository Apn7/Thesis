import 'package:flutter/material.dart';

/// Semantic label builder for accessibility
class AccessibilityLabels {
  // Home screen
  static const String homeScreen = 'হোম স্ক্রীন। আপনি বাড়িতে আছেন।';

  // Navigation buttons
  static const String navigateToLocation = 'আপনার অবস্থান দেখুন';
  static const String navigateToSettings = 'সেটিংস খুলুন';
  static const String navigateToHelp = 'সাহায্য পান';

  // Location screen
  static const String locationScreen =
      'অবস্থান স্ক্রীন। আপনার বর্তমান অবস্থান।';
  static const String refreshLocation = 'অবস্থান রিফ্রেশ করুন';

  // Settings screen
  static const String settingsScreen = 'সেটিংস স্ক্রীন।';

  // Help screen
  static const String helpScreen = 'সাহায্য স্ক্রীন।';

  // Actions
  static const String backButton = 'পিছনে যান';
  static const String voiceListening = 'শুনছি...';
  static const String voiceNotListening = 'ভয়েস কমান্ডের জন্য অপেক্ষা করছি';
}

/// Helper for building accessible widgets
class AccessibilityHelper {
  /// Wrap a widget with semantic labels for screen readers
  static Widget withSemantics({
    required Widget child,
    required String label,
    String? hint,
    bool? button,
    bool? header,
    bool? liveRegion,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      button: button ?? false,
      header: header ?? false,
      liveRegion: liveRegion ?? false,
      child: child,
    );
  }

  /// Wrap a button with enhanced accessibility
  static Widget accessibleButton({
    required Widget child,
    required String label,
    required VoidCallback onPressed,
    String? hint,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      button: true,
      enabled: true,
      child: child,
    );
  }

  /// Create a live region that announces changes
  static Widget liveRegion({
    required Widget child,
    required String label,
    bool assertive = false,
  }) {
    return Semantics(label: label, liveRegion: true, child: child);
  }
}
