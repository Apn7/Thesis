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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Required by sherpa_onnx before any recognizer can be created.
  sherpa.initBindings();

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
  
  runApp(const SmartCaneApp());
}

class SmartCaneApp extends StatelessWidget {
  const SmartCaneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'স্মার্ট ক্যান • Smart Cane',
      debugShowCheckedModeBanner: false,
      
      // Theme
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      
      // Accessibility
      showSemanticsDebugger: false, // Set to true for debugging accessibility  
      
      // Navigation
      initialRoute: AppRoutes.home,
      routes: {
        AppRoutes.home: (context) => const HomeScreen(),
        AppRoutes.location: (context) => const LocationScreen(),
        AppRoutes.settings: (context) => const SettingsScreen(),
        AppRoutes.help: (context) => const HelpScreen(),
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
        return MediaQuery(
          data: scaledMediaQueryData,
          child: child!,
        );
      },
    );
  }
}
