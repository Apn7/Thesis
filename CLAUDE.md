# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Accessibility-first Flutter companion app for a smart cane device, targeting visually impaired users in Bangladesh. Features bilingual Bangla/English UI, voice guidance (speech-to-text + TTS), BLE obstacle alerts from a Raspberry Pi, and GPS location. Targets Android + Windows (iOS/Linux/macOS folders exist but are not actively developed).

## Commands

### Setup & Run
```bash
flutter pub get
flutter run
flutter run -d <device-id>
```

**First-time setup:** copy `.env.example` to `.env` and set `GROQ_API_KEY`. Download sherpa-onnx model binaries (gitignored) with `python download_model.py` before running.

### Lint & Format
```bash
dart format .
flutter analyze
```

### Test
```bash
flutter test
flutter test <file> --plain-name "<test name>"
flutter test --reporter expanded
```

### Build
```bash
flutter build apk          # Android APK
flutter build appbundle    # Android App Bundle
flutter build windows
```

### Post-change verification
```bash
dart format .
flutter analyze
flutter test
```

## Known Issues
- `flutter analyze` passes with info-level deprecation warnings (`withOpacity`, deprecated `RadioListTile` APIs, `speech_to_text` listen params). These are expected.
- `flutter test` fails in `test/widget_test.dart` because `flutter_blue_plus` is unsupported on the test platform. Run focused single tests instead.
- TTS (`flutter_tts`) was removed on Windows due to CMake issues. The Windows stub logs instead of speaking.

## Architecture

Three-layer structure: `lib/core/` → `lib/services/` → `lib/presentation/`.

**State management:** Provider (`ChangeNotifier`). Services use singleton `.instance` accessors.

**Data flow (voice pipeline):**
1. User speaks → `SpeechService` (dual-engine STT) transcribes audio
2. Transcription → `GroqService` (Groq LLaMA API) returns `{"action": "...", "spoken_response": "..."}`
3. `VoiceNavigationService` orchestrates navigation + `TtsService` speaks response
4. BLE alerts → `BleService` receives `"LEVEL:OBJECT:CONFIDENCE:POSITION"` strings from Pi, parsed into `BleAlert` and announced via TTS

**Key services:**
- `VoiceNavigationService` — orchestrates the full voice pipeline; exposes `onNavigationAction` callback for routing
- `BleService` — BLE communication with Raspberry Pi; emits `BleAlert` objects; auto-reconnects after 3s
- `SpeechService` — dual-engine STT orchestrator; delegates to sherpa-onnx (Bengali) or Android built-in (English) based on `SettingsService.languageMode`
- `SettingsService` — persists app settings via `shared_preferences`; exposes `languageMode` ('bn'/'en'); calls `SpeechService.setLocale()` on change
- `GroqService` — Groq API HTTP client; maintains conversation history (max 10 messages)
- `TtsService` — abstract interface; platform-specific: `tts_service_impl.dart` (mobile) vs `tts_service_stub.dart` (Windows)
- `LocationService` — GPS via `geolocator` + reverse geocoding via OpenStreetMap Nominatim (no API key)

**STT subsystem (`lib/services/stt/`):**
- `SttEngine` (abstract) — interface with `startListening()`, `stopListening()`, `onResult(text, isFinal)` callback
- `SherpaEngine` — wraps `sherpa_onnx` streaming Zipformer model for offline Bengali; uses `AudioPipeline` for VAD + 16kHz mono capture
- `SttEngineFactory` — caches and disposes engine instances per locale
- `ModelAssetManager` — copies bundled model assets from Flutter assets to local storage on first launch (triggered from `SplashScreen`)
- Bengali uses streaming partial results; English uses Android's offline recognizer (online fallback if offline pack not installed)
- `sherpa.initBindings()` must be called before any recognizer is created — done in `main.dart`

**BLE protocol:** Service UUID `12345678-1234-5678-1234-56789abcdef0`, alert characteristic `...abcdef1`, battery `...abcdef2`. Debug logs prefixed `>> BLE:`.

**Config:** Groq API key loaded from `.env` at runtime via `flutter_dotenv` (also bundled as a Flutter asset). BLE UUIDs and model references in `lib/core/config/api_config.dart`. Do not log or expose the key; prefer `--dart-define` for any new secrets.

## Available Skills (`.agents/skills/`)

Invoke via the `Skill` tool using `superpowers:<skill-name>`. Use the most relevant skill **before** acting.

| Skill | When to use |
|-------|-------------|
| `using-superpowers` | Start of any conversation — establishes skill discovery rules |
| `brainstorming` | **Before any creative work** (new features, components, behavior changes); hard gate — no code until design is approved |
| `writing-plans` | After design is approved; creates bite-sized TDD implementation plans saved to `docs/superpowers/plans/` |
| `subagent-driven-development` | Executing a plan in the current session; dispatches a fresh subagent per task + two-stage review (spec then quality) |
| `executing-plans` | Executing a plan in a separate parallel session with human-in-loop checkpoints |
| `dispatching-parallel-agents` | 2+ independent failures/tasks with no shared state — investigate in parallel |
| `systematic-debugging` | Any bug, test failure, or unexpected behavior — 4 phases: root cause → pattern → hypothesis → fix |
| `test-driven-development` | Implementing any feature or bugfix — Red-Green-Refactor; no production code without a failing test first |
| `verification-before-completion` | Before claiming work is done, committing, or creating PRs — run commands, read output, then assert |
| `requesting-code-review` | After completing a task or feature — dispatches `code-reviewer` subagent with focused context |
| `receiving-code-review` | When receiving review feedback — verify before implementing; push back with technical reasoning if wrong |
| `finishing-a-development-branch` | When implementation is complete — verify tests, present 4 options (merge/PR/keep/discard) |
| `using-git-worktrees` | Before executing any plan — creates an isolated workspace on a new branch |
| `writing-skills` | Creating or editing skills using TDD for documentation |

## Conventions

- Imports: package imports for SDK/third-party; relative imports for app-local files.
- Reuse `AppColors`, `AppTextStyles`, `AppConstants`, `AppRoutes` before adding new values.
- Routes are centralized in `lib/core/navigation/app_routes.dart`.
- Check `mounted` after every `await` before calling `setState`, showing dialogs, or using `ScaffoldMessenger`.
- Preserve the bilingual Bangla/English text pattern on all user-facing strings. Use `AccessibilityLabels` in `lib/core/utils/accessibility_helper.dart` for semantic labels.
- Accessibility is non-optional: semantic labels, hints, large touch targets (`minTouchTargetSize` = 56px, `largeTouchTargetSize` = 72px). Portrait-only orientation and text-scale clamping (0.8–2.0×) are configured in `main.dart`.
- Wrap all plugin/BLE/HTTP/speech/TTS calls in `try/catch`; log with `debugPrint`; surface errors via state, dialogs, or `SnackBar`.
- For `ChangeNotifier`, update internal state before calling `notifyListeners()`.
