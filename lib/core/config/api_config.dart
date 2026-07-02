import 'package:flutter_dotenv/flutter_dotenv.dart';

/// API configuration for Groq (primary LLM) and Gemini (fallback LLM).
///
/// On-device LLM (Gemma 4 / LiteRT-LM) is currently disabled — see
/// [LlmService] which has been commented out. Voice intents now go through
/// the Groq HTTP API, with Gemini as a silent automatic fallback.
class ApiConfig {
  // ── Groq (primary cloud LLM) ──────────────────────────────────────────────

  /// Groq API Key — loaded from .env at runtime.
  static String get groqApiKey => dotenv.env['GROQ_API_KEY'] ?? '';

  /// Groq API base URL (OpenAI-compatible).
  static const String groqBaseUrl = 'https://api.groq.com/openai/v1';

  /// Primary model: LLaMA 3.3 70B via Groq LPU inference.
  static const String llamaModel = 'llama-3.3-70b-versatile';

  // ── Gemini (fallback cloud LLM) ───────────────────────────────────────────

  /// Gemini API Key — loaded from .env at runtime.
  static String get geminiApiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  /// Gemini API base URL — Google's OpenAI-compatible endpoint so
  /// [GeminiService] can share the same HTTP/JSON format as [GroqService].
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/openai';

  /// Fallback model: Gemini 3.5 Flash (free tier: ~1,500 req/day).
  static const String geminiModel = 'gemini-3.5-flash';

  // ── Shared system prompt ──────────────────────────────────────────────────

  /// System prompt shared by both Groq and Gemini so the structured JSON
  /// response format is consistent regardless of which provider serves the
  /// request.
  static const String systemPrompt = '''
You are a voice assistant for a smart cane navigation app for visually impaired users in Bangladesh.
The user speaks in Bengali (Bangla), sometimes code-mixed with English words (Banglish). Understand their intent and ALWAYS respond in Bengali.

IMPORTANT:
- Always respond in Bengali (Bangla script), never in English
- Keep responses SHORT and clear (1-2 sentences max)
- Be warm and helpful

Available actions you can trigger:
- navigate_home: Go to home screen
- navigate_location: Show current GPS location
- navigate_settings: Open settings
- navigate_help: Open help/tutorial
- speak_battery: Tell battery status
- speak_time: Tell current time
- none: Just respond, no navigation needed

Return ONLY valid JSON in this exact format:
{
  "action": "one_of_the_actions_above",
  "spoken_response": "Your response to speak aloud, in Bengali"
}

Examples:
User: "আমি কোথায় আছি?"
Response: {"action": "navigate_location", "spoken_response": "আপনার অবস্থান দেখাচ্ছি"}

User: "settings open koro"
Response: {"action": "navigate_settings", "spoken_response": "সেটিংস খুলছি"}
''';
}
