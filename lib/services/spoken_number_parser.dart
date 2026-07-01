/// Converts a Bengali spoken-number transcript into an ASCII digit string, and
/// back into a digit-by-digit Bengali read-back for confirmation.
///
/// The offline Bengali STT (sherpa-onnx Zipformer) transcribes spoken digits as
/// Bengali words (e.g. "শূন্য এক সাত") and occasionally as Bengali numerals
/// (০১৭…). Phone numbers must be stored/sent as ASCII (`017…`), so this parser
/// walks the transcript token-by-token, maps every recognised digit token to an
/// ASCII digit, and concatenates them in order — ignoring any non-digit words.
///
/// Digit-string recognition is error-prone (short, acoustically confusable
/// tokens), so callers MUST read the parsed number back to the user for
/// confirmation via [toBanglaReadback] before saving.
class SpokenNumberParser {
  SpokenNumberParser._();

  /// Bengali (and a few common borrowed) digit words → ASCII digit.
  static const Map<String, String> _wordToDigit = {
    'শূন্য': '0',
    'শুন্য': '0',
    'জিরো': '0',
    'এক': '1',
    'দুই': '2',
    'তিন': '3',
    'চার': '4',
    'পাঁচ': '5',
    'পাচ': '5',
    'ছয়': '6',
    'সাত': '7',
    'আট': '8',
    'নয়': '9',
    'নই': '9',
  };

  /// Bengali numerals → ASCII digit (used for the per-character fallback scan).
  static const Map<String, String> _banglaNumeralToAscii = {
    '০': '0',
    '১': '1',
    '২': '2',
    '৩': '3',
    '৪': '4',
    '৫': '5',
    '৬': '6',
    '৭': '7',
    '৮': '8',
    '৯': '9',
  };

  /// ASCII digit → Bengali word, for the spoken read-back.
  static const Map<String, String> _digitToBanglaWord = {
    '0': 'শূন্য',
    '1': 'এক',
    '2': 'দুই',
    '3': 'তিন',
    '4': 'চার',
    '5': 'পাঁচ',
    '6': 'ছয়',
    '7': 'সাত',
    '8': 'আট',
    '9': 'নয়',
  };

  // Keep only Bengali block (U+0980–U+09FF) and ASCII digits when cleaning a
  // token, so trailing punctuation ("সাত।") doesn't defeat the word lookup.
  static final RegExp _keepRe = RegExp(r'[^ঀ-৿0-9]');
  static final RegExp _asciiDigitRe = RegExp(r'[0-9]');

  // Google Bengali STT emits য় as the precomposed U+09DF (BENGALI LETTER YYA),
  // but the dictionary keys use the two-codepoint form U+09AF + U+09BC. Visually
  // identical, but string equality fails — causing ছয় (6) and নয় (9) to be
  // silently dropped. Normalise before every lookup.
  static String _normalizeToken(String token) =>
      token.replaceAll('য়', 'য়');

  /// Extract an ASCII digit string from a Bengali spoken-number [text].
  /// Returns digits in spoken order; non-digit words are ignored. Empty string
  /// if nothing digit-like was found.
  static String parseToAsciiDigits(String text) {
    final buffer = StringBuffer();
    for (final rawToken in text.split(RegExp(r'\s+'))) {
      final token = _normalizeToken(rawToken.replaceAll(_keepRe, ''));
      if (token.isEmpty) continue;

      // Whole-token digit word ("সাত" → 7).
      final word = _wordToDigit[token];
      if (word != null) {
        buffer.write(word);
        continue;
      }

      // Otherwise scan characters for Bengali numerals / ASCII digits, so a
      // token like "০১৭" or "017" still yields its digits.
      for (final ch in token.split('')) {
        final mapped = _banglaNumeralToAscii[ch];
        if (mapped != null) {
          buffer.write(mapped);
        } else if (_asciiDigitRe.hasMatch(ch)) {
          buffer.write(ch);
        }
      }
    }
    return buffer.toString();
  }

  /// Render [asciiDigits] as a comma-separated Bengali word sequence so TTS
  /// reads it back one digit at a time ("শূন্য, এক, সাত …") for confirmation.
  static String toBanglaReadback(String asciiDigits) {
    return asciiDigits
        .split('')
        .map((d) => _digitToBanglaWord[d] ?? d)
        .join(', ');
  }
}
