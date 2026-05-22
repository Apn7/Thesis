import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../core/navigation/app_routes.dart';
// import '../../services/ble_service.dart'; // Pi BLE — disabled
import '../../services/esp_ble_service.dart';
import '../../services/voice_navigation_service.dart';
import '../widgets/accessible_action_button.dart';
import '../widgets/colorful_waveform.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final VoiceNavigationService _voiceService = VoiceNavigationService.instance;
  // final BleService _bleService = BleService.instance; // Pi BLE — disabled
  final EspBleService _espBleService = EspBleService.instance;
  bool _isInitialized = false;
  // bool _connectionAnnounced = false; // Pi BLE — disabled
  bool _espConnectionAnnounced = false;

  // Pi alert state — disabled
  // BleAlert? _currentAlert;
  // Timer? _alertClearTimer;

  // Pi alert animation — disabled
  // late final AnimationController _alertAnimController;
  // late final Animation<double> _alertScale;
  // late final Animation<double> _alertOpacity;

  /// Repeating vibration timer for CRITICAL / WARNING — keeps the phone
  /// buzzing while the obstacle stays in range.  CAUTION uses a one-shot
  /// pulse and leaves this null.
  Timer? _vibrationTimer;

  /// Last verdict observed, used to fire speech (and the alert tone) only
  /// when severity strictly increases.  De-escalation and return-to-safe
  /// are silent — the user already knows the situation is improving.
  EspVerdict _lastEspVerdict = EspVerdict.noData;

  /// Pre-loaded player for the CRITICAL alert tone.  Preloading at init
  /// avoids first-play latency at the moment the user most needs immediate
  /// feedback.
  final AudioPlayer _alertPlayer = AudioPlayer();
  bool _alertReady = false;

  @override
  void initState() {
    super.initState();

    // Pi alert animation setup — disabled
    // _alertAnimController = AnimationController(
    //   vsync: this,
    //   duration: const Duration(milliseconds: 400),
    // );
    // _alertScale = CurvedAnimation(
    //   parent: _alertAnimController,
    //   curve: Curves.elasticOut,
    // );
    // _alertOpacity = CurvedAnimation(
    //   parent: _alertAnimController,
    //   curve: Curves.easeIn,
    // );

    _initializeServices();
    _setupNavigationCallback();
    _prepareAlertPlayer();
    // Pi BLE init — disabled
    // if (AppConstants.enablePiBle) {
    //   _initializeBle();
    // }
    if (AppConstants.enableEspBle) {
      _initializeEspBle();
    }
  }

  @override
  void dispose() {
    _vibrationTimer?.cancel();
    Vibration.cancel(); // stop any ongoing vibration immediately
    _alertPlayer.dispose();
    // _alertClearTimer?.cancel();       // Pi BLE — disabled
    // _alertAnimController.dispose();   // Pi BLE — disabled
    // if (AppConstants.enablePiBle) {   // Pi BLE — disabled
    //   _bleService.disconnect();
    // }
    if (AppConstants.enableEspBle) {
      _espBleService.disconnect();
    }
    super.dispose();
  }

  // ── Pi BLE initialisation — disabled ─────────────────────────────────────
  // Future<void> _initializeBle() async {
  //   _bleService.onAlertReceived = (message) {
  //     _handleIncomingMessage(message);
  //   };
  //
  //   _bleService.addListener(() {
  //     if (mounted) {
  //       setState(() {});
  //       if (_bleService.state == BleConnectionState.connected &&
  //           !_connectionAnnounced) {
  //         _connectionAnnounced = true;
  //         _voiceService.speak(
  //           'স্মার্ট ক্যান সংযুক্ত। Smart Cane connected via Bluetooth.',
  //         );
  //       } else if (_bleService.state == BleConnectionState.disconnected &&
  //           _connectionAnnounced) {
  //         _connectionAnnounced = false;
  //       }
  //     }
  //   });
  //
  //   await _bleService.initialize();
  // }

  Future<void> _initializeEspBle() async {
    _espBleService.onVerdictChanged = (verdict) {
      if (!mounted) return;

      final previous = _lastEspVerdict;
      _lastEspVerdict = verdict;

      // Any move away from CRITICAL stops the alert tone — the alarm has
      // done its job, no need to keep blaring while the user steps back.
      // (Re-escalation into CRITICAL restarts the tone from the top.)
      if (verdict != EspVerdict.critical) {
        _stopAlertTone();
      }

      // Path is clear — silence + stop buzzing.  No "all clear" message;
      // absence of warning IS the all-clear signal, and announcing it
      // would just add noise after every obstacle the user clears.
      if (verdict == EspVerdict.safe || verdict == EspVerdict.noData) {
        _vibrationTimer?.cancel();
        _vibrationTimer = null;
        Vibration.cancel();
        _voiceService.stopSpeaking();
        return;
      }

      // Drive vibration first — the lifeline channel.  Always (re)set on
      // verdict change so the pattern matches the *current* level (e.g.
      // CRITICAL → WARNING relaxes the buzz without speaking).
      _vibrateForVerdict(verdict);

      // Escalation only: severity strictly increased since last reading.
      // Combine the level word with the live distance so a single short
      // utterance carries actionable info ("কাছে ১৫০ সেন্টিমিটার").
      // De-escalation stays silent — the slower vibration already tells
      // the user the situation improved.
      if (verdict.severity > previous.severity) {
        final speech = _escalationSpeech(verdict);
        if (speech.isNotEmpty) {
          _voiceService.speak(speech);
        }
        // Distinctive alarm tone — reserved for CRITICAL so the sound
        // itself becomes the user's "stop right now" cue.  Used sparingly
        // so it never becomes background noise.
        if (verdict == EspVerdict.critical) {
          _playAlertTone();
        }
      }
    };

    _espBleService.addListener(() {
      if (!mounted) return;
      setState(() {});
      if (_espBleService.state == EspBleState.connected &&
          !_espConnectionAnnounced) {
        _espConnectionAnnounced = true;
        _voiceService.speak('ESP32 সেন্সর সংযুক্ত। ESP32 sensor connected.');
      } else if (_espBleService.state == EspBleState.disconnected &&
          _espConnectionAnnounced) {
        _espConnectionAnnounced = false;
        _vibrationTimer?.cancel();
        _vibrationTimer = null;
        Vibration.cancel();
        _voiceService.stopSpeaking();
        _stopAlertTone();
        _lastEspVerdict = EspVerdict.noData;
        _voiceService.speak(
          'ESP32 সেন্সর বিচ্ছিন্ন। ESP32 sensor disconnected.',
        );
      }
    });

    await _espBleService.initialize();
  }

  // ── Pi incoming message handler — disabled ────────────────────────────────
  // void _handleIncomingMessage(String message) {
  //   if (!mounted) return;
  //   final alert = BleAlert.parse(message);
  //
  //   _alertClearTimer?.cancel();
  //   setState(() => _currentAlert = alert);
  //   _alertClearTimer = Timer(const Duration(seconds: 5), () {
  //     if (mounted) setState(() => _currentAlert = null);
  //   });
  //
  //   _alertAnimController.forward(from: 0);
  //   _vibrateForAlert(alert);
  //
  //   final speechText = alert.objectName.isNotEmpty && alert.position.isNotEmpty
  //       ? '${alert.level}: ${alert.objectName} detected at ${alert.position}'
  //       : message;
  //   _voiceService.speak(speechText);
  // }

  // Future<void> _vibrateForAlert(BleAlert alert) async {
  //   final hasVibrator = await Vibration.hasVibrator();
  //   if (hasVibrator != true) return;
  //
  //   if (alert.isCritical) {
  //     Vibration.vibrate(pattern: [0, 400, 150, 400, 150, 400]);
  //   } else if (alert.isWarning) {
  //     Vibration.vibrate(pattern: [0, 250, 120, 250]);
  //   } else {
  //     Vibration.vibrate(duration: 150);
  //   }
  // }

  /// Bangla-digit conversion (০-৯) so spoken distances pronounce correctly
  /// in Bangla TTS — ASCII digits often get read in English even inside an
  /// otherwise-Bangla utterance.
  String _bnDigits(int n) {
    const bn = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    return n.toString().split('').map((d) => bn[int.parse(d)]).join();
  }

  /// Build the escalation utterance: level word + live distance rounded to
  /// 10 cm.  Rounding stabilises the announcement near threshold boundaries
  /// (47 cm and 53 cm both say "৫০") and keeps the spoken number short.
  String _escalationSpeech(EspVerdict v) {
    final base = v.speechText;
    if (base.isEmpty) return '';
    final d = _espBleService.latestDistance;
    if (d == null || d <= 0) return base;
    final rounded = (d / 10).round() * 10;
    return '$base ${_bnDigits(rounded)} সেন্টিমিটার';
  }

  /// Trigger phone vibration matching the current ESP32 distance verdict.
  ///
  /// CAUTION  — single light pulse ("heads up"), no loop.
  /// WARNING  — medium double pulse + a 1.5 s repeat — clear but not panicky.
  /// CRITICAL — aggressive 5-pulse opening burst then a ~90 % duty cycle
  ///            loop (450 ms vibrate every 500 ms).  Effectively continuous;
  ///            paired with the alert tone, this is the user's "stop now"
  ///            signal even if the phone is buried in a bag.
  void _vibrateForVerdict(EspVerdict verdict) async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;

    // Clear any prior loop / pattern before starting the new one.
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    Vibration.cancel();

    switch (verdict) {
      case EspVerdict.critical:
        // Near-continuous opening burst: five 600 ms pulses separated by
        // only 80 ms gaps — feels like one long shake with texture.
        Vibration.vibrate(
          pattern: [0, 600, 80, 600, 80, 600, 80, 600, 80, 600],
        );
        // Sustained ~90 % duty cycle loop: 450 ms vibrate every 500 ms.
        // Impossible to ignore even through a backpack.
        _vibrationTimer = Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => Vibration.vibrate(duration: 450),
        );
        break;
      case EspVerdict.warning:
        // Medium double pulse, then a 1.5 s repeat.
        Vibration.vibrate(pattern: [0, 250, 120, 250]);
        _vibrationTimer = Timer.periodic(
          const Duration(milliseconds: 1500),
          (_) => Vibration.vibrate(duration: 250),
        );
        break;
      case EspVerdict.caution:
        // Triple light tap — distinctive 'tic-tic-tic' rhythm so the user
        // can tell CAUTION apart from WARNING's heavier double-pulse and
        // CRITICAL's continuous shake by feel alone.  Loop every 2.5 s as
        // a gentle background reminder for distant obstacles — frequent
        // enough to keep awareness, sparse enough not to nag.
        const cautionPattern = [0, 80, 80, 80, 80, 80];
        Vibration.vibrate(pattern: cautionPattern);
        _vibrationTimer = Timer.periodic(
          const Duration(milliseconds: 2500),
          (_) => Vibration.vibrate(pattern: cautionPattern),
        );
        break;
      case EspVerdict.safe:
      case EspVerdict.noData:
        // Caller guards, but cancel for safety.
        Vibration.cancel();
        break;
    }
  }

  /// Preload assets/alerts/alert.wav so the first play-on-CRITICAL has no
  /// startup lag — the moment the user most needs immediate feedback.
  /// Failures degrade gracefully: vibration + speech still fire.
  Future<void> _prepareAlertPlayer() async {
    try {
      await _alertPlayer.setReleaseMode(ReleaseMode.stop);
      await _alertPlayer.setSource(AssetSource('alerts/alert.wav'));
      _alertReady = true;
    } catch (e) {
      debugPrint('>> Alert player prep failed: $e');
    }
  }

  /// Play the CRITICAL alert tone from the start.  Stops any in-flight
  /// playback first so re-entering CRITICAL within the tone's duration
  /// restarts cleanly instead of overlapping.
  Future<void> _playAlertTone() async {
    if (!_alertReady) return;
    try {
      await _alertPlayer.stop();
      await _alertPlayer.seek(Duration.zero);
      await _alertPlayer.resume();
    } catch (e) {
      debugPrint('>> Alert play failed: $e');
    }
  }

  /// Stop the CRITICAL alert tone immediately.  Called on any transition
  /// away from CRITICAL — de-escalation, path clear, or sensor disconnect —
  /// so the long WAV does not keep blaring after the user has cleared the
  /// danger zone.  Fire-and-forget; errors are logged but do not bubble.
  Future<void> _stopAlertTone() async {
    try {
      await _alertPlayer.stop();
    } catch (e) {
      debugPrint('>> Alert stop failed: $e');
    }
  }

  Future<void> _initializeServices() async {
    await _voiceService.initialize();
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

  // ── Pi alert banner helpers — disabled ────────────────────────────────────
  // Color _alertColor(BleAlert? alert) {
  //   if (alert == null) return AppColors.info;
  //   if (alert.isCritical) return AppColors.error;
  //   if (alert.isWarning) return AppColors.warning;
  //   return AppColors.info;
  // }
  //
  // IconData _alertIcon(BleAlert? alert) {
  //   if (alert == null) return Icons.notifications_active;
  //   if (alert.isCritical) return Icons.warning_rounded;
  //   if (alert.isWarning) return Icons.error_outline_rounded;
  //   return Icons.info_outline_rounded;
  // }

  // ── Widgets ───────────────────────────────────────────────────────────────

  // Pi alert card — disabled
  // Widget _buildAlertCard() {
  //   final alert = _currentAlert;
  //   final color = _alertColor(alert);
  //
  //   return ScaleTransition(
  //     scale: _alertScale,
  //     child: FadeTransition(
  //       opacity: _alertOpacity,
  //       child: Container(
  //         width: double.infinity,
  //         decoration: BoxDecoration(
  //           color: color.withValues(alpha: 0.12),
  //           borderRadius: BorderRadius.circular(AppConstants.radiusM),
  //           border: Border.all(color: color, width: 2),
  //         ),
  //         child: Column(
  //           crossAxisAlignment: CrossAxisAlignment.stretch,
  //           children: [
  //             Container(
  //               padding: EdgeInsets.symmetric(
  //                 horizontal: AppConstants.spacingM,
  //                 vertical: AppConstants.spacingS,
  //               ),
  //               decoration: BoxDecoration(
  //                 color: color,
  //                 borderRadius: BorderRadius.only(
  //                   topLeft: Radius.circular(AppConstants.radiusM - 2),
  //                   topRight: Radius.circular(AppConstants.radiusM - 2),
  //                 ),
  //               ),
  //               child: Row(
  //                 children: [
  //                   Icon(_alertIcon(alert), color: Colors.white, size: 20),
  //                   SizedBox(width: AppConstants.spacingS),
  //                   Text(
  //                     alert?.level ?? 'ALERT',
  //                     style: const TextStyle(
  //                       color: Colors.white,
  //                       fontWeight: FontWeight.bold,
  //                       fontSize: 13,
  //                       letterSpacing: 1.2,
  //                     ),
  //                   ),
  //                   const Spacer(),
  //                   if (alert?.confidence.isNotEmpty ?? false)
  //                     Container(
  //                       padding: const EdgeInsets.symmetric(
  //                         horizontal: 8,
  //                         vertical: 2,
  //                       ),
  //                       decoration: BoxDecoration(
  //                         color: Colors.white.withValues(alpha: 0.25),
  //                         borderRadius: BorderRadius.circular(20),
  //                       ),
  //                       child: Text(
  //                         alert!.confidence,
  //                         style: const TextStyle(
  //                           color: Colors.white,
  //                           fontSize: 12,
  //                           fontWeight: FontWeight.w600,
  //                         ),
  //                       ),
  //                     ),
  //                 ],
  //               ),
  //             ),
  //             Padding(
  //               padding: EdgeInsets.all(AppConstants.spacingM),
  //               child: Row(
  //                 crossAxisAlignment: CrossAxisAlignment.center,
  //                 children: [
  //                   Expanded(
  //                     child: Column(
  //                       crossAxisAlignment: CrossAxisAlignment.start,
  //                       children: [
  //                         Text(
  //                           alert?.objectName ?? '',
  //                           style: TextStyle(
  //                             fontSize: 22,
  //                             fontWeight: FontWeight.bold,
  //                             color: color,
  //                           ),
  //                         ),
  //                         if (alert?.position.isNotEmpty ?? false) ...[
  //                           SizedBox(height: AppConstants.spacingXs),
  //                           Row(
  //                             children: [
  //                               Icon(
  //                                 Icons.navigation_rounded,
  //                                 size: 14,
  //                                 color: AppColors.textSecondary,
  //                               ),
  //                               SizedBox(width: 4),
  //                               Text(
  //                                 alert!.position.toUpperCase(),
  //                                 style: TextStyle(
  //                                   fontSize: 13,
  //                                   fontWeight: FontWeight.w600,
  //                                   color: AppColors.textSecondary,
  //                                   letterSpacing: 0.8,
  //                                 ),
  //                               ),
  //                             ],
  //                           ),
  //                         ],
  //                       ],
  //                     ),
  //                   ),
  //                   Icon(_alertIcon(alert), color: color, size: 48),
  //                 ],
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }

  // ── ESP32 distance card ────────────────────────────────────────────────

  Color _verdictColor(EspVerdict v) {
    switch (v) {
      case EspVerdict.critical:
        return AppColors.error;
      case EspVerdict.warning:
        return AppColors.warning;
      case EspVerdict.caution:
        return AppColors.accent;
      case EspVerdict.safe:
        return AppColors.success;
      case EspVerdict.noData:
        return AppColors.textSecondary;
    }
  }

  Widget _buildEspCard() {
    final connected = _espBleService.isConnected;
    final scanning = _espBleService.isScanning;
    final btOff = _espBleService.state == EspBleState.bluetoothOff;
    final v = _espBleService.verdict;
    final d = _espBleService.latestDistance;
    final color = connected ? _verdictColor(v) : AppColors.primary;

    return Card(
      elevation: 4,
      color: connected
          ? color.withValues(alpha: 0.08)
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
        side: BorderSide(
          color: connected
              ? color
              : btOff
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
            // Header
            Row(
              children: [
                Icon(
                  connected
                      ? Icons.sensors
                      : btOff
                      ? Icons.bluetooth_disabled
                      : scanning
                      ? Icons.bluetooth_searching
                      : Icons.sensors_off,
                  color: connected
                      ? color
                      : btOff
                      ? AppColors.error
                      : scanning
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
                        'ESP32 দূরত্ব / Distance',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: AppConstants.spacingXs),
                      Text(
                        _espBleService.statusMessage,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: connected ? color : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connected ? color : AppColors.warning,
                    boxShadow: [
                      BoxShadow(
                        color: (connected ? color : AppColors.warning)
                            .withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (connected) ...[
              SizedBox(height: AppConstants.spacingL),
              // Big distance number + verdict pill
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d == null ? '— cm' : '${d.toStringAsFixed(1)} cm',
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                        ),
                        SizedBox(height: AppConstants.spacingS),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            v.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            if (!connected && !scanning) ...[
              SizedBox(height: AppConstants.spacingM),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _espBleService.startScanning(),
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Scan for ESP32 / স্ক্যান করুন'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary),
                    padding: EdgeInsets.symmetric(
                      vertical: AppConstants.spacingM,
                    ),
                  ),
                ),
              ),
            ],

            if (scanning) ...[
              SizedBox(height: AppConstants.spacingM),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  // ── Pi BLE card — disabled ────────────────────────────────────────────────
  // Widget _buildBleCard() {
  //   return Card(
  //     elevation: 4,
  //     color: _bleService.isConnected
  //         ? AppColors.success.withValues(alpha: 0.08)
  //         : Theme.of(context).colorScheme.surface,
  //     shape: RoundedRectangleBorder(
  //       borderRadius: BorderRadius.circular(AppConstants.radiusM),
  //       side: BorderSide(
  //         color: _bleService.isConnected
  //             ? AppColors.success
  //             : _bleService.state == BleConnectionState.bluetoothOff
  //                 ? AppColors.error.withValues(alpha: 0.5)
  //                 : AppColors.primary.withValues(alpha: 0.3),
  //         width: 2,
  //       ),
  //     ),
  //     child: Padding(
  //       padding: EdgeInsets.all(AppConstants.spacingL),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Row(
  //             children: [
  //               Icon(
  //                 _bleService.isConnected
  //                     ? Icons.bluetooth_connected
  //                     : _bleService.state == BleConnectionState.bluetoothOff
  //                         ? Icons.bluetooth_disabled
  //                         : _bleService.isScanning
  //                             ? Icons.bluetooth_searching
  //                             : Icons.bluetooth,
  //                 color: _bleService.isConnected
  //                     ? AppColors.success
  //                     : _bleService.state == BleConnectionState.bluetoothOff
  //                         ? AppColors.error
  //                         : _bleService.isScanning
  //                             ? AppColors.info
  //                             : AppColors.warning,
  //                 size: 28,
  //               ),
  //               SizedBox(width: AppConstants.spacingM),
  //               Expanded(
  //                 child: Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     Text(
  //                       'ব্লুটুথ কানেকশন / BLE',
  //                       style: Theme.of(context).textTheme.titleMedium
  //                           ?.copyWith(fontWeight: FontWeight.bold),
  //                     ),
  //                     SizedBox(height: AppConstants.spacingXs),
  //                     Text(
  //                       _bleService.statusMessage,
  //                       style: Theme.of(context).textTheme.bodyMedium?.copyWith(
  //                             color: _bleService.isConnected
  //                                 ? AppColors.success
  //                                 : AppColors.textSecondary,
  //                             fontWeight: FontWeight.w500,
  //                           ),
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //               Container(
  //                 width: 12,
  //                 height: 12,
  //                 decoration: BoxDecoration(
  //                   shape: BoxShape.circle,
  //                   color: _bleService.isConnected
  //                       ? AppColors.success
  //                       : _bleService.state == BleConnectionState.bluetoothOff
  //                           ? AppColors.error
  //                           : AppColors.warning,
  //                   boxShadow: [
  //                     BoxShadow(
  //                       color: (_bleService.isConnected
  //                               ? AppColors.success
  //                               : AppColors.warning)
  //                           .withValues(alpha: 0.5),
  //                       blurRadius: 8,
  //                       spreadRadius: 2,
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //             ],
  //           ),
  //           if (!_bleService.isConnected &&
  //               _bleService.state != BleConnectionState.scanning) ...[
  //             SizedBox(height: AppConstants.spacingM),
  //             SizedBox(
  //               width: double.infinity,
  //               child: OutlinedButton.icon(
  //                 onPressed: () => _bleService.startScanning(),
  //                 icon: const Icon(Icons.bluetooth_searching),
  //                 label: const Text('Scan for Smart Cane / স্ক্যান করুন'),
  //                 style: OutlinedButton.styleFrom(
  //                   foregroundColor: AppColors.primary,
  //                   side: BorderSide(color: AppColors.primary),
  //                   padding:
  //                       EdgeInsets.symmetric(vertical: AppConstants.spacingM),
  //                 ),
  //               ),
  //             ),
  //           ],
  //           if (_bleService.isScanning) ...[
  //             SizedBox(height: AppConstants.spacingM),
  //             const LinearProgressIndicator(),
  //           ],
  //           if (_currentAlert != null) ...[
  //             SizedBox(height: AppConstants.spacingM),
  //             Divider(color: AppColors.primary.withValues(alpha: 0.2)),
  //             SizedBox(height: AppConstants.spacingS),
  //             Text(
  //               'সর্বশেষ সতর্কতা / Latest Alert',
  //               style: Theme.of(context).textTheme.labelMedium?.copyWith(
  //                     color: AppColors.textSecondary,
  //                   ),
  //             ),
  //             SizedBox(height: AppConstants.spacingS),
  //             _buildAlertCard(),
  //           ],
  //         ],
  //       ),
  //     ),
  //   );
  // }

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
            return Stack(
              children: [
                SingleChildScrollView(
                  padding: EdgeInsets.all(AppConstants.spacingL).copyWith(
                    bottom: 160,
                  ), // Add padding to bottom so it's not hidden by wave
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Voice interaction hints ──────────────────────────────────
                      Card(
                        elevation: 4,
                        color: Theme.of(context).colorScheme.surface,
                        child: Padding(
                          padding: EdgeInsets.all(AppConstants.spacingXl),
                          child: Column(
                            children: [
                              Icon(
                                Icons.volume_up,
                                size: 48,
                                color: _voiceService.isListening
                                    ? AppColors.accent
                                    : AppColors.primary,
                              ),
                              SizedBox(height: AppConstants.spacingL),
                              Text(
                                _voiceService.isProcessing
                                    ? 'চিন্তা করছি...'
                                    : _voiceService.isListening
                                    ? 'শুনছি...'
                                    : 'ভয়েস কমান্ড',
                                style: Theme.of(context).textTheme.headlineSmall
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
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                              SizedBox(height: AppConstants.spacingM),
                              Text(
                                'কথা বলতে ভলিউম বোতাম চেপে ধরে রাখুন।\nPress and hold the Volume buttons to speak.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                              if (_voiceService
                                  .currentTranscript
                                  .isNotEmpty) ...[
                                SizedBox(height: AppConstants.spacingM),
                                Container(
                                  padding: EdgeInsets.all(
                                    AppConstants.spacingM,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight.withValues(
                                      alpha: 0.2,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppConstants.radiusM,
                                    ),
                                  ),
                                  child: Text(
                                    '"${_voiceService.currentTranscript}"',
                                    style: Theme.of(context).textTheme.bodyLarge
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
                                  padding: EdgeInsets.all(
                                    AppConstants.spacingM,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppConstants.radiusM,
                                    ),
                                    border: Border.all(
                                      color: AppColors.success.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: AppColors.success,
                                      ),
                                      SizedBox(width: AppConstants.spacingS),
                                      Expanded(
                                        child: Text(
                                          _voiceService.lastResponse,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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

                      // ── ESP32 distance card ───────────────────────────────────
                      if (AppConstants.enableEspBle) ...[
                        _buildEspCard(),
                        SizedBox(height: AppConstants.spacingL),
                      ],

                      // ── BLE + alert card (Pi) — disabled ──────────────────────
                      // if (AppConstants.enablePiBle) _buildBleCard(),
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
                          style: Theme.of(context).textTheme.titleLarge
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
                            onPressed: () => Navigator.pushNamed(
                              context,
                              AppRoutes.location,
                            ),
                            color: AppColors.info,
                          ),
                          AccessibleActionButton(
                            icon: Icons.settings,
                            label: 'সেটিংস',
                            labelEn: 'Settings',
                            semanticHint: 'সেটিংস খুলুন।',
                            onPressed: () => Navigator.pushNamed(
                              context,
                              AppRoutes.settings,
                            ),
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
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: ColorfulWaveform(
                      isListening: _voiceService.isListening,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
