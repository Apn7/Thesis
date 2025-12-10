import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/accessibility_helper.dart';
import '../../core/navigation/app_routes.dart';
import '../widgets/accessible_action_button.dart';
import '../widgets/voice_indicator.dart';

/// Home screen with voice-first navigation
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isListening = false;
  
  @override
  void initState() {
    super.initState();
    // Announce screen when loaded (will be connected to TTS later)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _announceScreen();
    });
  }
  
  void _announceScreen() {
    // Placeholder for TTS announcement
    // Will say: "শুরুর পাতা। বলুন কোথায় যেতে চান। Home screen. Say where you want to go."
    debugPrint('Screen announcement: ${AccessibilityLabels.homeScreen}');
  }
  
  void _navigateToLocation() {
    Navigator.pushNamed(context, AppRoutes.location);
  }
  
  void _navigateToSettings() {
    Navigator.pushNamed(context, AppRoutes.settings);
  }
  
  void _navigateToHelp() {
    Navigator.pushNamed(context, AppRoutes.help);
  }
  
  void _toggleVoiceListening() {
    setState(() {
      _isListening = !_isListening;
    });
    // Placeholder for voice recognition toggle
    debugPrint(_isListening ? 'Started listening...' : 'Stopped listening');
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Semantics(
          header: true,
          label: '${AppConstants.appName}। ${AppConstants.appNameEn}',
          child: Column(
            children: [
              Text(AppConstants.appName),
              Text(
                AppConstants.appNameEn,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppConstants.spacingL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Voice Indicator Header
              Card(
                elevation: 4,
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: EdgeInsets.all(AppConstants.spacingXl),
                  child: Column(
                    children: [
                      VoiceIndicator(
                        isListening: _isListening,
                        size: 120,
                      ),
                      SizedBox(height: AppConstants.spacingL),
                      Text(
                        _isListening ? 'শুনছি...' : 'ভয়েস কমান্ড',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _isListening ? AppColors.accent : AppColors.primary,
                        ),
                      ),
                      SizedBox(height: AppConstants.spacingXs),
                      Text(
                        _isListening ? 'Listening...' : 'Voice Command',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: AppConstants.spacingL),
                      FilledButton.icon(
                        onPressed: _toggleVoiceListening,
                        icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
                        label: Text(_isListening ? 'থামান (Stop)' : 'শুরু করুন (Start)'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _isListening ? AppColors.error : AppColors.accent,
                          padding: EdgeInsets.symmetric(
                            horizontal: AppConstants.spacingXl,
                            vertical: AppConstants.spacingL,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: AppConstants.spacingXl),
              
              // Navigation Header
              Semantics(
                header: true,
                label: 'নেভিগেশন অপশন। Navigation options.',
                child: Text(
                  'কোথায় যেতে চান? / Where to go?',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              SizedBox(height: AppConstants.spacingL),
              
              // Main Navigation Grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppConstants.spacingL,
                crossAxisSpacing: AppConstants.spacingL,
                childAspectRatio: 0.9,
                children: [
                  AccessibleActionButton(
                    icon: Icons.location_on,
                    label: 'আমি কোথায়?',
                    labelEn: 'Where am I?',
                    semanticHint: 'আপনার বর্তমান অবস্থান দেখুন। View your current location.',
                    onPressed: _navigateToLocation,
                    color: AppColors.info,
                  ),
                  AccessibleActionButton(
                    icon: Icons.settings,
                    label: 'সেটিংস',
                    labelEn: 'Settings',
                    semanticHint: 'সেটিংস খুলুন। Open settings.',
                    onPressed: _navigateToSettings,
                    color: AppColors.primary,
                  ),
                  AccessibleActionButton(
                    icon: Icons.help_outline,
                    label: 'সাহায্য',
                    labelEn: 'Help',
                    semanticHint: 'সাহায্য এবং টিউটোরিয়াল। Help and tutorial.',
                    onPressed: _navigateToHelp,
                    color: AppColors.success,
                  ),
                  AccessibleActionButton(
                    icon: Icons.battery_charging_full,
                    label: 'ব্যাটারি',
                    labelEn: 'Battery',
                    semanticHint: 'ব্যাটারি স্ট্যাটাস দেখুন। Check battery status.',
                    onPressed: () {
                      // Placeholder for battery status
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('ব্যাটারি: ৮৫% / Battery: 85%'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    color: AppColors.warning,
                  ),
                ],
              ),
              
              SizedBox(height: AppConstants.spacingXl),
              
              // Quick Info Section
              Card(
                child: Padding(
                  padding: EdgeInsets.all(AppConstants.spacingL),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppColors.info,
                            size: AppConstants.iconL,
                          ),
                          SizedBox(width: AppConstants.spacingM),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'দ্রুত তথ্য',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Quick Info',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: AppConstants.spacingL),
                      Divider(color: AppColors.divider),
                      SizedBox(height: AppConstants.spacingM),
                      _buildInfoRow(
                        context,
                        icon: Icons.access_time,
                        label: 'সর্বশেষ আপডেট / Last Update',
                        value: 'এখনই / Just now',
                      ),
                      SizedBox(height: AppConstants.spacingM),
                      _buildInfoRow(
                        context,
                        icon: Icons.wifi,
                        label: 'সংযোগ / Connection',
                        value: 'অফলাইন মোড / Offline Mode',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Semantics(
      label: '$label: $value',
      child: Row(
        children: [
          Icon(
            icon,
            size: AppConstants.iconM,
            color: AppColors.textSecondary,
          ),
          SizedBox(width: AppConstants.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(height: AppConstants.spacingXs),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
