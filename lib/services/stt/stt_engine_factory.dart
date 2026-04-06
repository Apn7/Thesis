import 'package:flutter/material.dart';

import 'sherpa_engine.dart';
import 'sherpa_model_config.dart';
import 'stt_engine.dart';

/// Creates, caches, and disposes [SttEngine] instances.
///
/// Only Bengali (`'bn'`) is handled here — the English path uses Android's
/// built-in speech recognizer managed directly by [SpeechService].
class SttEngineFactory {
  SttEngineFactory._();

  static final Map<String, SttEngine> _cache = {};

  /// Return the Bengali engine, creating it if necessary.
  ///
  /// [locale] must be `'bn'`.
  static SttEngine getEngine(String locale) {
    assert(locale == 'bn', 'SttEngineFactory only manages the Bengali engine');
    return _cache.putIfAbsent(locale, () {
      debugPrint('SttEngineFactory: creating SherpaEngine[bn]');
      return SherpaEngine(kBengaliSherpaConfig);
    });
  }

  /// Dispose the cached Bengali engine to free RAM.
  static void disposeEngine(String locale) {
    final engine = _cache.remove(locale);
    engine?.dispose();
    debugPrint('SttEngineFactory: disposed engine[$locale]');
  }

  /// Dispose all cached engines.  Call during app teardown only.
  static void disposeAll() {
    for (final engine in _cache.values) {
      engine.dispose();
    }
    _cache.clear();
  }
}
