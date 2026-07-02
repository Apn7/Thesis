import 'package:flutter/foundation.dart';

import '../core/utils/constants.dart';

/// Verdict computed from the latest distance reading.
///
/// Shared by every cane distance source (ESP32 over BLE, Pi HC-SR04 over WiFi)
/// so the rest of the app reacts identically regardless of which hardware
/// produced the reading.
enum ObstacleVerdict { noData, critical, warning, caution, safe }

extension ObstacleVerdictX on ObstacleVerdict {
  String get label {
    switch (this) {
      case ObstacleVerdict.noData:
        return 'তথ্য নেই';
      case ObstacleVerdict.critical:
        return 'বিপদ';
      case ObstacleVerdict.warning:
        return 'সতর্কতা';
      case ObstacleVerdict.caution:
        return 'সাবধান';
      case ObstacleVerdict.safe:
        return 'নিরাপদ';
    }
  }

  /// Short English word spoken on verdict *escalation* (severity goes up).
  /// Continuous distance feedback is carried by the click + vibration
  /// cadence in the UI layer; speech is reserved for the moment the
  /// situation gets worse, so the user is informed without being alarmed
  /// or talked over every few seconds.
  String get speechText {
    switch (this) {
      case ObstacleVerdict.critical:
        return 'থামুন';
      case ObstacleVerdict.warning:
        return 'খুব কাছে';
      case ObstacleVerdict.caution:
        return 'কাছে';
      case ObstacleVerdict.safe:
        return '';
      case ObstacleVerdict.noData:
        return '';
    }
  }

  /// Ordinal severity for escalation comparisons.  Speech fires only when
  /// this value strictly increases between consecutive readings.
  int get severity {
    switch (this) {
      case ObstacleVerdict.critical:
        return 3;
      case ObstacleVerdict.warning:
        return 2;
      case ObstacleVerdict.caution:
        return 1;
      case ObstacleVerdict.safe:
      case ObstacleVerdict.noData:
        return 0;
    }
  }
}

/// Classify a distance (cm) into a verdict using the shared `AppConstants`
/// thresholds. The single source of truth for both distance sources, so the
/// ESP32 and Pi paths can never drift apart on what counts as CRITICAL.
ObstacleVerdict verdictForDistanceCm(double? distanceCm) {
  final d = distanceCm;
  if (d == null || d < 0) return ObstacleVerdict.noData;
  if (d < AppConstants.espCriticalCm) return ObstacleVerdict.critical;
  if (d < AppConstants.espWarningCm) return ObstacleVerdict.warning;
  if (d < AppConstants.espCautionCm) return ObstacleVerdict.caution;
  return ObstacleVerdict.safe;
}

/// [verdictForDistanceCm] with **de-escalation hysteresis**.
///
/// A cane swinging at a threshold boundary (e.g. ~50 cm) makes the raw verdict
/// flap CRITICAL↔WARNING on nearly every reading — each flap restarts the
/// alarm tone, the vibration burst, and (on the way back up) the escalation
/// speech. Chattering alarms are the classic embedded-alert failure mode, so:
///
///  * **Escalation is instant** — severity going *up* always passes through
///    unmodified (safety first, no added latency).
///  * **De-escalation is sticky** — the reading must clear the previous
///    verdict's boundary by [AppConstants.verdictHysteresisCm] before the
///    verdict relaxes (e.g. leave CRITICAL only at ≥ 60 cm, not 50).
///  * `noData` always passes through — a lost link must silence the alarm.
ObstacleVerdict verdictForDistanceCmSticky(
  double? distanceCm,
  ObstacleVerdict previous,
) {
  final raw = verdictForDistanceCm(distanceCm);
  if (raw == ObstacleVerdict.noData) return raw;
  if (raw.severity >= previous.severity) return raw;

  final double boundary;
  switch (previous) {
    case ObstacleVerdict.critical:
      boundary = AppConstants.espCriticalCm;
    case ObstacleVerdict.warning:
      boundary = AppConstants.espWarningCm;
    case ObstacleVerdict.caution:
      boundary = AppConstants.espCautionCm;
    case ObstacleVerdict.safe:
    case ObstacleVerdict.noData:
      return raw; // nothing below these to hold on to
  }
  final held = distanceCm! < boundary + AppConstants.verdictHysteresisCm;
  return held ? previous : raw;
}

/// Connection lifecycle state of a distance source.
///
/// Named for the original ESP32 BLE peripheral; the Pi-over-WiFi source reuses
/// the same states so the UI is shared. For the WiFi source, `scanning` means
/// "socket bound, waiting for the Pi to dial in", `connected` means "the Pi is
/// streaming", and `bluetoothOff` never occurs.
enum SensorLinkState {
  disconnected,
  scanning,
  connecting,
  connected,
  bluetoothOff,
  error,
}

/// The surface `HomeScreen` consumes from whatever feeds distance alerts.
///
/// Both [EspBleService] (BLE) and [PiDistanceService] (WiFi) implement this,
/// so switching the cane's distance hardware is a one-line change at the call
/// site — the alert/haptics/speech logic downstream is untouched.
abstract class DistanceAlertSource implements Listenable {
  /// Current connection lifecycle state.
  SensorLinkState get state;

  /// True once a sensor is connected and (presumably) streaming.
  bool get isConnected;

  /// True while waiting for / searching for the sensor.
  bool get isScanning;

  /// Human-readable status for the on-screen card.
  String get statusMessage;

  /// Latest distance in centimetres, or null when there is no valid reading.
  double? get latestDistance;

  /// Verdict derived from [latestDistance] via [verdictForDistanceCm].
  ObstacleVerdict get verdict;

  /// Fired when the verdict transitions (e.g. SAFE → CRITICAL). Drives TTS and
  /// haptics without spamming on every reading.
  abstract void Function(ObstacleVerdict verdict)? onVerdictChanged;

  /// Begin operating (scan for BLE / bind the WiFi socket).
  Future<void> initialize();

  /// (Re)start searching for the sensor.
  Future<void> startScanning();

  /// Stop and tear down the connection.
  Future<void> disconnect();
}
