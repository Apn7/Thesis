import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists user preferences and notifies listeners.
///
/// The app is **Bengali-only**, so [languageMode] is fixed at `'bn'`. The
/// stored key is retained for forward-compatibility / silent migration so an
/// older preferences file doesn't cause errors.
class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  static const _kLangKey = 'stt_language_mode';

  /// Always `'bn'` — the app speaks and listens in Bengali only.
  String get languageMode => 'bn';

  /// Load persisted settings. Call once at app startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Migrate any stored language value to 'bn' silently.
    if (prefs.getString(_kLangKey) != 'bn') {
      await prefs.setString(_kLangKey, 'bn');
    }
    debugPrint('SettingsService: loaded (language fixed at bn)');
  }

  /// No-op — kept for call-site compatibility. Language is always Bengali.
  Future<void> setLanguageMode(String mode) async {
    debugPrint('SettingsService: setLanguageMode ignored — fixed at bn');
  }
}
