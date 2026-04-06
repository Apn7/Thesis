# AGENTS.md

Guide for coding agents working in this repository.

## Project Snapshot

- **Stack:** Flutter + Dart 3.10+, Provider state management.
- **App:** Accessibility-first smart cane companion app for visually impaired users in Bangladesh.
- **Entrypoint:** `lib/main.dart` → `SmartCaneApp`.
- **Key features:** Bilingual Bangla/English UI, offline STT (sherpa-onnx), Groq LLM intent, BLE obstacle alerts from Raspberry Pi, GPS location.
- **Targets:** Android + Windows. (iOS/Linux/macOS platform folders exist but are not actively developed.)

## Architecture

Three-layer structure: `lib/core/` → `lib/services/` → `lib/presentation/`.

**Data flow (voice pipeline):**
1. User speaks → `SpeechService` (offline sherpa-onnx zipformer) transcribes audio.
2. Transcription → `GroqService` (Groq LLaMA API) returns `{"action": "...", "spoken_response": "..."}`.
3. `VoiceNavigationService` orchestrates navigation + `TtsService` speaks response.
4. BLE alerts → `BleService` receives `"LEVEL:OBJECT:CONFIDENCE:POSITION"` strings from Pi, parsed into `BleAlert` and announced via TTS.

**Key services (singleton `.instance` accessors):**
- `VoiceNavigationService` — full voice pipeline orchestrator; exposes `onNavigationAction` callback for routing.
- `BleService` — BLE comms with Pi; auto-reconnects after 3s. Service UUID `12345678-1234-5678-1234-56789abcdef0`, alert char `...abcdef1`, battery `...abcdef2`. Debug logs prefixed `>> BLE:`.
- `SpeechService` — offline STT via sherpa-onnx; records 16kHz mono WAV; models from `assets/models/`.
- `GroqService` — Groq API HTTP client; conversation history (max 10 messages).
- `TtsService` — abstract interface; `tts_service_impl.dart` (mobile) vs `tts_service_stub.dart` (Windows stub that logs instead of speaking).
- `LocationService` — GPS via `geolocator` + reverse geocoding via OpenStreetMap Nominatim (no API key).
- `SettingsService` — persisted app settings via `shared_preferences`.

**Routes:** centralized in `lib/core/navigation/app_routes.dart` (`/`, `/home`, `/location`, `/settings`, `/help`).

## Setup Quirks

- **`.env` file:** required at runtime; loaded via `flutter_dotenv` and also bundled as a Flutter asset. Copy `.env.example` to `.env` and set `GROQ_API_KEY`.
- **sherpa-onnx models:** `assets/models/` directories are declared but model binaries (`*.bin`, `*.onnx`, `*.txt`) are **gitignored**. Use `download_model.py` to fetch them before running.
- **`sherpa.initBindings()`** must be called before any recognizer is created (done in `main.dart`).
- **TTS stub on Windows:** `flutter_tts` was removed due to CMake issues. The Windows stub logs instead of speaking.
- **`.agents/` and `.agent/` directories are gitignored** — do not expect them to persist across clones.

## Commands

### Setup / Run
```bash
flutter pub get
flutter run
flutter run -d <device-id>
```

### Lint / Format
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

## Conventions

- **Imports:** package imports for SDK/third-party; relative imports for app-local files. Order: Dart SDK → packages → relative.
- **Reuse tokens:** `AppColors`, `AppTextStyles`, `AppConstants`, `AppRoutes` before adding new values. Touch target sizes: `minTouchTargetSize` = 56px, `largeTouchTargetSize` = 72px.
- **Bilingual text:** preserve Bangla/English pairing on all user-facing strings.
- **Accessibility is non-optional:** semantic labels, hints, headers, large touch targets. Portrait-only orientation and text-scale clamping (0.8–2.0×) are configured in `main.dart`.
- **Error handling:** wrap all plugin/BLE/HTTP/speech/TTS calls in `try/catch`; log with `debugPrint`; surface errors via state, dialogs, or `SnackBar`.
- **State management:** Provider `ChangeNotifier`; update internal state before `notifyListeners()`. Check `mounted` after `await` before `setState` or showing dialogs.
- **Security:** Groq API key loaded from `.env`; do not log or expose it. Prefer `--dart-define` for any new secrets.
