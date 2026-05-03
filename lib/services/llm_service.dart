// On-device LLM (Gemma 4 E2B via LiteRT-LM) is currently disabled.
// Voice intents are handled by GroqService (cloud-hosted LLaMA 3.3 70B).
// The full implementation is preserved below in a block comment so it can
// be restored when the Gemma model is re-bundled.
//
// To re-enable:
//   1. Uncomment the code below.
//   2. Re-add the model asset in pubspec.yaml.
//   3. Swap GroqService back to LlmService in voice_navigation_service.dart.
//   4. Set AppConstants.enableLlm = true.

/*
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/config/api_config.dart';

/// Response from the on-device LLM for a voice command.
///
/// Same contract as the old GroqService response so [VoiceNavigationService]
/// requires no structural changes.
class VoiceCommandResponse {
  final String action;
  final String spokenResponse;

  VoiceCommandResponse({required this.action, required this.spokenResponse});

  factory VoiceCommandResponse.fromJson(Map<String, dynamic> json) {
    return VoiceCommandResponse(
      action: json['action'] as String? ?? 'none',
      spokenResponse:
          json['spoken_response'] as String? ?? 'দুঃখিত, বুঝতে পারিনি',
    );
  }

  factory VoiceCommandResponse.error(String message) =>
      VoiceCommandResponse(action: 'none', spokenResponse: message);
}

/// On-device LLM service backed by Gemma 4 E2B via the LiteRT-LM Android SDK.
///
/// Communication happens through a [MethodChannel] to native Kotlin code in
/// [MainActivity].  All heavy work (model loading, inference) runs on a
/// background thread on the Kotlin side.
///
/// Lifecycle (called from SplashScreen):
///   1. [init()] — copies the model to device storage if needed, then loads it
///      into the LiteRT-LM Engine.  Safe to call multiple times.
///   2. [processCommand()] — runs inference; identical API to the old
///      GroqService.processCommand().
///   3. [dispose()] — releases native engine resources.
class LlmService {
  LlmService._();

  static LlmService? _instance;
  static LlmService get instance => _instance ??= LlmService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.test_app_1/llm');

  bool _initialized = false;
  bool get isInitialized => _initialized;

  // ── Setup ─────────────────────────────────────────────────────────

  /// Initialise the LiteRT-LM engine.
  ///
  /// On first launch this triggers a ~2.58 GB file copy from the APK asset to
  /// device storage — subsequent launches find the file already there and
  /// complete in seconds.  The SplashScreen status text should reflect this.
  Future<void> init() async {
    if (_initialized) return;
    try {
      debugPrint('LlmService: calling native initialize…');
      await _channel.invokeMethod<void>('initialize', {
        'systemInstruction': ApiConfig.systemPrompt,
      });
      _initialized = true;
      debugPrint('LlmService: engine ready.');
    } on PlatformException catch (e) {
      debugPrint('LlmService: init failed — ${e.code}: ${e.message}');
      rethrow;
    }
  }

  // ── Inference ─────────────────────────────────────────────────────

  /// Process a transcribed voice command and return the action + spoken reply.
  Future<VoiceCommandResponse> processCommand(String userText) async {
    if (!_initialized) {
      return VoiceCommandResponse.error(
        'AI মডেল প্রস্তুত নয়। Model not ready.',
      );
    }

    try {
      final raw = await _channel.invokeMethod<String>(
        'processCommand',
        {'text': userText},
      );
      debugPrint('LlmService raw response: $raw');
      return _parseResponse(raw ?? '');
    } on PlatformException catch (e) {
      debugPrint('LlmService: processCommand failed — ${e.code}: ${e.message}');
      return VoiceCommandResponse.error(
        'দুঃখিত, একটি সমস্যা হয়েছে। Error: ${e.message}',
      );
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────

  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('dispose');
    } catch (_) {}
    _initialized = false;
    debugPrint('LlmService: disposed.');
  }

  // ── Helpers ───────────────────────────────────────────────────────

  VoiceCommandResponse _parseResponse(String raw) {
    // Try to pull a JSON object out of the model output.
    // Gemma may wrap JSON in markdown fences or add prose — the regex
    // tolerates that.
    final match = RegExp(r'\{[^{}]+\}', dotAll: true).firstMatch(raw);
    if (match != null) {
      try {
        final json = jsonDecode(match.group(0)!) as Map<String, dynamic>;
        return VoiceCommandResponse.fromJson(json);
      } catch (_) {
        // JSON parse failed — fall through.
      }
    }
    // No valid JSON: return the raw text as the spoken reply, no navigation.
    return VoiceCommandResponse(
      action: 'none',
      spokenResponse: raw.isNotEmpty ? raw : 'দুঃখিত, বুঝতে পারিনি',
    );
  }
}
*/
