import 'package:flutter_test/flutter_test.dart';
import 'package:test_app_1/services/intent_matcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SOS-scoped IntentMatcher (assets/intents/sos_intents.json)', () {
    late IntentMatcher matcher;

    setUp(() async {
      matcher = IntentMatcher.scoped('assets/intents/sos_intents.json');
      await matcher.load();
    });

    test('loads and is isolated from the global intents.json', () {
      expect(matcher.isLoaded, isTrue);
      // The global instance must NOT have SOS-dialog control words anymore.
      expect(IntentMatcher.instance, isNot(same(matcher)));
    });

    test('matches "read contacts" phrasing', () {
      expect(matcher.match('যোগাযোগ পড়ো')?.action, 'read_contacts');
      expect(matcher.match('jogajog poro')?.action, 'read_contacts');
    });

    test('matches "add contact" phrasing', () {
      expect(matcher.match('যোগাযোগ যোগ করো')?.action, 'add_contact');
    });

    test('matches confirm yes/no and cancel', () {
      expect(matcher.match('হ্যাঁ')?.action, 'confirm_yes');
      expect(matcher.match('না')?.action, 'confirm_no');
      expect(matcher.match('বাতিল')?.action, 'cancel');
    });

    test('matches "delete contact" phrasing', () {
      expect(matcher.match('যোগাযোগ মুছো')?.action, 'delete_contact');
      expect(matcher.match('যোগাযোগ মুছে ফেলো')?.action, 'delete_contact');
      expect(matcher.match('contact delete koro')?.action, 'delete_contact');
    });

    test('matches "edit contact" phrasing', () {
      expect(matcher.match('যোগাযোগ বদলাও')?.action, 'edit_contact');
      expect(matcher.match('নম্বর বদলাও')?.action, 'edit_contact');
      expect(matcher.match('number bodlao')?.action, 'edit_contact');
    });

    test('matches "send to one contact" phrasing', () {
      expect(matcher.match('একজনকে পাঠাও')?.action, 'send_single');
      expect(matcher.match('শুধু একজনকে পাঠাও')?.action, 'send_single');
      expect(matcher.match('ekjonke pathao')?.action, 'send_single');
    });

    test('add vs delete vs edit do not collide', () {
      // These near-neighbours share the word "যোগাযোগ" — each must still
      // resolve to its own action, never a sibling's.
      expect(matcher.match('যোগাযোগ যোগ করো')?.action, 'add_contact');
      expect(matcher.match('যোগাযোগ মুছো')?.action, 'delete_contact');
      expect(matcher.match('যোগাযোগ বদলাও')?.action, 'edit_contact');
      expect(matcher.match('যোগাযোগ পড়ো')?.action, 'read_contacts');
    });
  });

  group('Global IntentMatcher.instance no longer owns SOS control words', () {
    test(
      'confirm_yes/no/cancel/add_contact/read_contacts are gone globally',
      () async {
        final global = IntentMatcher.instance;
        await global.load();
        for (final phrase in [
          'হ্যাঁ',
          'না',
          'বাতিল',
          'যোগাযোগ যোগ করো',
          'যোগাযোগ পড়ো',
        ]) {
          final m = global.match(phrase);
          expect(
            m,
            anyOf(
              isNull,
              isNot(
                predicate(
                  (IntentMatch im) => [
                    'confirm_yes',
                    'confirm_no',
                    'cancel',
                    'add_contact',
                    'read_contacts',
                  ].contains(im.action),
                ),
              ),
            ),
            reason:
                'global matcher should not resolve "$phrase" to an SOS-dialog action',
          );
        }
      },
    );
  });
}
