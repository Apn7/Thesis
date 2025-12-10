import 'package:flutter/material.dart';

/// Semantic label builder for accessibility
class AccessibilityLabels {
  // Home screen
  static const String homeScreen = 'হোম স্ক্রীন। আপনি বাড়িতে আছেন।';
  static const String homeScreenEn = 'Home screen. You are at home.';
  
  // Navigation buttons
  static const String navigateToLocation = 'আপনার অবস্থান দেখুন';
  static const String navigateToLocationEn = 'View your location';
  
  static const String navigateToSettings = 'সেটিংস খুলুন';
  static const String navigateToSettingsEn = 'Open settings';
  
  static const String navigateToHelp = 'সাহায্য পান';
  static const String navigateToHelpEn = 'Get help';
  
  // Location screen
  static const String locationScreen = 'অবস্থান স্ক্রীন। আপনার বর্তমান অবস্থান।';
  static const String locationScreenEn = 'Location screen. Your current location.';
  
  static const String refreshLocation = 'অবস্থান রিফ্রেশ করুন';
  static const String refreshLocationEn = 'Refresh location';
  
  // Settings screen
  static const String settingsScreen = 'সেটিংস স্ক্রীন।';
  static const String settingsScreenEn = 'Settings screen.';
  
  // Help screen
  static const String helpScreen = 'সাহায্য স্ক্রীন।';
  static const String helpScreenEn = 'Help screen.';
  
  // Actions
  static const String backButton = 'পিছনে যান';
  static const String backButtonEn = 'Go back';
  
  static const String voiceListening = 'শুনছি...';
  static const String voiceListeningEn = 'Listening...';
  
  static const String voiceNotListening = 'ভয়েস কমান্ডের জন্য অপেক্ষা করছি';
  static const String voiceNotListeningEn = 'Waiting for voice command';
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
    return Semantics(
      label: label,
      liveRegion: true,
      // Assertive interrupts current speech, use sparingly
      child: child,
    );
  }
}
