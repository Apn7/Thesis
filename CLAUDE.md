# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Accessibility-first Flutter companion app for the Smart Cane — assistive navigation for visually impaired users in Bangladesh. Bengali-only voice UI with hands-free voice commands (offline STT → intent matching or cloud LLM → TTS), **on-device YOLOv11n vision**, BLE distance alerts from the cane, GPS, and **zero-tap emergency SOS** (voice or button triggers countdown → auto-SMS all saved contacts with live location). Targets **Android + Windows** (iOS/Linux/macOS folders exist but are not actively developed).

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
- **New assets require full rebuild:** Adding a file to `pubspec.yaml`'s `assets:` section only takes effect on `flutter run`, not hot reload/hot restart. If a new `.json` asset is not loading, do a full rebuild.
- **Bengali nukta Unicode mismatch:** Sherpa-onnx STT emits Bengali nukta letters (ড়/ঢ়/য়) as precomposed single codepoints (U+09DC/09DD/09DF), but human-typed text typically uses decomposed forms (base consonant + U+09BC nukta). They render identically but fail string equality. Fixed in `IntentMatcher._normalize()` with `_canonicalizeNukta()`, which collapses both to precomposed before every similarity comparison — protects all intents globally, not just one phrase. Do the same for any new Bengali intent phrases or vocabulary lists.

## Architecture

Three layers: `lib/core/` (config, theme, routing, accessibility utils, constants) → `lib/services/` → `lib/presentation/` (`screens/`, `widgets/`). State via Provider/`ChangeNotifier`; services use singleton `.instance` accessors. Routes centralized in `lib/core/navigation/app_routes.dart`. Feature flags + tunables live in `lib/core/utils/constants.dart`.

### Three independent subsystems

**1. Voice pipeline** (push-to-talk: hold a volume key to talk)
1. `HardwareKeyService` — forwards Android volume-key down/up over a `MethodChannel` (`MainActivity.kt` consumes the keys so system volume doesn't change); wired once in `main.dart` as push-to-talk start/stop.
2. `SpeechService` — STT orchestrator using offline Bengali sherpa-onnx Zipformer (bundled; `assets/models/sherpa-onnx-streaming-zipformer-bn-vosk-2026-02-09`). The `speech_to_text` platform recognizer is **intentionally not used** — the app is Bengali-only for blind Bangladeshi users.
3. `IntentMatcher` — offline hybrid ensemble intent classifier (Damerau–Levenshtein + Jaro–Winkler + Sørensen–Dice bigram + TF-IDF + Jaccard token). Resolves common commands locally from `assets/intents/intents.json` (global nav/utility commands). Below τ=0.70 confidence it falls through to the cloud LLM. **Unicode fix:** canonicalizes Bengali nukta letters (ড়/ঢ়/য়) from precomposed ↔ decomposed forms in `_normalize()` so STT output doesn't silently miss exact phrases.
4. `GroqService` — cloud LLaMA 3.3 70B via Groq API; returns `{"action": "...", "spoken_response": "..."}`; keeps ≤10 messages of history. **This is the active LLM.**
5. `VoiceNavigationService` — orchestrates the above; exposes `onNavigationAction` callback for routing and optional `transcriptInterceptor` for screen-scoped handlers (see SOS feature below). Speaks results via `TtsService`. Implements turn-epoch barge-in model — PTT press aborts the old turn and starts a new one atomically.
- `LlmService` (on-device Gemma 4 E2B via LiteRT-LM Kotlin channel) is **intentionally disabled** — see the header comment in `llm_service.dart` for the exact re-enable steps. Note `AppConstants.enableLlm = true` means "route voice commands through the cloud `GroqService`," not Gemma.

**2. On-device vision** (`vision_demo_screen.dart`)
- Uses the **`ultralytics_yolo` plugin's `YOLOView`** — a native Kotlin/CameraX platform view that owns the camera, rotation, preprocessing, inference, NMS, and box overlay. Flutter receives only decoded `Detection` results + `YOLOPerformanceMetrics`. There is no pure-Dart frame loop.
- Model: `assets/models/yolo11n_float16.tflite` (FP16; INT8 not bundled). Thesis quantization study toggles FP16↔INT8 (`YOLOView.modelPath`) and CPU↔GPU (`useGpu`). Default thresholds: confidence `0.25`, IoU `0.45`. `export_yolo_models.py` regenerates the `.tflite`. Shared types: `detection_models.dart` (`Detection`, `BBox`, `ModelVariant`, `InferenceDelegate`); results UI: `widgets/detection_list_tile.dart`.

**3. BLE distance alerts** — two mutually-exclusive paths, both gated by flags in `constants.dart`:
- **ESP32 (active, `enableEspBle = true`):** `EspBleService` connects to `SmartCane_ESP`, reads a raw ultrasonic distance, and **the app** classifies it into CRITICAL/WARNING/CAUTION using cm thresholds (`espCriticalCm` 50 / `espWarningCm` 100 / `espCautionCm` 200). UUIDs `a1b2c3d4-...`. Auto-reconnects after 3s.
- **Legacy Pi (off, `enablePiBle = false`):** `BleService` parses old `"LEVEL:OBJECT:CONFIDENCE:POSITION"` strings (UUIDs `12345678-...`). The Pi backend that produced them is gone; parser/UUIDs remain dormant.
- When touching BLE, confirm which path/UUIDs you mean — they differ in UUIDs and message semantics.

**4. Emergency SOS** — zero-tap, hands-free alert workflow.
- **SOS screen** (`lib/presentation/screens/sos_screen.dart`) — 4-phase FSM (`idle → countdown → sending → done`). Big red button + voice command starts a **cancelable countdown** (user hears each second), then sends direct SMS with live GPS location to all saved emergency contacts at once.
- **Contact management** (`lib/services/sos_dialog_controller.dart`) — screen-scoped voice dialog FSM (`idle → askName → askNumber → confirm`) for managing contacts entirely hands-free. Uses `IntentMatcher.scoped('assets/intents/sos_intents.json')` — a **separate, private matcher** loaded only on the SOS screen that owns `add_contact`/`read_contacts`/`confirm_yes`/`confirm_no`/`cancel` intents. Prevents "হ্যাঁ" or "বাতিল" said anywhere else in the app from being intercepted by this dialog.
- **Transcript interceptor** — the SOS screen owns `VoiceNavigationService.transcriptInterceptor` while mounted; every transcript is offered to the dialog first (returns `true` if consumed, `false` to fall through to global pipeline). Defensively cleared on dispose.
- **Spoken-number parser** (`lib/services/spoken_number_parser.dart`) — static utility that maps Bengali digit words ("শূন্য এক সাত…") and Bengali numeral characters (০১৭…) to ASCII phone-number strings, ignoring filler words. Output is read back digit-by-digit in Bengali for confirmation before saving. Handles both forms of each digit (e.g. "পাঁচ" and "পাচ" → `5`).
- **Intent split:** `assets/intents/intents.json` (global navigation) vs `assets/intents/sos_intents.json` (dialog-only control words). The global matcher never sees the SOS action list; the scoped matcher never loads the navigation-command phrases. This isolation is **critical** — control words must not leak into the global pipeline or spoken "yes"/"no" elsewhere in the app becomes ambiguous.
- **Voice commands:** Say "জরুরি"/"বাঁচাও"/"ইমার্জেন্সি" (and 20+ variants) to trigger SOS with auto-countdown. Say "জরুরি যোগাযোগ" to open the page for managing contacts (no auto-countdown). On the SOS screen itself, say "যোগাযোগ যোগ করো" (add), "যোগাযোগ পড়ো" (read), "হ্যাঁ"/"না" (confirm), "বাতিল" (cancel).

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
- **Screen-scoped voice dialogs:** Use `IntentMatcher.scoped(assetPath)` for a screen-local vocabulary (never the global `.instance`). Control words like "yes"/"no"/"cancel" must be isolated from the global pipeline. Set `VoiceNavigationService.transcriptInterceptor` in `initState`, clear it defensively in `dispose`. The pattern is lock-free and thread-safe due to turn-epoch barge-in.
- **Bengali nukta Unicode:** Sherpa STT emits nukta letters (ড়/ঢ়/য়) as precomposed single codepoints; typed text uses decomposed forms. Both render identically but fail string equality. Canonicalise in any new intent matcher or phrase-matching code — see `IntentMatcher._canonicalizeNukta()` for the pattern.
