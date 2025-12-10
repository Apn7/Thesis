import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/config/api_config.dart';

/// Response from Groq for voice commands
class VoiceCommandResponse {
  final String action;
  final String spokenResponse;
  
  VoiceCommandResponse({
    required this.action,
    required this.spokenResponse,
  });
  
  factory VoiceCommandResponse.fromJson(Map<String, dynamic> json) {
    return VoiceCommandResponse(
      action: json['action'] ?? 'none',
      spokenResponse: json['spoken_response'] ?? 'দুঃখিত, বুঝতে পারিনি',
    );
  }
  
  factory VoiceCommandResponse.error(String message) {
    return VoiceCommandResponse(
      action: 'none',
      spokenResponse: message,
    );
  }
}

/// Service for interacting with Groq API (Whisper + LLaMA)
class GroqService {
  static GroqService? _instance;
  
  final List<Map<String, String>> _conversationHistory = [];
  
  // Singleton pattern
  static GroqService get instance {
    _instance ??= GroqService._();
    return _instance!;
  }
  
  GroqService._();
  
  /// Process a voice command text through LLaMA and get navigation action
  Future<VoiceCommandResponse> processCommand(String userText) async {
    try {
      // Add user message to history
      _conversationHistory.add({
        'role': 'user',
        'content': userText,
      });
      
      // Build messages with system prompt
      final messages = [
        {
          'role': 'system',
          'content': ApiConfig.systemPrompt,
        },
        ..._conversationHistory,
      ];
      
      final response = await http.post(
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
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        
        // Add assistant response to history
        _conversationHistory.add({
          'role': 'assistant',
          'content': content,
        });
        
        // Keep history manageable
        if (_conversationHistory.length > 10) {
          _conversationHistory.removeRange(0, 2);
        }
        
        // Parse JSON response
        final jsonMatch = RegExp(r'\{[^}]+\}').firstMatch(content);
        if (jsonMatch != null) {
          final jsonStr = jsonMatch.group(0)!;
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          return VoiceCommandResponse.fromJson(json);
        }
        
        return VoiceCommandResponse(
          action: 'none',
          spokenResponse: content,
        );
      } else {
        debugPrint('Groq API Error: ${response.statusCode} - ${response.body}');
        return VoiceCommandResponse.error(
          'সংযোগে সমস্যা। API error: ${response.statusCode}',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Groq Error: $e');
      debugPrint('Stack: $stackTrace');
      return VoiceCommandResponse.error(
        'সংযোগে সমস্যা: $e',
      );
    }
  }
  
  /// Reset conversation context
  void resetContext() {
    _conversationHistory.clear();
  }
}
