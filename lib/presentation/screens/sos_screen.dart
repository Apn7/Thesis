import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/voice_announcer.dart';
import '../../models/emergency_contact.dart';
import '../../services/settings_service.dart';
import '../../services/sos_service.dart';

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

  _SosPhase _phase = _SosPhase.idle;
  int _countdown = AppConstants.sosCountdownSeconds;
  Timer? _countdownTimer;
  String _resultMessage = '';
  bool _resultOk = false;
  bool _autoStartHandled = false;

  List<EmergencyContact> get _contacts => _settings.sosContacts;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
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
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  // ── SOS flow ────────────────────────────────────────────────────────────

  void _startCountdown() {
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
    });
    VoiceAnnouncer.announce(
      '$_countdown সেকেন্ডের মধ্যে জরুরি বার্তা পাঠানো হবে। '
      'বাতিল করতে স্ক্রিনে চাপুন।',
    );
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _countdown--);
      if (_countdown <= 0) {
        timer.cancel();
        _dispatch();
      } else {
        VoiceAnnouncer.speak('$_countdown');
      }
    });
  }

  void _cancel() {
    _countdownTimer?.cancel();
    setState(() {
      _phase = _SosPhase.idle;
      _countdown = AppConstants.sosCountdownSeconds;
    });
    VoiceAnnouncer.announce('জরুরি বার্তা বাতিল করা হয়েছে।');
  }

  Future<void> _dispatch() async {
    setState(() => _phase = _SosPhase.sending);
    await VoiceAnnouncer.announce('অবস্থান নিয়ে বার্তা পাঠানো হচ্ছে।');

    final result = await _sos.sendSos(_contacts);
    if (!mounted) return;

    final ok = result == SosResult.sent;
    final message = switch (result) {
      SosResult.sent =>
        '${_contacts.length} জন জরুরি যোগাযোগে বার্তা পাঠানো হয়েছে।',
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
        if (!_resultOk)
          Semantics(
            button: true,
            label: 'আবার চেষ্টা করুন',
            child: FilledButton.icon(
              onPressed: _startCountdown,
              icon: const Icon(Icons.refresh),
              label: const Text('আবার চেষ্টা করুন'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                padding: EdgeInsets.symmetric(vertical: AppConstants.spacingL),
              ),
            ),
          )
        else
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
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.error,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(c.name),
                subtitle: Text('+${c.phone}'),
                trailing: Semantics(
                  button: true,
                  label: '${c.name} মুছুন',
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'মুছুন',
                    onPressed: () => _removeContact(i),
                  ),
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
