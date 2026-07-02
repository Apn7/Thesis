import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/voice_announcer.dart';
import '../../services/settings_service.dart';
import '../../services/tts_service.dart';

/// Settings screen — every control here is real: it persists via
/// [SettingsService] and takes effect immediately. No placeholder toggles; a
/// blind user cannot see that a switch "does nothing", so a dead control is
/// worse than no control.
///
/// Voice equivalents exist for the key settings ("ধীরে বলো" / "দ্রুত বলো"
/// adjust the same speech rate), so the screen is a touch fallback, not the
/// only path.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService.instance;

  @override
  void initState() {
    super.initState();
    // Rebuild when a voice command ("দ্রুত বলো") changes a setting while this
    // screen is open — the slider must track the real stored value.
    _settings.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VoiceAnnouncer.announce(
        'সেটিংস পেইজ। কথার গতি আর কম্পন এখানে বদলানো যায়।',
      );
    });
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  /// Apply the new rate to the engine, persist it, and speak a sample at the
  /// new pace so the user hears exactly what they chose.
  Future<void> _applySpeechRate(double multiplier) async {
    await _settings.setSpeechRateMultiplier(multiplier);
    try {
      await TtsService.instance.setSpeechRate(_settings.ttsSpeechRate);
    } catch (e) {
      debugPrint('SettingsScreen: setSpeechRate failed: $e');
    }
    VoiceAnnouncer.announce('কথার গতি এখন এরকম শোনাবে।');
  }

  @override
  Widget build(BuildContext context) {
    final ratePercent = (_settings.speechRateMultiplier * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          label: 'সেটিংস',
          child: const Text('সেটিংস'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(AppConstants.spacingL),
          children: [
            // ── Voice Settings ────────────────────────────────────────
            _buildSectionHeader(context, 'ভয়েস সেটিংস'),

            Card(
              child: Padding(
                padding: EdgeInsets.all(AppConstants.spacingL),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.speed),
                        SizedBox(width: AppConstants.spacingM),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('কথা বলার গতি'),
                              Text(
                                '$ratePercent%',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Semantics(
                      slider: true,
                      label: 'কথা বলার গতি, এখন $ratePercent শতাংশ',
                      child: Slider(
                        value: _settings.speechRateMultiplier,
                        min: SettingsService.speechRateMin,
                        max: SettingsService.speechRateMax,
                        divisions:
                            ((SettingsService.speechRateMax -
                                        SettingsService.speechRateMin) /
                                    SettingsService.speechRateStep)
                                .round(),
                        label: '$ratePercent%',
                        // Live drag just moves the thumb; commit (persist +
                        // engine + spoken sample) happens on release so we
                        // don't spam TTS on every tick.
                        onChanged: (value) {
                          setState(() {});
                          _settings.setSpeechRateMultiplier(value);
                        },
                        onChangeEnd: _applySpeechRate,
                      ),
                    ),
                    Text(
                      'ভয়েস কমান্ডেও বদলানো যায়: "ধীরে বলো" বা "দ্রুত বলো"',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppConstants.spacingXl),

            // ── Accessibility Settings ────────────────────────────────
            _buildSectionHeader(context, 'অ্যাক্সেসিবিলিটি'),

            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.vibration),
                title: const Text('ভাইব্রেশন ফিডব্যাক'),
                subtitle: Text(
                  'বাধার সতর্কতায় ফোন কাঁপবে',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                value: _settings.vibrationEnabled,
                onChanged: (value) async {
                  await _settings.setVibrationEnabled(value);
                  VoiceAnnouncer.announce(
                    value ? 'ভাইব্রেশন চালু হয়েছে।' : 'ভাইব্রেশন বন্ধ হয়েছে।',
                  );
                },
              ),
            ),

            SizedBox(height: AppConstants.spacingXl),

            // ── Safety / Emergency Section ────────────────────────────
            if (AppConstants.enableSos) ...[
              _buildSectionHeader(context, 'নিরাপত্তা'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.sos, color: AppColors.error),
                  title: const Text('জরুরি যোগাযোগ'),
                  subtitle: Text(
                    'বিপদে যাদের অবস্থানসহ বার্তা পাঠানো হবে',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Navigator.pushNamed(context, AppRoutes.sos),
                ),
              ),
              SizedBox(height: AppConstants.spacingXl),
            ],

            // ── About Section ─────────────────────────────────────────
            _buildSectionHeader(context, 'সম্পর্কে'),

            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('অ্যাপ ভার্সন'),
                    trailing: Text(
                      AppConstants.appVersion,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.school),
                    title: const Text('থিসিস প্রকল্প'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      _showAboutDialog(context);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('সাহায্য ও সহায়তা'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pushNamed(context, AppRoutes.help);
                    },
                  ),
                ],
              ),
            ),

            SizedBox(height: AppConstants.spacingXxl),

            // ── Reset Button ──────────────────────────────────────────
            OutlinedButton.icon(
              onPressed: () {
                _showResetDialog(context);
              },
              icon: const Icon(Icons.refresh, color: AppColors.warning),
              label: const Text(
                'ডিফল্টে রিসেট করুন',
                style: TextStyle(color: AppColors.warning),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.warning),
                padding: EdgeInsets.symmetric(vertical: AppConstants.spacingL),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Semantics(
      header: true,
      label: title,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppConstants.spacingS,
          bottom: AppConstants.spacingM,
        ),
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('সম্পর্কে'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'স্বয়ংক্রিয় স্মার্ট ক্যান',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              SizedBox(height: 16),
              Text(
                'দৃষ্টিপ্রতিবন্ধীদের জন্য একটি আইওটি-নির্ভর, ভিশন ও ভয়েস-সহায়ক চলাচল সহায়িকা।',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ঠিক আছে'),
          ),
        ],
      ),
    );
  }

  void _showResetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('রিসেট নিশ্চিত করুন'),
        content: const Text('সব সেটিংস ডিফল্ট মানে রিসেট করবেন?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _settings.resetToDefaults();
              try {
                await TtsService.instance.setSpeechRate(
                  _settings.ttsSpeechRate,
                );
              } catch (e) {
                debugPrint('SettingsScreen: reset setSpeechRate failed: $e');
              }
              VoiceAnnouncer.announce('সব সেটিংস ডিফল্টে ফিরেছে।');
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('রিসেট'),
          ),
        ],
      ),
    );
  }
}
