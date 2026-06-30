import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../services/settings_service.dart';

/// Settings screen for app configuration
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _speechRate = 1.0;
  bool _vibrationEnabled = true;
  bool _voiceConfirmationEnabled = true;
  bool _batterySaverMode = false;

  @override
  Widget build(BuildContext context) {
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
              child: Column(
                children: [
                  Padding(
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
                                    '${(_speechRate * 100).round()}%',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _speechRate,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          label: '${(_speechRate * 100).round()}%',
                          onChanged: (value) {
                            setState(() {
                              _speechRate = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.check_circle_outline),
                    title: const Text('ভয়েস নিশ্চিতকরণ'),
                    value: _voiceConfirmationEnabled,
                    onChanged: (value) {
                      setState(() {
                        _voiceConfirmationEnabled = value;
                      });
                    },
                  ),
                ],
              ),
            ),

            SizedBox(height: AppConstants.spacingXl),

            // ── Accessibility Settings ────────────────────────────────
            _buildSectionHeader(context, 'অ্যাক্সেসিবিলিটি'),

            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.vibration),
                    title: const Text('ভাইব্রেশন ফিডব্যাক'),
                    value: _vibrationEnabled,
                    onChanged: (value) {
                      setState(() {
                        _vibrationEnabled = value;
                      });
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.battery_saver),
                    title: const Text('ব্যাটারি সেভার মোড'),
                    value: _batterySaverMode,
                    onChanged: (value) {
                      setState(() {
                        _batterySaverMode = value;
                      });
                    },
                  ),
                ],
              ),
            ),

            SizedBox(height: AppConstants.spacingXl),

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
                      Navigator.pushNamed(context, '/help');
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
      builder: (context) => AlertDialog(
        title: const Text('রিসেট নিশ্চিত করুন'),
        content: const Text('সব সেটিংস ডিফল্ট মানে রিসেট করবেন?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _speechRate = 1.0;
                _vibrationEnabled = true;
                _voiceConfirmationEnabled = true;
                _batterySaverMode = false;
              });
              SettingsService.instance.setLanguageMode('bn');
              Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('সেটিংস রিসেট হয়েছে')),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('রিসেট'),
          ),
        ],
      ),
    );
  }
}
