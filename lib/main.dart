import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'core/theme/app_theme.dart';
import 'core/navigation/app_routes.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/location_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/screens/help_screen.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/vision_demo_screen.dart';
import 'presentation/screens/pi_vision_screen.dart';
import 'services/hardware_key_service.dart';
import 'services/stt/stt_engine_factory.dart';
import 'services/voice_navigation_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise sherpa-onnx native bindings, then pre-warm the offline Bengali
  // STT model (copy ~91 MB from assets + load the recognizer) in the
  // background so the first push-to-talk isn't blocked on a cold model load.
  sherpa.initBindings();
  unawaited(SttEngineFactory.getEngine('bn').initialize());

  // Load environment variables from .env
  await dotenv.load(fileName: ".env");

  // Set preferred orientations (portrait only for accessibility)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Volume keys (up or down) act as the global push-to-talk button while the
  // app is in the foreground: hold to listen, release to submit. Pressing while
  // the agent is thinking or speaking is a *barge-in* — VoiceNavigationService
  // silences the reply and starts a fresh turn — so the handlers are
  // unconditional and the state machine owns all the guarding.
  HardwareKeyService.instance.setVolumeKeyHandlers(
    onDown: () => VoiceNavigationService.instance.startListening(),
    onUp: () => VoiceNavigationService.instance.stopListening(),
  );

  runApp(const SmartCaneApp());
}

class SmartCaneApp extends StatelessWidget {
  const SmartCaneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Cane',
      debugShowCheckedModeBanner: false,

      // Theme
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,

      // Accessibility
      showSemanticsDebugger: false, // Set to true for debugging accessibility
      // Navigation
      initialRoute: AppRoutes.splash,
      routes: {
        AppRoutes.splash: (context) => const SplashScreen(),
        AppRoutes.home: (context) => const HomeScreen(),
        AppRoutes.location: (context) => const LocationScreen(),
        AppRoutes.settings: (context) => const SettingsScreen(),
        AppRoutes.help: (context) => const HelpScreen(),
        AppRoutes.visionDemo: (context) => const VisionDemoScreen(),
        AppRoutes.piVision: (context) => const PiVisionScreen(),
      },

      // Error handling
      builder: (context, child) {
        // Ensure text scale factor doesn't exceed 2.0 for layout stability
        final mediaQueryData = MediaQuery.of(context);
        final scaledMediaQueryData = mediaQueryData.copyWith(
          textScaler: TextScaler.linear(
            mediaQueryData.textScaler.scale(1.0).clamp(0.8, 2.0),
          ),
        );
        return MediaQuery(data: scaledMediaQueryData, child: child!);
      },
    );
  }
}
