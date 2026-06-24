import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../services/tts_service.dart';

/// Central "who speaks" policy for the hybrid TalkBack model.
///
/// The app cooperates with the OS screen reader (TalkBack) rather than
/// competing with it:
///   * When a screen reader is running it owns navigation and reads the UI,
///     so *status* speech is routed through it to avoid two voices at once.
///   * When no screen reader is running the app is self-voicing, so the same
///     status speech comes from our own [TtsService].
///
/// The live OS flag is read on every call (never cached) so the policy reacts
/// immediately if the user toggles TalkBack while the app is open.
class VoiceAnnouncer {
  VoiceAnnouncer._();

  /// True when an OS screen reader (TalkBack / VoiceOver) is currently active.
  static bool get screenReaderOn => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .accessibleNavigation;

  /// Status / feedback speech — errors, "ready", processing, permission hints.
  ///
  /// Routes through the active screen reader (via
  /// [SemanticsService.sendAnnouncement]) when one is present so we never talk
  /// over TalkBack; otherwise speaks with our own TTS.
  static Future<void> announce(String message) async {
    if (message.isEmpty) return;
    if (screenReaderOn) {
      final view = WidgetsBinding.instance.platformDispatcher.implicitView;
      if (view != null) {
        await SemanticsService.sendAnnouncement(
          view,
          message,
          TextDirection.ltr,
        );
      }
    } else {
      await TtsService.instance.speak(message);
    }
  }

  /// The app's own voice — command replies and obstacle / cane alerts.
  ///
  /// Always uses our TTS and is allowed to interrupt.  These are event-driven
  /// (the user just spoke a command, or a sensor fired), so TalkBack isn't
  /// reading anything at that instant and there's no collision to avoid.
  static Future<void> speak(String message) async {
    if (message.isEmpty) return;
    await TtsService.instance.speak(message);
  }
}
