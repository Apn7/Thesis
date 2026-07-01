import 'package:flutter_test/flutter_test.dart';
import 'package:test_app_1/services/spoken_number_parser.dart';

void main() {
  group('SpokenNumberParser.parseToAsciiDigits', () {
    test('maps Bengali digit words spoken one-by-one', () {
      // "শূন্য এক সাত এক দুই তিন চার পাঁচ ছয় সাত আট" → 01712345678
      const spoken = 'শূন্য এক সাত এক দুই তিন চার পাঁচ ছয় সাত আট';
      expect(SpokenNumberParser.parseToAsciiDigits(spoken), '01712345678');
    });

    test('maps Bengali numerals', () {
      expect(
        SpokenNumberParser.parseToAsciiDigits('০১৭১২৩৪৫৬৭৮'),
        '01712345678',
      );
    });

    test('ignores filler words and keeps digit order', () {
      const spoken = 'আমার নম্বর শূন্য এক নয় আট';
      expect(SpokenNumberParser.parseToAsciiDigits(spoken), '0198');
    });

    test('strips trailing Bengali punctuation on a digit word', () {
      expect(SpokenNumberParser.parseToAsciiDigits('সাত।'), '7');
    });

    test('handles common variants (শুন্য / পাচ / নই)', () {
      expect(SpokenNumberParser.parseToAsciiDigits('শুন্য পাচ নই'), '059');
    });

    test('returns empty when nothing digit-like is present', () {
      expect(SpokenNumberParser.parseToAsciiDigits('কেমন আছো'), '');
    });
  });

  group('SpokenNumberParser.toBanglaReadback', () {
    test('renders digit-by-digit Bengali words', () {
      expect(SpokenNumberParser.toBanglaReadback('017'), 'শূন্য, এক, সাত');
    });

    test('round-trips with the parser', () {
      const ascii = '8801712345678';
      final readback = SpokenNumberParser.toBanglaReadback(ascii);
      expect(SpokenNumberParser.parseToAsciiDigits(readback), ascii);
    });
  });
}
