import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Dart handle for the Android [CaneForegroundService] (see the Kotlin file of
/// that name): a foreground service + partial wake lock + WiFi lock that keep
/// the cane pipeline — TCP frame/sonar servers, YOLO inference, obstacle
/// alerts — running while the phone is pocketed with the screen off.
///
/// Without it, Android freezes the cached process minutes after the screen
/// locks and the alerts die *silently* — the user keeps walking, trusting a
/// pipeline that is no longer there. The service holds no logic of its own;
/// all state stays in this isolate.
///
/// Start it when the cane pipeline starts, stop it when the pipeline stops
/// (HomeScreen owns both). Both calls are idempotent and safe no-ops on
/// non-Android platforms or if the platform side fails — the app must never
/// crash over a missing shield.
class CaneForegroundService {
  CaneForegroundService._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.test_app_1/foreground_service',
  );

  static bool _running = false;

  /// True after a successful [start] (best-effort mirror of the native state).
  static bool get isRunning => _running;

  static Future<void> start() async {
    if (!Platform.isAndroid || _running) return;
    // Android 13+ gates the service's status notification behind a runtime
    // permission. Ask once here; a denial is fine — the service still runs,
    // the shade entry is just hidden (permission_handler auto-grants < 13).
    try {
      await Permission.notification.request();
    } on Object catch (e) {
      debugPrint('CaneForegroundService: notification permission — $e');
    }
    try {
      await _channel.invokeMethod<bool>('start');
      _running = true;
      debugPrint('CaneForegroundService: started (screen-off shield up)');
    } on Object catch (e) {
      debugPrint('CaneForegroundService: start failed — $e');
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid || !_running) return;
    try {
      await _channel.invokeMethod<bool>('stop');
      debugPrint('CaneForegroundService: stopped');
    } on Object catch (e) {
      debugPrint('CaneForegroundService: stop failed — $e');
    } finally {
      _running = false;
    }
  }
}
