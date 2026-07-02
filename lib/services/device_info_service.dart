import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin Dart handle for the `system` MethodChannel in `MainActivity.kt` —
/// real device facts the voice assistant speaks (battery level today).
///
/// Every call is wrapped so a platform failure degrades to `null` and the
/// caller can speak an honest "couldn't read it" instead of crashing or —
/// worse — announcing made-up numbers to a blind user.
class DeviceInfoService {
  DeviceInfoService._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.test_app_1/system',
  );

  /// The phone's battery percentage (0–100), or null if unavailable
  /// (non-Android platform, platform error).
  static Future<int?> batteryLevel() async {
    if (!Platform.isAndroid) return null;
    try {
      final level = await _channel.invokeMethod<int>('getBatteryLevel');
      return (level != null && level >= 0 && level <= 100) ? level : null;
    } catch (e) {
      debugPrint('DeviceInfoService: battery read failed — $e');
      return null;
    }
  }
}
