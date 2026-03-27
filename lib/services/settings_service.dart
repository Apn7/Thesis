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

  /// One of `'bn'`, `'en'`, or `'both'`.
  String _languageMode = 'both';

  String get languageMode => _languageMode;

  /// Load persisted settings.  Call once at app startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _languageMode = prefs.getString(_kLangKey) ?? 'both';
    debugPrint('SettingsService: loaded languageMode = $_languageMode');
  }

  /// Update the language mode, persist it, notify listeners, and
  /// propagate to [SpeechService].
  Future<void> setLanguageMode(String mode) async {
    if (mode == _languageMode) return;
    _languageMode = mode;
    notifyListeners();
    await SpeechService.instance.setLocale(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangKey, mode);
    debugPrint('SettingsService: saved languageMode = $mode');
  }
}
