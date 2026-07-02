import 'package:flutter_test/flutter_test.dart';
import 'package:test_app_1/services/distance_alert_source.dart';
import 'package:test_app_1/services/sensor_fusion_service.dart';

void main() {
  group('verdictForDistanceCmSticky (de-escalation hysteresis)', () {
    test('escalation is instant — severity up passes through unmodified', () {
      expect(
        verdictForDistanceCmSticky(45, ObstacleVerdict.safe),
        ObstacleVerdict.critical,
      );
      expect(
        verdictForDistanceCmSticky(95, ObstacleVerdict.caution),
        ObstacleVerdict.warning,
      );
    });

    test('a reading flapping on the CRITICAL boundary holds CRITICAL', () {
      // The demo-killer: cane swinging at ~50 cm would restart the alarm
      // tone + vibration burst on every reading without hysteresis.
      expect(
        verdictForDistanceCmSticky(52, ObstacleVerdict.critical),
        ObstacleVerdict.critical, // held: 52 < 50 + 10
      );
      expect(
        verdictForDistanceCmSticky(59.9, ObstacleVerdict.critical),
        ObstacleVerdict.critical,
      );
    });

    test('de-escalation happens once the margin is cleared', () {
      expect(
        verdictForDistanceCmSticky(61, ObstacleVerdict.critical),
        ObstacleVerdict.warning,
      );
      expect(
        verdictForDistanceCmSticky(115, ObstacleVerdict.warning),
        ObstacleVerdict.caution,
      );
      expect(
        verdictForDistanceCmSticky(215, ObstacleVerdict.caution),
        ObstacleVerdict.safe,
      );
    });

    test('a big jump skips bands without being held', () {
      expect(
        verdictForDistanceCmSticky(180, ObstacleVerdict.critical),
        ObstacleVerdict.caution,
      );
    });

    test('noData always passes through — a lost link silences the alarm', () {
      expect(
        verdictForDistanceCmSticky(null, ObstacleVerdict.critical),
        ObstacleVerdict.noData,
      );
      expect(
        verdictForDistanceCmSticky(-1, ObstacleVerdict.warning),
        ObstacleVerdict.noData,
      );
    });
  });

  group('SensorFusionService.spokenDistance (coarse Bengali phrasing)', () {
    test('below 1 m speaks centimetres rounded to 10 (matches the alarm)', () {
      expect(SensorFusionService.spokenDistance(87), '৯০ সেন্টিমিটার');
      expect(SensorFusionService.spokenDistance(52), '৫০ সেন্টিমিটার');
      // 99 cm must not round up into "১০০ সেন্টিমিটার".
      expect(SensorFusionService.spokenDistance(99), '৯০ সেন্টিমিটার');
    });

    test('1 m and above speaks idiomatic half-metre steps', () {
      expect(SensorFusionService.spokenDistance(100), '১ মিটার');
      expect(SensorFusionService.spokenDistance(140), 'দেড় মিটার');
      expect(SensorFusionService.spokenDistance(250), 'আড়াই মিটার');
      expect(SensorFusionService.spokenDistance(300), '৩ মিটার');
      expect(SensorFusionService.spokenDistance(340), 'সাড়ে ৩ মিটার');
      expect(SensorFusionService.spokenDistance(390), '৪ মিটার');
    });

    test('never emits an ASCII decimal point for the TTS to stumble on', () {
      for (double cm = 10; cm <= 400; cm += 7) {
        expect(SensorFusionService.spokenDistance(cm).contains('.'), isFalse);
      }
    });
  });
}
