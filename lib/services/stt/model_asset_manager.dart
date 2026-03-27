import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'sherpa_model_config.dart';

/// Copies bundled model assets from the APK to local app storage on first run.
///
/// Sherpa-onnx requires file-system paths — it cannot read directly from
/// Flutter's asset bundle.  This manager bridges that gap by extracting assets
/// once to [getApplicationSupportDirectory] and returning the local path.
class ModelAssetManager {
  ModelAssetManager._();

  static String? _baseDir;

  static Future<String> get _appDir async {
    if (_baseDir != null) return _baseDir!;
    final dir = await getApplicationSupportDirectory();
    _baseDir = dir.path;
    return _baseDir!;
  }

  // ─── Public API ──────────────────────────────────────────────────

  /// Ensure all files for [config] are present in local storage and return
  /// the directory path.  Safe to call multiple times — skips files that are
  /// already the correct size.
  static Future<String> ensureSherpaModel(SherpaModelConfig config) =>
      _ensure(config.modelDirName, config.modelFiles);

  /// Ensure all files for the SLI [config] are present and return the dir.
  static Future<String> ensureSliModel(SliModelConfig config) =>
      _ensure(config.modelDirName, config.modelFiles);

  static Future<String> _ensure(
    String modelDirName,
    Map<String, int> files,
  ) async {
    final dir = await _modelDir(modelDirName);
    await _copyFiles(
      assetDir: 'assets/models/$modelDirName',
      destDir: dir,
      files: files,
    );
    return dir;
  }

  // ─── Internal helpers ────────────────────────────────────────────

  static Future<String> _modelDir(String name) async {
    final base = await _appDir;
    final dir = Directory('$base/$name');
    await dir.create(recursive: true);
    return dir.path;
  }

  static Future<void> _copyFiles({
    required String assetDir,
    required String destDir,
    required Map<String, int> files,
  }) async {
    for (final entry in files.entries) {
      final fileName = entry.key;
      final expectedMinSize = entry.value;
      final dest = File('$destDir/$fileName');

      // Skip if already present and healthy.
      if (await dest.exists()) {
        final size = await dest.length();
        if (size >= expectedMinSize * 0.8) {
          debugPrint('ModelAssetManager: $fileName already present, skipping.');
          continue;
        }
        debugPrint(
          'ModelAssetManager: $fileName looks corrupt (${size}B), re-copying.',
        );
      }

      debugPrint('ModelAssetManager: copying $fileName from assets…');
      try {
        final data = await rootBundle.load('$assetDir/$fileName');
        await dest.writeAsBytes(data.buffer.asUint8List());
        debugPrint(
          'ModelAssetManager: $fileName copied (${dest.lengthSync()}B)',
        );
      } catch (e) {
        debugPrint('ModelAssetManager: failed to copy $fileName – $e');
        rethrow;
      }
    }
  }
}
