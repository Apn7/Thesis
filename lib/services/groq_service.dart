import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';

/// Response from Groq for voice commands.
///
/// Same shape as [VoiceCommandResponse] in [LlmService] (currently disabled)
/// so [VoiceNavigationService] requires no structural changes when swapping
/// between on-device LLM and the cloud-hosted Groq API.
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

/// Cloud-hosted intent recognition via Groq's chat completions API
/// (LLaMA 3.3 70B). Maintains a short rolling conversation history so
/// follow-up commands have context.
class GroqService {
  GroqService._();

  static GroqService? _instance;
  static GroqService get instance => _instance ??= GroqService._();

  final List<Map<String, String>> _conversationHistory = [];

  /// Process a transcribed voice command and return the action + spoken reply.
  Future<VoiceCommandResponse> processCommand(String userText) async {
    try {
      _conversationHistory.add({'role': 'user', 'content': userText});

      final messages = [
        {'role': 'system', 'content': ApiConfig.systemPrompt},
        ..._conversationHistory,
      ];

      // Hard timeout so a flaky/half-open connection can never leave the user
      // stuck in the "processing" state. The caller also gates this on
      // reachability, so this mainly guards the connected-but-no-internet case.
      final response = await http
          .post(
            Uri.parse('${ApiConfig.groqBaseUrl}/chat/completions'),
            headers: {
              'Authorization': 'Bearer ${ApiConfig.groqApiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': ApiConfig.llamaModel,
              'messages': messages,
              'temperature': 0.3,
              'max_tokens': 200,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('Groq API error ${response.statusCode}: ${response.body}');
        return VoiceCommandResponse.error(
          'সংযোগে সমস্যা। API error: ${response.statusCode}',
        );
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final content = data['choices'][0]['message']['content'] as String;

      _conversationHistory.add({'role': 'assistant', 'content': content});
      if (_conversationHistory.length > 10) {
        _conversationHistory.removeRange(0, 2);
      }

      final match = RegExp(r'\{[\s\S]*?\}').firstMatch(content);
      if (match != null) {
        try {
          final json = jsonDecode(match.group(0)!) as Map<String, dynamic>;
          return VoiceCommandResponse.fromJson(json);
        } catch (_) {
          // fall through — return raw content as spoken reply
        }
      }
      return VoiceCommandResponse(action: 'none', spokenResponse: content);
    } on TimeoutException {
      debugPrint('Groq error: request timed out');
      return VoiceCommandResponse.error('সার্ভারে সংযোগ করা যায়নি।');
    } catch (e, st) {
      // Never speak the raw exception (TTS would read the stack/URL aloud).
      debugPrint('Groq error: $e\n$st');
      return VoiceCommandResponse.error('ইন্টারনেট সংযোগে সমস্যা।');
    }
  }

  void resetContext() => _conversationHistory.clear();
}
