import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../core/navigation/app_routes.dart';
import '../../services/ble_service.dart';
import '../../services/voice_navigation_service.dart';
import '../widgets/accessible_action_button.dart';
import '../widgets/voice_indicator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final VoiceNavigationService _voiceService = VoiceNavigationService.instance;
  final BleService _bleService = BleService.instance;
  bool _isInitialized = false;
  bool _connectionAnnounced = false;

  // Active alert — cleared automatically when Pi stops sending (object gone)
  BleAlert? _currentAlert;
  Timer? _alertClearTimer;

  late final AnimationController _alertAnimController;
  late final Animation<double> _alertScale;
  late final Animation<double> _alertOpacity;

  @override
  void initState() {
    super.initState();

    _alertAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _alertScale = CurvedAnimation(
      parent: _alertAnimController,
      curve: Curves.elasticOut,
    );
    _alertOpacity = CurvedAnimation(
      parent: _alertAnimController,
      curve: Curves.easeIn,
    );

    _initializeServices();
    _setupNavigationCallback();
    _initializeBle();
  }

  @override
  void dispose() {
    _alertClearTimer?.cancel();
    _alertAnimController.dispose();
    _bleService.disconnect();
    super.dispose();
  }

  Future<void> _initializeBle() async {
    _bleService.onAlertReceived = (message) {
      _handleIncomingMessage(message);
    };

    _bleService.addListener(() {
      if (mounted) {
        setState(() {});
        if (_bleService.state == BleConnectionState.connected &&
            !_connectionAnnounced) {
          _connectionAnnounced = true;
          _voiceService.speak(
            'স্মার্ট ক্যান সংযুক্ত। Smart Cane connected via Bluetooth.',
          );
        } else if (_bleService.state == BleConnectionState.disconnected &&
            _connectionAnnounced) {
          _connectionAnnounced = false;
        }
      }
    });

    await _bleService.initialize();
  }

  void _handleIncomingMessage(String message) {
    if (!mounted) return;
    final alert = BleAlert.parse(message);

    // Update displayed alert and reset the auto-clear timer.
    // Pi sends every 3 s while the object is in scene; 5 s timeout means
    // the card disappears ~2 s after the object leaves the frame.
    _alertClearTimer?.cancel();
    setState(() => _currentAlert = alert);
    _alertClearTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _currentAlert = null);
    });

    // Trigger bounce animation
    _alertAnimController.forward(from: 0);

    // Vibrate based on severity
    _vibrateForAlert(alert);

    // Speak the alert
    final speechText = alert.objectName.isNotEmpty && alert.position.isNotEmpty
        ? '${alert.level}: ${alert.objectName} detected at ${alert.position}'
        : message;
    _voiceService.speak(speechText);
  }

  Future<void> _vibrateForAlert(BleAlert alert) async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;

    if (alert.isCritical) {
      // Three strong pulses — pattern: [delay, on, off, on, off, on]
      Vibration.vibrate(pattern: [0, 400, 150, 400, 150, 400]);
    } else if (alert.isWarning) {
      // Two medium pulses
      Vibration.vibrate(pattern: [0, 250, 120, 250]);
    } else {
      // Single short pulse for caution
      Vibration.vibrate(duration: 150);
    }
  }

  Future<void> _initializeServices() async {
    await _voiceService.initialize();
    if (mounted) setState(() => _isInitialized = true);
    await Future.delayed(const Duration(milliseconds: 500));
    await _voiceService.speak(
      'স্মার্ট ক্যান অ্যাপে স্বাগতম। বলুন কোথায় যেতে চান। Welcome to Smart Cane. Say where you want to go.',
    );
  }

  void _setupNavigationCallback() {
    _voiceService.onNavigationAction = (action) {
      switch (action) {
        case VoiceAction.navigateHome:
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
          _voiceService.speak(
            'সময় ${now.hour}:${now.minute}। Time is ${now.format(context)}.',
          );
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

  // ── Alert banner colours / icons ──────────────────────────────────────────

  Color _alertColor(BleAlert? alert) {
    if (alert == null) return AppColors.info;
    if (alert.isCritical) return AppColors.error;
    if (alert.isWarning) return AppColors.warning;
    return AppColors.info;
  }

  IconData _alertIcon(BleAlert? alert) {
    if (alert == null) return Icons.notifications_active;
    if (alert.isCritical) return Icons.warning_rounded;
    if (alert.isWarning) return Icons.error_outline_rounded;
    return Icons.info_outline_rounded;
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildAlertCard() {
    final alert = _currentAlert;
    final color = _alertColor(alert);

    return ScaleTransition(
      scale: _alertScale,
      child: FadeTransition(
        opacity: _alertOpacity,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppConstants.radiusM),
            border: Border.all(color: color, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Level header strip
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingM,
                  vertical: AppConstants.spacingS,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(AppConstants.radiusM - 2),
                    topRight: Radius.circular(AppConstants.radiusM - 2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(_alertIcon(alert), color: Colors.white, size: 20),
                    SizedBox(width: AppConstants.spacingS),
                    Text(
                      alert?.level ?? 'ALERT',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    if (alert?.confidence.isNotEmpty ?? false)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          alert!.confidence,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Object name + position
              Padding(
                padding: EdgeInsets.all(AppConstants.spacingM),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alert?.objectName ?? '',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          if (alert?.position.isNotEmpty ?? false) ...[
                            SizedBox(height: AppConstants.spacingXs),
                            Row(
                              children: [
                                Icon(
                                  Icons.navigation_rounded,
                                  size: 14,
                                  color: AppColors.textSecondary,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  alert!.position.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Big level icon
                    Icon(_alertIcon(alert), color: color, size: 48),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBleCard() {
    return Card(
      elevation: 4,
      color: _bleService.isConnected
          ? AppColors.success.withValues(alpha: 0.08)
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
        side: BorderSide(
          color: _bleService.isConnected
              ? AppColors.success
              : _bleService.state == BleConnectionState.bluetoothOff
                  ? AppColors.error.withValues(alpha: 0.5)
                  : AppColors.primary.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(AppConstants.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection header
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
                        'ব্লুটুথ কানেকশন / BLE',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
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
                // Status dot
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
                                : AppColors.warning)
                            .withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (!_bleService.isConnected &&
                _bleService.state != BleConnectionState.scanning) ...[
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
                    padding:
                        EdgeInsets.symmetric(vertical: AppConstants.spacingM),
                  ),
                ),
              ),
            ],

            if (_bleService.isScanning) ...[
              SizedBox(height: AppConstants.spacingM),
              const LinearProgressIndicator(),
            ],

            // Alert card — shown while an object is in scene, cleared after 5 s
            if (_currentAlert != null) ...[
              SizedBox(height: AppConstants.spacingM),
              Divider(color: AppColors.primary.withValues(alpha: 0.2)),
              SizedBox(height: AppConstants.spacingS),
              Text(
                'সর্বশেষ সতর্কতা / Latest Alert',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              SizedBox(height: AppConstants.spacingS),
              _buildAlertCard(),
            ],
          ],
        ),
      ),
    );
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
                      color: Colors.white.withValues(alpha: 0.9),
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
                  // ── Voice indicator card ──────────────────────────────────
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
                          Text(
                            _voiceService.isProcessing
                                ? 'চিন্তা করছি...'
                                : _voiceService.isListening
                                    ? 'শুনছি...'
                                    : 'ভয়েস কমান্ড',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
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
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                          if (_voiceService.currentTranscript.isNotEmpty) ...[
                            SizedBox(height: AppConstants.spacingM),
                            Container(
                              padding: EdgeInsets.all(AppConstants.spacingM),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusM),
                              ),
                              child: Text(
                                '"${_voiceService.currentTranscript}"',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(fontStyle: FontStyle.italic),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                          if (_voiceService.lastResponse.isNotEmpty &&
                              !_voiceService.isListening &&
                              !_voiceService.isProcessing) ...[
                            SizedBox(height: AppConstants.spacingM),
                            Container(
                              padding: EdgeInsets.all(AppConstants.spacingM),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusM),
                                border: Border.all(
                                  color:
                                      AppColors.success.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle,
                                      color: AppColors.success),
                                  SizedBox(width: AppConstants.spacingS),
                                  Expanded(
                                    child: Text(
                                      _voiceService.lastResponse,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          SizedBox(height: AppConstants.spacingL),
                          FilledButton.icon(
                            onPressed:
                                _isInitialized ? _toggleVoiceListening : null,
                            icon: Icon(_voiceService.isListening
                                ? Icons.mic_off
                                : Icons.mic),
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

                  // ── BLE + alert card ──────────────────────────────────────
                  _buildBleCard(),

                  SizedBox(height: AppConstants.spacingXl),

                  // ── Test command ──────────────────────────────────────────
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
                                onPressed: () {},
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

                  // ── Navigation grid ───────────────────────────────────────
                  Semantics(
                    header: true,
                    label: 'নেভিগেশন অপশন। Navigation options.',
                    child: Text(
                      'কোথায় যেতে চান? / Where to go?',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  SizedBox(height: AppConstants.spacingL),

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
                        onPressed: () =>
                            Navigator.pushNamed(context, AppRoutes.location),
                        color: AppColors.info,
                      ),
                      AccessibleActionButton(
                        icon: Icons.settings,
                        label: 'সেটিংস',
                        labelEn: 'Settings',
                        semanticHint: 'সেটিংস খুলুন।',
                        onPressed: () =>
                            Navigator.pushNamed(context, AppRoutes.settings),
                        color: AppColors.primary,
                      ),
                      AccessibleActionButton(
                        icon: Icons.help_outline,
                        label: 'সাহায্য',
                        labelEn: 'Help',
                        semanticHint: 'সাহায্য এবং টিউটোরিয়াল।',
                        onPressed: () =>
                            Navigator.pushNamed(context, AppRoutes.help),
                        color: AppColors.success,
                      ),
                      AccessibleActionButton(
                        icon: Icons.battery_charging_full,
                        label: 'ব্যাটারি',
                        labelEn: 'Battery',
                        semanticHint: 'ব্যাটারি স্ট্যাটাস।',
                        onPressed: () {
                          _voiceService.speak(
                            'ব্যাটারি ৮৫ শতাংশ। Battery is 85 percent.',
                          );
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
