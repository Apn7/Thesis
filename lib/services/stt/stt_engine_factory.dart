import 'package:flutter/material.dart';

import 'sherpa_engine.dart';
import 'stt_engine.dart';
import 'whisper_engine.dart';

/// Creates and caches [SttEngine] instances by locale.
///
/// Engines are lazily created on first request and kept alive for the
/// lifetime of the process.  Bengali (`'bn'`) routes to
/// [SherpaEngine]; everything else falls back to [WhisperEngine].
class SttEngineFactory {
  SttEngineFactory._();

  static final Map<String, SttEngine> _cache = {};

  /// Return the preferred engine for [locale], creating it if necessary.
  static SttEngine getEngine(String locale) {
    return _cache.putIfAbsent(locale, () {
      debugPrint('SttEngineFactory: creating engine for locale "$locale"');
      return locale == 'bn' ? SherpaEngine() : WhisperEngine();
    });
  }

  /// Return the [WhisperEngine] singleton – useful as a cross-language
  /// fallback when the primary engine fails.
  static SttEngine get fallbackEngine => getEngine('en');

  /// Dispose every cached engine.  Call during app teardown only.
  static void disposeAll() {
    for (final engine in _cache.values) {
      engine.dispose();
    }
    _cache.clear();
  }
}
