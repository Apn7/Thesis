# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Accessibility-first Flutter companion app for a smart cane device, targeting visually impaired users in Bangladesh. Features bilingual Bangla/English UI, voice guidance (speech-to-text + TTS), BLE obstacle alerts from a Raspberry Pi, and GPS location.

## Commands

### Setup & Run
```bash
flutter pub get
flutter run
flutter run -d <device-id>
```

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
- `flutter analyze` passes with info-level deprecation warnings (`withOpacity`, deprecated `RadioListTile` APIs, `speech_to_text` listen params).
- `flutter test` fails in `test/widget_test.dart` because `flutter_blue_plus` is unsupported on the test platform. This is expected — run a focused single test instead.
- TTS (`flutter_tts`) is stubbed on Windows due to CMake issues. The stub logs instead of speaking.

## Architecture

Three-layer structure: `lib/core/` → `lib/services/` → `lib/presentation/`.

**State management:** Provider (`ChangeNotifier`). Services use singleton `.instance` accessors.

**Data flow:**
1. User speaks → `SpeechService` (offline Whisper GGML) transcribes audio
2. Transcription → `GroqService` (Groq LLaMA API) returns `{"action": "...", "spoken_response": "..."}`
3. `VoiceNavigationService` orchestrates navigation + `TtsService` speaks response
4. BLE alerts → `BleService` receives `"LEVEL:OBJECT:CONFIDENCE:POSITION"` strings from Pi, parsed into `BleAlert` and announced via TTS

**Key services:**
- `VoiceNavigationService` — orchestrates the full voice pipeline; exposes `onNavigationAction` callback for routing
- `BleService` — BLE communication with Raspberry Pi; emits `BleAlert` objects; auto-reconnects after 3s
- `SpeechService` — offline STT via `whisper_ggml`; records 16kHz mono WAV, loads model from `assets/models/`
- `GroqService` — Groq API HTTP client; maintains conversation history (max 10 messages)
- `TtsService` — abstract interface; platform-specific: `tts_service_impl.dart` (mobile) vs `tts_service_stub.dart` (Windows)
- `LocationService` — GPS via `geolocator` + reverse geocoding via OpenStreetMap Nominatim (no API key)

**BLE protocol:** Service UUID `12345678-1234-5678-1234-56789abcdef0`, alert characteristic `...abcdef1`, battery `...abcdef2`. Debug logs prefixed `>> BLE:`.

**Config:** `lib/core/config/api_config.dart` holds the Groq API key and BLE UUIDs. The key is currently checked in — do not log or expose it further. Prefer `--dart-define` for any new secrets.

## Conventions

- Use relative imports for app-local files; package imports for SDK and third-party.
- Reuse `AppColors`, `AppTextStyles`, `AppConstants`, `AppRoutes` before adding new values.
- Routes are centralized in `lib/core/navigation/app_routes.dart`.
- Check `mounted` after every `await` before calling `setState`, showing dialogs, or using `ScaffoldMessenger`.
- Preserve the bilingual Bangla/English text pattern on all user-facing strings.
- Accessibility is non-optional: keep semantic labels, hints, large touch targets (`minTouchTargetSize` = 56px, `largeTouchTargetSize` = 72px).
- Wrap all plugin/BLE/HTTP/speech/TTS calls in `try/catch`; surface errors via state, dialogs, or `SnackBar`.
- For `ChangeNotifier`, update internal state before calling `notifyListeners()`.
- Keep portrait-only orientation and text-scale clamping (0.8–2.0×) configured in `lib/main.dart`.
