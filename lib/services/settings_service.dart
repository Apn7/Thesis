import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/constants.dart';
import '../models/emergency_contact.dart';

/// Persists user preferences and notifies listeners.
///
/// The app is **Bengali-only**, so [languageMode] is fixed at `'bn'`. The
/// stored key is retained for forward-compatibility / silent migration so an
/// older preferences file doesn't cause errors.
class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  static const _kLangKey = 'stt_language_mode';
  static const _kSosContactsKey = 'sos_emergency_contacts';
  static const _kSpeechRateKey = 'tts_speech_rate_multiplier';
  static const _kVibrationKey = 'vibration_enabled';

  /// Always `'bn'` — the app speaks and listens in Bengali only.
  String get languageMode => 'bn';

  // ── Speech rate ───────────────────────────────────────────────────────

  /// User-facing speech-rate multiplier: 1.0 is the default pace, range
  /// 0.5×–2.0×. The actual engine rate is derived via [ttsSpeechRate].
  static const double speechRateMin = 0.5;
  static const double speechRateMax = 2.0;
  static const double speechRateStep = 0.25;

  /// flutter_tts engine rate that corresponds to multiplier 1.0. Chosen for
  /// clear Bengali at default settings; the multiplier scales around it.
  static const double _engineBaseRate = 0.45;

  double _speechRateMultiplier = 1.0;
  double get speechRateMultiplier => _speechRateMultiplier;

  /// The engine-level rate to pass to `TtsService.setSpeechRate`.
  double get ttsSpeechRate =>
      (_engineBaseRate * _speechRateMultiplier).clamp(0.15, 1.0);

  Future<void> setSpeechRateMultiplier(double multiplier) async {
    _speechRateMultiplier = multiplier.clamp(speechRateMin, speechRateMax);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kSpeechRateKey, _speechRateMultiplier);
    } catch (e) {
      debugPrint('SettingsService: failed to persist speech rate: $e');
    }
  }

  // ── Vibration ─────────────────────────────────────────────────────────

  bool _vibrationEnabled = true;
  bool get vibrationEnabled => _vibrationEnabled;

  Future<void> setVibrationEnabled(bool enabled) async {
    _vibrationEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kVibrationKey, enabled);
    } catch (e) {
      debugPrint('SettingsService: failed to persist vibration: $e');
    }
  }

  /// Restore every user preference to its default and persist. Used by the
  /// settings screen's reset action — resets *real* stored values, not just
  /// widget state.
  Future<void> resetToDefaults() async {
    await setSpeechRateMultiplier(1.0);
    await setVibrationEnabled(true);
  }

  /// Emergency contacts the SOS feature alerts, in priority order (index 0 is
  /// contacted first). In-memory cache loaded once in [load]; mutations persist
  /// to disk and notify listeners so any open UI rebuilds.
  List<EmergencyContact> _sosContacts = const [];
  List<EmergencyContact> get sosContacts => List.unmodifiable(_sosContacts);

  /// Load persisted settings. Call once at app startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Migrate any stored language value to 'bn' silently.
    if (prefs.getString(_kLangKey) != 'bn') {
      await prefs.setString(_kLangKey, 'bn');
    }
    _sosContacts = _decodeContacts(prefs.getString(_kSosContactsKey));
    _speechRateMultiplier = (prefs.getDouble(_kSpeechRateKey) ?? 1.0).clamp(
      speechRateMin,
      speechRateMax,
    );
    _vibrationEnabled = prefs.getBool(_kVibrationKey) ?? true;
    debugPrint(
      'SettingsService: loaded (language fixed at bn, '
      'sosContacts=${_sosContacts.length}, '
      'speechRate=${_speechRateMultiplier}x, vibration=$_vibrationEnabled)',
    );
  }

  /// No-op — kept for call-site compatibility. Language is always Bengali.
  Future<void> setLanguageMode(String mode) async {
    debugPrint('SettingsService: setLanguageMode ignored — fixed at bn');
  }

  // ── Emergency contacts ────────────────────────────────────────────────

  /// Append [contact] (deduped by phone). Caps the list at
  /// [AppConstants.sosMaxContacts]; returns false (no change) when full or a
  /// duplicate. Persists and notifies on success.
  Future<bool> addSosContact(EmergencyContact contact) async {
    if (_sosContacts.length >= AppConstants.sosMaxContacts) return false;
    if (_sosContacts.any((c) => c.phone == contact.phone)) return false;
    _sosContacts = [..._sosContacts, contact];
    await _persistContacts();
    notifyListeners();
    return true;
  }

  /// Replace the contact at [index] with [contact]. Returns false (no change)
  /// when the index is out of range or the new phone duplicates another
  /// contact. Persists and notifies on success.
  Future<bool> updateSosContactAt(int index, EmergencyContact contact) async {
    if (index < 0 || index >= _sosContacts.length) return false;
    for (var i = 0; i < _sosContacts.length; i++) {
      if (i != index && _sosContacts[i].phone == contact.phone) return false;
    }
    final next = [..._sosContacts];
    next[index] = contact;
    _sosContacts = next;
    await _persistContacts();
    notifyListeners();
    return true;
  }

  /// Remove the contact at [index] (no-op if out of range).
  Future<void> removeSosContactAt(int index) async {
    if (index < 0 || index >= _sosContacts.length) return;
    final next = [..._sosContacts]..removeAt(index);
    _sosContacts = next;
    await _persistContacts();
    notifyListeners();
  }

  Future<void> _persistContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_sosContacts.map((c) => c.toJson()).toList());
      await prefs.setString(_kSosContactsKey, encoded);
    } catch (e) {
      debugPrint('SettingsService: failed to persist SOS contacts: $e');
    }
  }

  List<EmergencyContact> _decodeContacts(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(EmergencyContact.fromJson)
          .where((c) => c.phone.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('SettingsService: failed to decode SOS contacts: $e');
      return const [];
    }
  }
}
