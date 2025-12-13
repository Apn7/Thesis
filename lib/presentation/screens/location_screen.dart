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
  String _addressEn = 'Loading location...';
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
    debugPrint('Location: $_address, $_addressEn');
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
        _addressEn = locationData.addressEn;
        _isLoading = false;
        _hasError = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('অবস্থান পাওয়া গেছে / Location found'),
          duration: Duration(seconds: 2),
        ),
      );
      _announceLocation();
    } else {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'অবস্থান পাওয়া যায়নি। অনুগ্রহ করে GPS চালু করুন এবং অনুমতি দিন।';
        _latitude = '--';
        _longitude = '--';
        _address = 'অবস্থান পাওয়া যায়নি';
        _addressEn = 'Location not available';
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
          label: 'আমার অবস্থান। My Location',
          child: const Column(
            children: [
              Text('আমার অবস্থান'),
              Text(
                'My Location',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          Semantics(
            button: true,
            label: 'রিফ্রেশ করুন। Refresh location',
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
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: AppConstants.spacingM),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _locationService.openLocationSettings(),
                              icon: const Icon(Icons.settings),
                              label: const Text('GPS সেটিংস'),
                            ),
                          ),
                          SizedBox(width: AppConstants.spacingS),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _locationService.openAppSettings(),
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
                          'GPS থেকে অবস্থান নেওয়া হচ্ছে...',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Getting location from GPS...',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
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
                      label: 'মানচিত্র প্রদর্শন। ভবিষ্যতে সক্রিয় হবে। Map display. Will be active in future.',
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
                              'মানচিত্র এখানে থাকবে',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Map will appear here',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
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
                label: 'ঠিকানা তথ্য। Address information',
                child: Text(
                  'ঠিকানা / Address',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              SizedBox(height: AppConstants.spacingL),
              
              Card(
                elevation: 2,
                child: Padding(
                  padding: EdgeInsets.all(AppConstants.spacingL),
                  child: Semantics(
                    label: 'আপনার ঠিকানা: $_address, $_addressEn',
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(AppConstants.spacingL),
                          decoration: BoxDecoration(
                            color: AppColors.info.withAlpha(25),
                            borderRadius: BorderRadius.circular(AppConstants.radiusM),
                          ),
                          child: Icon(
                            Icons.location_city,
                            size: AppConstants.iconXl,
                            color: AppColors.info,
                          ),
                        ),
                        SizedBox(width: AppConstants.spacingL),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _address,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: AppConstants.spacingXs),
                              Text(
                                _addressEn,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
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
                label: 'স্থানাঙ্ক। Coordinates',
                child: Text(
                  'স্থানাঙ্ক / Coordinates',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              SizedBox(height: AppConstants.spacingL),
              
              InfoCard(
                icon: Icons.north,
                title: 'অক্ষাংশ',
                titleEn: 'Latitude',
                value: _latitude,
                color: AppColors.success,
                semanticLabel: 'অক্ষাংশ, Latitude: $_latitude',
              ),
              
              SizedBox(height: AppConstants.spacingM),
              
              InfoCard(
                icon: Icons.east,
                title: 'দ্রাঘিমাংশ',
                titleEn: 'Longitude',
                value: _longitude,
                color: AppColors.warning,
                semanticLabel: 'দ্রাঘিমাংশ, Longitude: $_longitude',
              ),
              
              SizedBox(height: AppConstants.spacingXl),
              
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isLoading ? null : _refreshLocation,
                      icon: const Icon(Icons.my_location),
                      label: const Text('আবার পড়ুন\nRefresh'),
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
                            content: Text('অবস্থান সংরক্ষিত / Location saved'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('সংরক্ষণ\nSave'),
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
                  label: 'তথ্য: GPS অবস্থান অফলাইনে কাজ করে, ঠিকানার জন্য ইন্টারনেট প্রয়োজন। GPS location works offline, address requires internet.',
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.info,
                        size: AppConstants.iconL,
                      ),
                      SizedBox(width: AppConstants.spacingM),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '💡 GPS অবস্থান অফলাইনে কাজ করে',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: AppConstants.spacingXs),
                            Text(
                              'GPS works offline, address needs internet',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
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
