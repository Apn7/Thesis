import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/voice_announcer.dart';
// import '../../core/utils/constants.dart'; // only needed for enableLlm flag — disabled
// import '../../services/llm_service.dart'; // on-device LLM — disabled to reduce APK size
import '../../services/settings_service.dart';
import '../../services/speech_service.dart';
import '../../services/tts_service.dart';
// import '../../services/stt/model_asset_manager.dart'; // Sherpa offline Bengali STT — disabled
// import '../../services/stt/sherpa_model_config.dart'; // Sherpa offline Bengali STT — disabled

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
  String _status = 'চালু হচ্ছে...';
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
    // Bring up TTS first so the TalkBack-off path can actually *speak* the
    // permission guidance below.  TTS needs no permission of its own.
    try {
      await TtsService.instance.initialize();
    } catch (e) {
      debugPrint('SplashScreen TTS init error: $e');
    }

    try {
      await _requestPermissions();
      // await _copyModels();                            // Bengali STT model — disabled
      // if (AppConstants.enableLlm) await _initLlm();  // on-device LLM — disabled
      await _initServices();
    } catch (e) {
      debugPrint('SplashScreen setup error: $e');
      // Even on error, proceed — individual services handle failures gracefully.
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  /// Request all dangerous permissions at first launch so blind users never
  /// need to navigate to system Settings manually.
  Future<void> _requestPermissions() async {
    final required = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.microphone,
    ];

    // Only prompt for what's still missing so repeat launches stay silent —
    // a blind user shouldn't hear a permission lecture every time they open
    // the app.
    final toRequest = <Permission>[];
    for (final p in required) {
      if (!(await p.status).isGranted) toRequest.add(p);
    }
    if (toRequest.isEmpty) {
      _update('অনুমতি ✓', 0.04);
      return;
    }

    // Hybrid model: the OS permission dialog can only be read and operated by
    // a screen reader (TalkBack) or a sighted helper — an app cannot accept it
    // itself.  With no screen reader running, the user can't see or hear the
    // dialog, so speak an instruction with our own TTS.  Fire-and-forget so the
    // dialog appears immediately and the instruction plays *alongside* it —
    // awaiting it (now that TTS awaits completion) would delay the prompt by the
    // whole sentence.
    if (!VoiceAnnouncer.screenReaderOn) {
      unawaited(
        TtsService.instance.speak(
          'স্মার্ট ক্যানের কিছু অনুমতি প্রয়োজন। অনুমতি দিতে টকব্যাক চালু করুন, '
          'অথবা চোখে দেখেন এমন কারও সাহায্য নিন।',
        ),
      );
    }

    _update('অনুমতি চাওয়া হচ্ছে...', 0.02);

    final statuses = await toRequest.request();

    for (final entry in statuses.entries) {
      debugPrint('Permission ${entry.key}: ${entry.value}');
    }

    // If any critical permission is permanently denied, guide user to settings.
    final permanentlyDenied = statuses.entries
        .where((e) => e.value.isPermanentlyDenied)
        .map((e) => e.key.toString().split('.').last)
        .toList();

    if (permanentlyDenied.isNotEmpty && mounted) {
      debugPrint(
        'Permanently denied: $permanentlyDenied — guiding to settings',
      );

      // TalkBack reads this dialog itself; if it's off, speak it so a blind
      // user isn't stranded at a silent dialog.
      if (!VoiceAnnouncer.screenReaderOn) {
        unawaited(
          TtsService.instance.speak(
            'কিছু অনুমতি বন্ধ আছে। অনুগ্রহ করে সেটিংসে গিয়ে অনুমতি দিন।',
          ),
        );
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('অনুমতি প্রয়োজন'),
          content: Text(
            'অনুগ্রহ করে অনুমতি দিন: ${permanentlyDenied.join(", ")}\n\n'
            'সেটিংস → অ্যাপ → অনুমতি',
          ),
          actions: [
            TextButton(
              onPressed: () {
                openAppSettings();
                Navigator.pop(context);
              },
              child: const Text('সেটিংস খুলুন'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('এড়িয়ে যান'),
            ),
          ],
        ),
      );
    }

    _update('অনুমতি সম্পন্ন ✓', 0.04);
  }

  // Bengali STT model copy — disabled to reduce APK size
  // Future<void> _copyModels() async {
  //   _update('বাংলা ভয়েস মডেল প্রস্তুত হচ্ছে...', 'Preparing Bengali voice model...', 0.05);
  //   await ModelAssetManager.ensureSherpaModel(kBengaliSherpaConfig);
  //   _update('মডেল প্রস্তুত ✓', 'Model ready ✓', 0.80);
  // }

  // On-device LLM init — disabled to reduce APK size
  // Future<void> _initLlm() async {
  //   _update('AI মডেল লোড হচ্ছে...', 'Loading AI model...', 0.82);
  //   await LlmService.instance.init();
  //   _update('AI মডেল প্রস্তুত ✓', 'AI model ready ✓', 0.92);
  // }

  Future<void> _initServices() async {
    _update('সার্ভিস চালু হচ্ছে...', 0.94);
    await SettingsService.instance.load();
    // Fully ready the offline Bengali STT (model was pre-warmed in main()).
    await SpeechService.instance.initialize();
    _update('প্রস্তুত!', 1.0);

    if (VoiceAnnouncer.screenReaderOn) {
      // TalkBack was only needed to grant the permission dialog.  For daily use
      // the app is self-voicing, and TalkBack's element-by-element narration
      // competes with our own voice — so ask the user to switch it off.
      await TtsService.instance.speak(
        'প্রস্তুত। সেরা অভিজ্ঞতার জন্য দুটি ভলিউম বোতাম তিন সেকেন্ড চেপে ধরে '
        'এখন টকব্যাক বন্ধ করুন।',
      );
    } else {
      await VoiceAnnouncer.announce('প্রস্তুত।');
    }

    await Future.delayed(const Duration(milliseconds: 400));
  }

  void _update(String status, double progress) {
    if (!mounted) return;
    setState(() {
      _status = status;
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
                  semanticLabel: 'স্মার্ট ক্যান',
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
                _status,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textOnDark,
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
