import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/voice_announcer.dart';
import '../../services/location_service.dart';
import '../../services/sensor_fusion_service.dart';
import '../widgets/info_card.dart';

/// Location screen: fetches GPS + address and — voice first — *speaks* the
/// result. The screen text mirrors what is spoken, never replaces it: a blind
/// user must get the answer without touching or reading anything.
class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final LocationService _locationService = LocationService.instance;

  String _latitude = '--';
  String _longitude = '--';
  String _address = 'অবস্থান লোড হচ্ছে...';

  /// Short spoken form of the address; kept so "ঠিকানা বলুন" can re-announce
  /// without re-fetching.
  String _spokenAddress = '';
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Own the audio channel while mounted (SOS pattern): the address readout
    // arrives *seconds* after entry (GPS + geocoding), and fusion's obstacle
    // callouts would interrupt it — TTS is last-writer-wins. The sonar
    // CRITICAL alarm is independent and still gets through.
    SensorFusionService.instance.holdUiAudio(this);
    // Orient the user, then fetch. The entry line is short so the address
    // announcement (seconds later, after GPS + geocoding) never collides.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VoiceAnnouncer.announce('অবস্থান পেইজ। জিপিএস থেকে অবস্থান নিচ্ছি।');
      _fetchLocation();
    });
  }

  @override
  void dispose() {
    SensorFusionService.instance.releaseUiAudio(this);
    super.dispose();
  }

  /// Speak the fetched address — the entire point of this screen for a blind
  /// user. Repeatable via the "ঠিকানা বলুন" button.
  void _announceLocation() {
    if (_spokenAddress.isEmpty) {
      VoiceAnnouncer.announce('ঠিকানা এখনো পাওয়া যায়নি।');
      return;
    }
    VoiceAnnouncer.announce('আপনি এখন $_spokenAddress এলাকায় আছেন।');
  }

  Future<void> _fetchLocation() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    final locationData = await _locationService.getCurrentLocation();

    if (!mounted) return;

    if (locationData != null) {
      setState(() {
        _latitude = locationData.latitudeFormatted;
        _longitude = locationData.longitudeFormatted;
        _address = locationData.addressBn;
        _spokenAddress = locationData.addressSpoken;
        _isLoading = false;
        _hasError = false;
      });
      _announceLocation();
    } else {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage =
            'অবস্থান পাওয়া যায়নি। জিপিএস চালু করুন এবং অনুমতি দিন।';
        _latitude = '--';
        _longitude = '--';
        _address = 'অবস্থান পাওয়া যায়নি';
        _spokenAddress = '';
      });
      // The error must be *heard*, not just shown — and end with a way
      // forward so it is never a dead end.
      VoiceAnnouncer.announce(
        'অবস্থান পাওয়া যায়নি। জিপিএস চালু আছে কি না দেখুন, '
        'তারপর রিফ্রেশ বোতাম চাপুন।',
      );
    }
  }

  Future<void> _refreshLocation() async {
    VoiceAnnouncer.announce('অবস্থান আবার নিচ্ছি।');
    await _fetchLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          label: 'আমার অবস্থান',
          child: const Text('আমার অবস্থান'),
        ),
        actions: [
          Semantics(
            button: true,
            label: 'অবস্থান রিফ্রেশ করুন',
            child: IconButton(
              icon: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _refreshLocation,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppConstants.spacingL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Error Banner (if permission denied)
              if (_hasError)
                Container(
                  margin: EdgeInsets.only(bottom: AppConstants.spacingL),
                  padding: EdgeInsets.all(AppConstants.spacingL),
                  decoration: BoxDecoration(
                    color: AppColors.error.withAlpha(25),
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    border: Border.all(
                      color: AppColors.error.withAlpha(77),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.location_off,
                            color: AppColors.error,
                            size: AppConstants.iconL,
                          ),
                          SizedBox(width: AppConstants.spacingM),
                          Expanded(
                            child: Text(
                              _errorMessage,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: AppConstants.spacingM),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _locationService.openLocationSettings(),
                              icon: const Icon(Icons.settings),
                              label: const Text('জিপিএস সেটিংস'),
                            ),
                          ),
                          SizedBox(width: AppConstants.spacingS),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _locationService.openAppSettings(),
                              icon: const Icon(Icons.app_settings_alt),
                              label: const Text('অ্যাপ অনুমতি'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              // Loading Indicator
              if (_isLoading)
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withAlpha(77),
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        SizedBox(height: AppConstants.spacingL),
                        Text(
                          'জিপিএস থেকে অবস্থান নেওয়া হচ্ছে...',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),

              if (_isLoading) SizedBox(height: AppConstants.spacingXl),

              // Address Section — the primary answer, first on the page.
              Semantics(
                header: true,
                label: 'ঠিকানার তথ্য',
                child: Text(
                  'ঠিকানা',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),

              SizedBox(height: AppConstants.spacingL),

              Card(
                elevation: 2,
                child: Padding(
                  padding: EdgeInsets.all(AppConstants.spacingL),
                  child: Semantics(
                    label: 'আপনার ঠিকানা: $_address',
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(AppConstants.spacingL),
                          decoration: BoxDecoration(
                            color: AppColors.info.withAlpha(25),
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusM,
                            ),
                          ),
                          child: Icon(
                            Icons.location_city,
                            size: AppConstants.iconXl,
                            color: AppColors.info,
                          ),
                        ),
                        SizedBox(width: AppConstants.spacingL),
                        Expanded(
                          child: Text(
                            _address,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              SizedBox(height: AppConstants.spacingL),

              // Primary action: hear the address again. Full-width, first in
              // focus order after the address — the button a blind user wants.
              FilledButton.icon(
                onPressed: _isLoading ? null : _announceLocation,
                icon: const Icon(Icons.volume_up),
                label: const Text('ঠিকানা বলুন'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(
                    AppConstants.minTouchTargetSize,
                  ),
                  padding: EdgeInsets.symmetric(
                    vertical: AppConstants.spacingL,
                  ),
                ),
              ),

              SizedBox(height: AppConstants.spacingXl),

              // Coordinates Section — secondary detail, useful when relaying
              // the position to a sighted helper or emergency services.
              Semantics(
                header: true,
                label: 'স্থানাঙ্ক',
                child: Text(
                  'স্থানাঙ্ক',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),

              SizedBox(height: AppConstants.spacingL),

              InfoCard(
                icon: Icons.north,
                title: 'অক্ষাংশ',
                titleEn: 'অক্ষাংশ',
                value: _latitude,
                color: AppColors.success,
                semanticLabel: 'অক্ষাংশ: $_latitude',
              ),

              SizedBox(height: AppConstants.spacingM),

              InfoCard(
                icon: Icons.east,
                title: 'দ্রাঘিমাংশ',
                titleEn: 'দ্রাঘিমাংশ',
                value: _longitude,
                color: AppColors.warning,
                semanticLabel: 'দ্রাঘিমাংশ: $_longitude',
              ),

              SizedBox(height: AppConstants.spacingXl),

              // Info Box
              Container(
                padding: EdgeInsets.all(AppConstants.spacingL),
                decoration: BoxDecoration(
                  color: AppColors.info.withAlpha(25),
                  borderRadius: BorderRadius.circular(AppConstants.radiusM),
                  border: Border.all(
                    color: AppColors.info.withAlpha(77),
                    width: 1,
                  ),
                ),
                child: Semantics(
                  label:
                      'জিপিএস ইন্টারনেট ছাড়াই কাজ করে, ঠিকানার জন্য ইন্টারনেট লাগে।',
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.info,
                        size: AppConstants.iconL,
                      ),
                      SizedBox(width: AppConstants.spacingM),
                      Expanded(
                        child: Text(
                          'জিপিএস অফলাইনে কাজ করে, ঠিকানার জন্য ইন্টারনেট লাগে',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
