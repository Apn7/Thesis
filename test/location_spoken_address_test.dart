import 'package:flutter_test/flutter_test.dart';
import 'package:test_app_1/services/location_service.dart';

/// Unit tests for the concise spoken-address builder — the string TTS reads
/// aloud on the location screen. It must pick the most local meaningful parts
/// and never fall back to the ~20-second full postal hierarchy unless empty.
void main() {
  group('LocationService.spokenAddressFromParts', () {
    test('road + neighbourhood + city', () {
      final spoken = LocationService.spokenAddressFromParts({
        'road': 'মিরপুর রোড',
        'neighbourhood': 'ধানমন্ডি',
        'city': 'ঢাকা',
        'state': 'ঢাকা বিভাগ',
        'postcode': '1205',
        'country': 'বাংলাদেশ',
      }, fallback: 'x');
      expect(spoken, 'মিরপুর রোড, ধানমন্ডি, ঢাকা');
    });

    test('suburb substitutes for missing neighbourhood, town for city', () {
      final spoken = LocationService.spokenAddressFromParts({
        'suburb': 'সাভার',
        'town': 'সাভার পৌরসভা',
        'country': 'বাংলাদেশ',
      }, fallback: 'x');
      expect(spoken, 'সাভার, সাভার পৌরসভা');
    });

    test('village-only address still speaks something local', () {
      final spoken = LocationService.spokenAddressFromParts({
        'village': 'চর কুকরি মুকরি',
        'state': 'বরিশাল বিভাগ',
      }, fallback: 'x');
      expect(spoken, 'চর কুকরি মুকরি');
    });

    test('empty or irrelevant parts fall back', () {
      expect(
        LocationService.spokenAddressFromParts({
          'country': 'বাংলাদেশ',
          'postcode': '1205',
        }, fallback: 'পুরো ঠিকানা'),
        'পুরো ঠিকানা',
      );
      expect(
        LocationService.spokenAddressFromParts({'road': '   '}, fallback: 'f'),
        'f',
      );
    });
  });
}
