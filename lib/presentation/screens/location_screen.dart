import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../services/location_service.dart';
import '../widgets/info_card.dart';

/// Location screen displaying GPS coordinates and address
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
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Fetch location on screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLocation();
    });
  }

  void _announceLocation() {
    debugPrint('Location: $_address');
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
        _address = locationData.addressEn;
        _isLoading = false;
        _hasError = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('অবস্থান পাওয়া গেছে'),
          duration: Duration(seconds: 2),
        ),
      );
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
      });
    }
  }

  Future<void> _refreshLocation() async {
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
                  height: 200,
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

              // Map Placeholder (when not loading)
              if (!_isLoading)
                Card(
                  elevation: 4,
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withAlpha(77),
                      borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    ),
                    child: Semantics(
                      label: 'মানচিত্র। ভবিষ্যতে চালু হবে।',
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.map,
                              size: AppConstants.iconXxl,
                              color: AppColors.primary,
                            ),
                            SizedBox(height: AppConstants.spacingM),
                            Text(
                              'মানচিত্র এখানে আসবে',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              SizedBox(height: AppConstants.spacingXl),

              // Address Section
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

              SizedBox(height: AppConstants.spacingXl),

              // Coordinates Section
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

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isLoading ? null : _refreshLocation,
                      icon: const Icon(Icons.my_location),
                      label: const Text('রিফ্রেশ'),
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: AppConstants.spacingL,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: AppConstants.spacingM),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('অবস্থান সংরক্ষণ করা হয়েছে'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('সংরক্ষণ'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: AppConstants.spacingL,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: AppConstants.spacingL),

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
                  label: 'জিপিএস ইন্টারনেট ছাড়াই কাজ করে, ঠিকানার জন্য ইন্টারনেট লাগে।',
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
