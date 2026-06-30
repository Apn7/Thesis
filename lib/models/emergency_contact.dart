import '../core/utils/constants.dart';

/// A saved emergency contact the SOS feature texts.
///
/// [phone] is stored as a full international number with **no** '+', spaces, or
/// dashes (e.g. `8801712345678`); the SOS service prepends '+' when handing it
/// to the SMS layer. Use [EmergencyContact.fromInput] to normalise whatever the
/// user typed into that canonical form.
class EmergencyContact {
  final String name;
  final String phone;

  const EmergencyContact({required this.name, required this.phone});

  /// Build a contact from raw UI input, normalising the phone number: strips
  /// every non-digit, then — if the result looks like a bare local Bangladeshi
  /// number (leading 0, ~11 digits) — swaps the leading 0 for the default
  /// country code. Numbers that already include a country code are kept as-is.
  factory EmergencyContact.fromInput({
    required String name,
    required String rawPhone,
  }) {
    return EmergencyContact(name: name.trim(), phone: normalisePhone(rawPhone));
  }

  /// Normalise a phone string to the digits-only international form.
  /// Exposed (and used by [fromInput]) so callers can validate.
  static String normalisePhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    // Local form like 01712345678 → drop the trunk 0 and prepend the country
    // code. (Bangladeshi mobile numbers are 11 digits starting with 0.)
    if (digits.startsWith('0')) {
      digits = '${AppConstants.sosDefaultCountryCode}${digits.substring(1)}';
    }
    return digits;
  }

  /// A plausible international mobile number is 11–15 digits (ITU E.164 caps
  /// at 15). Good enough to catch empty / obviously-wrong input before saving.
  bool get isValid => phone.length >= 11 && phone.length <= 15;

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        name: (json['name'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
      );
}
