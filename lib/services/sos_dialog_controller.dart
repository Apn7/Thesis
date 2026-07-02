import 'package:flutter/foundation.dart';

import '../core/utils/constants.dart';
import '../core/utils/voice_announcer.dart';
import '../models/emergency_contact.dart';
import 'intent_matcher.dart';
import 'settings_service.dart';
import 'spoken_number_parser.dart';

/// Stage of the spoken contact-management dialog.
enum ContactDialogStage {
  idle,
  askName,
  askNumber,
  confirm,

  /// Choosing which saved contact an operation targets ("বলুন কত নম্বর…").
  pickContact,

  /// Final yes/no gate before a destructive delete.
  confirmDelete,
}

/// Which multi-step operation the dialog is currently walking through.
enum SosDialogOp { none, add, edit, delete, sendOne }

/// Deterministic, screen-scoped voice dialog for managing SOS contacts.
///
/// Production voice agents drive the conversation with a state machine and use
/// language models only to *interpret* utterances — never to decide flow. This
/// controller is that state machine: a small FSM that is fully offline and
/// predictable. The existing [IntentMatcher] recognises the control words
/// (add/read/delete/edit/send-one/yes/no/cancel); free-text slots (the name,
/// the number via [SpokenNumberParser], and the pick-a-contact index) bypass
/// matching.
///
/// Supported hands-free flows:
///  * add:      name → number → readback confirm → save
///  * read:     numbered list spoken aloud
///  * delete:   pick contact (skipped when only one) → yes/no → remove
///  * edit:     pick contact → new number → readback confirm → replace
///  * send-one: pick contact → [onSendToContact] (the screen runs its normal
///              cancelable countdown, so no extra confirm stage is needed)
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

  /// Set by the SOS screen: fire the (cancelable) SOS countdown targeting just
  /// this one contact. The countdown itself is the safety gate.
  void Function(EmergencyContact contact)? onSendToContact;

  ContactDialogStage _stage = ContactDialogStage.idle;
  ContactDialogStage get stage => _stage;
  bool get isActive => _stage != ContactDialogStage.idle;

  SosDialogOp _op = SosDialogOp.none;
  SosDialogOp get op => _op;

  String _pendingName = '';
  String _pendingDigits = ''; // ASCII, local form (e.g. 01712345678)
  int? _targetIndex; // contact being edited / deleted
  String get pendingName => _pendingName;
  String get pendingDigits => _pendingDigits;

  /// Name of the contact the current pick/delete/edit targets, for the UI
  /// mirror card ('' when none).
  String get targetName {
    final i = _targetIndex;
    final contacts = _settings.sosContacts;
    return (i != null && i >= 0 && i < contacts.length) ? contacts[i].name : '';
  }

  void _setStage(ContactDialogStage s) {
    _stage = s;
    notifyListeners();
  }

  /// Whether [text] is one of the dialog's cancel control words. Exposed so
  /// the SOS screen can honour a spoken "বাতিল" during the alert countdown
  /// too — the countdown is not a dialog stage, but a blind user cancelling by
  /// voice must work there most of all.
  Future<bool> isCancelPhrase(String text) async {
    await _matcher.load();
    return _actionOf(text.trim()) == 'cancel';
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
      case ContactDialogStage.pickContact:
        return _handlePickContact(t);
      case ContactDialogStage.confirmDelete:
        return _handleConfirmDelete(t);
    }
  }

  /// Reset to idle (e.g. when the screen is disposed mid-dialog).
  void reset() {
    _pendingName = '';
    _pendingDigits = '';
    _targetIndex = null;
    _op = SosDialogOp.none;
    _setStage(ContactDialogStage.idle);
  }

  // ── Stage handlers ──────────────────────────────────────────────────────

  Future<bool> _handleIdle(String t) async {
    switch (_actionOf(t)) {
      case 'add_contact':
        if (_settings.sosContacts.length >= AppConstants.sosMaxContacts) {
          await VoiceAnnouncer.speak(
            'তালিকা পূর্ণ। নতুন যোগ করতে আগে একজনকে মুছুন।',
          );
          return true;
        }
        _pendingName = '';
        _pendingDigits = '';
        _op = SosDialogOp.add;
        _setStage(ContactDialogStage.askName);
        await VoiceAnnouncer.speak('নতুন যোগাযোগের নাম বলুন।');
        return true;
      case 'read_contacts':
        await _readContacts();
        return true;
      case 'delete_contact':
        return _startPick(SosDialogOp.delete);
      case 'edit_contact':
        return _startPick(SosDialogOp.edit);
      case 'send_single':
        return _startPick(SosDialogOp.sendOne);
      default:
        return false; // not a contact command — let the global pipeline decide
    }
  }

  /// Begin a pick-a-contact flow for [op]. With exactly one saved contact the
  /// pick stage is skipped — fewer turns is better voice UX.
  Future<bool> _startPick(SosDialogOp op) async {
    final contacts = _settings.sosContacts;
    if (contacts.isEmpty) {
      await VoiceAnnouncer.speak(
        'কোনো জরুরি যোগাযোগ সংরক্ষণ করা নেই। যোগ করতে বলুন "যোগাযোগ যোগ করো"।',
      );
      return true;
    }
    _op = op;
    if (contacts.length == 1) {
      return _onContactPicked(0);
    }
    final list = _numberedList(contacts);
    final prompt = switch (op) {
      SosDialogOp.delete => 'কত নম্বর যোগাযোগ মুছবেন? সংখ্যাটি বলুন।',
      SosDialogOp.edit => 'কত নম্বর যোগাযোগ বদলাবেন? সংখ্যাটি বলুন।',
      _ => 'কত নম্বর জনকে বার্তা পাঠাবেন? সংখ্যাটি বলুন।',
    };
    _setStage(ContactDialogStage.pickContact);
    await VoiceAnnouncer.speak('$list$prompt');
    return true;
  }

  Future<bool> _handlePickContact(String t) async {
    final contacts = _settings.sosContacts;
    final index = _resolveContactIndex(t, contacts);
    if (index == null) {
      await VoiceAnnouncer.speak(
        'বুঝতে পারিনি। এক থেকে ${SpokenNumberParser.toBanglaReadback('${contacts.length}')} '
        'এর মধ্যে একটি সংখ্যা বলুন, অথবা বাতিল বলুন।',
      );
      return true;
    }
    return _onContactPicked(index);
  }

  Future<bool> _onContactPicked(int index) async {
    final contacts = _settings.sosContacts;
    final contact = contacts[index];
    _targetIndex = index;
    switch (_op) {
      case SosDialogOp.delete:
        _setStage(ContactDialogStage.confirmDelete);
        await VoiceAnnouncer.speak(
          '${contact.name} মুছে ফেলবেন? হ্যাঁ বা না বলুন।',
        );
        return true;
      case SosDialogOp.edit:
        _pendingName = contact.name;
        _setStage(ContactDialogStage.askNumber);
        await VoiceAnnouncer.speak(
          '${contact.name} এর নতুন মোবাইল নম্বর বলুন। '
          'একটি একটি করে সংখ্যা বলুন।',
        );
        return true;
      case SosDialogOp.sendOne:
        final send = onSendToContact;
        reset();
        if (send == null) {
          await VoiceAnnouncer.speak('এখন পাঠানো যাচ্ছে না।');
        } else {
          // The screen's countdown announces itself and remains cancelable.
          send(contact);
        }
        return true;
      case SosDialogOp.add:
      case SosDialogOp.none:
        reset();
        return true;
    }
  }

  Future<bool> _handleConfirmDelete(String t) async {
    switch (_actionOf(t)) {
      case 'confirm_yes':
        final index = _targetIndex;
        final contacts = _settings.sosContacts;
        final name = (index != null && index < contacts.length)
            ? contacts[index].name
            : '';
        if (index != null) await _settings.removeSosContactAt(index);
        reset();
        await VoiceAnnouncer.speak('$name মুছে ফেলা হয়েছে।');
        return true;
      case 'confirm_no':
        reset();
        await VoiceAnnouncer.speak('ঠিক আছে, মুছা হয়নি।');
        return true;
      default:
        await VoiceAnnouncer.speak('মুছতে হ্যাঁ বলুন, না মুছতে না বলুন।');
        return true;
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
      '$_pendingName এর নম্বর: $readback। '
      'সংরক্ষণ করতে হ্যাঁ বলুন, ভুল হলে না বলুন।',
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
        final editIndex = _op == SosDialogOp.edit ? _targetIndex : null;
        final bool ok;
        if (editIndex != null) {
          ok = await _settings.updateSosContactAt(editIndex, contact);
        } else {
          ok = await _settings.addSosContact(contact);
        }
        final name = _pendingName;
        final edited = editIndex != null;
        reset();
        await VoiceAnnouncer.speak(
          ok
              ? (edited
                    ? '$name এর নম্বর বদলানো হয়েছে।'
                    : '$name যোগ করা হয়েছে।')
              : 'সংরক্ষণ করা যায়নি। তালিকা পূর্ণ অথবা নম্বরটি আগে থেকেই আছে।',
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
    await VoiceAnnouncer.speak(
      '${SpokenNumberParser.toBanglaReadback('${contacts.length}')} জন জরুরি '
      'যোগাযোগ আছে। ${_numberedList(contacts, withNumbers: true)}',
    );
  }

  /// "১. আম্মু। ২. ভাইয়া। " — the spoken menu for pick flows; with
  /// [withNumbers] the phone numbers are read back too.
  String _numberedList(
    List<EmergencyContact> contacts, {
    bool withNumbers = false,
  }) {
    final buffer = StringBuffer();
    for (var i = 0; i < contacts.length; i++) {
      final c = contacts[i];
      buffer.write(
        '${SpokenNumberParser.toBanglaReadback('${i + 1}')}. ${c.name}',
      );
      if (withNumbers) {
        buffer.write(', নম্বর ${SpokenNumberParser.toBanglaReadback(c.phone)}');
      }
      buffer.write('। ');
    }
    return buffer.toString();
  }

  /// Resolve a spoken pick to a contact index: first as a number ("দুই" → 2),
  /// then as a (nukta-normalised) name match. Returns null when unresolvable.
  int? _resolveContactIndex(String t, List<EmergencyContact> contacts) {
    final digits = SpokenNumberParser.parseToAsciiDigits(t);
    if (digits.isNotEmpty) {
      final n = int.tryParse(digits);
      if (n != null && n >= 1 && n <= contacts.length) return n - 1;
    }
    final spoken = _normalizeName(t);
    if (spoken.isEmpty) return null;
    for (var i = 0; i < contacts.length; i++) {
      final name = _normalizeName(contacts[i].name);
      if (name.isNotEmpty && (spoken.contains(name) || name.contains(spoken))) {
        return i;
      }
    }
    return null;
  }

  /// Lowercase + collapse Bengali nukta letters to precomposed form so a name
  /// saved by voice (precomposed STT output) matches one typed by a helper
  /// (decomposed keyboard output). Same issue as IntentMatcher._canonicalizeNukta.
  String _normalizeName(String s) {
    return s
        .toLowerCase()
        .replaceAll('ড়', 'ড়')
        .replaceAll('ঢ়', 'ঢ়')
        .replaceAll('য়', 'য়')
        .trim();
  }

  /// Local intent action for [text], or null if none clears the matcher
  /// threshold. Used only for control words — never for slot values.
  String? _actionOf(String text) => _matcher.match(text)?.action;
}
