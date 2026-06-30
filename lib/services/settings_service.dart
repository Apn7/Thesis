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

  /// Always `'bn'` — the app speaks and listens in Bengali only.
  String get languageMode => 'bn';

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
    debugPrint(
      'SettingsService: loaded (language fixed at bn, '
      'sosContacts=${_sosContacts.length})',
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
