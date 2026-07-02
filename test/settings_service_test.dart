import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_app_1/services/settings_service.dart';

/// Persistence tests for the real user preferences added in the 2026-07-03
/// pass: speech-rate multiplier and vibration toggle. These settings back the
/// settings screen AND the "ধীরে বলো"/"দ্রুত বলো" voice commands, so a silent
/// persistence failure would surface as "my setting didn't stick".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await settings.load();
  });

  group('speech rate', () {
    test('defaults to 1.0x', () {
      expect(settings.speechRateMultiplier, 1.0);
    });

    test('set persists and survives reload', () async {
      await settings.setSpeechRateMultiplier(1.5);
      expect(settings.speechRateMultiplier, 1.5);

      await settings.load();
      expect(settings.speechRateMultiplier, 1.5);
    });

    test('clamps to the allowed range', () async {
      await settings.setSpeechRateMultiplier(9.0);
      expect(settings.speechRateMultiplier, SettingsService.speechRateMax);

      await settings.setSpeechRateMultiplier(0.1);
      expect(settings.speechRateMultiplier, SettingsService.speechRateMin);
    });

    test(
      'ttsSpeechRate scales around the engine base and stays bounded',
      () async {
        await settings.setSpeechRateMultiplier(1.0);
        final base = settings.ttsSpeechRate;

        await settings.setSpeechRateMultiplier(2.0);
        expect(settings.ttsSpeechRate, greaterThan(base));
        expect(settings.ttsSpeechRate, lessThanOrEqualTo(1.0));

        await settings.setSpeechRateMultiplier(0.5);
        expect(settings.ttsSpeechRate, lessThan(base));
        expect(settings.ttsSpeechRate, greaterThanOrEqualTo(0.15));
      },
    );
  });

  group('vibration', () {
    test('defaults to enabled', () {
      expect(settings.vibrationEnabled, isTrue);
    });

    test('set persists and survives reload', () async {
      await settings.setVibrationEnabled(false);
      expect(settings.vibrationEnabled, isFalse);

      await settings.load();
      expect(settings.vibrationEnabled, isFalse);
    });
  });

  test('resetToDefaults restores and persists both', () async {
    await settings.setSpeechRateMultiplier(2.0);
    await settings.setVibrationEnabled(false);

    await settings.resetToDefaults();
    expect(settings.speechRateMultiplier, 1.0);
    expect(settings.vibrationEnabled, isTrue);

    await settings.load();
    expect(settings.speechRateMultiplier, 1.0);
    expect(settings.vibrationEnabled, isTrue);
  });
}
