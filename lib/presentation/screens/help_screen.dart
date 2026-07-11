import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/voice_announcer.dart';
import '../../services/sensor_fusion_service.dart';
import '../../services/voice_navigation_service.dart';

/// Help screen with tutorials and the command list.
///
/// Voice first: the whole command list can be *heard* — via the big
/// "সব কমান্ড শুনুন" button here, or from anywhere by saying "কী বলতে পারি".
/// The visible list below mirrors [VoiceNavigationService.commandTour] so the
/// spoken and written help never drift apart.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  @override
  void initState() {
    super.initState();
    // Own the audio channel while mounted (SOS pattern): the spoken command
    // tour is long, and a single fusion obstacle callout would cut the whole
    // manual off mid-sentence. The sonar CRITICAL alarm still gets through.
    SensorFusionService.instance.holdUiAudio(this);
    // Guided spoken tour, in learning order: first the পরামর্শ (how to talk
    // to the app), then the full command list — a blind user gets the whole
    // manual read to them just by opening this page. Interruptible at any
    // moment: pressing a volume button barges in and stops the tour.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VoiceAnnouncer.announce(
        'সাহায্য পেইজ। '
        '${VoiceNavigationService.helpTips} '
        'এবার কমান্ডের তালিকা। '
        '${VoiceNavigationService.commandTour} '
        'সব কমান্ড আবার শুনতে বলুন: কমান্ড বলো।',
      );
    });
  }

  @override
  void dispose() {
    SensorFusionService.instance.releaseUiAudio(this);
    super.dispose();
  }

  void _speakCommandTour() {
    VoiceAnnouncer.announce(VoiceNavigationService.commandTour);
  }

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

            SizedBox(height: AppConstants.spacingL),

            // Hear-all-commands — the primary help action for a voice user.
            FilledButton.icon(
              onPressed: _speakCommandTour,
              icon: const Icon(Icons.volume_up),
              label: const Text('সব কমান্ড শুনুন'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(
                  AppConstants.largeTouchTargetSize,
                ),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            SizedBox(height: AppConstants.spacingXl),

            // Quick Start Guide
            _buildSectionHeader(context, 'দ্রুত শুরু'),

            _buildStepCard(
              context,
              step: '১',
              title: 'ভলিউম বোতাম চেপে ধরুন',
              description:
                  'যেকোনো পেইজ থেকে ভলিউম বোতাম চেপে ধরুন। '
                  'ছোট্ট সুর বাজলে কথা বলা শুরু করুন।',
              icon: Icons.mic,
              color: AppColors.accent,
            ),

            _buildStepCard(
              context,
              step: '২',
              title: 'কমান্ড বলে বোতাম ছাড়ুন',
              description: 'বোতাম ছাড়লেই আপনার কথা পাঠানো হয়।',
              icon: Icons.record_voice_over,
              color: AppColors.primary,
            ),

            _buildStepCard(
              context,
              step: '৩',
              title: 'অডিও উত্তর শুনুন',
              description: 'অ্যাপ অডিও উত্তর দেবে। আবার শুনতে বলুন: আবার বলো।',
              icon: Icons.volume_up,
              color: AppColors.info,
            ),

            SizedBox(height: AppConstants.spacingXl),

            // Voice Commands List — mirrors VoiceNavigationService.commandTour.
            _buildSectionHeader(context, 'ভয়েস কমান্ড'),

            Card(
              child: Column(
                children: [
                  _buildCommandTile(
                    'আমি কোথায়?',
                    'আপনার অবস্থান ও ঠিকানা বলে',
                    Icons.location_on,
                    AppColors.info,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'সামনে কী আছে?',
                    'ক্যামেরায় দেখা বস্তু বর্ণনা করে',
                    Icons.visibility,
                    AppColors.warning,
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
                    'যোগাযোগ পেইজ খোলে — সেখানে বলুন: যোগ করো, পড়ো, মুছো, বদলাও, একজনকে পাঠাও',
                    Icons.contacts,
                    AppColors.info,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'ব্যাটারি',
                    'ফোনের চার্জ কত জানায়',
                    Icons.battery_charging_full,
                    AppColors.success,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'সময় কত?',
                    'এখনকার সময় বলে',
                    Icons.access_time,
                    AppColors.primary,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'আবার বলো',
                    'শেষ উত্তরটি আবার শোনায়',
                    Icons.replay,
                    AppColors.accent,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'ধীরে বলো / দ্রুত বলো',
                    'কথার গতি কমায় বা বাড়ায়',
                    Icons.speed,
                    AppColors.warning,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'পিছনে যাও',
                    'আগের পেইজে ফিরে যায়',
                    Icons.arrow_back,
                    AppColors.textSecondary,
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
                    'সেটিংস / সাহায্য',
                    'সেটিংস বা এই সাহায্য পেইজ খোলে',
                    Icons.settings,
                    AppColors.primary,
                  ),
                  const Divider(height: 1),
                  _buildCommandTile(
                    'কী বলতে পারি?',
                    'এই কমান্ডগুলোর তালিকা পড়ে শোনায়',
                    Icons.help,
                    AppColors.success,
                  ),
                ],
              ),
            ),

            SizedBox(height: AppConstants.spacingXl),

            // Tips Section — mirrors VoiceNavigationService.helpTips.
            _buildSectionHeader(context, 'পরামর্শ'),

            _buildTipCard(
              context,
              icon: Icons.music_note,
              tip: 'বোতাম চাপার পর ছোট্ট সুর শুনে তবেই কথা শুরু করুন',
              color: AppColors.accent,
            ),

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
              icon: Icons.touch_app,
              tip:
                  'অ্যাপ কথা বলার সময় ভলিউম বোতাম চাপলে সে থেমে আপনার কথা শোনে',
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
