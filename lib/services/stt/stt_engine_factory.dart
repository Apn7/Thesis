import 'package:flutter/material.dart';

import 'sherpa_engine.dart';
import 'sherpa_model_config.dart';
import 'sli_detector.dart';
import 'stt_engine.dart';

/// Creates, caches, and disposes [SttEngine] instances by locale.
///
/// Bengali (`'bn'`) and English (`'en'`) both route to [SherpaEngine]
/// with the appropriate [SherpaModelConfig].  The `'both'` locale is
/// resolved by [AudioPipeline] before reaching this factory.
class SttEngineFactory {
  SttEngineFactory._();

  static final Map<String, SttEngine> _cache = {};
  static SliDetector? _sliDetector;

  /// Return the preferred engine for [locale], creating it if necessary.
  ///
  /// [locale] must be `'bn'` or `'en'` — `'both'` is resolved upstream.
  static SttEngine getEngine(String locale) {
    assert(locale == 'bn' || locale == 'en');
    return _cache.putIfAbsent(locale, () {
      final cfg = locale == 'bn' ? kBengaliSherpaConfig : kEnglishSherpaConfig;
      debugPrint('SttEngineFactory: creating SherpaEngine[${cfg.language}]');
      return SherpaEngine(cfg);
    });
  }

  /// The shared SLI detector for "both" mode.  Lazily created.
  static SliDetector? get sliDetector => _sliDetector;

  /// Initialise the SLI detector (call when user selects "both" mode).
  static Future<bool> initSliDetector() async {
    _sliDetector ??= SliDetector();
    if (_sliDetector!.isInitialized) return true;
    return await _sliDetector!.initialize();
  }

  /// Dispose a single cached engine to free RAM.
  static void disposeEngine(String locale) {
    final engine = _cache.remove(locale);
    engine?.dispose();
    debugPrint('SttEngineFactory: disposed engine[$locale]');
  }

  /// Dispose the SLI detector.
  static void disposeSli() {
    _sliDetector?.dispose();
    _sliDetector = null;
    debugPrint('SttEngineFactory: disposed SLI detector');
  }

  /// Dispose every cached engine and SLI.  Call during app teardown only.
  static void disposeAll() {
    for (final engine in _cache.values) {
      engine.dispose();
    }
    _cache.clear();
    disposeSli();
  }
}
