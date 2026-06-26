# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Accessibility-first Flutter companion app for the Smart Cane — assistive navigation for visually impaired users in Bangladesh. Bilingual Bangla/English voice UI, push-to-talk voice commands (STT → cloud LLM intent → TTS), **on-device YOLOv11n vision**, BLE distance alerts from the cane, and GPS. Targets **Android + Windows** (iOS/Linux/macOS folders exist but are not actively developed).

> This subdirectory is where nearly all work happens. The repo-root `../../CLAUDE.md` describes the wider system; `../../Thesis_pi_zero/PI_ZERO_VISION_PLAN.md` is the active feature plan (Pi Zero camera replacing the ESP32 — see "Active feature" below).

## Commands

```bash
flutter pub get
flutter run                       # or: flutter run -d <device-id>

dart format .
flutter analyze
flutter test
flutter test <file> --plain-name "<test name>"   # run a single test
flutter test --reporter expanded

flutter build apk                 # Android APK
flutter build appbundle           # Android App Bundle
flutter build windows
```

**First-time setup:** copy `.env.example` → `.env` and set `GROQ_API_KEY` (loaded at runtime via `flutter_dotenv` and bundled as a Flutter asset). The YOLO model (`assets/models/yolo11n_float16.tflite`) ships in the repo. `download_model.py` fetches the gitignored sherpa-onnx Bengali STT binaries — only needed if you re-enable offline STT (see below).

**Post-change verification:** `dart format . && flutter analyze && flutter test`.

## Known Issues
- `flutter analyze` passes with info-level deprecation warnings (`withOpacity`, `RadioListTile`, `speech_to_text` listen params). Expected.
- `flutter test` fails in `test/widget_test.dart` because `flutter_blue_plus` is unsupported on the test host. Run focused single tests instead.
- On Windows, `flutter_tts` was removed (CMake issues); `tts_service_stub.dart` logs instead of speaking.

## Architecture

Three layers: `lib/core/` (config, theme, routing, accessibility utils, constants) → `lib/services/` → `lib/presentation/` (`screens/`, `widgets/`). State via Provider/`ChangeNotifier`; services use singleton `.instance` accessors. Routes centralized in `lib/core/navigation/app_routes.dart`. Feature flags + tunables live in `lib/core/utils/constants.dart`.

### Three independent subsystems

**1. Voice pipeline** (push-to-talk: hold a volume key to talk)
1. `HardwareKeyService` — forwards Android volume-key down/up over a `MethodChannel` (`MainActivity.kt` consumes the keys so system volume doesn't change); wired once in `main.dart` as push-to-talk start/stop.
2. `SpeechService` — STT orchestrator. **Both `bn` and `en` currently route through the `speech_to_text` (platform/Google built-in) recognizer** (`bn-BD` / `en_US`). The offline sherpa-onnx Zipformer path in `lib/services/stt/` is **disabled** but kept commented for re-enable (`sherpa.initBindings()` in `main.dart` is also commented out).
3. `IntentMatcher` — offline hybrid fuzzy/code-mixing intent classifier; resolves common commands locally. Below its confidence threshold it falls back to the cloud LLM. `VoiceNavigationService.lastWasLocal` tracks which path handled the command.
4. `GroqService` — cloud LLaMA 3.3 70B via Groq API; returns `{"action": "...", "spoken_response": "..."}`; keeps ≤10 messages of history. **This is the active LLM.**
5. `VoiceNavigationService` — orchestrates the above and exposes `onNavigationAction` for routing; speaks results via `TtsService`.
- `LlmService` (on-device Gemma 4 E2B via LiteRT-LM Kotlin channel) is **intentionally disabled** — see the header comment in `llm_service.dart` for the exact re-enable steps. Note `AppConstants.enableLlm = true` means "route voice commands through the cloud `GroqService`," not Gemma.

**2. On-device vision** (`vision_demo_screen.dart`)
- Uses the **`ultralytics_yolo` plugin's `YOLOView`** — a native Kotlin/CameraX platform view that owns the camera, rotation, preprocessing, inference, NMS, and box overlay. Flutter receives only decoded `Detection` results + `YOLOPerformanceMetrics`. There is no pure-Dart frame loop.
- Model: `assets/models/yolo11n_float16.tflite` (FP16; INT8 not bundled). Thesis quantization study toggles FP16↔INT8 (`YOLOView.modelPath`) and CPU↔GPU (`useGpu`). Default thresholds: confidence `0.25`, IoU `0.45`. `export_yolo_models.py` regenerates the `.tflite`. Shared types: `detection_models.dart` (`Detection`, `BBox`, `ModelVariant`, `InferenceDelegate`); results UI: `widgets/detection_list_tile.dart`.

**3. BLE distance alerts** — two mutually-exclusive paths, both gated by flags in `constants.dart`:
- **ESP32 (active, `enableEspBle = true`):** `EspBleService` connects to `SmartCane_ESP`, reads a raw ultrasonic distance, and **the app** classifies it into CRITICAL/WARNING/CAUTION using cm thresholds (`espCriticalCm` 50 / `espWarningCm` 100 / `espCautionCm` 200). UUIDs `a1b2c3d4-...`. Auto-reconnects after 3s.
- **Legacy Pi (off, `enablePiBle = false`):** `BleService` parses old `"LEVEL:OBJECT:CONFIDENCE:POSITION"` strings (UUIDs `12345678-...`). The Pi backend that produced them is gone; parser/UUIDs remain dormant.
- When touching BLE, confirm which path/UUIDs you mean — they differ in UUIDs and message semantics.

### Other services
- `LocationService` — GPS via `geolocator` + reverse geocoding via OpenStreetMap Nominatim (no API key).
- `SettingsService` — persists settings via `shared_preferences`; `languageMode` (`'bn'`/`'en'`) drives `SpeechService` locale.
- `TtsService` — abstract; `tts_service_impl.dart` (mobile) vs `tts_service_stub.dart` (Windows, logs only).

## Active feature: Pi Zero vision (in progress)

Replacing the ESP32 cane hardware with a **Raspberry Pi Zero 2 W + Arducam IMX519** camera that streams JPEG frames to the phone to feed the **same** YOLO pipeline. Locked design: **BLE provisions WiFi** (app creates a `LocalOnlyHotspot`, sends SSID/password to the Pi over BLE), **WiFi carries latest-frame-wins JPEG** (Pi dials the phone gateway, no router/mDNS), and frames go through the plugin's **`YOLO.predict(Uint8List)`** still-image API (since `YOLOView` has no external-frame input). New code is gated behind an `enablePiVision` flag and a parallel screen — **leave `vision_demo_screen.dart` untouched**. Full handoff doc + research: `../../Thesis_pi_zero/PI_ZERO_VISION_PLAN.md`.

## Conventions

- **Imports:** package imports for SDK/third-party; relative for app-local. Order: Dart SDK → packages → relative.
- **Reuse tokens** before adding new values: `AppColors`, `AppTextStyles`, `AppConstants` (`constants.dart`), `AppRoutes`. Touch targets: `minTouchTargetSize` 56px, `largeTouchTargetSize` 72px.
- **Bilingual text is mandatory** on all user-facing strings (Bangla/English pairing). Use `AccessibilityLabels` in `lib/core/utils/accessibility_helper.dart` for semantic labels.
- **Accessibility is non-optional:** semantic labels/hints/headers, large touch targets. Portrait-only orientation and text-scale clamping (0.8–2.0×) are set in `main.dart`.
- **Error handling:** wrap every plugin/BLE/HTTP/speech/TTS call in `try/catch`; log with `debugPrint`; surface errors via state/dialog/`SnackBar`.
- **`ChangeNotifier`:** update internal state *before* `notifyListeners()`. Check `mounted` after every `await` before `setState`, dialogs, or `ScaffoldMessenger`.
- **Secrets:** Groq key from `.env`; never log it. Prefer `--dart-define` for any new secret. When changing BLE UUIDs or the alert format, mirror the change on both producer (firmware) and consumer (`constants.dart` / the relevant `*BleService`).
