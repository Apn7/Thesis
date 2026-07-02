import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/voice_announcer.dart';
import '../../models/emergency_contact.dart';
import '../../services/sensor_fusion_service.dart';
import '../../services/settings_service.dart';
import '../../services/sos_dialog_controller.dart';
import '../../services/sos_service.dart';
import '../../services/spoken_number_parser.dart';
import '../../services/voice_navigation_service.dart';

/// Phase of the SOS flow. Models the whole screen as one explicit state machine
/// so a voice-only user is never stranded mid-alert.
enum _SosPhase { idle, countdown, sending, done }

/// Emergency SOS screen.
///
/// A big, TalkBack-labelled SOS button (also triggerable by voice → routed here
/// with `autoStart: true`) starts a cancelable countdown, then sends a direct
/// SMS — with the user's live GPS location as a Google Maps link — to every
/// saved emergency contact at once. Sending is **zero-tap and hands-free**: no
/// app to open, no send button to find. Contact management (list/add/delete)
/// lives on this same screen so a blind user handles everything in one place.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final SettingsService _settings = SettingsService.instance;
  final SosService _sos = SosService.instance;
  final VoiceNavigationService _voice = VoiceNavigationService.instance;
  final SosDialogController _dialog = SosDialogController();

  _SosPhase _phase = _SosPhase.idle;
  int _countdown = AppConstants.sosCountdownSeconds;
  Timer? _countdownTimer;
  String _resultMessage = '';
  bool _resultOk = false;
  bool _autoStartHandled = false;

  /// When set, the countdown/dispatch targets only this contact (voice
  /// "একজনকে পাঠাও" or the per-contact button); null = alert everyone.
  EmergencyContact? _target;

  List<EmergencyContact> get _contacts => _settings.sosContacts;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _dialog.addListener(_onSettingsChanged);
    _dialog.onSendToContact = (contact) => _startCountdown(target: contact);
    // Take over the voice pipeline while this screen is mounted: a spoken
    // "বাতিল" cancels a running countdown first (the moment voice cancel
    // matters most), then the contact dialog gets first crack; anything it
    // doesn't own falls through to the normal global command handling.
    _voice.transcriptInterceptor = _handleTranscript;
    // Own the audio channel too: the SOS countdown and the contact dialog
    // must never be interleaved with fusion's obstacle callouts (TTS
    // interrupts — a scene callout would swallow a countdown number). The
    // sonar CRITICAL alarm is independent and still gets through.
    SensorFusionService.instance.uiAudioHold = true;
    // If we arrived from a voice command, begin immediately (next frame so the
    // route arguments and the first build are ready).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoStartHandled) return;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map && args['autoStart'] == true) {
        _autoStartHandled = true;
        _startCountdown();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _settings.removeListener(_onSettingsChanged);
    _dialog.removeListener(_onSettingsChanged);
    // Only relinquish the pipeline if it's still ours (defensive against
    // overlapping screens stomping each other's handler).
    if (_voice.transcriptInterceptor == _handleTranscript) {
      _voice.transcriptInterceptor = null;
    }
    SensorFusionService.instance.uiAudioHold = false;
    _dialog.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  /// Screen-scoped transcript handler. A spoken cancel word during the
  /// countdown aborts the alert (voice must work where hands can't find the
  /// screen); everything else goes to the contact dialog, then falls through
  /// to the global pipeline.
  Future<bool> _handleTranscript(String text) async {
    if (_phase == _SosPhase.countdown && await _dialog.isCancelPhrase(text)) {
      _cancel();
      return true;
    }
    return _dialog.handleTranscript(text);
  }

  // ── SOS flow ────────────────────────────────────────────────────────────

  void _startCountdown({EmergencyContact? target}) {
    if (_contacts.isEmpty) {
      VoiceAnnouncer.announce(
        'কোনো জরুরি যোগাযোগ সংরক্ষণ করা নেই। প্রথমে একজন যোগ করুন।',
      );
      return;
    }
    _countdownTimer?.cancel();
    setState(() {
      _phase = _SosPhase.countdown;
      _countdown = AppConstants.sosCountdownSeconds;
      _target = target;
    });
    _runCountdown(target);
  }

  /// Speak a short intro, *then* start ticking — a periodic timer started
  /// alongside the intro would cut it off after one second, so the user never
  /// heard how to cancel. Ticks are spoken as Bengali words (the bn-BD voice
  /// reads bare ASCII digits unpredictably).
  Future<void> _runCountdown(EmergencyContact? target) async {
    await VoiceAnnouncer.announce(
      target == null
          ? 'জরুরি বার্তা যাচ্ছে। বাতিল করতে স্ক্রিনে চাপুন বা বাতিল বলুন।'
          : '${target.name} কে জরুরি বার্তা যাচ্ছে। '
                'বাতিল করতে স্ক্রিনে চাপুন বা বাতিল বলুন।',
    );
    if (!mounted || _phase != _SosPhase.countdown) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _countdown--);
      if (_countdown <= 0) {
        timer.cancel();
        _dispatch();
      } else if (!_voice.isListening && !_voice.isProcessing) {
        // Stay quiet while the user is speaking a command (e.g. "বাতিল") —
        // a spoken tick would feed the open microphone and garble the
        // transcript. The countdown itself keeps running either way.
        VoiceAnnouncer.speak(
          SpokenNumberParser.toBanglaReadback('$_countdown'),
        );
      }
    });
  }

  void _cancel() {
    _countdownTimer?.cancel();
    setState(() {
      _phase = _SosPhase.idle;
      _countdown = AppConstants.sosCountdownSeconds;
      _target = null;
    });
    VoiceAnnouncer.announce('জরুরি বার্তা বাতিল করা হয়েছে।');
  }

  Future<void> _dispatch() async {
    final target = _target;
    final recipients = target != null ? [target] : _contacts;
    setState(() => _phase = _SosPhase.sending);
    await VoiceAnnouncer.announce('অবস্থান নিয়ে বার্তা পাঠানো হচ্ছে।');

    final result = await _sos.sendSos(recipients);
    if (!mounted) return;

    final ok = result == SosResult.sent;
    final message = switch (result) {
      SosResult.sent =>
        target != null
            ? '${target.name} কে বার্তা পাঠানো হয়েছে।'
            : '${recipients.length} জন জরুরি যোগাযোগে বার্তা পাঠানো হয়েছে।',
      SosResult.permissionDenied =>
        'এসএমএস পাঠানোর অনুমতি দেওয়া হয়নি। সেটিংসে অনুমতি দিন।',
      SosResult.noContacts => 'কোনো জরুরি যোগাযোগ নেই।',
      SosResult.unsupported => 'এই ডিভাইসে এসএমএস সমর্থিত নয়।',
      SosResult.failed => 'বার্তা পাঠানো যায়নি। সিম ও নেটওয়ার্ক দেখুন।',
    };

    setState(() {
      _phase = _SosPhase.done;
      _resultOk = ok;
      _resultMessage = message;
    });
    await VoiceAnnouncer.announce(message);
  }

  void _reset() {
    setState(() {
      _phase = _SosPhase.idle;
      _resultMessage = '';
      _resultOk = false;
      _target = null;
    });
  }

  // ── Contact management ────────────────────────────────────────────────────

  Future<void> _showAddContactDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('জরুরি যোগাযোগ যোগ করুন'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'নাম',
                hintText: 'যেমন: আম্মু',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            SizedBox(height: AppConstants.spacingM),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'মোবাইল নম্বর',
                hintText: '01XXXXXXXXX',
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('সংরক্ষণ'),
          ),
        ],
      ),
    );

    if (added != true || !mounted) return;

    final contact = EmergencyContact.fromInput(
      name: nameController.text.isEmpty ? 'যোগাযোগ' : nameController.text,
      rawPhone: phoneController.text,
    );
    if (!contact.isValid) {
      VoiceAnnouncer.announce('নম্বরটি সঠিক নয়। আবার চেষ্টা করুন।');
      return;
    }
    final ok = await _settings.addSosContact(contact);
    if (!mounted) return;
    VoiceAnnouncer.announce(
      ok
          ? '${contact.name} যোগ করা হয়েছে।'
          : 'যোগ করা যায়নি। তালিকা পূর্ণ বা নম্বরটি আগে থেকেই আছে।',
    );
  }

  Future<void> _removeContact(int index) async {
    final name = _contacts[index].name;
    await _settings.removeSosContactAt(index);
    if (!mounted) return;
    VoiceAnnouncer.announce('$name মুছে ফেলা হয়েছে।');
  }

  Future<void> _showEditContactDialog(int index) async {
    final existing = _contacts[index];
    final nameController = TextEditingController(text: existing.name);
    final phoneController = TextEditingController(text: '+${existing.phone}');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('যোগাযোগ সম্পাদনা করুন'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'নাম'),
              textCapitalization: TextCapitalization.words,
            ),
            SizedBox(height: AppConstants.spacingM),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'মোবাইল নম্বর'),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('সংরক্ষণ'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    final contact = EmergencyContact.fromInput(
      name: nameController.text.isEmpty ? existing.name : nameController.text,
      rawPhone: phoneController.text,
    );
    if (!contact.isValid) {
      VoiceAnnouncer.announce('নম্বরটি সঠিক নয়। আবার চেষ্টা করুন।');
      return;
    }
    final ok = await _settings.updateSosContactAt(index, contact);
    if (!mounted) return;
    VoiceAnnouncer.announce(
      ok
          ? '${contact.name} এর তথ্য বদলানো হয়েছে।'
          : 'বদলানো যায়নি। নম্বরটি অন্য যোগাযোগে আগে থেকেই আছে।',
    );
  }

  /// Accessible action sheet for one contact: send SOS to just them, edit,
  /// or delete — big touch targets, fully TalkBack-labelled.
  Future<void> _showContactActions(int index) async {
    final contact = _contacts[index];
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(AppConstants.spacingM),
              child: Semantics(
                header: true,
                child: Text(
                  '${contact.name} — +${contact.phone}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            ListTile(
              minTileHeight: AppConstants.minTouchTargetSize,
              leading: const Icon(Icons.sos, color: AppColors.error),
              title: const Text('শুধু এই জনকে জরুরি বার্তা পাঠান'),
              onTap: () {
                Navigator.pop(sheetContext);
                _startCountdown(target: contact);
              },
            ),
            ListTile(
              minTileHeight: AppConstants.minTouchTargetSize,
              leading: const Icon(Icons.edit),
              title: const Text('সম্পাদনা করুন'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showEditContactDialog(index);
              },
            ),
            ListTile(
              minTileHeight: AppConstants.minTouchTargetSize,
              leading: const Icon(Icons.delete_outline),
              title: const Text('মুছে ফেলুন'),
              onTap: () {
                Navigator.pop(sheetContext);
                _removeContact(index);
              },
            ),
            SizedBox(height: AppConstants.spacingS),
          ],
        ),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          label: 'জরুরি সাহায্য',
          child: const Text('জরুরি সাহায্য'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(AppConstants.spacingL),
          children: [
            _buildActionArea(),
            if (_dialog.isActive) ...[
              SizedBox(height: AppConstants.spacingL),
              _buildDialogStatus(),
            ],
            SizedBox(height: AppConstants.spacingXl),
            _buildContactsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionArea() {
    switch (_phase) {
      case _SosPhase.idle:
        return _buildSosButton();
      case _SosPhase.countdown:
        return _buildCountdown();
      case _SosPhase.sending:
        return _buildSending();
      case _SosPhase.done:
        return _buildDone();
    }
  }

  Widget _buildSosButton() {
    final hasContacts = _contacts.isNotEmpty;
    return Semantics(
      button: true,
      label: 'জরুরি সাহায্য পাঠান',
      hint: hasContacts
          ? 'চাপলে $_countdown সেকেন্ড পরে জরুরি যোগাযোগে অবস্থানসহ বার্তা যাবে।'
          : 'প্রথমে নিচে একজন জরুরি যোগাযোগ যোগ করুন।',
      enabled: hasContacts,
      child: GestureDetector(
        onTap: hasContacts ? _startCountdown : _showAddContactDialog,
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            color: hasContacts ? AppColors.error : AppColors.textSecondary,
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            boxShadow: [
              BoxShadow(
                color: (hasContacts ? AppColors.error : AppColors.textSecondary)
                    .withValues(alpha: 0.4),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.sos, size: 96, color: Colors.white),
              SizedBox(height: AppConstants.spacingM),
              const Text(
                'এসওএস',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdown() {
    return Semantics(
      button: true,
      label: 'বাতিল করুন',
      hint: '$_countdown সেকেন্ড পরে বার্তা পাঠানো হবে। চাপলে বাতিল হবে।',
      child: GestureDetector(
        onTap: _cancel,
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            color: AppColors.warning,
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$_countdown',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 88,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: AppConstants.spacingS),
              const Text(
                'বাতিল করতে চাপুন',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSending() {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: AppColors.info,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 20),
            Text(
              'বার্তা পাঠানো হচ্ছে...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDone() {
    final color = _resultOk ? AppColors.success : AppColors.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.all(AppConstants.spacingL),
          constraints: const BoxConstraints(minHeight: 180),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _resultOk ? Icons.check_circle : Icons.error,
                  size: 64,
                  color: Colors.white,
                ),
                SizedBox(height: AppConstants.spacingM),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _resultMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: AppConstants.spacingL),
        if (!_resultOk) ...[
          Semantics(
            button: true,
            label: 'আবার চেষ্টা করুন',
            child: FilledButton.icon(
              onPressed: () => _startCountdown(target: _target),
              icon: const Icon(Icons.refresh),
              label: const Text('আবার চেষ্টা করুন'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                padding: EdgeInsets.symmetric(vertical: AppConstants.spacingL),
              ),
            ),
          ),
          SizedBox(height: AppConstants.spacingM),
        ],
        // Always offer a way back to idle — a failure screen with only a
        // retry button would strand the user if the send keeps failing.
        Semantics(
          button: true,
          label: 'ঠিক আছে',
          child: OutlinedButton(
            onPressed: _reset,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: AppConstants.spacingL),
            ),
            child: const Text('ঠিক আছে'),
          ),
        ),
      ],
    );
  }

  /// Visual mirror of the in-progress voice dialog (the prompts are spoken;
  /// this card helps a sighted helper follow along, and is a live region so
  /// TalkBack re-announces stage changes).
  Widget _buildDialogStatus() {
    final (label, detail) = switch (_dialog.stage) {
      ContactDialogStage.askName => ('নাম বলুন', _dialog.pendingName),
      ContactDialogStage.askNumber => (
        'নম্বর বলুন',
        _dialog.pendingName.isEmpty ? '' : 'নাম: ${_dialog.pendingName}',
      ),
      ContactDialogStage.confirm => (
        'সংরক্ষণ করবেন? "হ্যাঁ" বা "না" বলুন',
        '${_dialog.pendingName} — +${_dialog.pendingDigits}',
      ),
      ContactDialogStage.pickContact => ('কত নম্বর যোগাযোগ? সংখ্যা বলুন', ''),
      ContactDialogStage.confirmDelete => (
        'মুছে ফেলবেন? "হ্যাঁ" বা "না" বলুন',
        _dialog.targetName,
      ),
      ContactDialogStage.idle => ('', ''),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(AppConstants.spacingL),
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppConstants.radiusL),
          border: Border.all(color: AppColors.info, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mic, color: AppColors.info),
                SizedBox(width: AppConstants.spacingS),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.info,
                    ),
                  ),
                ),
              ],
            ),
            if (detail.isNotEmpty) ...[
              SizedBox(height: AppConstants.spacingS),
              Text(detail, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContactsSection() {
    final atCapacity = _contacts.length >= AppConstants.sosMaxContacts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'জরুরি যোগাযোগ',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(height: AppConstants.spacingXs),
        Text(
          'ভয়েসে বলতে পারেন: "যোগাযোগ যোগ করো", "যোগাযোগ পড়ো", '
          '"যোগাযোগ মুছো", "নম্বর বদলাও" অথবা "একজনকে পাঠাও"।',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        SizedBox(height: AppConstants.spacingS),
        if (_contacts.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: AppConstants.spacingM),
            child: Text(
              'এখনো কোনো যোগাযোগ নেই। বিপদে যাকে বার্তা পাঠাতে চান তাকে যোগ করুন।',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          )
        else
          ..._contacts.asMap().entries.map((entry) {
            final i = entry.key;
            final c = entry.value;
            return Card(
              child: Semantics(
                button: true,
                label: 'যোগাযোগ ${i + 1}: ${c.name}',
                hint: 'চাপলে পাঠানো, সম্পাদনা ও মুছার অপশন খুলবে।',
                child: ListTile(
                  minTileHeight: AppConstants.minTouchTargetSize,
                  onTap: () => _showContactActions(i),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.error,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(c.name),
                  subtitle: Text('+${c.phone}'),
                  trailing: const Icon(Icons.more_vert),
                ),
              ),
            );
          }),
        SizedBox(height: AppConstants.spacingM),
        Semantics(
          button: true,
          label: 'জরুরি যোগাযোগ যোগ করুন',
          enabled: !atCapacity,
          child: OutlinedButton.icon(
            onPressed: atCapacity ? null : _showAddContactDialog,
            icon: const Icon(Icons.person_add),
            label: Text(atCapacity ? 'তালিকা পূর্ণ' : 'যোগাযোগ যোগ করুন'),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: AppConstants.spacingM),
            ),
          ),
        ),
      ],
    );
  }
}
