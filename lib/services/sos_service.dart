import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/emergency_contact.dart';
import 'location_service.dart';

/// Result of an SOS dispatch, so the UI can speak an accurate outcome.
enum SosResult {
  /// SMS handed to the radio for every contact.
  sent,

  /// The user (or OS) denied the SEND_SMS permission.
  permissionDenied,

  /// No emergency contacts are configured.
  noContacts,

  /// SMS is not available on this platform (e.g. Windows desktop).
  unsupported,

  /// The native send failed (no SIM, airplane mode, radio error…).
  failed,
}

/// Builds and dispatches the emergency SOS as a **direct SMS** — zero-tap and
/// hands-free, which is the whole point for a blind user. Each saved contact
/// receives one text containing a bilingual alert and a Google Maps link to the
/// user's live GPS location.
///
/// SMS (not WhatsApp/data) is deliberate: it is the only channel that needs no
/// app on the recipient's phone, reaches any handset, and — crucially — can be
/// sent programmatically without the user tapping a "send" button. The actual
/// send goes through a Kotlin [MethodChannel] to Android's `SmsManager`
/// (see `MainActivity.kt`); there is no SMS path on non-Android platforms.
class SosService {
  static final SosService instance = SosService._();
  SosService._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.test_app_1/sms',
  );

  final LocationService _location = LocationService.instance;

  /// Acquire one GPS fix and dispatch the SOS SMS to [contacts].
  ///
  /// Never throws — every failure maps to a [SosResult] the caller can speak.
  /// Sends to all contacts in a single native call (no per-contact tapping).
  Future<SosResult> sendSos(List<EmergencyContact> contacts) async {
    if (contacts.isEmpty) return SosResult.noContacts;
    if (!Platform.isAndroid) return SosResult.unsupported;

    // Runtime permission — SEND_SMS is dangerous-tier, so it must be granted
    // at run time (the manifest entry alone is not enough on Android 6+).
    final status = await Permission.sms.request();
    if (!status.isGranted) return SosResult.permissionDenied;

    final message = await _buildMessage();
    final addresses = contacts.map((c) => '+${c.phone}').toList();

    try {
      final sent = await _channel.invokeMethod<int>('sendSms', {
        'addresses': addresses,
        'message': message,
      });
      return (sent != null && sent > 0) ? SosResult.sent : SosResult.failed;
    } on PlatformException catch (e) {
      debugPrint('SosService: sendSms failed: ${e.code} ${e.message}');
      return e.code == 'NO_PERMISSION'
          ? SosResult.permissionDenied
          : SosResult.failed;
    } catch (e) {
      debugPrint('SosService: sendSms error: $e');
      return SosResult.failed;
    }
  }

  /// Compose the alert text. Kept compact on purpose: Bengali is Unicode SMS
  /// (~70 chars/segment), so we send a short bilingual line plus the maps link
  /// and skip the verbose reverse-geocoded address — the link already carries
  /// the exact location and keeps the message to a couple of segments.
  Future<String> _buildMessage() async {
    String? mapsLink;
    try {
      final loc = await _location.getCurrentLocation();
      if (loc != null) {
        mapsLink =
            'https://maps.google.com/?q=${loc.latitude},${loc.longitude}';
      }
    } catch (e) {
      debugPrint('SosService: location fetch failed: $e');
    }

    // Bilingual on purpose: a caregiver may read either language; it costs
    // little and the English line aids non-Bengali responders.
    final buffer = StringBuffer(
      'জরুরি! আমার সাহায্য দরকার। EMERGENCY! Need help.',
    );
    if (mapsLink != null) {
      buffer.write('\nLocation: $mapsLink');
    } else {
      buffer.write('\n(অবস্থান পাওয়া যায়নি / location unavailable)');
    }
    return buffer.toString();
  }
}
