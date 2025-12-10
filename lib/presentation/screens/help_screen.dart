import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';

/// Help screen with tutorials and command list
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          label: 'সাহায্য। Help',
          child: const Column(
            children: [
              Text('সাহায্য'),
              Text(
                'Help',
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
            // Welcome Card
            Card(
              elevation: 4,
              color: AppColors.primaryLight.withOpacity(0.2),
              child: Padding(
                padding: EdgeInsets.all(AppConstants.spacingXl),
                child: Column(
                  children: [
                    Icon(
                      Icons.waving_hand,
                      size: AppConstants.iconXxl,
                      color: AppColors.primary,
                    ),
                    SizedBox(height: AppConstants.spacingL),
                    Text(
                      'স্বাগতম!',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(height: AppConstants.spacingXs),
                    Text(
                      'Welcome!',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: AppConstants.spacingM),
                    const Text(
                      'এই অ্যাপ্লিকেশনটি ভয়েস কমান্ড ব্যবহার করে নেভিগেট করার জন্য ডিজাইন করা হয়েছে।',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: AppConstants.spacingXs),
                    const Text(
                      'This app is designed to navigate using voice commands.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: AppConstants.spacingXl),
            
            // Quick Start Guide
            _buildSectionHeader(context, 'দ্রুত শুরু / Quick Start'),
            
            _buildStepCard(
              context,
              step: '১',
              stepEn: '1',
              title: 'হোম স্ক্রিনে যান',
              titleEn: 'Go to Home Screen',
              description: 'অ্যাপটি খুলুন এবং "শুরু করুন" বোতামে ট্যাপ করুন।',
              descriptionEn: 'Open the app and tap the "Start" button.',
              icon: Icons.home,
              color: AppColors.primary,
            ),
            
            _buildStepCard(
              context,
              step: '২',
              stepEn: '2',
              title: 'ভয়েস কমান্ড বলুন',
              titleEn: 'Speak Voice Command',
              description: 'মাইক্রোফোন সক্রিয় করুন এবং আপনার কমান্ড বলুন।',
              descriptionEn: 'Activate the microphone and speak your command.',
              icon: Icons.mic,
              color: AppColors.accent,
            ),
            
            _buildStepCard(
              context,
              step: '৩',
              stepEn: '3',
              title: 'অডিও ফিডব্যাক শুনুন',
              titleEn: 'Hear Audio Feedback',
              description: 'অ্যাপ্লিকেশন আপনাকে অডিও মাধ্যমে গাইড করবে।',
              descriptionEn: 'The app will guide you through audio.',
              icon: Icons.volume_up,
              color: AppColors.info,
            ),
            
            SizedBox(height: AppConstants.spacingXl),
            
            // Voice Commands List
            _buildSectionHeader(context, 'ভয়েস কমান্ড / Voice Commands'),
            
            Card(
              child: Column(
                children: [
                  _buildCommandTile(
                    'আমি কোথায়?',
                    'Where am I?',
                    'আপনার বর্তমান অবস্থান দেখায়',
                    'Shows your current location',
                    Icons.location_on,
                    AppColors.info,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'সেটিংস',
                    'Settings',
                    'সেটিংস মেনু খোলে',
                    'Opens settings menu',
                    Icons.settings,
                    AppColors.primary,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'সাহায্য',
                    'Help',
                    'এই সাহায্য পৃষ্ঠা দেখায়',
                    'Shows this help page',
                    Icons.help,
                    AppColors.success,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'হোম / শুরু',
                    'Home / Start',
                    'হোম পৃষ্ঠায় ফিরে যায়',
                    'Returns to home page',
                    Icons.home,
                    AppColors.accent,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'থামো',
                    'Stop',
                    'বর্তমান ভয়েস বন্ধ করে',
                    'Stops current voice',
                    Icons.stop,
                    AppColors.error,
                  ),
                ],
              ),
            ),
            
            SizedBox(height: AppConstants.spacingXl),
            
            // Tips Section
            _buildSectionHeader(context, 'টিপস / Tips'),
            
            _buildTipCard(
              context,
              icon: Icons.lightbulb_outline,
              tip: 'স্পষ্টভাবে এবং ধীরে ধীরে কথা বলুন',
              tipEn: 'Speak clearly and slowly',
              color: AppColors.warning,
            ),
            
            _buildTipCard(
              context,
              icon: Icons.headphones,
              tip: 'শান্ত পরিবেশে ব্যবহার করুন',
              tipEn: 'Use in a quiet environment',
              color: AppColors.info,
            ),
            
            _buildTipCard(
              context,
              icon: Icons.battery_charging_full,
              tip: 'ব্যাটারি সেভার মোড বেশি ব্যাটারি সাশ্রয় করে',
              tipEn: 'Battery saver mode conserves more battery',
              color: AppColors.success,
            ),
            
            SizedBox(height: AppConstants.spacingXl),
            
            // Support Section
            Card(
              elevation: 2,
              color: AppColors.accentLight.withOpacity(0.2),
              child: Padding(
                padding: EdgeInsets.all(AppConstants.spacingL),
                child: Column(
                  children: [
                    Icon(
                      Icons.support_agent,
                      size: AppConstants.iconXl,
                      color: AppColors.accent,
                    ),
                    SizedBox(height: AppConstants.spacingM),
                    const Text(
                      'সাহায্য প্রয়োজন?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: AppConstants.spacingXs),
                    const Text(
                      'Need Help?',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: AppConstants.spacingM),
                    const Text(
                      'এই একটি থিসিস প্রজেক্ট। আরও তথ্যের জন্য সেটিংসে যান।',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: AppConstants.spacingXs),
                    const Text(
                      'This is a thesis project. Go to Settings for more information.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
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
  
  Widget _buildStepCard(
    BuildContext context, {
    required String step,
    required String stepEn,
    required String title,
    required String titleEn,
    required String description,
    required String descriptionEn,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      margin: EdgeInsets.only(bottom: AppConstants.spacingM),
      child: Padding(
        padding: EdgeInsets.all(AppConstants.spacingL),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  step,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(width: AppConstants.spacingL),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    titleEn,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: AppConstants.spacingS),
                  Text(description),
                  Text(
                    descriptionEn,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCommandTile(
    String command,
    String commandEn,
    String description,
    String descriptionEn,
    IconData icon,
    Color color,
  ) {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(AppConstants.spacingS),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppConstants.radiusS),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text('$command / $commandEn'),
      subtitle: Text('$description\n$descriptionEn'),
      isThreeLine: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppConstants.spacingL,
        vertical: AppConstants.spacingS,
      ),
    );
  }
  
  Widget _buildTipCard(
    BuildContext context, {
    required IconData icon,
    required String tip,
    required String tipEn,
    required Color color,
  }) {
    return Card(
      margin: EdgeInsets.only(bottom: AppConstants.spacingM),
      child: Padding(
        padding: EdgeInsets.all(AppConstants.spacingL),
        child: Row(
          children: [
            Icon(icon, color: color, size: AppConstants.iconL),
            SizedBox(width: AppConstants.spacingL),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tip,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    tipEn,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
