import 'package:flutter/foundation.dart';

import '../core/utils/voice_announcer.dart';
import '../models/emergency_contact.dart';
import 'intent_matcher.dart';
import 'settings_service.dart';
import 'spoken_number_parser.dart';

/// Stage of the spoken contact-management dialog.
enum ContactDialogStage { idle, askName, askNumber, confirm }

/// Deterministic, screen-scoped voice dialog for managing SOS contacts.
///
/// Production voice agents drive the conversation with a state machine and use
/// language models only to *interpret* utterances — never to decide flow. This
/// controller is that state machine: a small FSM (name → number → confirm →
/// save) that is fully offline and predictable. The existing [IntentMatcher]
/// recognises the control words (start/read/yes/no/cancel); free-text slots
/// (the name, and the number via [SpokenNumberParser]) bypass matching.
///
/// It is fed by [VoiceNavigationService]'s transcript interceptor while the SOS
/// screen is mounted: [handleTranscript] gets first crack at every final
/// transcript and returns whether it consumed the utterance.
class SosDialogController extends ChangeNotifier {
  SosDialogController({SettingsService? settings, IntentMatcher? matcher})
    : _settings = settings ?? SettingsService.instance,
      // Scoped, NOT IntentMatcher.instance: control words like "yes"/"no"/
      // "cancel" must only be recognised while this dialog owns the voice
      // pipeline, never globally (saying "হ্যাঁ" elsewhere in the app must not
      // be swallowed by this dialog's vocabulary).
      _matcher =
          matcher ?? IntentMatcher.scoped('assets/intents/sos_intents.json');

  final SettingsService _settings;
  final IntentMatcher _matcher;

  ContactDialogStage _stage = ContactDialogStage.idle;
  ContactDialogStage get stage => _stage;
  bool get isActive => _stage != ContactDialogStage.idle;

  String _pendingName = '';
  String _pendingDigits = ''; // ASCII, local form (e.g. 01712345678)
  String get pendingName => _pendingName;
  String get pendingDigits => _pendingDigits;

  void _setStage(ContactDialogStage s) {
    _stage = s;
    notifyListeners();
  }

  /// First crack at a final [text] transcript. Returns true if the dialog
  /// consumed it (so the global intent/LLM pipeline is skipped), false to let
  /// the normal pipeline handle it (e.g. "go home" while idle).
  Future<bool> handleTranscript(String text) async {
    // No-op after the first call: IntentMatcher.load() short-circuits once
    // _loaded is true, so this is cheap to await on every transcript.
    await _matcher.load();

    final t = text.trim();
    if (t.isEmpty) return isActive; // swallow empties only mid-dialog

    // "cancel" aborts from any active stage.
    if (isActive && _actionOf(t) == 'cancel') {
      await _cancel();
      return true;
    }

    switch (_stage) {
      case ContactDialogStage.idle:
        return _handleIdle(t);
      case ContactDialogStage.askName:
        return _handleName(t);
      case ContactDialogStage.askNumber:
        return _handleNumber(t);
      case ContactDialogStage.confirm:
        return _handleConfirm(t);
    }
  }

  /// Reset to idle (e.g. when the screen is disposed mid-dialog).
  void reset() {
    _pendingName = '';
    _pendingDigits = '';
    _setStage(ContactDialogStage.idle);
  }

  // ── Stage handlers ──────────────────────────────────────────────────────

  Future<bool> _handleIdle(String t) async {
    switch (_actionOf(t)) {
      case 'add_contact':
        _pendingName = '';
        _pendingDigits = '';
        _setStage(ContactDialogStage.askName);
        await VoiceAnnouncer.speak('নতুন যোগাযোগের নাম বলুন।');
        return true;
      case 'read_contacts':
        await _readContacts();
        return true;
      default:
        return false; // not a contact command — let the global pipeline decide
    }
  }

  Future<bool> _handleName(String t) async {
    _pendingName = t;
    _setStage(ContactDialogStage.askNumber);
    await VoiceAnnouncer.speak(
      '$_pendingName এর মোবাইল নম্বর বলুন। একটি একটি করে সংখ্যা বলুন।',
    );
    return true;
  }

  Future<bool> _handleNumber(String t) async {
    final digits = SpokenNumberParser.parseToAsciiDigits(t);
    // Validate via the same normalisation the manual flow uses.
    final candidate = EmergencyContact.fromInput(
      name: _pendingName,
      rawPhone: digits,
    );
    if (digits.isEmpty || !candidate.isValid) {
      await VoiceAnnouncer.speak(
        'নম্বরটি বুঝতে পারিনি বা সংখ্যা ঠিক হয়নি। অনুগ্রহ করে আবার বলুন।',
      );
      return true; // stay in askNumber
    }
    _pendingDigits = digits;
    _setStage(ContactDialogStage.confirm);
    final readback = SpokenNumberParser.toBanglaReadback(digits);
    await VoiceAnnouncer.speak(
      'আপনি বলেছেন: $readback। সংরক্ষণ করতে হ্যাঁ বলুন, ভুল হলে না বলুন।',
    );
    return true;
  }

  Future<bool> _handleConfirm(String t) async {
    switch (_actionOf(t)) {
      case 'confirm_yes':
        final contact = EmergencyContact.fromInput(
          name: _pendingName,
          rawPhone: _pendingDigits,
        );
        final ok = await _settings.addSosContact(contact);
        final name = _pendingName;
        reset();
        await VoiceAnnouncer.speak(
          ok
              ? '$name যোগ করা হয়েছে।'
              : 'যোগ করা যায়নি। তালিকা পূর্ণ অথবা নম্বরটি আগে থেকেই আছে।',
        );
        return true;
      case 'confirm_no':
        _setStage(ContactDialogStage.askNumber);
        await VoiceAnnouncer.speak('ঠিক আছে, নম্বরটি আবার বলুন।');
        return true;
      default:
        await VoiceAnnouncer.speak(
          'সংরক্ষণ করতে হ্যাঁ বলুন, বাতিল করতে না বলুন।',
        );
        return true;
    }
  }

  Future<void> _cancel() async {
    reset();
    await VoiceAnnouncer.speak('বাতিল করা হয়েছে।');
  }

  Future<void> _readContacts() async {
    final contacts = _settings.sosContacts;
    if (contacts.isEmpty) {
      await VoiceAnnouncer.speak(
        'কোনো জরুরি যোগাযোগ সংরক্ষণ করা নেই। যোগ করতে বলুন "যোগাযোগ যোগ করো"।',
      );
      return;
    }
    final buffer = StringBuffer('${contacts.length} জন জরুরি যোগাযোগ আছে। ');
    for (var i = 0; i < contacts.length; i++) {
      final c = contacts[i];
      final readback = SpokenNumberParser.toBanglaReadback(c.phone);
      buffer.write('${i + 1}. ${c.name}, নম্বর $readback। ');
    }
    await VoiceAnnouncer.speak(buffer.toString());
  }

  /// Local intent action for [text], or null if none clears the matcher
  /// threshold. Used only for control words — never for slot values.
  String? _actionOf(String text) => _matcher.match(text)?.action;
}
