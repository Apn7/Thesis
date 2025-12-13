import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

/// Location data containing coordinates and address
class LocationData {
  final double latitude;
  final double longitude;
  final String addressBn;
  final String addressEn;
  final DateTime timestamp;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.addressBn,
    required this.addressEn,
    required this.timestamp,
  });

  String get latitudeFormatted => '${latitude.toStringAsFixed(4)}° ${latitude >= 0 ? 'N' : 'S'}';
  String get longitudeFormatted => '${longitude.toStringAsFixed(4)}° ${longitude >= 0 ? 'E' : 'W'}';
}

/// Service for handling GPS location and reverse geocoding
class LocationService {
  static LocationService? _instance;

  // Singleton
  static LocationService get instance {
    _instance ??= LocationService._();
    return _instance!;
  }

  LocationService._();

  /// Check if location services are enabled and permission is granted
  Future<bool> checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permission permanently denied');
      return false;
    }

    return true;
  }

  /// Get current GPS location with address
  Future<LocationData?> getCurrentLocation() async {
    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) {
        return null;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      debugPrint('Got position: ${position.latitude}, ${position.longitude}');

      // Try to get address (requires internet)
      String addressBn = 'ঠিকানা পাওয়া যায়নি';
      String addressEn = 'Address not available';

      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          // Build address string
          final parts = <String>[];
          if (place.street != null && place.street!.isNotEmpty) {
            parts.add(place.street!);
          }
          if (place.subLocality != null && place.subLocality!.isNotEmpty) {
            parts.add(place.subLocality!);
          }
          if (place.locality != null && place.locality!.isNotEmpty) {
            parts.add(place.locality!);
          }
          if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
            parts.add(place.administrativeArea!);
          }

          if (parts.isNotEmpty) {
            addressEn = parts.join(', ');
            // For Bengali, we use the same address (geocoding doesn't return Bengali)
            // In a production app, you might use a translation API
            addressBn = addressEn;
          }

          debugPrint('Address: $addressEn');
        }
      } catch (e) {
        debugPrint('Geocoding error (may be offline): $e');
        // Keep default "Address not available" messages
      }

      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        addressBn: addressBn,
        addressEn: addressEn,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Location error: $e');
      return null;
    }
  }

  /// Open device location settings
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Open app settings (for permission)
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }
}
