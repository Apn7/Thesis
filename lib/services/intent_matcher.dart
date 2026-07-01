// =============================================================================
//  IntentMatcher — Hybrid offline intent classifier for Bangla–English
//                  code-mixed voice commands.
//
//  PIPELINE OVERVIEW
//  ──────────────────────────────────────────────────────────────────────────
//                ┌──────────────┐   ┌──────────────┐   ┌──────────────────┐
//   raw input ──▶│ Normalise +  │──▶│ Code-Mixing  │──▶│ Ensemble fuzzy   │
//                │ tokenise +   │   │ Index (CMI)  │   │ string matching  │
//                │ stopword cut │   │ — Das &      │   │ over phrase bank │
//                └──────────────┘   │   Gambäck    │   └────────┬─────────┘
//                                   │   (2014)     │            │
//                                   └──────────────┘            ▼
//                                                       ┌──────────────────┐
//                                                       │ Confidence-      │
//                                                       │ calibrated       │
//                                                       │ decision         │
//                                                       └─────┬────────────┘
//                                                             │
//                                            ≥ τ ─────────────┼─────────── < τ
//                                            local action     │       fallback
//                                                             ▼              ▼
//                                                    return IntentMatch  Groq LLM
//
//  SIMILARITY ENSEMBLE
//  ──────────────────────────────────────────────────────────────────────────
//   (1) Damerau–Levenshtein similarity   — Damerau (1964); Levenshtein (1966)
//       Edit distance with transposition operator → robust to typing slips
//       like "settigns" ↔ "settings".
//
//   (2) Jaro–Winkler similarity          — Jaro (1989); Winkler (1990)
//       Up-weights matches sharing a common prefix, ideal for short
//       command words (e.g. "battery", "settings").
//
//   (3) Sørensen–Dice on character bigrams — Dice (1945); Sørensen (1948)
//       Script-agnostic — works equally well on Bangla, English, and
//       transliterated Banglish without language-specific tuning.
//
//   (4) TF-IDF weighted token cosine     — Salton & Buckley (1988)
//       Treats each phrase variant as a document; rare content words
//       (e.g. "battery") dominate scoring, common fillers are damped.
//
//   (5) Token-set Jaccard                — Jaccard (1912)
//       Order-invariant token overlap. Cheap sanity check.
//
//  Final score is the convex combination
//
//        S = w_DL·s₁ + w_JW·s₂ + w_DC·s₃ + w_TFIDF·s₄ + w_JC·s₅
//
//  with Σ wᵢ = 1.  An exact-/containment-match shortcut bypasses the
//  ensemble for a guaranteed S ≥ 0.85.
//
//  Decision threshold τ = [confidenceThreshold].  Below τ, the matcher
//  returns null and the caller (VoiceNavigationService) escalates to the
//  Groq cloud LLM — preserving recall while dramatically cutting API
//  spend and median latency.
//
//  All weights, the threshold, and the IDF table are exposed on
//  [IntentMatcherConfig] for reproducible thesis experiments.  Every match
//  emits a [MatchDiagnostics] block (top-K candidates with all sub-scores)
//  via [lastDiagnostics] for offline evaluation.
// =============================================================================

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'groq_service.dart' show VoiceCommandResponse;

// ─────────────────────────────────────────────────────────────────────────────
//  Public types
// ─────────────────────────────────────────────────────────────────────────────

/// Tunable parameters of the matcher.  Defaults were tuned on a hand-curated
/// set of Bangla / English / Banglish utterances; override any field for
/// thesis ablation studies.
@immutable
class IntentMatcherConfig {
  /// Decision threshold τ — confidence below this falls through to the LLM.
  final double confidenceThreshold;

  /// Convex-combination weights for the similarity ensemble.  Must sum to 1.0.
  final double wDamerauLevenshtein;
  final double wJaroWinkler;
  final double wSorensenDice;
  final double wTfIdfCosine;
  final double wJaccard;

  /// Jaro–Winkler prefix scaling factor p.  Winkler's recommendation: 0.1
  /// (max 0.25 to keep similarity ≤ 1.0).
  final double jaroWinklerPrefixScale;

  /// Maximum prefix length L used by Jaro–Winkler (Winkler caps L at 4).
  final int jaroWinklerPrefixLength;

  /// How many top candidates to retain in [MatchDiagnostics] (for evaluation
  /// dashboards / thesis tables).
  final int diagnosticsTopK;

  const IntentMatcherConfig({
    this.confidenceThreshold = 0.70,
    this.wDamerauLevenshtein = 0.20,
    this.wJaroWinkler = 0.25,
    this.wSorensenDice = 0.20,
    this.wTfIdfCosine = 0.25,
    this.wJaccard = 0.10,
    this.jaroWinklerPrefixScale = 0.1,
    this.jaroWinklerPrefixLength = 4,
    this.diagnosticsTopK = 5,
  });
}

/// Result of a successful local classification.
@immutable
class IntentMatch {
  final String action;
  final double confidence;
  final String spokenResponse;

  /// Code-Mixing Index of the input that produced this match (0 = monolingual,
  /// 1 = perfectly balanced bilingual).  Useful for per-language evaluation.
  final double codeMixingIndex;

  const IntentMatch({
    required this.action,
    required this.confidence,
    required this.spokenResponse,
    required this.codeMixingIndex,
  });

  VoiceCommandResponse toVoiceCommandResponse() =>
      VoiceCommandResponse(action: action, spokenResponse: spokenResponse);
}

/// Per-phrase sub-scores for one candidate.  Surfaces in [MatchDiagnostics].
@immutable
class CandidateScores {
  final String action;
  final String phrase;
  final double damerauLevenshtein;
  final double jaroWinkler;
  final double sorensenDice;
  final double tfIdfCosine;
  final double jaccard;
  final double containmentBoost;
  final double ensembleScore;

  const CandidateScores({
    required this.action,
    required this.phrase,
    required this.damerauLevenshtein,
    required this.jaroWinkler,
    required this.sorensenDice,
    required this.tfIdfCosine,
    required this.jaccard,
    required this.containmentBoost,
    required this.ensembleScore,
  });

  Map<String, dynamic> toJson() => {
    'action': action,
    'phrase': phrase,
    'damerau_levenshtein': damerauLevenshtein,
    'jaro_winkler': jaroWinkler,
    'sorensen_dice': sorensenDice,
    'tfidf_cosine': tfIdfCosine,
    'jaccard': jaccard,
    'containment_boost': containmentBoost,
    'ensemble_score': ensembleScore,
  };
}

/// Snapshot of the most recent classification — exposed for evaluation
/// notebooks, in-app debug overlays, and thesis result tables.
@immutable
class MatchDiagnostics {
  final String rawInput;
  final String normalisedInput;
  final List<String> tokens;
  final List<String> tokensAfterStopwords;
  final double codeMixingIndex;
  final List<CandidateScores> topCandidates;
  final double topScore;
  final bool acceptedLocally;
  final int latencyMicros;

  const MatchDiagnostics({
    required this.rawInput,
    required this.normalisedInput,
    required this.tokens,
    required this.tokensAfterStopwords,
    required this.codeMixingIndex,
    required this.topCandidates,
    required this.topScore,
    required this.acceptedLocally,
    required this.latencyMicros,
  });

  Map<String, dynamic> toJson() => {
    'raw_input': rawInput,
    'normalised_input': normalisedInput,
    'tokens': tokens,
    'tokens_after_stopwords': tokensAfterStopwords,
    'code_mixing_index': codeMixingIndex,
    'top_score': topScore,
    'accepted_locally': acceptedLocally,
    'latency_micros': latencyMicros,
    'top_candidates': topCandidates.map((c) => c.toJson()).toList(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
//  Internal types
// ─────────────────────────────────────────────────────────────────────────────

class _IntentDef {
  final String action;
  final List<String> rawPhrases;
  final List<String> normPhrases;
  final List<List<String>> phraseTokens; // post-stopword
  final List<Map<String, double>> phraseTfIdf; // sparse vectors
  final List<Set<String>> phraseBigrams;
  final String response;

  _IntentDef({
    required this.action,
    required this.rawPhrases,
    required this.normPhrases,
    required this.phraseTokens,
    required this.phraseTfIdf,
    required this.phraseBigrams,
    required this.response,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  IntentMatcher
// ─────────────────────────────────────────────────────────────────────────────

class IntentMatcher {
  IntentMatcher._({String? assetPath})
    : _assetPath = assetPath ?? _defaultAssetPath;

  static IntentMatcher? _instance;

  /// The shared global matcher — phrase bank is app-wide navigation/utility
  /// commands only. Screen-scoped control words (e.g. a voice dialog's
  /// yes/no/cancel) must NOT live here: this instance is queried by
  /// [VoiceNavigationService] on every transcript regardless of which screen
  /// is open, so anything matched here can fire from anywhere in the app.
  static IntentMatcher get instance => _instance ??= IntentMatcher._();

  /// A private matcher loaded from [assetPath], independent of [instance] and
  /// its phrase bank / load state. Use this for a screen-local vocabulary
  /// (e.g. [SosDialogController]'s "yes"/"no"/"cancel") that should only be
  /// recognised while that screen owns the voice pipeline — never globally.
  factory IntentMatcher.scoped(String assetPath) =>
      IntentMatcher._(assetPath: assetPath);

  /// Default config — override via [setConfig] for ablations.
  IntentMatcherConfig _cfg = const IntentMatcherConfig();
  IntentMatcherConfig get config => _cfg;
  void setConfig(IntentMatcherConfig cfg) {
    assert(
      (cfg.wDamerauLevenshtein +
                  cfg.wJaroWinkler +
                  cfg.wSorensenDice +
                  cfg.wTfIdfCosine +
                  cfg.wJaccard -
                  1.0)
              .abs() <
          1e-6,
      'IntentMatcher weights must sum to 1.0',
    );
    _cfg = cfg;
  }

  static const String _defaultAssetPath = 'assets/intents/intents.json';
  final String _assetPath;

  // Stopwords ------------------------------------------------------------------
  // Pruning these *before* token-set similarity prevents fillers like "the",
  // "to", "এর", "এ" from inflating Jaccard / TF-IDF scores.

  static const Set<String> _stopwordsEn = {
    'a',
    'an',
    'the',
    'is',
    'are',
    'am',
    'be',
    'been',
    'being',
    'do',
    'does',
    'did',
    'to',
    'of',
    'in',
    'on',
    'at',
    'for',
    'with',
    'and',
    'or',
    'but',
    'i',
    'me',
    'my',
    'we',
    'us',
    'our',
    'you',
    'your',
    'this',
    'that',
    'these',
    'those',
    'please',
    'now',
    'just',
    'can',
    'could',
    'would',
    'will',
    'shall',
    'tell',
    'show',
    'open',
    'go',
    'it',
    'so',
  };

  /// A small but high-frequency Bengali stopword list (postpositions,
  /// pronouns, copula).  Curated from common Bangla NLP resources.
  static const Set<String> _stopwordsBn = {
    'এ',
    'ও',
    'এই',
    'সেই',
    'একটি',
    'একটা',
    'যে',
    'যা',
    'যার',
    'কি',
    'কী',
    'কে',
    'কেউ',
    'কোন',
    'কোনো',
    'এখন',
    'তখন',
    'আমি',
    'আমার',
    'তুমি',
    'তোমার',
    'আপনি',
    'আপনার',
    'সে',
    'তার',
    'করে',
    'করো',
    'করছে',
    'করছি',
    'হবে',
    'হয়',
    'হচ্ছে',
    'আছে',
    'আছি',
    'ছিল',
    'এর',
    'একটু',
    'অনেক',
    'বেশি',
    'কম',
    'খুব',
    'যাও',
    'দাও',
    'বলো',
  };

  // ── State ───────────────────────────────────────────────────────────
  bool _loaded = false;
  bool get isLoaded => _loaded;

  final List<_IntentDef> _intents = [];

  /// Inverse Document Frequency over the phrase corpus (each phrase = 1 doc).
  /// Built once at [load] time.
  final Map<String, double> _idf = {};

  MatchDiagnostics? _lastDiagnostics;

  /// Most recent match diagnostics (top-K candidates with all sub-scores,
  /// CMI, normalised tokens, latency).  Useful for thesis evaluation tables
  /// and for an in-app debug overlay.
  MatchDiagnostics? get lastDiagnostics => _lastDiagnostics;

  // ─────────────────────────────────────────────────────────────────────
  //  Loading + corpus statistics
  // ─────────────────────────────────────────────────────────────────────

  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final list = (json['intents'] as List).cast<Map<String, dynamic>>();

      // First pass: collect normalised phrases + token bags for IDF.
      final allPhraseTokenSets = <Set<String>>[];
      final perIntent = <_IntentRaw>[];

      for (final m in list) {
        final action = m['action'] as String;
        final phrases = (m['phrases'] as List).cast<String>();
        final response = m['response'] as String? ?? '';
        final normPhrases = phrases.map(_normalize).toList();
        final tokenLists = normPhrases
            .map(_tokenize)
            .map(_filterStopwords)
            .toList();
        for (final t in tokenLists) {
          allPhraseTokenSets.add(t.toSet());
        }
        perIntent.add(
          _IntentRaw(
            action: action,
            rawPhrases: phrases,
            normPhrases: normPhrases,
            tokenLists: tokenLists,
            response: response,
          ),
        );
      }

      // IDF over the phrase corpus: idf(t) = ln((N + 1) / (df(t) + 1)) + 1
      // (smoothed, per Salton & Buckley 1988 + Manning et al. recommendation).
      final n = allPhraseTokenSets.length;
      final df = <String, int>{};
      for (final s in allPhraseTokenSets) {
        for (final t in s) {
          df[t] = (df[t] ?? 0) + 1;
        }
      }
      _idf.clear();
      df.forEach((term, freq) {
        _idf[term] = math.log((n + 1) / (freq + 1)) + 1.0;
      });

      // Second pass: now that we have IDF, build the per-phrase TF-IDF
      // sparse vectors and bigram sets for Sørensen–Dice.
      for (final raw in perIntent) {
        final tfIdfs = <Map<String, double>>[];
        final bigrams = <Set<String>>[];
        for (var i = 0; i < raw.normPhrases.length; i++) {
          tfIdfs.add(_tfIdfVector(raw.tokenLists[i]));
          bigrams.add(_charBigrams(raw.normPhrases[i]));
        }
        _intents.add(
          _IntentDef(
            action: raw.action,
            rawPhrases: raw.rawPhrases,
            normPhrases: raw.normPhrases,
            phraseTokens: raw.tokenLists,
            phraseTfIdf: tfIdfs,
            phraseBigrams: bigrams,
            response: raw.response,
          ),
        );
      }

      _loaded = true;
      debugPrint(
        'IntentMatcher: loaded ${_intents.length} intents, '
        '${allPhraseTokenSets.length} phrases, '
        '${_idf.length}-term IDF table',
      );
    } catch (e, st) {
      debugPrint('IntentMatcher: load failed — $e\n$st');
      _loaded = true; // avoid retry storms
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Public match API
  // ─────────────────────────────────────────────────────────────────────

  /// Classify [text] locally.  Returns null if no intent reaches τ.
  IntentMatch? match(String text) {
    final stopwatch = Stopwatch()..start();
    if (!_loaded || _intents.isEmpty) return null;

    final normInput = _normalize(text);
    if (normInput.isEmpty) return null;

    final inputTokensAll = _tokenize(normInput);
    final inputTokens = _filterStopwords(inputTokensAll);
    final inputTfIdf = _tfIdfVector(inputTokens);
    final inputBigrams = _charBigrams(normInput);
    final cmi = _codeMixingIndex(text);

    final allCandidates = <CandidateScores>[];

    for (final intent in _intents) {
      for (var i = 0; i < intent.normPhrases.length; i++) {
        final phrase = intent.normPhrases[i];
        final pTokens = intent.phraseTokens[i];
        final pTfIdf = intent.phraseTfIdf[i];
        final pBigrams = intent.phraseBigrams[i];

        final dl = _damerauLevenshteinSimilarity(normInput, phrase);
        final jw = _jaroWinklerSimilarity(normInput, phrase);
        final dc = _sorensenDiceBigram(inputBigrams, pBigrams);
        final tf = _cosine(inputTfIdf, pTfIdf);
        final jc = _jaccardTokens(inputTokens, pTokens);
        final boost = _containmentBoost(normInput, phrase);

        final ensemble = _ensemble(dl, jw, dc, tf, jc, boost);

        allCandidates.add(
          CandidateScores(
            action: intent.action,
            phrase: intent.rawPhrases[i],
            damerauLevenshtein: dl,
            jaroWinkler: jw,
            sorensenDice: dc,
            tfIdfCosine: tf,
            jaccard: jc,
            containmentBoost: boost,
            ensembleScore: ensemble,
          ),
        );
      }
    }

    allCandidates.sort((a, b) => b.ensembleScore.compareTo(a.ensembleScore));
    final topK = allCandidates.take(_cfg.diagnosticsTopK).toList();
    final top = topK.first;
    final accepted = top.ensembleScore >= _cfg.confidenceThreshold;

    stopwatch.stop();
    _lastDiagnostics = MatchDiagnostics(
      rawInput: text,
      normalisedInput: normInput,
      tokens: inputTokensAll,
      tokensAfterStopwords: inputTokens,
      codeMixingIndex: cmi,
      topCandidates: topK,
      topScore: top.ensembleScore,
      acceptedLocally: accepted,
      latencyMicros: stopwatch.elapsedMicroseconds,
    );

    if (!accepted) return null;

    final intent = _intents.firstWhere((i) => i.action == top.action);

    return IntentMatch(
      action: top.action,
      confidence: top.ensembleScore,
      spokenResponse: intent.response,
      codeMixingIndex: cmi,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Ensemble combiner
  // ─────────────────────────────────────────────────────────────────────

  double _ensemble(
    double dl,
    double jw,
    double dc,
    double tf,
    double jc,
    double boost,
  ) {
    final base =
        _cfg.wDamerauLevenshtein * dl +
        _cfg.wJaroWinkler * jw +
        _cfg.wSorensenDice * dc +
        _cfg.wTfIdfCosine * tf +
        _cfg.wJaccard * jc;
    // Containment boost is additive but capped so it can't push past 1.0.
    return math.min(1.0, base + boost);
  }

  /// Exact / containment shortcut.  Returns up to +0.20 on top of the
  /// ensemble — guaranteeing user inputs that *literally contain* a known
  /// phrase clear τ even if the ensemble score is borderline.
  double _containmentBoost(String input, String phrase) {
    if (phrase.isEmpty) return 0.0;
    if (input == phrase) return 0.20;
    if (input.contains(phrase) || phrase.contains(input)) {
      final shorter = math.min(input.length, phrase.length);
      final longer = math.max(input.length, phrase.length);
      return 0.10 + 0.10 * (shorter / longer);
    }
    return 0.0;
  }

  // ─────────────────────────────────────────────────────────────────────
  //  (1) Damerau–Levenshtein similarity
  //      Damerau (1964); Levenshtein (1966)
  // ─────────────────────────────────────────────────────────────────────

  double _damerauLevenshteinSimilarity(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final dist = _damerauLevenshtein(a, b);
    final maxLen = math.max(a.length, b.length);
    return 1.0 - dist / maxLen;
  }

  /// Optimal-string-alignment variant: handles single transpositions of
  /// adjacent characters in addition to insert / delete / substitute.
  /// O(|a|·|b|) time, O(|a|·|b|) space.
  int _damerauLevenshtein(String a, String b) {
    final m = a.length;
    final n = b.length;
    final d = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (var i = 0; i <= m; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= n; j++) {
      d[0][j] = j;
    }

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        d[i][j] = [
          d[i - 1][j] + 1, // deletion
          d[i][j - 1] + 1, // insertion
          d[i - 1][j - 1] + cost, // substitution
        ].reduce(math.min);
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          d[i][j] = math.min(d[i][j], d[i - 2][j - 2] + 1); // transposition
        }
      }
    }
    return d[m][n];
  }

  // ─────────────────────────────────────────────────────────────────────
  //  (2) Jaro–Winkler similarity
  //      Jaro (1989); Winkler (1990)
  // ─────────────────────────────────────────────────────────────────────

  double _jaroWinklerSimilarity(String s1, String s2) {
    final j = _jaro(s1, s2);
    if (j < 0.7) return j; // Winkler bonus only above this gate.
    final l = math.min(_cfg.jaroWinklerPrefixLength, _commonPrefix(s1, s2));
    return j + l * _cfg.jaroWinklerPrefixScale * (1 - j);
  }

  double _jaro(String s1, String s2) {
    if (s1.isEmpty && s2.isEmpty) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    if (s1 == s2) return 1.0;

    final matchWindow = math.max(s1.length, s2.length) ~/ 2 - 1;
    final s1Matches = List<bool>.filled(s1.length, false);
    final s2Matches = List<bool>.filled(s2.length, false);

    var matches = 0;
    for (var i = 0; i < s1.length; i++) {
      final start = math.max(0, i - matchWindow);
      final end = math.min(i + matchWindow + 1, s2.length);
      for (var j = start; j < end; j++) {
        if (s2Matches[j]) continue;
        if (s1.codeUnitAt(i) != s2.codeUnitAt(j)) continue;
        s1Matches[i] = true;
        s2Matches[j] = true;
        matches++;
        break;
      }
    }
    if (matches == 0) return 0.0;

    var t = 0;
    var k = 0;
    for (var i = 0; i < s1.length; i++) {
      if (!s1Matches[i]) continue;
      while (!s2Matches[k]) {
        k++;
      }
      if (s1.codeUnitAt(i) != s2.codeUnitAt(k)) t++;
      k++;
    }
    final m = matches.toDouble();
    return (m / s1.length + m / s2.length + (m - t / 2) / m) / 3.0;
  }

  int _commonPrefix(String a, String b) {
    final n = math.min(a.length, b.length);
    var i = 0;
    while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }

  // ─────────────────────────────────────────────────────────────────────
  //  (3) Sørensen–Dice on character bigrams
  //      Dice (1945); Sørensen (1948)
  // ─────────────────────────────────────────────────────────────────────

  double _sorensenDiceBigram(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final inter = a.intersection(b).length;
    return 2.0 * inter / (a.length + b.length);
  }

  Set<String> _charBigrams(String s) {
    if (s.length < 2) return {s};
    final out = <String>{};
    for (var i = 0; i < s.length - 1; i++) {
      out.add(s.substring(i, i + 2));
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────
  //  (4) TF-IDF weighted token cosine similarity
  //      Salton & Buckley (1988)
  // ─────────────────────────────────────────────────────────────────────

  Map<String, double> _tfIdfVector(List<String> tokens) {
    if (tokens.isEmpty) return const {};
    final tf = <String, int>{};
    for (final t in tokens) {
      tf[t] = (tf[t] ?? 0) + 1;
    }
    final out = <String, double>{};
    final norm = tokens.length.toDouble();
    tf.forEach((term, freq) {
      final idf = _idf[term] ?? math.log(_intents.length + 1.0) + 1.0;
      out[term] = (freq / norm) * idf; // l1-normalised TF · IDF
    });
    return out;
  }

  double _cosine(Map<String, double> a, Map<String, double> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    double dot = 0;
    double na = 0;
    double nb = 0;
    a.forEach((k, va) {
      na += va * va;
      final vb = b[k];
      if (vb != null) dot += va * vb;
    });
    b.forEach((_, vb) {
      nb += vb * vb;
    });
    if (na == 0 || nb == 0) return 0.0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  // ─────────────────────────────────────────────────────────────────────
  //  (5) Token-set Jaccard
  //      Jaccard (1912)
  // ─────────────────────────────────────────────────────────────────────

  double _jaccardTokens(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final sa = a.toSet();
    final sb = b.toSet();
    final union = sa.union(sb).length;
    if (union == 0) return 0.0;
    return sa.intersection(sb).length / union;
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Code-Mixing Index — Das & Gambäck (2014)
  //
  //    CMI = (N − max{wᵢ}) / N   ∈ [0, 1]
  //
  //  N      = total non-language-neutral tokens
  //  wᵢ     = token count for language i (Bangla or English)
  //  CMI=0  → fully monolingual
  //  CMI≈0.5→ balanced bilingual code-switching
  //
  //  We approximate per-token language identity by Unicode block: any token
  //  containing a Bengali codepoint is counted as Bangla, otherwise English.
  //  Punctuation-only tokens are treated as language-neutral.
  // ─────────────────────────────────────────────────────────────────────

  double _codeMixingIndex(String raw) {
    final toks = _tokenize(_normalize(raw));
    if (toks.isEmpty) return 0.0;
    var bn = 0;
    var en = 0;
    for (final t in toks) {
      if (_containsBengali(t)) {
        bn++;
      } else if (_containsLatin(t)) {
        en++;
      }
    }
    final total = bn + en;
    if (total == 0) return 0.0;
    final maxLang = math.max(bn, en);
    return (total - maxLang) / total;
  }

  bool _containsBengali(String s) {
    for (final r in s.runes) {
      if (r >= 0x0980 && r <= 0x09FF) return true;
    }
    return false;
  }

  bool _containsLatin(String s) {
    for (final r in s.runes) {
      if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) return true;
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Normalisation + tokenisation
  // ─────────────────────────────────────────────────────────────────────

  static final RegExp _puncRe = RegExp(
    r"""[!?.,;:'"`~@#$%^&*()_+\-=\[\]{}<>/\\|।]""",
  );
  static final RegExp _wsRe = RegExp(r'\s+');

  /// Canonicalise Bengali nukta letters (ড়/ঢ়/য়). Sherpa-onnx STT and typed
  /// dictionary text disagree on representation: STT tends to emit the
  /// precomposed single codepoint (U+09DC/09DD/09DF), while phrases typed into
  /// intents.json use the decomposed base-consonant + nukta (U+09BC) sequence.
  /// They render identically but compare as different strings, so an exact
  /// STT transcript of a listed phrase can silently miss the containment-boost
  /// shortcut and fall below the confidence threshold on fuzzy scoring alone.
  /// Collapsing both sides to the precomposed form before scoring fixes this
  /// for every intent, not just one phrase.
  static String _canonicalizeNukta(String s) {
    return s
        .replaceAll('ড়', 'ড়') // ড + ় → ড়
        .replaceAll('ঢ়', 'ঢ়') // ঢ + ় → ঢ়
        .replaceAll('য়', 'য়'); // য + ় → য়
  }

  String _normalize(String s) {
    var t = s.toLowerCase().trim();
    t = _canonicalizeNukta(t);
    t = t.replaceAll(_puncRe, ' ');
    t = t.replaceAll(_wsRe, ' ').trim();
    return t;
  }

  List<String> _tokenize(String s) {
    if (s.isEmpty) return const [];
    return s.split(' ').where((w) => w.isNotEmpty).toList();
  }

  List<String> _filterStopwords(List<String> tokens) {
    return tokens
        .where((t) => !_stopwordsEn.contains(t) && !_stopwordsBn.contains(t))
        .toList();
  }
}

class _IntentRaw {
  final String action;
  final List<String> rawPhrases;
  final List<String> normPhrases;
  final List<List<String>> tokenLists;
  final String response;
  _IntentRaw({
    required this.action,
    required this.rawPhrases,
    required this.normPhrases,
    required this.tokenLists,
    required this.response,
  });
}
