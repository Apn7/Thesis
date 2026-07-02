import 'package:flutter/material.dart';

/// Bengali rendering helpers for numbers and time-of-day.
///
/// The app's TTS voice is bn-BD; feeding it ASCII digits or an
/// English-formatted clock string ("2:30 PM") produces unpredictable
/// pronunciation. Everything spoken to the user goes through these helpers so
/// the utterance is native Bengali.
class BanglaFormat {
  BanglaFormat._();

  static const List<String> _digits = [
    '০',
    '১',
    '২',
    '৩',
    '৪',
    '৫',
    '৬',
    '৭',
    '৮',
    '৯',
  ];

  /// Render a non-negative [value] with Bengali numerals (85 → "৮৫").
  static String digits(int value) {
    return value.toString().split('').map((c) {
      final d = c.codeUnitAt(0) - 0x30;
      return (d >= 0 && d <= 9) ? _digits[d] : c;
    }).join();
  }

  /// Bengali day-period word for a 24-hour [hour] (ভোর/সকাল/দুপুর/বিকেল/
  /// সন্ধ্যা/রাত) — Bengali time is always spoken with the period, since the
  /// 12-hour number alone is ambiguous.
  static String dayPeriod(int hour) {
    if (hour >= 4 && hour < 6) return 'ভোর';
    if (hour >= 6 && hour < 12) return 'সকাল';
    if (hour >= 12 && hour < 16) return 'দুপুর';
    if (hour >= 16 && hour < 18) return 'বিকেল';
    if (hour >= 18 && hour < 20) return 'সন্ধ্যা';
    return 'রাত';
  }

  /// Natural spoken Bengali clock phrase for [time]
  /// (14:30 → "দুপুর ২টা বেজে ৩০ মিনিট").
  static String spokenTime(TimeOfDay time) {
    final hour12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final period = dayPeriod(time.hour);
    final h = digits(hour12);
    if (time.minute == 0) return '$period ঠিক $hটা';
    return '$period $hটা বেজে ${digits(time.minute)} মিনিট';
  }
}
