import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

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

      // Get address using HTTP-based geocoding (works on all platforms including web)
      final address = await _reverseGeocodeHTTP(position.latitude, position.longitude);

      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        addressBn: address,
        addressEn: address,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Location error: $e');
      return null;
    }
  }

  /// Reverse geocoding using OpenStreetMap Nominatim API (works on web + mobile)
  Future<String> _reverseGeocodeHTTP(double lat, double lon) async {
    try {
      debugPrint('Attempting HTTP reverse geocoding for: $lat, $lon');
      
      // Using OpenStreetMap Nominatim API (free, no API key required)
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=18&addressdetails=1'
      );
      
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'SmartCaneApp/1.0', // Required by Nominatim
          'Accept-Language': 'en,bn', // Request English and Bengali
        },
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        debugPrint('Nominatim response: ${response.body}');
        
        // Get display name (full formatted address)
        if (data.containsKey('display_name')) {
          final displayName = data['display_name'] as String;
          debugPrint('Address found: $displayName');
          return displayName;
        }
        
        // Fallback: build address from parts
        if (data.containsKey('address')) {
          final address = data['address'] as Map<String, dynamic>;
          final parts = <String>[];
          
          // Add relevant address parts
          if (address['road'] != null) parts.add(address['road']);
          if (address['neighbourhood'] != null) parts.add(address['neighbourhood']);
          if (address['suburb'] != null) parts.add(address['suburb']);
          if (address['city'] != null) parts.add(address['city']);
          if (address['town'] != null) parts.add(address['town']);
          if (address['village'] != null) parts.add(address['village']);
          if (address['state'] != null) parts.add(address['state']);
          if (address['country'] != null) parts.add(address['country']);
          
          if (parts.isNotEmpty) {
            final formattedAddress = parts.join(', ');
            debugPrint('Address built from parts: $formattedAddress');
            return formattedAddress;
          }
        }
        
        return 'Address not available';
      } else {
        debugPrint('Nominatim API error: ${response.statusCode}');
        return 'Address not available';
      }
    } catch (e) {
      debugPrint('HTTP Geocoding error: $e');
      return 'Address not available';
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
