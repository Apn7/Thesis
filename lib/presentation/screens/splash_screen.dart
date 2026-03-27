import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../services/settings_service.dart';
import '../../services/speech_service.dart';
import '../../services/stt/model_asset_manager.dart';
import '../../services/stt/sherpa_model_config.dart';

/// First-launch setup screen: copies bundled model assets to local storage,
/// then navigates to the home screen automatically.
///
/// On subsequent launches all files are already present so the copy step
/// completes immediately and the user sees this screen for only a moment.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  String _statusBn = 'শুরু হচ্ছে...';
  String _statusEn = 'Starting up...';
  double _progress = 0.0;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Run setup after first frame so the UI is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ─── Setup ──────────────────────────────────────────────────────

  Future<void> _setup() async {
    try {
      await _copyModels();
      await _initServices();
    } catch (e) {
      debugPrint('SplashScreen setup error: $e');
      // Even on error, proceed — SpeechService handles failures gracefully.
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  Future<void> _copyModels() async {
    // ── Bengali STT ──────────────────────────────────────────────
    _update('বাংলা ভয়েস মডেল প্রস্তুত হচ্ছে...', 'Preparing Bengali voice model...', 0.05);
    await ModelAssetManager.ensureSherpaModel(kBengaliSherpaConfig);
    _update('বাংলা মডেল প্রস্তুত ✓', 'Bengali model ready ✓', 0.40);

    // ── English STT ──────────────────────────────────────────────
    _update('ইংরেজি ভয়েস মডেল প্রস্তুত হচ্ছে...', 'Preparing English voice model...', 0.42);
    await ModelAssetManager.ensureSherpaModel(kEnglishSherpaConfig);
    _update('ইংরেজি মডেল প্রস্তুত ✓', 'English model ready ✓', 0.80);

    // ── SLI (language detection) ─────────────────────────────────
    _update('ভাষা শনাক্তকরণ প্রস্তুত হচ্ছে...', 'Preparing language detector...', 0.82);
    await ModelAssetManager.ensureSliModel(kSliWhisperTinyConfig);
    _update('সব মডেল প্রস্তুত ✓', 'All models ready ✓', 0.92);
  }

  Future<void> _initServices() async {
    _update('সার্ভিস চালু হচ্ছে...', 'Starting services...', 0.94);
    await SettingsService.instance.load();
    await SpeechService.instance.setLocale(SettingsService.instance.languageMode);
    _update('প্রস্তুত!', 'Ready!', 1.0);
    // Brief pause so the user sees "Ready".
    await Future.delayed(const Duration(milliseconds: 400));
  }

  void _update(String bn, String en, double progress) {
    if (!mounted) return;
    setState(() {
      _statusBn = bn;
      _statusEn = en;
      _progress = progress;
    });
  }

  // ─── UI ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              // Pulsing cane icon
              ScaleTransition(
                scale: _pulseAnim,
                child: const Icon(
                  Icons.accessibility_new,
                  size: 96,
                  color: AppColors.primary,
                  semanticLabel: 'Smart Cane',
                ),
              ),
              const SizedBox(height: 24),
              // App name
              const Text(
                'স্মার্ট ক্যান',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textOnDark,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'Smart Cane',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondaryOnDark,
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  backgroundColor: AppColors.primaryDark.withAlpha(80),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Status text
              Text(
                _statusBn,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textOnDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                _statusEn,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondaryOnDark,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
