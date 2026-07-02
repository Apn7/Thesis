import 'package:flutter_test/flutter_test.dart';
import 'package:test_app_1/services/intent_matcher.dart';

/// Coverage for the 2026-07-03 global intent additions: go_back, repeat_last,
/// speech_faster/slower and speak_commands — including the near-neighbour
/// phrases that share tokens ("কি বললে" repeat vs "কি বলতে পারি" commands).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Global IntentMatcher — navigation control intents', () {
    late IntentMatcher matcher;

    setUp(() async {
      matcher = IntentMatcher.instance;
      await matcher.load();
    });

    test('go_back phrasing', () {
      expect(matcher.match('পিছনে যাও')?.action, 'go_back');
      expect(matcher.match('ফিরে যাও')?.action, 'go_back');
      expect(matcher.match('go back')?.action, 'go_back');
      expect(matcher.match('pichone jao')?.action, 'go_back');
    });

    test('repeat_last phrasing', () {
      expect(matcher.match('আবার বলো')?.action, 'repeat_last');
      expect(matcher.match('আরেকবার বলো')?.action, 'repeat_last');
      expect(matcher.match('say again')?.action, 'repeat_last');
      expect(matcher.match('abar bolo')?.action, 'repeat_last');
    });

    test('speech rate phrasing', () {
      expect(matcher.match('ধীরে বলো')?.action, 'speech_slower');
      expect(matcher.match('আস্তে বলো')?.action, 'speech_slower');
      expect(matcher.match('speak slower')?.action, 'speech_slower');
      expect(matcher.match('দ্রুত বলো')?.action, 'speech_faster');
      expect(matcher.match('তাড়াতাড়ি বলো')?.action, 'speech_faster');
      expect(matcher.match('speak faster')?.action, 'speech_faster');
    });

    test('speak_commands phrasing', () {
      expect(matcher.match('কী বলতে পারি')?.action, 'speak_commands');
      expect(matcher.match('সব কমান্ড বলো')?.action, 'speak_commands');
      expect(matcher.match('what can i say')?.action, 'speak_commands');
    });

    test('near-neighbours do not collide', () {
      // "আবার বলো" (repeat) shares বলো with the rate/command intents; the
      // rate pair differ only in the adverb; "কি বললে" (repeat) vs
      // "কি বলতে পারি" (commands) share two of three tokens.
      expect(matcher.match('আবার বলো')?.action, 'repeat_last');
      expect(matcher.match('ধীরে বলো')?.action, 'speech_slower');
      expect(matcher.match('দ্রুত বলো')?.action, 'speech_faster');
      expect(matcher.match('কী বললে')?.action, 'repeat_last');
      expect(matcher.match('কী বলতে পারি')?.action, 'speak_commands');
    });

    test('new intents do not shadow existing navigation', () {
      expect(matcher.match('আমি কোথায়')?.action, 'navigate_location');
      expect(matcher.match('হোমে যাও')?.action, 'navigate_home');
      expect(matcher.match('সেটিংস')?.action, 'navigate_settings');
      expect(matcher.match('জরুরি')?.action, 'trigger_sos');
      expect(matcher.match('সময় কত')?.action, 'speak_time');
    });
  });
}
