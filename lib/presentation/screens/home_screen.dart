import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../core/navigation/app_routes.dart';
import '../../services/ble_service.dart';
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
  final BleService _bleService = BleService.instance;
  bool _isInitialized = false;
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
    _setupNavigationCallback();
    _initializeBle();
  }
  
  @override
  void dispose() {
    _bleService.disconnect();
    super.dispose();
  }
  
  /// Initialize BLE service and set up alert callback
  bool _connectionAnnounced = false;
  
  Future<void> _initializeBle() async {
    // Set up alert callback — when Pi sends an obstacle alert via BLE
    _bleService.onAlertReceived = (message) {
      _handleIncomingMessage(message);
    };
    
    // Listen for BLE state changes to rebuild UI
    _bleService.addListener(() {
      if (mounted) {
        setState(() {});
        
        // Announce connection via voice (only once per connection session)
        if (_bleService.state == BleConnectionState.connected && !_connectionAnnounced) {
          _connectionAnnounced = true;
          _voiceService.speak('স্মার্ট ক্যান সংযুক্ত। Smart Cane connected via Bluetooth.');
        } else if (_bleService.state == BleConnectionState.disconnected && _connectionAnnounced) {
          _connectionAnnounced = false;
        }
      }
    });
    
    await _bleService.initialize();
  }
  
  /// Handles incoming messages from the Raspberry Pi (via BLE)
  /// Format from Pi: "LEVEL:OBJECT_NAME:CONFIDENCE:POSITION"
  void _handleIncomingMessage(String message) {
    if (!mounted) return;
    
    final alert = BleAlert.parse(message);
    
    // Build human-readable speech string
    String speechText;
    if (alert.objectName.isNotEmpty && alert.position.isNotEmpty) {
      speechText = '${alert.level}: ${alert.objectName} detected at ${alert.position}';
    } else {
      speechText = message;
    }
    
    // Speak the alert
    _voiceService.speak(speechText);
    
    // Show critical alert dialog for immediate-danger obstacles
    if (alert.isCritical) {
      _showCriticalAlertDialog(alert.displayMessage);
    }
  }
  
  /// Shows a critical alert dialog for emergency warnings
  void _showCriticalAlertDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusL),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 32),
              SizedBox(width: AppConstants.spacingM),
              const Expanded(
                child: Text(
                  '⚠️ CRITICAL ALERT',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          content: Container(
            padding: EdgeInsets.all(AppConstants.spacingM),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppConstants.radiusM),
            ),
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.error,
                  padding: EdgeInsets.symmetric(vertical: AppConstants.spacingM),
                ),
                child: const Text(
                  'DISMISS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        );
      },
    );
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
                  
                  SizedBox(height: AppConstants.spacingL),
                  
                  // BLE Connection Status Card
                  Card(
                    elevation: 4,
                    color: _bleService.isConnected
                        ? AppColors.success.withOpacity(0.1)
                        : Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusM),
                      side: BorderSide(
                        color: _bleService.isConnected
                            ? AppColors.success 
                            : _bleService.state == BleConnectionState.bluetoothOff
                                ? AppColors.error.withOpacity(0.5)
                                : AppColors.primary.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(AppConstants.spacingL),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            children: [
                              Icon(
                                _bleService.isConnected 
                                    ? Icons.bluetooth_connected
                                    : _bleService.state == BleConnectionState.bluetoothOff
                                        ? Icons.bluetooth_disabled
                                        : _bleService.isScanning
                                            ? Icons.bluetooth_searching
                                            : Icons.bluetooth,
                                color: _bleService.isConnected 
                                    ? AppColors.success 
                                    : _bleService.state == BleConnectionState.bluetoothOff
                                        ? AppColors.error
                                        : _bleService.isScanning
                                            ? AppColors.info
                                            : AppColors.warning,
                                size: 28,
                              ),
                              SizedBox(width: AppConstants.spacingM),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ব্লুটুথ কানেকশন / BLE Connection',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: AppConstants.spacingXs),
                                    Text(
                                      _bleService.statusMessage,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: _bleService.isConnected 
                                            ? AppColors.success 
                                            : AppColors.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Connection indicator dot
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _bleService.isConnected 
                                      ? AppColors.success 
                                      : _bleService.state == BleConnectionState.bluetoothOff
                                          ? AppColors.error
                                          : AppColors.warning,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_bleService.isConnected 
                                          ? AppColors.success 
                                          : AppColors.warning).withOpacity(0.5),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          
                          // Scan/Reconnect Button
                          if (!_bleService.isConnected && _bleService.state != BleConnectionState.scanning) ...[
                            SizedBox(height: AppConstants.spacingM),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _bleService.startScanning(),
                                icon: const Icon(Icons.bluetooth_searching),
                                label: const Text('Scan for Smart Cane / স্ক্যান করুন'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  side: BorderSide(color: AppColors.primary),
                                  padding: EdgeInsets.symmetric(vertical: AppConstants.spacingM),
                                ),
                              ),
                            ),
                          ],
                          
                          // Scanning progress indicator
                          if (_bleService.isScanning) ...[
                            SizedBox(height: AppConstants.spacingM),
                            const LinearProgressIndicator(),
                          ],
                          
                          // Latest Alert Display
                          if (_bleService.latestAlert.isNotEmpty) ...[
                            SizedBox(height: AppConstants.spacingM),
                            Divider(color: AppColors.primary.withOpacity(0.2)),
                            SizedBox(height: AppConstants.spacingM),
                            Builder(
                              builder: (context) {
                                final alert = _bleService.latestParsedAlert;
                                final isCritical = alert?.isCritical ?? false;
                                final isWarning = alert?.isWarning ?? false;
                                
                                // Pick color based on danger level
                                final alertColor = isCritical 
                                    ? AppColors.error 
                                    : isWarning 
                                        ? AppColors.warning 
                                        : AppColors.info;
                                
                                return Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.all(AppConstants.spacingM),
                                  decoration: BoxDecoration(
                                    color: alertColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(AppConstants.radiusS),
                                    border: Border.all(
                                      color: alertColor.withOpacity(0.5),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            isCritical 
                                                ? Icons.warning_amber_rounded
                                                : isWarning
                                                    ? Icons.error_outline
                                                    : Icons.notifications_active,
                                            color: alertColor,
                                            size: 20,
                                          ),
                                          SizedBox(width: AppConstants.spacingS),
                                          Expanded(
                                            child: Text(
                                              alert != null 
                                                  ? '${alert.level} — ${alert.position}'
                                                  : 'সর্বশেষ সতর্কতা / Latest Alert',
                                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: alertColor,
                                              ),
                                            ),
                                          ),
                                          if (alert?.confidence.isNotEmpty ?? false)
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: AppConstants.spacingS,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: alertColor.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                alert!.confidence,
                                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                  color: alertColor,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      SizedBox(height: AppConstants.spacingS),
                                      Text(
                                        alert?.displayMessage ?? _bleService.latestAlert,
                                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
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
