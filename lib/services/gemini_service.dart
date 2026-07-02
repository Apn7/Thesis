import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import 'groq_service.dart' show VoiceCommandResponse;

/// Fallback cloud LLM backed by Google Gemini 2.5 Flash via the
/// OpenAI-compatible REST endpoint.
///
/// [GeminiService] is intentionally stateless (no conversation history):
///   • It is only reached when [GroqService] fails or times out, so any prior
///     conversation context from Groq is already lost.
///   • Keeping it stateless means each call is independent and retryable
///     without stale history causing confusion.
///
/// The OpenAI-compatible endpoint means the request/response format is
/// identical to [GroqService] — same JSON body, same `choices[0].message`
/// parse path, same regex extraction for the structured
/// `{"action":…,"spoken_response":…}` payload.
///
/// Free tier (as of 2025): ~1,500 requests/day, 10–15 RPM.  Enough for
/// thesis evaluation and fallback use; no billing needed.
class GeminiService {
  GeminiService._();

  static GeminiService? _instance;
  static GeminiService get instance => _instance ??= GeminiService._();

  /// Process a transcribed voice command and return the action + spoken reply.
  ///
  /// Mirrors [GroqService.processCommand] exactly so [VoiceNavigationService]
  /// can call either service with the same signature.
  Future<VoiceCommandResponse> processCommand(String userText) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.geminiBaseUrl}/chat/completions'),
            headers: {
              'Authorization': 'Bearer ${ApiConfig.geminiApiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': ApiConfig.geminiModel,
              'messages': [
                {'role': 'system', 'content': ApiConfig.systemPrompt},
                {'role': 'user', 'content': userText},
              ],
              'temperature': 0.3,
              'max_tokens': 200,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        debugPrint(
          'GeminiService: API error ${response.statusCode}: ${response.body}',
        );
        return VoiceCommandResponse.error(
          'Gemini API error: ${response.statusCode}',
        );
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final content = data['choices'][0]['message']['content'] as String;

      final match = RegExp(r'\{[\s\S]*?\}').firstMatch(content);
      if (match != null) {
        try {
          final json = jsonDecode(match.group(0)!) as Map<String, dynamic>;
          return VoiceCommandResponse.fromJson(json);
        } catch (_) {
          // JSON parse failed — return raw content as spoken reply.
        }
      }
      return VoiceCommandResponse(action: 'none', spokenResponse: content);
    } on TimeoutException {
      debugPrint('GeminiService: request timed out');
      return VoiceCommandResponse.error('সার্ভারে সংযোগ করা যায়নি।');
    } catch (e, st) {
      debugPrint('GeminiService error: $e\n$st');
      return VoiceCommandResponse.error('ইন্টারনেট সংযোগে সমস্যা।');
    }
  }
}
