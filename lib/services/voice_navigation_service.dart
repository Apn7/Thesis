import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../core/utils/constants.dart';
import 'gemini_service.dart';
import 'groq_service.dart';
import 'intent_matcher.dart';
// import 'llm_service.dart'; // on-device Gemma — disabled, see llm_service.dart
import 'sensor_fusion_service.dart';
import 'speech_service.dart';
import 'tts_service.dart';
import '../core/utils/voice_announcer.dart';

/// Navigation actions that can be triggered by voice
enum VoiceAction {
  navigateHome,
  navigateLocation,
  navigateSettings,
  navigateHelp,
  speakBattery,
  speakTime,

  /// "What's in front of me?" — answered locally from the fusion window
  /// rather than by navigating anywhere.
  describeScene,

  /// Emergency: open the SOS screen and auto-start the alert countdown.
  triggerSos,

  /// Open the emergency-contacts management page.
  navigateEmergencyContacts,
  none,
}

/// The voice agent's lifecycle, modelled as an explicit state machine so there
/// is exactly one source of truth and no path can strand the user.
///
/// ```
///   idle ──(button down)──► listening ──(button up)──► thinking ──► speaking ──► idle
///     ▲                          │                         │            │
///     └──────────────────────────┴─────────────────────────┴────────────┘
///                       (button down = barge-in: jump back to listening)
/// ```
enum VoiceState { idle, listening, thinking, speaking }

/// Orchestrates speech recognition, intent matching, the cloud LLM, and
/// navigation as a single-turn voice agent with **barge-in**.
///
/// Design (push-to-talk, so the button is the turn-detector — no VAD/echo
/// cancellation needed):
///  * **Button down** always starts a fresh turn. If the agent was thinking or
///    speaking, that is a *barge-in*: TTS is silenced immediately and the
///    previous turn is invalidated so its late result is discarded.
///  * **Turn epoch** ([_turn]): every async result (STT, LLM, TTS) is tagged
///    with the turn it belongs to and dropped if a newer turn has begun — this
///    is what makes interruption safe and race-free.
///  * **No dead ends**: empty transcripts, errors, timeouts and barge-in all
///    transition to a defined state; a per-turn watchdog is the final net so
///    the user can never be locked out of the microphone.
class VoiceNavigationService extends ChangeNotifier {
  static VoiceNavigationService? _instance;

  final GroqService _groq = GroqService.instance;
  final GeminiService _gemini = GeminiService.instance;
  final IntentMatcher _matcher = IntentMatcher.instance;
  final SpeechService _speech = SpeechService.instance;
  final TtsService _tts = TtsService.instance;

  /// Whether the most recent command was resolved locally (true) or
  /// escalated to the cloud LLM (false).  Surfaces in debug overlays.
  bool _lastWasLocal = false;
  bool get lastWasLocal => _lastWasLocal;

  VoiceState _state = VoiceState.idle;

  /// Monotonic turn counter. Bumped on every button-down; async work compares
  /// the turn it captured against this to know if it has been superseded.
  int _turn = 0;

  String _currentTranscript = '';
  String _lastResponse = '';
  String _error = '';

  // Navigation callback
  Function(VoiceAction action)? onNavigationAction;

  /// Optional screen-scoped handler that gets first crack at a final
  /// transcript (set by the SOS screen for its contact dialog). Returns true
  /// if it consumed the utterance; false to fall through to the normal
  /// intent-matcher / LLM pipeline so global commands still work.
  Future<bool> Function(String transcript)? transcriptInterceptor;

  // Singleton
  static VoiceNavigationService get instance {
    _instance ??= VoiceNavigationService._();
    return _instance!;
  }

  VoiceNavigationService._() {
    _setupSpeechCallbacks();
  }

  // ── State getters (back the existing UI) ──────────────────────────
  bool get isListening => _state == VoiceState.listening;
  bool get isProcessing => _state == VoiceState.thinking;
  bool get isSpeaking => _state == VoiceState.speaking;
  bool get isBusy => _state != VoiceState.idle;
  String get currentTranscript => _currentTranscript;
  String get lastResponse => _lastResponse;
  String get error => _error;

  void _setState(VoiceState s) {
    if (_state == s) return;
    _state = s;
    // Audio-channel arbitration: while a turn is live (user dictating, LLM
    // thinking, reply speaking) the fusion layer must not talk over it —
    // fusion speech would corrupt STT capture or cut off the reply. The sonar
    // CRITICAL alarm stays independent, so safety is not reduced.
    if (AppConstants.enableSensorFusion) {
      SensorFusionService.instance.voicePipelineBusy = s != VoiceState.idle;
    }
    notifyListeners();
  }

  /// Initialize all services
  Future<void> initialize() async {
    debugPrint('[INIT] VoiceNavigationService.initialize()');

    // TTS first — so it is ready to *speak* any failure from the steps below
    // (e.g. mic permission denied during speech init) instead of failing
    // silently for a blind user.
    try {
      await _tts.initialize();
      debugPrint('[INIT] TtsService ready');
    } catch (e) {
      debugPrint('[INIT] !! TTS init error: $e');
    }

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
  }

  /// Setup speech recognition callbacks
  void _setupSpeechCallbacks() {
    _speech.onResult = (text, isFinal) {
      _currentTranscript = text;
      notifyListeners();

      final tag = isFinal ? 'FINAL  ' : 'partial';
      debugPrint('[STT] $tag : "$text" (len=${text.length})');

      if (isFinal) _onFinalTranscript(text);
    };

    // Status is informational only — the state machine here is authoritative,
    // so a stray status can never strand the user (the old bug).
    _speech.onStatus = (status) => debugPrint('[STT] status -> $status');

    _speech.onError = (error) {
      // Don't speak here: the pipeline also delivers an empty final transcript
      // on error, and [_onFinalTranscript] gives a single retry cue. Just
      // record it for the debug overlay.
      debugPrint('[STT] !! error : $error');
      _error = error;
    };
  }

  // ── Push-to-talk turn control ─────────────────────────────────────

  /// Button **down**. Always honored — this is the barge-in entry point.
  Future<void> startListening() async {
    // Already capturing (a duplicate key-down) — ignore.
    if (_state == VoiceState.listening) return;

    // New turn: invalidates any in-flight thinking/speaking from a prior turn.
    final turn = ++_turn;
    _error = '';
    _currentTranscript = '';

    // Barge-in: silence the assistant at once so it neither talks over the user
    // nor lets the mic capture its own TTS.
    try {
      await _tts.stop();
    } catch (_) {}

    _setState(VoiceState.listening);
    debugPrint('[STT] >>> startListening() turn=$turn');

    try {
      // Blocks for the whole hold; the final transcript arrives via onResult
      // and is handled in [_onFinalTranscript]. After this returns the state is
      // already thinking/speaking/idle, so we don't touch it here.
      await _speech.startListening();
    } catch (e) {
      debugPrint('[STT] !! startListening error: $e');
      if (turn == _turn) {
        _setState(VoiceState.idle);
        VoiceAnnouncer.announce('শুনতে সমস্যা হয়েছে।');
      }
    }
  }

  /// Button **up**. Finalizes the current utterance (tail-drain → transcript).
  Future<void> stopListening() async {
    if (_state != VoiceState.listening) return;
    debugPrint('[STT] <<< stopListening() — finalizing');
    // Reflect "wrapping up" immediately; the transcript handler decides whether
    // there's anything to process.
    _setState(VoiceState.thinking);
    await _speech.stopListening();
  }

  void _onFinalTranscript(String text) {
    final turn = _turn;
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      // Nothing recognised (silence, a too-short press, or an STT error). Never
      // hang — return to idle and give one short retry cue.
      debugPrint('[STT] final transcript empty — prompting retry');
      if (turn == _turn) _setState(VoiceState.idle);
      VoiceAnnouncer.announce('শুনতে পাইনি, আবার বলুন।');
      return;
    }

    // A screen-scoped interceptor (e.g. the SOS contact dialog) gets first
    // crack. If it consumes the utterance, the normal intent/LLM pipeline is
    // skipped; otherwise we fall through so global commands still work.
    final interceptor = transcriptInterceptor;
    if (interceptor != null) {
      _setState(VoiceState.thinking);
      interceptor(trimmed)
          .then((handled) {
            if (turn != _turn) return;
            if (handled) {
              _setState(VoiceState.idle);
            } else {
              _processCommand(trimmed, turn);
            }
          })
          .catchError((Object e) {
            debugPrint('[VOICE] interceptor error: $e');
            if (turn == _turn) _processCommand(trimmed, turn);
          });
      return;
    }

    _processCommand(trimmed, turn);
  }

  /// Short spoken reminder of the main things the user can say, appended
  /// whenever a command doesn't resolve to an action so a voice-only user
  /// always has a way forward.  These all resolve locally (no network), so the
  /// suggestions still work even when the cloud LLM is unreachable.
  static const String _commandHint =
      'আপনি বলতে পারেন: আমি কোথায়, ব্যাটারি, সাহায্য, বা সেটিংস।';

  /// Process the voice command for [turn].
  ///
  /// Two-tier classification: local fuzzy/CMI matcher first (offline,
  /// sub-millisecond); cloud LLM only when the matcher is unsure AND the
  /// network is actually reachable. Every side effect is gated on [turn] so a
  /// barge-in cleanly discards a stale result, and a watchdog guarantees the
  /// machine always returns to idle.
  Future<void> _processCommand(String text, int turn) async {
    _setState(VoiceState.thinking);

    // Final safety net: nothing below may leave the user stuck in a busy state.
    final watchdog = Timer(const Duration(seconds: 20), () {
      if (turn != _turn) return;
      debugPrint('[VOICE] !! watchdog fired — force-reset to idle');
      _setState(VoiceState.idle);
      VoiceAnnouncer.announce('সময় শেষ। আবার চেষ্টা করুন।');
    });

    try {
      VoiceCommandResponse response;

      _logBlockOpen(text);

      // Tier 1 — local fuzzy/CMI match (fully offline, sub-millisecond).
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
      } else if (AppConstants.enableLlm && await _hasInternet()) {
        // Tier 2 — cloud LLM fallback (Groq → Gemini), only when the host is
        // actually reachable so we never block an offline user on a socket
        // timeout.
        _lastWasLocal = false;
        response = await _tryCloudLlm(text);
      } else {
        // Tier 3 — local-only fallback: the LLM is disabled, or we're offline.
        // Answer immediately (no network wait); the no-action branch below
        // appends the list of commands that work offline.
        _lastWasLocal = false;
        final offline = AppConstants.enableLlm;
        response = VoiceCommandResponse(
          action: 'none',
          spokenResponse: offline
              ? 'ইন্টারনেট সংযোগ নেই।'
              : 'দুঃখিত, বুঝতে পারিনি।',
        );
        _logResolution(
          source: offline ? 'OFFLINE' : 'STUB',
          action: response.action,
          reply: response.spokenResponse,
        );
      }

      _logBlockClose();

      // Barged-in while thinking? Drop this result — the new turn owns things.
      if (turn != _turn) {
        debugPrint('[VOICE] result superseded by newer turn — discarding');
        return;
      }

      _lastResponse = response.spokenResponse;
      final action = _parseAction(response.action);

      final String toSpeak;
      if (action == VoiceAction.describeScene) {
        // Answer from the live fusion window instead of speaking the canned
        // intent reply — this is what makes "what's in front of me?" useful.
        toSpeak = SensorFusionService.instance.getSceneDescription();
        _lastResponse = toSpeak;
      } else if (action == VoiceAction.none) {
        // Dead end — append a short reminder of what the user CAN say.
        toSpeak = '${response.spokenResponse} $_commandHint';
      } else {
        toSpeak = response.spokenResponse;
      }

      // Speak the reply. Interruptible: a button press calls _tts.stop(), which
      // resolves this await early, and the turn check below discards the rest.
      _setState(VoiceState.speaking);
      await VoiceAnnouncer.speak(
        toSpeak,
      ).timeout(const Duration(seconds: 15), onTimeout: () {});

      // Barged-in during playback? Don't navigate on an abandoned turn.
      if (turn != _turn) return;

      // describeScene is answered in-place above; everything else that maps to
      // a real action routes through the navigation callback.
      if (action != VoiceAction.none && action != VoiceAction.describeScene) {
        onNavigationAction?.call(action);
      }
    } catch (e) {
      debugPrint('[VOICE] !! processing error: $e');
      _logBlockClose();
      if (turn == _turn) {
        _error = 'Processing error: $e';
        await VoiceAnnouncer.announce(
          'দুঃখিত, একটি সমস্যা হয়েছে। $_commandHint',
        );
      }
    } finally {
      watchdog.cancel();
      // Only the current turn may close the machine — a barge-in turn owns the
      // state now and must not be reset out from under itself.
      if (turn == _turn &&
          (_state == VoiceState.thinking || _state == VoiceState.speaking)) {
        _setState(VoiceState.idle);
      }
    }
  }

  /// Two-tier cloud LLM: tries Groq first (fast LPU), silently falls back to
  /// Gemini if Groq fails or its response indicates an error.
  ///
  /// The fallback is transparent to the user — they only hear the final
  /// spoken response regardless of which provider delivered it.
  Future<VoiceCommandResponse> _tryCloudLlm(String text) async {
    // ── Tier 2a: Groq (primary) ──────────────────────────────────────────
    final groqSw = Stopwatch()..start();
    _logGroqRequest();
    VoiceCommandResponse groqResponse;
    try {
      groqResponse = await _groq
          .processCommand(text)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                VoiceCommandResponse.error('সার্ভারে সংযোগ করা যায়নি।'),
          );
    } catch (e) {
      debugPrint('[GROQ] !! exception: $e');
      groqResponse = VoiceCommandResponse.error('Groq error: $e');
    }
    groqSw.stop();

    // A valid Groq response has action != 'none' OR a non-error spoken reply.
    // We treat a response as "failed" only when it carries the specific error
    // strings emitted by GroqService.error() — meaning a network/API failure,
    // not a legitimate "none" action from the model.
    final groqFailed =
        groqResponse.action == 'none' &&
        (groqResponse.spokenResponse.contains('সংযোগ') ||
            groqResponse.spokenResponse.contains('error') ||
            groqResponse.spokenResponse.contains('Error'));

    if (!groqFailed) {
      _logCloudResponse(
        provider: 'GROQ',
        action: groqResponse.action,
        reply: groqResponse.spokenResponse,
        elapsedMs: groqSw.elapsedMilliseconds,
      );
      return groqResponse;
    }

    // ── Tier 2b: Gemini (fallback) ────────────────────────────────────────
    debugPrint(
      '[GROQ] failed (${groqSw.elapsedMilliseconds}ms) — escalating to Gemini',
    );
    _logGeminiRequest();
    final geminiSw = Stopwatch()..start();
    VoiceCommandResponse geminiResponse;
    try {
      geminiResponse = await _gemini
          .processCommand(text)
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => VoiceCommandResponse.error('Gemini timeout'),
          );
    } catch (e) {
      debugPrint('[GEMINI] !! exception: $e');
      geminiResponse = VoiceCommandResponse.error('দুঃখিত, বুঝতে পারিনি।');
    }
    geminiSw.stop();
    _logCloudResponse(
      provider: 'GEMINI',
      action: geminiResponse.action,
      reply: geminiResponse.spokenResponse,
      elapsedMs: geminiSw.elapsedMilliseconds,
    );
    return geminiResponse;
  }

  /// Fast reachability probe for the cloud LLM host. A DNS lookup bounded by a
  /// short timeout distinguishes "no internet" (airplane mode, Wi-Fi off,
  /// captive portal) from "online" without a plugin dependency — so an offline
  /// user gets an instant local answer instead of waiting on a socket timeout
  /// while stuck in the processing state.
  Future<bool> _hasInternet() async {
    try {
      final r = await InternetAddress.lookup(
        'api.groq.com',
      ).timeout(const Duration(seconds: 3));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
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
      debugPrint('  top      : ${top.action} <- "${top.phrase}"');
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

  void _logGroqRequest() {
    debugPrint(_logSubRule);
    debugPrint('[GROQ] >>> sending to Groq LLM (primary cloud)');
    debugPrint('  reason   : local confidence below threshold');
    debugPrint('  endpoint : api.groq.com  (LLaMA 3.3 70B)');
  }

  void _logGeminiRequest() {
    debugPrint(_logSubRule);
    debugPrint('[GEMINI] >>> escalating to Gemini (fallback cloud)');
    debugPrint('  reason   : Groq failed or timed out');
    debugPrint(
      '  endpoint : generativelanguage.googleapis.com  (Gemini 2.5 Flash)',
    );
  }

  void _logCloudResponse({
    required String provider,
    required String action,
    required String reply,
    required int elapsedMs,
  }) {
    debugPrint('[$provider] <<< response received');
    debugPrint('  action   : $action');
    debugPrint('  reply    : "$reply"');
    debugPrint('  latency  : ${elapsedMs}ms');
    debugPrint('>> RESOLVED via $provider  (API call made)');
  }

  void _logResolution({
    required String source,
    required String action,
    required String reply,
  }) {
    final tag = source == 'LOCAL'
        ? '>> RESOLVED via LOCAL  (no API call)'
        : source == 'OFFLINE'
        ? '>> RESOLVED via OFFLINE (local-only, no network)'
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
      case 'describe_scene':
        return VoiceAction.describeScene;
      case 'trigger_sos':
        return VoiceAction.triggerSos;
      case 'navigate_emergency_contacts':
        return VoiceAction.navigateEmergencyContacts;
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
}
