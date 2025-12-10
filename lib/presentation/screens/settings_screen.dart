import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';

/// Settings screen for app configuration
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedLanguage = 'both'; // 'bangla', 'english', 'both'
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
          label: 'সেটিংস। Settings',
          child: const Column(
            children: [
              Text('সেটিংস'),
              Text(
                'Settings',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(AppConstants.spacingL),
          children: [
            // Language Section
            _buildSectionHeader(context, 'ভাষা / Language'),
            
            Card(
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: const Text('শুধু বাংলা / Bangla Only'),
                    value: 'bangla',
                    groupValue: _selectedLanguage,
                    onChanged: (value) {
                      setState(() {
                        _selectedLanguage = value!;
                      });
                    },
                    secondary: const Icon(Icons.language),
                  ),
                  const Divider(height: 1),
                  RadioListTile<String>(
                    title: const Text('শুধু ইংরেজি / English Only'),
                    value: 'english',
                    groupValue: _selectedLanguage,
                    onChanged: (value) {
                      setState(() {
                        _selectedLanguage = value!;
                      });
                    },
                    secondary: const Icon(Icons.translate),
                  ),
                  const Divider(height: 1),
                  RadioListTile<String>(
                    title: const Text('উভয় / Both'),
                    subtitle: const Text('প্রস্তাবিত / Recommended'),
                    value: 'both',
                    groupValue: _selectedLanguage,
                    onChanged: (value) {
                      setState(() {
                        _selectedLanguage = value!;
                      });
                    },
                    secondary: const Icon(Icons.g_translate),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: AppConstants.spacingXl),
            
            // Voice Settings
            _buildSectionHeader(context, 'ভয়েস সেটিংস / Voice Settings'),
            
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
                                  const Text('কথা বলার গতি / Speech Rate'),
                                  Text(
                                    '${(_speechRate * 100).round()}%',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                    subtitle: const Text('Voice Confirmation'),
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
            
            // Accessibility Settings
            _buildSectionHeader(context, 'অ্যাক্সেসিবিলিটি / Accessibility'),
            
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.vibration),
                    title: const Text('ভাইব্রেশন ফিডব্যাক'),
                    subtitle: const Text('Vibration Feedback'),
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
                    subtitle: const Text('Battery Saver Mode'),
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
            
            // About Section
            _buildSectionHeader(context, 'সম্পর্কে / About'),
            
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('অ্যাপ সংস্করণ / App Version'),
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
                    title: const Text('থিসিস প্রজেক্ট'),
                    subtitle: const Text('Thesis Project'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      _showAboutDialog(context);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('সাহায্য ও সহায়তা'),
                    subtitle: const Text('Help & Support'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pushNamed(context, '/help');
                    },
                  ),
                ],
              ),
            ),
            
            SizedBox(height: AppConstants.spacingXxl),
            
            // Reset Button
            OutlinedButton.icon(
              onPressed: () {
                _showResetDialog(context);
              },
              icon: const Icon(Icons.refresh, color: AppColors.warning),
              label: const Text(
                'ডিফল্ট রিসেট করুন / Reset to Default',
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
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
  
  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('সম্পর্কে / About'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'স্বয়ংক্রিয় স্মার্ট ক্যান',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              SizedBox(height: 4),
              Text(
                'Autonomous Smart Cane',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text(
                'একটি IoT-সক্ষম, ভিশন এবং ভয়েস-সহায়তা নেভিগেশন সহায়ক যন্ত্র দৃষ্টিহীনদের জন্য।',
              ),
              SizedBox(height: 8),
              Text(
                'An IoT-enabled, vision and voice-assisted navigation aid for the visually impaired.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ঠিক আছে / OK'),
          ),
        ],
      ),
    );
  }
  
  void _showResetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('রিসেট নিশ্চিত করুন / Confirm Reset'),
        content: const Text(
          'সব সেটিংস ডিফল্ট মানগুলিতে পুনরায় সেট করবেন?\n\nReset all settings to default values?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('বাতিল / Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _selectedLanguage = 'both';
                _speechRate = 1.0;
                _vibrationEnabled = true;
                _voiceConfirmationEnabled = true;
                _batterySaverMode = false;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('সেটিংস রিসেট হয়েছে / Settings reset'),
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('রিসেট / Reset'),
          ),
        ],
      ),
    );
  }
}
