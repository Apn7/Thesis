import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'speech_service.dart';

/// Persists user preferences (language mode, etc.) and notifies listeners.
///
/// Uses [SharedPreferences] for simple key-value storage.
/// Access via [SettingsService.instance].
class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  static const _kLangKey = 'stt_language_mode';

  /// One of `'bn'` (Bangla, default) or `'en'` (English via Android STT).
  String _languageMode = 'bn';

  String get languageMode => _languageMode;

  /// Load persisted settings.  Call once at app startup.
  ///
  /// Migrates any legacy `'both'` value (from the previous SLI-based
  /// implementation) to `'bn'` so existing users don't end up in an
  /// unsupported state.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kLangKey) ?? 'bn';
    // Migrate legacy 'both' → 'bn'
    _languageMode = (stored == 'bn' || stored == 'en') ? stored : 'bn';
    debugPrint('SettingsService: loaded languageMode = $_languageMode');
  }

  /// Update the language mode, persist it, notify listeners, and
  /// propagate to [SpeechService].
  Future<void> setLanguageMode(String mode) async {
    assert(
      mode == 'bn' || mode == 'en',
      'setLanguageMode: mode must be bn or en',
    );
    if (mode == _languageMode) return;
    _languageMode = mode;
    notifyListeners();
    await SpeechService.instance.setLocale(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangKey, mode);
    debugPrint('SettingsService: saved languageMode = $mode');
  }
}
