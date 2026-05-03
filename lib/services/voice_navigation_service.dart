import 'package:flutter/material.dart';
import '../core/utils/constants.dart';
import 'groq_service.dart';
import 'intent_matcher.dart';
// import 'llm_service.dart'; // on-device Gemma — disabled, see llm_service.dart
import 'speech_service.dart';
import 'tts_service.dart';

/// Navigation actions that can be triggered by voice
enum VoiceAction {
  navigateHome,
  navigateLocation,
  navigateSettings,
  navigateHelp,
  speakBattery,
  speakTime,
  none,
}

/// Orchestrates speech recognition, Groq AI, and navigation
class VoiceNavigationService extends ChangeNotifier {
  static VoiceNavigationService? _instance;

  final GroqService _groq = GroqService.instance;
  final IntentMatcher _matcher = IntentMatcher.instance;
  final SpeechService _speech = SpeechService.instance;
  final TtsService _tts = TtsService.instance;

  /// Whether the most recent command was resolved locally (true) or
  /// escalated to the cloud LLM (false).  Surfaces in debug overlays.
  bool _lastWasLocal = false;
  bool get lastWasLocal => _lastWasLocal;

  bool _isListening = false;
  bool _isProcessing = false;
  String _currentTranscript = '';
  String _lastResponse = '';
  String _error = '';

  // Navigation callback
  Function(VoiceAction action)? onNavigationAction;

  // Singleton
  static VoiceNavigationService get instance {
    _instance ??= VoiceNavigationService._();
    return _instance!;
  }

  VoiceNavigationService._() {
    _setupSpeechCallbacks();
  }

  // Getters
  bool get isListening => _isListening;
  bool get isProcessing => _isProcessing;
  String get currentTranscript => _currentTranscript;
  String get lastResponse => _lastResponse;
  String get error => _error;

  /// Initialize all services
  Future<void> initialize() async {
    debugPrint('[INIT] VoiceNavigationService.initialize()');

    // Local intent matcher loads its phrase bank + IDF table once at boot.
    try {
      await _matcher.load();
      debugPrint(
        '[INIT] IntentMatcher loaded=${_matcher.isLoaded} '
        'tau=${_matcher.config.confidenceThreshold}',
      );
    } catch (e) {
      debugPrint('[INIT] !! IntentMatcher load error: $e');
    }

    try {
      await _speech.initialize();
      debugPrint('[INIT] SpeechService initialized=${_speech.isInitialized}');
    } catch (e) {
      debugPrint('[INIT] !! Speech init error: $e');
    }

    try {
      await _tts.initialize();
      debugPrint('[INIT] TtsService ready');
    } catch (e) {
      debugPrint('[INIT] !! TTS init error: $e');
    }
  }

  /// Setup speech recognition callbacks
  void _setupSpeechCallbacks() {
    _speech.onResult = (text, isFinal) {
      _currentTranscript = text;
      notifyListeners();

      // Trace every transcription event so you can see partials in real time
      // and spot empty-final-result cases.
      final tag = isFinal ? 'FINAL  ' : 'partial';
      debugPrint('[STT] $tag : "$text" (len=${text.length})');

      if (isFinal) {
        if (text.isNotEmpty) {
          _processCommand(text);
        } else {
          debugPrint(
            '[STT] !! final transcript was empty — '
            'spoke too softly / too briefly / mic permission?',
          );
        }
      }
    };

    _speech.onStatus = (status) {
      debugPrint('[STT] status -> $status');
      if (status == 'processing') {
        _isProcessing = true;
        notifyListeners();
      } else if (status == 'done' || status == 'notListening') {
        _isListening = false;
        notifyListeners();
      }
    };

    _speech.onError = (error) {
      debugPrint('[STT] !! error : $error');
      _error = error;
      _isListening = false;
      notifyListeners();
    };
  }

  /// Start listening for voice commands
  Future<void> startListening() async {
    if (_isListening || _isProcessing) return;

    debugPrint('[STT] >>> startListening()');
    _error = '';
    _currentTranscript = '';
    _isListening = true;
    notifyListeners();

    await _speech.startListening();
  }

  /// Stop listening
  Future<void> stopListening() async {
    debugPrint('[STT] <<< stopListening() — requesting final result');
    await _speech.stopListening();
    _isListening = false;
    notifyListeners();
  }

  /// Process the voice command.
  ///
  /// Two-tier classification pipeline:
  ///   1. **Local fuzzy intent matcher** — sub-millisecond, fully offline.
  ///      Uses the Damerau-Levenshtein / Jaro-Winkler / Sørensen-Dice /
  ///      TF-IDF cosine / Jaccard ensemble in [IntentMatcher].
  ///   2. **Groq cloud LLM** — invoked only when the local matcher's
  ///      confidence is below τ (or when [AppConstants.enableLlm] is true).
  ///
  /// Catches ~most common phrasings without an API call; the LLM acts as a
  /// safety net for novel or ambiguous inputs.
  Future<void> _processCommand(String text) async {
    if (text.isEmpty) return;

    _isProcessing = true;
    _isListening = false;
    notifyListeners();

    try {
      VoiceCommandResponse response;

      _logBlockOpen(text);

      // Tier 1 — local fuzzy match.
      final local = _matcher.match(text);
      _logLocalTier(local);

      if (local != null) {
        _lastWasLocal = true;
        response = local.toVoiceCommandResponse();
        _logResolution(
          source: 'LOCAL',
          action: response.action,
          reply: response.spokenResponse,
        );
      } else if (AppConstants.enableLlm) {
        // Tier 2 — cloud LLM fallback.
        _lastWasLocal = false;
        final sw = Stopwatch()..start();
        _logCloudRequest();
        response = await _groq.processCommand(text);
        sw.stop();
        _logCloudResponse(
          action: response.action,
          reply: response.spokenResponse,
          elapsedMs: sw.elapsedMilliseconds,
        );
      } else {
        _lastWasLocal = false;
        response = VoiceCommandResponse(
          action: 'none',
          spokenResponse: 'দুঃখিত, বুঝতে পারিনি। '
              "Sorry, I didn't understand.",
        );
        _logResolution(
          source: 'STUB',
          action: response.action,
          reply: response.spokenResponse,
        );
      }

      _logBlockClose();

      _lastResponse = response.spokenResponse;
      await _tts.speak(response.spokenResponse);

      final action = _parseAction(response.action);
      if (action != VoiceAction.none) {
        onNavigationAction?.call(action);
      }
    } catch (e) {
      _error = 'Processing error: $e';
      debugPrint('[VOICE] !! processing error: $e');
      _logBlockClose();
      await _tts.speak(
        'দুঃখিত, একটি সমস্যা হয়েছে। Sorry, there was an error.',
      );
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  // ── Structured trace logging ──────────────────────────────────────
  //
  // Every voice command produces one block that makes the routing decision
  // unambiguous in the console.  Use the [LOCAL] / [CLOUD] / [STUB] tags to
  // grep — and the bottom RESOLVED line to see which tier won.

  static const String _logRule =
      '==========================================================';
  static const String _logSubRule =
      '----------------------------------------------------------';

  void _logBlockOpen(String input) {
    debugPrint(_logRule);
    debugPrint('[VOICE] command received');
    debugPrint('  input    : "$input"');
  }

  void _logLocalTier(IntentMatch? match) {
    final diag = _matcher.lastDiagnostics;
    final tau = _matcher.config.confidenceThreshold.toStringAsFixed(2);

    debugPrint(_logSubRule);
    debugPrint('[LOCAL] intent classifier (offline)');

    if (diag == null) {
      debugPrint('  (matcher not loaded — falling through)');
      return;
    }

    final cmiTag = _cmiTag(diag.codeMixingIndex);
    debugPrint('  norm     : "${diag.normalisedInput}"');
    debugPrint(
      '  tokens   : ${diag.tokensAfterStopwords} '
      '(raw=${diag.tokens.length}, kept=${diag.tokensAfterStopwords.length})',
    );
    debugPrint(
      '  cmi      : ${diag.codeMixingIndex.toStringAsFixed(2)}  ($cmiTag)',
    );

    if (diag.topCandidates.isNotEmpty) {
      final top = diag.topCandidates.first;
      final verdict = match != null ? 'ACCEPTED' : 'REJECTED';
      final cmp = match != null ? '>=' : '<';
      debugPrint(
        '  top      : ${top.action} <- "${top.phrase}"',
      );
      debugPrint(
        '  conf     : ${top.ensembleScore.toStringAsFixed(4)}  '
        '$cmp tau=$tau   $verdict',
      );
      debugPrint(
        '  scores   : '
        'DL=${top.damerauLevenshtein.toStringAsFixed(3)} '
        'JW=${top.jaroWinkler.toStringAsFixed(3)} '
        'Dice=${top.sorensenDice.toStringAsFixed(3)} '
        'TFIDF=${top.tfIdfCosine.toStringAsFixed(3)} '
        'JC=${top.jaccard.toStringAsFixed(3)}'
        '${top.containmentBoost > 0 ? " (+boost ${top.containmentBoost.toStringAsFixed(2)})" : ""}',
      );
      // One line per runner-up so ablation/ambiguity is visible.
      for (var i = 1; i < diag.topCandidates.length && i < 3; i++) {
        final c = diag.topCandidates[i];
        debugPrint(
          '            #${i + 1} ${c.action.padRight(18)} '
          '${c.ensembleScore.toStringAsFixed(4)}  <- "${c.phrase}"',
        );
      }
    }
    debugPrint('  latency  : ${diag.latencyMicros}µs');
  }

  void _logCloudRequest() {
    debugPrint(_logSubRule);
    debugPrint('[CLOUD] >>> escalating to Groq LLM (network call)');
    debugPrint('  reason   : local confidence below threshold');
    debugPrint('  endpoint : api.groq.com  (LLaMA 3.3 70B)');
  }

  void _logCloudResponse({
    required String action,
    required String reply,
    required int elapsedMs,
  }) {
    debugPrint('[CLOUD] <<< response received');
    debugPrint('  action   : $action');
    debugPrint('  reply    : "$reply"');
    debugPrint('  latency  : ${elapsedMs}ms');
    debugPrint('>> RESOLVED via CLOUD  (API call made)');
  }

  void _logResolution({
    required String source,
    required String action,
    required String reply,
  }) {
    final tag = source == 'LOCAL'
        ? '>> RESOLVED via LOCAL  (no API call)'
        : '>> RESOLVED via STUB   (LLM disabled)';
    debugPrint(tag);
    debugPrint('  action   : $action');
    debugPrint('  reply    : "$reply"');
  }

  void _logBlockClose() {
    debugPrint(_logRule);
  }

  String _cmiTag(double cmi) {
    if (cmi == 0.0) return 'monolingual';
    if (cmi < 0.20) return 'mostly monolingual';
    if (cmi < 0.40) return 'mildly mixed';
    return 'balanced bilingual';
  }

  /// Parse action string to enum
  VoiceAction _parseAction(String actionStr) {
    switch (actionStr.toLowerCase()) {
      case 'navigate_home':
        return VoiceAction.navigateHome;
      case 'navigate_location':
        return VoiceAction.navigateLocation;
      case 'navigate_settings':
        return VoiceAction.navigateSettings;
      case 'navigate_help':
        return VoiceAction.navigateHelp;
      case 'speak_battery':
        return VoiceAction.speakBattery;
      case 'speak_time':
        return VoiceAction.speakTime;
      default:
        return VoiceAction.none;
    }
  }

  /// Speak a message directly
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  /// Send a text command directly (for testing)
  Future<void> sendTextCommand(String text) async {
    _currentTranscript = text;
    notifyListeners();
    await _processCommand(text);
  }
}
