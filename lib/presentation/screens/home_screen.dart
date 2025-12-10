import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../core/navigation/app_routes.dart';
import '../../services/voice_navigation_service.dart';
import '../widgets/accessible_action_button.dart';
import '../widgets/voice_indicator.dart';

/// Home screen with voice-first navigation
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final VoiceNavigationService _voiceService = VoiceNavigationService.instance;
  bool _isInitialized = false;
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
    _setupNavigationCallback();
  }
  
  Future<void> _initializeServices() async {
    await _voiceService.initialize();
    setState(() {
      _isInitialized = true;
    });
    
    // Welcome message
    await Future.delayed(const Duration(milliseconds: 500));
    await _voiceService.speak(
      'স্মার্ট ক্যান অ্যাপে স্বাগতম। বলুন কোথায় যেতে চান। Welcome to Smart Cane. Say where you want to go.',
    );
  }
  
  void _setupNavigationCallback() {
    _voiceService.onNavigationAction = (action) {
      switch (action) {
        case VoiceAction.navigateHome:
          // Already on home
          break;
        case VoiceAction.navigateLocation:
          Navigator.pushNamed(context, AppRoutes.location);
          break;
        case VoiceAction.navigateSettings:
          Navigator.pushNamed(context, AppRoutes.settings);
          break;
        case VoiceAction.navigateHelp:
          Navigator.pushNamed(context, AppRoutes.help);
          break;
        case VoiceAction.speakBattery:
          _voiceService.speak('ব্যাটারি ৮৫ শতাংশ। Battery is 85 percent.');
          break;
        case VoiceAction.speakTime:
          final now = TimeOfDay.now();
          _voiceService.speak('সময় ${now.hour}:${now.minute}। Time is ${now.format(context)}.');
          break;
        case VoiceAction.none:
          break;
      }
    };
  }
  
  void _toggleVoiceListening() async {
    if (_voiceService.isListening) {
      await _voiceService.stopListening();
    } else {
      await _voiceService.startListening();
    }
    setState(() {});
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
        child: ListenableBuilder(
          listenable: _voiceService,
          builder: (context, child) {
            return SingleChildScrollView(
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
                            isListening: _voiceService.isListening,
                            size: 120,
                          ),
                          SizedBox(height: AppConstants.spacingL),
                          
                          // Status text
                          Text(
                            _voiceService.isProcessing
                                ? 'চিন্তা করছি...'
                                : _voiceService.isListening
                                    ? 'শুনছি...'
                                    : 'ভয়েস কমান্ড',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _voiceService.isListening 
                                  ? AppColors.accent 
                                  : _voiceService.isProcessing
                                      ? AppColors.info
                                      : AppColors.primary,
                            ),
                          ),
                          SizedBox(height: AppConstants.spacingXs),
                          Text(
                            _voiceService.isProcessing
                                ? 'Processing...'
                                : _voiceService.isListening
                                    ? 'Listening...'
                                    : 'Voice Command',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          
                          // Transcript display
                          if (_voiceService.currentTranscript.isNotEmpty) ...[
                            SizedBox(height: AppConstants.spacingM),
                            Container(
                              padding: EdgeInsets.all(AppConstants.spacingM),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(AppConstants.radiusM),
                              ),
                              child: Text(
                                '"${_voiceService.currentTranscript}"',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                          
                          // Last response
                          if (_voiceService.lastResponse.isNotEmpty && 
                              !_voiceService.isListening && 
                              !_voiceService.isProcessing) ...[
                            SizedBox(height: AppConstants.spacingM),
                            Container(
                              padding: EdgeInsets.all(AppConstants.spacingM),
                              decoration: BoxDecoration(
                                color: AppColors.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(AppConstants.radiusM),
                                border: Border.all(color: AppColors.success.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle, color: AppColors.success),
                                  SizedBox(width: AppConstants.spacingS),
                                  Expanded(
                                    child: Text(
                                      _voiceService.lastResponse,
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          
                          SizedBox(height: AppConstants.spacingL),
                          
                          // Listen button
                          FilledButton.icon(
                            onPressed: _isInitialized ? _toggleVoiceListening : null,
                            icon: Icon(
                              _voiceService.isListening ? Icons.mic_off : Icons.mic,
                            ),
                            label: Text(
                              _voiceService.isListening 
                                  ? 'থামান (Stop)' 
                                  : 'শুরু করুন (Start)',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: _voiceService.isListening 
                                  ? AppColors.error 
                                  : AppColors.accent,
                              padding: EdgeInsets.symmetric(
                                horizontal: AppConstants.spacingXl,
                                vertical: AppConstants.spacingL,
                              ),
                            ),
                          ),
                          
                          // Error display
                          if (_voiceService.error.isNotEmpty) ...[
                            SizedBox(height: AppConstants.spacingM),
                            Text(
                              _voiceService.error,
                              style: TextStyle(color: AppColors.error),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  SizedBox(height: AppConstants.spacingXl),
                  
                  // Text input for testing (helpful for demo)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppConstants.spacingM),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'টেস্ট কমান্ড / Test Command',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          SizedBox(height: AppConstants.spacingS),
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'Type a command...',
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.send),
                                onPressed: () {
                                  // Get text from controller and send
                                },
                              ),
                            ),
                            onSubmitted: (text) {
                              if (text.isNotEmpty) {
                                _voiceService.sendTextCommand(text);
                              }
                            },
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
                        semanticHint: 'আপনার বর্তমান অবস্থান দেখুন।',
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.location),
                        color: AppColors.info,
                      ),
                      AccessibleActionButton(
                        icon: Icons.settings,
                        label: 'সেটিংস',
                        labelEn: 'Settings',
                        semanticHint: 'সেটিংস খুলুন।',
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
                        color: AppColors.primary,
                      ),
                      AccessibleActionButton(
                        icon: Icons.help_outline,
                        label: 'সাহায্য',
                        labelEn: 'Help',
                        semanticHint: 'সাহায্য এবং টিউটোরিয়াল।',
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.help),
                        color: AppColors.success,
                      ),
                      AccessibleActionButton(
                        icon: Icons.battery_charging_full,
                        label: 'ব্যাটারি',
                        labelEn: 'Battery',
                        semanticHint: 'ব্যাটারি স্ট্যাটাস।',
                        onPressed: () {
                          _voiceService.speak('ব্যাটারি ৮৫ শতাংশ। Battery is 85 percent.');
                        },
                        color: AppColors.warning,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
