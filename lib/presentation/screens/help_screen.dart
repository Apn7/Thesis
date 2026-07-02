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
          label: 'সাহায্য',
          child: const Text('সাহায্য'),
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
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                    ),
                    SizedBox(height: AppConstants.spacingM),
                    const Text(
                      'এই অ্যাপটি ভয়েস কমান্ড দিয়ে চলাচলের জন্য তৈরি।',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppConstants.spacingXl),

            // Quick Start Guide
            _buildSectionHeader(context, 'দ্রুত শুরু'),

            _buildStepCard(
              context,
              step: '১',
              title: 'হোম স্ক্রিনে যান',
              description: 'অ্যাপ খুললেই আপনি হোম স্ক্রিনে চলে আসবেন।',
              icon: Icons.home,
              color: AppColors.primary,
            ),

            _buildStepCard(
              context,
              step: '২',
              title: 'ভয়েস কমান্ড বলুন',
              description: 'ভলিউম বোতাম চেপে ধরে আপনার কমান্ড বলুন।',
              icon: Icons.mic,
              color: AppColors.accent,
            ),

            _buildStepCard(
              context,
              step: '৩',
              title: 'অডিও উত্তর শুনুন',
              description: 'অ্যাপ অডিও উত্তরের মাধ্যমে আপনাকে পথ দেখাবে।',
              icon: Icons.volume_up,
              color: AppColors.info,
            ),

            SizedBox(height: AppConstants.spacingXl),

            // Voice Commands List
            _buildSectionHeader(context, 'ভয়েস কমান্ড'),

            Card(
              child: Column(
                children: [
                  _buildCommandTile(
                    'আমি কোথায়?',
                    'আপনার বর্তমান অবস্থান দেখায়',
                    Icons.location_on,
                    AppColors.info,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'সেটিংস',
                    'সেটিংস মেনু খোলে',
                    Icons.settings,
                    AppColors.primary,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'সাহায্য',
                    'এই সাহায্য পেইজ দেখায়',
                    Icons.help,
                    AppColors.success,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'হোম',
                    'হোম স্ক্রিনে ফিরে যায়',
                    Icons.home,
                    AppColors.accent,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'সামনে কী আছে?',
                    'সামনের সনাক্ত হওয়া বস্তু বর্ণনা করে',
                    Icons.visibility,
                    AppColors.warning,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'ব্যাটারি',
                    'ব্যাটারির পরিমাণ জানায়',
                    Icons.battery_charging_full,
                    AppColors.error,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'জরুরি / বাঁচাও',
                    'জরুরি যোগাযোগে অবস্থানসহ বার্তা পাঠায় (বাতিল বলা যায়)',
                    Icons.sos,
                    AppColors.error,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'জরুরি যোগাযোগ',
                    'জরুরি যোগাযোগ পেইজ খোলে — সেখানে বলুন: যোগ করো, পড়ো, মুছো, বদলাও, একজনকে পাঠাও',
                    Icons.contacts,
                    AppColors.info,
                  ),
                ],
              ),
            ),

            SizedBox(height: AppConstants.spacingXl),

            // Tips Section
            _buildSectionHeader(context, 'পরামর্শ'),

            _buildTipCard(
              context,
              icon: Icons.lightbulb_outline,
              tip: 'স্পষ্টভাবে ও স্বাভাবিক গতিতে বলুন',
              color: AppColors.warning,
            ),

            _buildTipCard(
              context,
              icon: Icons.headphones,
              tip: 'ভালো ফলের জন্য শান্ত পরিবেশে ব্যবহার করুন',
              color: AppColors.info,
            ),

            _buildTipCard(
              context,
              icon: Icons.battery_charging_full,
              tip: 'ব্যাটারি সেভার মোডে কম্পন কম হয়',
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
                      'সাহায্য দরকার?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: AppConstants.spacingM),
                    const Text(
                      'এটি একটি থিসিস প্রকল্প। আরও তথ্যের জন্য সেটিংসে যান।',
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
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildStepCard(
    BuildContext context, {
    required String step,
    required String title,
    required String description,
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
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
                  SizedBox(height: AppConstants.spacingS),
                  Text(description),
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
    String description,
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
      title: Text(command),
      subtitle: Text(description),
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
              child: Text(
                tip,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
