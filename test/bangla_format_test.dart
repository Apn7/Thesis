import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app_1/core/utils/bangla_format.dart';

void main() {
  group('BanglaFormat.digits', () {
    test('maps every digit and multi-digit values', () {
      expect(BanglaFormat.digits(0), '০');
      expect(BanglaFormat.digits(85), '৮৫');
      expect(BanglaFormat.digits(1234567890), '১২৩৪৫৬৭৮৯০');
    });
  });

  group('BanglaFormat.spokenTime', () {
    test('afternoon with minutes', () {
      expect(
        BanglaFormat.spokenTime(const TimeOfDay(hour: 14, minute: 30)),
        'দুপুর ২টা বেজে ৩০ মিনিট',
      );
    });

    test('exact hour drops the minutes', () {
      expect(
        BanglaFormat.spokenTime(const TimeOfDay(hour: 9, minute: 0)),
        'সকাল ঠিক ৯টা',
      );
    });

    test('midnight and noon use 12, not 0', () {
      expect(
        BanglaFormat.spokenTime(const TimeOfDay(hour: 0, minute: 5)),
        'রাত ১২টা বেজে ৫ মিনিট',
      );
      expect(
        BanglaFormat.spokenTime(const TimeOfDay(hour: 12, minute: 15)),
        'দুপুর ১২টা বেজে ১৫ মিনিট',
      );
    });

    test('day periods cover the clock', () {
      expect(BanglaFormat.dayPeriod(4), 'ভোর');
      expect(BanglaFormat.dayPeriod(7), 'সকাল');
      expect(BanglaFormat.dayPeriod(13), 'দুপুর');
      expect(BanglaFormat.dayPeriod(16), 'বিকেল');
      expect(BanglaFormat.dayPeriod(18), 'সন্ধ্যা');
      expect(BanglaFormat.dayPeriod(22), 'রাত');
      expect(BanglaFormat.dayPeriod(2), 'রাত');
    });
  });
}
