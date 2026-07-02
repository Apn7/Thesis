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

  /// Short spoken form (road, neighbourhood, city) — what TTS reads aloud.
  /// The full [addressBn] is a postal hierarchy that takes ~20 s to speak;
  /// this is the part a person actually needs to orient themselves.
  final String addressSpoken;
  final DateTime timestamp;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.addressBn,
    required this.addressEn,
    required this.addressSpoken,
    required this.timestamp,
  });

  String get latitudeFormatted =>
      '${latitude.toStringAsFixed(4)}° ${latitude >= 0 ? 'N' : 'S'}';
  String get longitudeFormatted =>
      '${longitude.toStringAsFixed(4)}° ${longitude >= 0 ? 'E' : 'W'}';
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
      final address = await _reverseGeocodeHTTP(
        position.latitude,
        position.longitude,
      );

      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        addressBn: address.full,
        addressEn: address.full,
        addressSpoken: address.spoken,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Location error: $e');
      return null;
    }
  }

  static const String _addressUnavailable = 'ঠিকানা পাওয়া যায়নি';

  /// Build the short spoken form of a Nominatim `address` object: the two or
  /// three most local, human-meaningful parts (road → area → city). Public
  /// static so it is unit-testable without network.
  ///
  /// Returns [fallback] when the object has none of the wanted parts.
  static String spokenAddressFromParts(
    Map<String, dynamic> address, {
    required String fallback,
  }) {
    String? first(List<String> keys) {
      for (final k in keys) {
        final v = address[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    final candidates = <String?>[
      first(['road', 'pedestrian', 'footway']),
      first(['neighbourhood', 'quarter', 'suburb', 'residential']),
      first(['city', 'town', 'village', 'municipality', 'county']),
    ];
    final parts = candidates.whereType<String>().toList();

    return parts.isEmpty ? fallback : parts.join(', ');
  }

  /// Reverse geocoding using OpenStreetMap Nominatim API (works on web + mobile)
  Future<({String full, String spoken})> _reverseGeocodeHTTP(
    double lat,
    double lon,
  ) async {
    const unavailable = (
      full: _addressUnavailable,
      spoken: _addressUnavailable,
    );
    try {
      debugPrint('Attempting HTTP reverse geocoding for: $lat, $lon');

      // Using OpenStreetMap Nominatim API (free, no API key required)
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=18&addressdetails=1',
      );

      final response = await http
          .get(
            url,
            headers: {
              'User-Agent': 'SmartCaneApp/1.0', // Required by Nominatim
              'Accept-Language': 'bn,en', // Prefer Bengali place names
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('Nominatim API error: ${response.statusCode}');
        return unavailable;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint('Nominatim response: ${response.body}');

      final displayName = data['display_name'] as String?;
      final addressParts = data['address'];

      // Full form for the screen; short form for the voice. When the parts
      // object is missing, fall back to the display name for both.
      final full = displayName ?? _addressUnavailable;
      final spoken = addressParts is Map<String, dynamic>
          ? spokenAddressFromParts(addressParts, fallback: full)
          : full;

      debugPrint('Address found: full="$full" spoken="$spoken"');
      return (full: full, spoken: spoken);
    } catch (e) {
      debugPrint('HTTP Geocoding error: $e');
      return unavailable;
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
