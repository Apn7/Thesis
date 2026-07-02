import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_app_1/models/emergency_contact.dart';
import 'package:test_app_1/services/settings_service.dart';
import 'package:test_app_1/services/sos_dialog_controller.dart';

/// End-to-end FSM tests for the hands-free SOS contact dialog: real scoped
/// IntentMatcher (loads assets/intents/sos_intents.json), real SettingsService
/// over a mocked SharedPreferences. TTS goes through the Windows stub on the
/// test host, so speech is a timed no-op.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsService.instance;

  Future<void> clearContacts() async {
    while (settings.sosContacts.isNotEmpty) {
      await settings.removeSosContactAt(0);
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await settings.load();
    await clearContacts();
  });

  Future<void> seed(List<(String, String)> entries) async {
    for (final (name, phone) in entries) {
      final ok = await settings.addSosContact(
        EmergencyContact.fromInput(name: name, rawPhone: phone),
      );
      expect(ok, isTrue, reason: 'seeding $name should succeed');
    }
  }

  group('SosDialogController FSM', () {
    test('add flow: name → spoken number → yes → saved', () async {
      final dialog = SosDialogController();

      expect(await dialog.handleTranscript('যোগাযোগ যোগ করো'), isTrue);
      expect(dialog.stage, ContactDialogStage.askName);

      expect(await dialog.handleTranscript('আম্মু'), isTrue);
      expect(dialog.stage, ContactDialogStage.askNumber);

      expect(
        await dialog.handleTranscript(
          'শূন্য এক সাত এক দুই তিন চার পাঁচ ছয় সাত আট',
        ),
        isTrue,
      );
      expect(dialog.stage, ContactDialogStage.confirm);

      expect(await dialog.handleTranscript('হ্যাঁ'), isTrue);
      expect(dialog.stage, ContactDialogStage.idle);
      expect(settings.sosContacts, hasLength(1));
      expect(settings.sosContacts.first.name, 'আম্মু');
      expect(settings.sosContacts.first.phone, '8801712345678');
    });

    test('delete flow with several contacts: pick by number → yes', () async {
      await seed([('আম্মু', '01712345678'), ('ভাইয়া', '01898765432')]);
      final dialog = SosDialogController();

      expect(await dialog.handleTranscript('যোগাযোগ মুছো'), isTrue);
      expect(dialog.stage, ContactDialogStage.pickContact);

      expect(await dialog.handleTranscript('এক'), isTrue);
      expect(dialog.stage, ContactDialogStage.confirmDelete);
      expect(dialog.targetName, 'আম্মু');

      expect(await dialog.handleTranscript('হ্যাঁ'), isTrue);
      expect(dialog.stage, ContactDialogStage.idle);
      expect(settings.sosContacts, hasLength(1));
      expect(settings.sosContacts.first.name, 'ভাইয়া');
    });

    test('delete flow with one contact skips the pick stage', () async {
      await seed([('আম্মু', '01712345678')]);
      final dialog = SosDialogController();

      expect(await dialog.handleTranscript('যোগাযোগ মুছো'), isTrue);
      expect(dialog.stage, ContactDialogStage.confirmDelete);

      expect(await dialog.handleTranscript('না'), isTrue);
      expect(dialog.stage, ContactDialogStage.idle);
      expect(
        settings.sosContacts,
        hasLength(1),
        reason: '"না" must not delete',
      );
    });

    test('delete flow: pick by spoken name', () async {
      await seed([('আম্মু', '01712345678'), ('ভাইয়া', '01898765432')]);
      final dialog = SosDialogController();

      await dialog.handleTranscript('যোগাযোগ মুছো');
      expect(await dialog.handleTranscript('ভাইয়া'), isTrue);
      expect(dialog.stage, ContactDialogStage.confirmDelete);
      expect(dialog.targetName, 'ভাইয়া');
    });

    test('edit flow: single contact → new number → yes → replaced', () async {
      await seed([('আম্মু', '01712345678')]);
      final dialog = SosDialogController();

      expect(await dialog.handleTranscript('নম্বর বদলাও'), isTrue);
      expect(dialog.stage, ContactDialogStage.askNumber);

      await dialog.handleTranscript(
        'শূন্য এক আট নয় আট সাত ছয় পাঁচ চার তিন দুই',
      );
      expect(dialog.stage, ContactDialogStage.confirm);

      await dialog.handleTranscript('হ্যাঁ');
      expect(dialog.stage, ContactDialogStage.idle);
      expect(settings.sosContacts, hasLength(1));
      expect(settings.sosContacts.first.name, 'আম্মু', reason: 'name kept');
      expect(settings.sosContacts.first.phone, '8801898765432');
    });

    test('send-one flow: pick fires onSendToContact and resets', () async {
      await seed([('আম্মু', '01712345678'), ('ভাইয়া', '01898765432')]);
      final dialog = SosDialogController();
      EmergencyContact? sent;
      dialog.onSendToContact = (c) => sent = c;

      expect(await dialog.handleTranscript('একজনকে পাঠাও'), isTrue);
      expect(dialog.stage, ContactDialogStage.pickContact);

      expect(await dialog.handleTranscript('দুই'), isTrue);
      expect(dialog.stage, ContactDialogStage.idle);
      expect(sent?.name, 'ভাইয়া');
    });

    test('cancel aborts from any stage', () async {
      final dialog = SosDialogController();
      await dialog.handleTranscript('যোগাযোগ যোগ করো');
      expect(dialog.stage, ContactDialogStage.askName);

      expect(await dialog.handleTranscript('বাতিল'), isTrue);
      expect(dialog.stage, ContactDialogStage.idle);
      expect(settings.sosContacts, isEmpty);
    });

    test('isCancelPhrase recognises cancel words, rejects others', () async {
      final dialog = SosDialogController();
      expect(await dialog.isCancelPhrase('বাতিল'), isTrue);
      expect(await dialog.isCancelPhrase('cancel'), isTrue);
      expect(await dialog.isCancelPhrase('হ্যাঁ'), isFalse);
      expect(await dialog.isCancelPhrase('আম্মু'), isFalse);
    });

    test(
      'unknown speech while idle falls through to global pipeline',
      () async {
        final dialog = SosDialogController();
        expect(await dialog.handleTranscript('আমি কোথায়'), isFalse);
        expect(dialog.stage, ContactDialogStage.idle);
      },
    );

    test('pick stage: out-of-range number re-prompts and stays', () async {
      await seed([('আম্মু', '01712345678'), ('ভাইয়া', '01898765432')]);
      final dialog = SosDialogController();
      await dialog.handleTranscript('যোগাযোগ মুছো');

      expect(await dialog.handleTranscript('পাঁচ'), isTrue);
      expect(dialog.stage, ContactDialogStage.pickContact);
      expect(settings.sosContacts, hasLength(2));
    });
  });
}
