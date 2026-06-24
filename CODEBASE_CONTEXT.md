# Smart Cane App Codebase Context

Last indexed: 2026-06-23

This file is the fast handoff map for `test_app_1`, the Flutter companion app
for an accessibility-first smart cane thesis project. It is intentionally more
implementation-focused than `README*.md`: use it to understand the current
runtime behavior, where each subsystem lives, and which older/restorable paths
are disabled.

## Current Reality In One Page

- Stack: Flutter + Dart 3.10+, Material 3, Provider-style `ChangeNotifier`
  services, Android-first with Windows support.
- Entrypoint: `lib/main.dart` -> `SmartCaneApp`.
- App layers:
  - `lib/core/`: routes, theme tokens, constants, config, accessibility helpers.
  - `lib/services/`: singletons and platform/service orchestration.
  - `lib/presentation/`: screens and reusable widgets.
- Active voice flow:
  1. Hardware volume key or UI starts push-to-talk.
  2. `SpeechService` uses `speech_to_text` with locale `bn`/`en`.
  3. `VoiceNavigationService` tries local `IntentMatcher`.
  4. If local confidence is below threshold and `AppConstants.enableLlm` is
     true, it falls back to `GroqService` cloud LLaMA API.
  5. `TtsService` speaks the short response and route callbacks navigate.
- Active obstacle flow:
  - `EspBleService` connects to ESP32 `SmartCane_ESP` and receives distance
    values in centimeters.
  - `HomeScreen` maps distance to SAFE/CAUTION/WARNING/CRITICAL, then drives
    vibration, TTS escalation speech, and `assets/alerts/alert.wav`.
- Pi vision BLE is implemented but currently disabled by
  `AppConstants.enablePiBle = false`.
- On-device Gemma/LiteRT LLM is preserved as commented code and native channel
  stubs, but is not active or bundled.
- Offline sherpa-onnx STT files and code are preserved, but current
  `SpeechService` routes both Bangla and English through `speech_to_text`.
- Vision demo is active in the UI at `/vision`; it uses the `ultralytics_yolo`
  plugin with native CameraX/inference/overlay and a bundled FP16 YOLOv11n
  TFLite model.

## Top-Level Files

- `AGENTS.md`: repository instructions for coding agents. Treat it as the
  highest-level local guidance.
- `ARCHITECTURE.md`: cross-repo architecture index for the app, Raspberry Pi
  backend, and ESP32 firmware. It contains some older wording around on-device
  LLM; verify against source before repeating.
- `CODEBASE_CONTEXT.md`: this file, focused on the current Flutter app.
- `pubspec.yaml`: dependencies and bundled assets.
- `.env`: runtime secret source for `GROQ_API_KEY`; do not log or commit new
  secrets.
- `.env.example`: template for required Groq key.
- `download_model.py`: downloader for sherpa-onnx model assets.
- `export_yolo_models.py`: YOLO export helper for FP16/INT8 TFLite.
- `assets/intents/intents.json`: local intent phrase bank.
- `assets/models/README.md`: model generation notes for the vision demo.
- `test/widget_test.dart`: basic widget smoke test; full `flutter test` is
  currently known to be fragile because plugins are not supported on the test
  platform.

## Runtime Flags And Constants

File: `lib/core/utils/constants.dart`

Important constants:

- `AppConstants.enablePiBle = false`
  - Pi/Raspberry vision BLE code exists but is disabled in `HomeScreen`.
- `AppConstants.enableEspBle = true`
  - ESP32 distance BLE is active.
- `AppConstants.enableLlm = true`
  - In current code this means "allow Groq cloud fallback" in
    `VoiceNavigationService`.
  - It does not enable the native Gemma/LiteRT path.
- Pi BLE UUIDs:
  - service: `12345678-1234-5678-1234-56789abcdef0`
  - alert characteristic: `...abcdef1`
  - battery characteristic: `...abcdef2`
  - device name match: `SmartCane`
- ESP32 BLE UUIDs:
  - service: `a1b2c3d4-0001-1000-8000-00805f9b34fb`
  - distance characteristic: `a1b2c3d4-0002-1000-8000-00805f9b34fb`
  - device name match: `SmartCane_ESP`
- ESP32 distance thresholds:
  - critical: `< 50 cm`
  - warning: `< 100 cm`
  - caution: `< 200 cm`
  - safe: `>= 200 cm`

If BLE UUIDs or alert formats change, update both the producer firmware/backend
and the app constants/parser together.

## App Startup

File: `lib/main.dart`

Startup responsibilities:

- `WidgetsFlutterBinding.ensureInitialized()`.
- Load `.env` with `flutter_dotenv`.
- Lock orientation to portrait up/down for accessibility.
- Set status bar styling.
- Register volume key push-to-talk handlers through `HardwareKeyService`.
- Run `SmartCaneApp`.

`SmartCaneApp`:

- Uses `AppTheme.lightTheme` and `AppTheme.darkTheme`.
- Clamps text scaling to `0.8..2.0` for layout stability.
- Starts at `AppRoutes.splash`.
- Defines routes:
  - `/` -> `SplashScreen`
  - `/home` -> `HomeScreen`
  - `/location` -> `LocationScreen`
  - `/settings` -> `SettingsScreen`
  - `/help` -> `HelpScreen`
  - `/vision` -> `VisionDemoScreen`

## Navigation And Screens

Routes live in `lib/core/navigation/app_routes.dart`.

### Splash Screen

File: `lib/presentation/screens/splash_screen.dart`

Responsibilities:

- Requests Bluetooth scan/connect, location, and microphone permissions at
  first launch.
- Loads persisted settings through `SettingsService`.
- Applies the selected STT locale to `SpeechService`.
- Navigates to `/home`.

Disabled/commented paths:

- sherpa Bengali model copy via `ModelAssetManager`.
- on-device LLM initialization via `LlmService`.

### Home Screen

File: `lib/presentation/screens/home_screen.dart`

Responsibilities:

- Initializes `VoiceNavigationService`.
- Initializes ESP32 BLE when `AppConstants.enableEspBle` is true.
- Keeps Pi BLE code commented/disabled.
- Maps `VoiceAction` callbacks to routes or spoken utility responses.
- Shows voice command state, current transcript, last response, error state,
  ESP32 distance status, test command input, navigation grid, and bottom
  waveform.
- Handles ESP32 verdict transitions:
  - SAFE/noData: cancel vibration, stop speaking, stop critical alert tone.
  - CAUTION: light repeating haptic pattern.
  - WARNING: stronger repeating haptic pattern.
  - CRITICAL: near-continuous vibration plus alert WAV.
  - TTS escalation fires only when severity increases.

Important asset dependency:

- `assets/alerts/alert.wav` is expected by `AudioPlayer` as
  `AssetSource('alerts/alert.wav')`.

### Location Screen

File: `lib/presentation/screens/location_screen.dart`

Responsibilities:

- Fetches current GPS location through `LocationService`.
- Shows address, latitude, longitude, loading state, and permission/GPS error
  actions.
- Reverse geocoded address requires network; GPS coordinates can work offline.
- "Save" currently only shows a SnackBar; it does not persist a saved location.

### Settings Screen

File: `lib/presentation/screens/settings_screen.dart`

Responsibilities:

- Reads and writes `SettingsService.languageMode`.
- UI exposes Bangla (`bn`) and English (`en`) STT modes.
- Other controls such as speech rate, vibration feedback, voice confirmation,
  and battery saver are local UI state only unless wired later.
- Reset restores Bangla and local default values.

### Help Screen

File: `lib/presentation/screens/help_screen.dart`

Responsibilities:

- Static bilingual help/tutorial content.

### Vision Demo Screen

File: `lib/presentation/screens/vision_demo_screen.dart`

Responsibilities:

- Requests camera permission.
- Builds `YOLOView` from `ultralytics_yolo`.
- Native plugin handles camera, rotation, preprocessing, inference, NMS,
  overlay, FPS, and latency metrics.
- Flutter receives `YOLOResult` and maps to local `Detection`.
- Runtime toggles:
  - Model: `ModelVariant.fp16` or `ModelVariant.int8`.
  - Delegate: CPU or GPU.
- INT8 fallback:
  - If INT8 model load fails, state falls back to FP16 and surfaces error.

Current bundled model:

- `assets/models/yolo11n_float16.tflite` is bundled in `pubspec.yaml`.
- `assets/models/yolo11n_int8.tflite` is referenced in code but commented out
  in `pubspec.yaml` because INT8 export can OOM on constrained machines.

## Service Index

Most services are singletons exposed as `.instance`.

### VoiceNavigationService

File: `lib/services/voice_navigation_service.dart`

Role:

- Central voice pipeline orchestrator and `ChangeNotifier`.
- Owns `GroqService`, `IntentMatcher`, `SpeechService`, and `TtsService`.
- Exposes UI state:
  - `isListening`
  - `isProcessing`
  - `currentTranscript`
  - `lastResponse`
  - `error`
  - `lastWasLocal`
- Exposes `onNavigationAction` callback for screens to route actions.

Processing algorithm:

1. `startListening()` delegates to `SpeechService.startListening()`.
2. Final STT result calls `_processCommand(text)`.
3. `IntentMatcher.match(text)` runs first.
4. If accepted locally, no API call is made.
5. If not local and `AppConstants.enableLlm` is true, call
   `GroqService.processCommand(text)`.
6. If Groq fallback is disabled, return a bilingual "did not understand"
   response.
7. Speak the response.
8. Parse action string into `VoiceAction` and fire `onNavigationAction`.

Log tags:

- `[STT]`: speech events.
- `[LOCAL]`: local classifier decision.
- `[CLOUD]`: Groq request/response.
- `[VOICE]`: command block and error logs.

### IntentMatcher

File: `lib/services/intent_matcher.dart`

Role:

- Offline Bangla/English/Banglish fuzzy intent classifier.
- Loads phrase bank from `assets/intents/intents.json`.
- Returns an `IntentMatch` only if confidence clears threshold.
- Exposes `lastDiagnostics` for thesis/debugging: normalized input, tokens,
  code-mixing index, top candidates, sub-scores, latency.

Default config:

- threshold: `0.70`
- ensemble:
  - Damerau-Levenshtein
  - Jaro-Winkler
  - Sorensen-Dice character bigrams
  - TF-IDF cosine
  - token Jaccard
- exact/containment boost can push obvious matches over threshold.

To add a voice action:

1. Add phrases and bilingual responses in `assets/intents/intents.json`.
2. Add action to `ApiConfig.systemPrompt`.
3. Add action to `VoiceAction`.
4. Add parsing case in `VoiceNavigationService._parseAction`.
5. Handle it in `HomeScreen._setupNavigationCallback`.

### GroqService

File: `lib/services/groq_service.dart`

Role:

- Cloud fallback for intent recognition via Groq chat completions.
- Uses `ApiConfig.groqBaseUrl`, `ApiConfig.llamaModel`, and
  `ApiConfig.systemPrompt`.
- Reads `GROQ_API_KEY` from `.env` through `ApiConfig.groqApiKey`.
- Maintains short conversation history, capped around 10 messages.
- Extracts JSON object from the model response and maps to
  `VoiceCommandResponse`.

Security note:

- Do not print or expose `ApiConfig.groqApiKey`.

### LlmService

File: `lib/services/llm_service.dart`

Role:

- Disabled/commented on-device Gemma/LiteRT implementation preserved for
  restoration.
- Current native channel in `MainActivity.kt` returns `LLM_DISABLED`.

To restore on-device LLM:

1. Re-enable Dart implementation in `llm_service.dart`.
2. Re-add Gemma `.litertlm` asset in `pubspec.yaml`.
3. Restore LiteRT-LM imports/dependency/native code in Android.
4. Resolve duplicate `libLiteRt.so` conflict with `ultralytics_yolo`.
5. Swap `VoiceNavigationService` from `GroqService` to `LlmService`.

Important current ambiguity:

- `AppConstants.enableLlm` currently gates Groq fallback, despite older
  comments saying it controls native LLM.

### SpeechService

File: `lib/services/speech_service.dart`

Role:

- STT orchestrator.
- Current active backend is `speech_to_text` for both Bangla and English.
- `bn` uses a resolved Bengali locale when available, falling back to `bn_BD`.
- `en` maps to `en_US`.
- Defaults to Bangla.
- Handles push-to-talk semantics by retrying transient Android recognizer
  errors while the user is still holding the key.

Retryable Android errors:

- `error_no_match`
- `error_speech_timeout`
- `error_client`
- `error_recognizer_busy`

On-device language pack behavior:

- Starts with `onDevice: true`.
- If `error_language_unavailable` or `error_language_not_supported` occurs,
  it retries online and keeps `onDevice` false for subsequent sessions.

Disabled/restorable path:

- `lib/services/stt/` contains sherpa-onnx streaming interfaces, model manager,
  audio recording pipeline, and engine factory, but `SpeechService` currently
  has the sherpa path commented out.

### STT Subsystem

Directory: `lib/services/stt/`

Files:

- `stt_engine.dart`: streaming STT interface.
- `sherpa_engine.dart`: sherpa-onnx recognizer implementation.
- `sherpa_model_config.dart`: model file names and config.
- `stt_engine_factory.dart`: cached Bengali engine factory.
- `audio_pipeline.dart`: microphone recording, amplitude polling, silence
  detection, sample conversion.
- `model_asset_manager.dart`: copies bundled model files to app support storage
  because sherpa requires filesystem paths.

Current status:

- Code remains useful for re-enabling offline Bengali STT.
- `main.dart` has `sherpa.initBindings()` commented out.
- sherpa model assets are present locally in this workspace but are commented
  out of `pubspec.yaml`, so they are not bundled in normal builds.

### TtsService

Files:

- `lib/services/tts_service.dart`
- `lib/services/tts_service_impl.dart`
- `lib/services/tts_service_stub.dart`

Role:

- Abstract text-to-speech interface.
- Mobile implementation uses `flutter_tts` with default `bn-BD`.
- Windows uses a stub because `flutter_tts` caused CMake/platform issues.
- `speak()` stops current speech before speaking new text, so alerts do not
  queue up.

### HardwareKeyService

File: `lib/services/hardware_key_service.dart`

Role:

- Listens for native Android volume-key events over MethodChannel
  `com.example.test_app_1/hardware_keys`.
- Provides `setVolumeKeyHandlers(onDown, onUp)`.
- Guards duplicate down/up events with `_isPressed`.

Native side:

- `android/app/src/main/kotlin/com/example/test_app_1/MainActivity.kt`
  intercepts volume up/down, consumes them, and forwards press/release.
- Native also pins media volume to maximum on engine configure and window focus.

### EspBleService

File: `lib/services/esp_ble_service.dart`

Role:

- BLE client for ESP32 distance firmware.
- Scans bonded devices first because Android may hide already paired devices
  from active scans.
- Subscribes to distance characteristic notifications.
- Receives ASCII distance strings like `"142.3"` or `"-1"`.
- Exposes latest raw value, parsed distance, state, and derived verdict.
- Fires `onVerdictChanged` when verdict changes.

State enum:

- disconnected
- scanning
- connecting
- connected
- bluetoothOff
- error

Verdict enum:

- noData
- safe
- caution
- warning
- critical

### BleService

File: `lib/services/ble_service.dart`

Role:

- BLE client for Raspberry Pi vision alerts.
- Implemented but not active in `HomeScreen` because Pi BLE is disabled.
- Parses Pi alert format: `LEVEL:OBJECT:CONFIDENCE:POSITION`.
- Expected examples:
  - `CRITICAL:person:87%:center`
  - `WARNING:chair:73%:left`
- Exposes `BleAlert` with `level`, `objectName`, `confidence`, `position`,
  and `displayMessage`.

### LocationService

File: `lib/services/location_service.dart`

Role:

- Requests/checks location service and permission.
- Reads GPS via `geolocator`.
- Reverse geocodes with OpenStreetMap Nominatim over HTTP.
- Uses `User-Agent: SmartCaneApp/1.0` and `Accept-Language: en,bn`.
- Returns `LocationData` with latitude, longitude, address, and timestamp.

Network note:

- Coordinate fetch uses device GPS.
- Address lookup requires internet.

### SettingsService

File: `lib/services/settings_service.dart`

Role:

- Persists `stt_language_mode` with `shared_preferences`.
- Supported values: `bn`, `en`.
- Migrates legacy `both` or unknown values to `bn`.
- Calls `SpeechService.instance.setLocale(mode)` after updates.

### Detection Models

File: `lib/services/detection_models.dart`

Role:

- Flutter-side model classes for the vision demo:
  - `Detection`
  - `BBox`
  - `PositionZone`
  - `ModelVariant`
  - `InferenceDelegate`
- `Detection.position` is computed from bounding-box center:
  - `< 0.33`: left
  - `> 0.67`: right
  - otherwise center

## Config And Assets

### API Config

File: `lib/core/config/api_config.dart`

Responsibilities:

- Reads `GROQ_API_KEY`.
- Defines Groq base URL and model name:
  - `https://api.groq.com/openai/v1`
  - `llama-3.3-70b-versatile`
- Holds system prompt and allowed action names.

When changing supported actions, keep this file in sync with:

- `assets/intents/intents.json`
- `VoiceAction`
- `VoiceNavigationService._parseAction`
- `HomeScreen._setupNavigationCallback`

### Bundled Assets In pubspec.yaml

Currently bundled:

- `.env`
- `assets/intents/intents.json`
- `assets/alerts/`
- `assets/models/coco_labels.txt`
- `assets/models/yolo11n_float16.tflite`

Commented/not bundled:

- `assets/models/yolo11n_int8.tflite`
- sherpa-onnx model directories
- `assets/models/gemma-4-E2B-it.litertlm`

Important distinction:

- Large model files may exist locally under `assets/models/`, but if they are
  commented out in `pubspec.yaml` they are not included in Flutter builds.

### Vision Model Assets

File: `assets/models/README.md`

Current model setup:

- FP16 YOLOv11n TFLite exists and is bundled.
- INT8 TFLite is expected by the runtime toggle but not bundled until generated
  and uncommented.
- `export_yolo_models.py` and the README describe Colab/local generation.
- The model classes are standard COCO labels from `coco_labels.txt`.

## Native Android Integration

### MainActivity

File: `android/app/src/main/kotlin/com/example/test_app_1/MainActivity.kt`

Responsibilities:

- MethodChannel `com.example.test_app_1/hardware_keys`:
  - forwards volume key down/up to Dart.
  - consumes the native key event so system volume does not change.
- MethodChannel `com.example.test_app_1/llm`:
  - currently returns `LLM_DISABLED` for `initialize` and `processCommand`.
  - `dispose` succeeds.
- Forces media stream volume to max for accessibility.

### Android Manifest

File: `android/app/src/main/AndroidManifest.xml`

Important permissions/features:

- location: fine, coarse, background
- vibration
- microphone
- camera
- internet/network state
- BLE legacy permissions for API <= 30
- BLE scan/connect for API >= 31
- BLE feature required
- speech recognition query

### Android Build

File: `android/app/build.gradle.kts`

Important settings:

- namespace/applicationId: `com.example.test_app_1`
- `minSdk = 31`
- Java/Kotlin target 17
- NDK version `29.0.13113456`
- `noCompress` for `onnx`, `txt`, `tflite`, `litertlm`
- LiteRT-LM dependency is commented out due duplicate native library conflict
  with `ultralytics_yolo`.

## UI And Accessibility Conventions

Core files:

- `lib/core/theme/app_colors.dart`
- `lib/core/theme/app_text_styles.dart`
- `lib/core/theme/app_theme.dart`
- `lib/core/utils/accessibility_helper.dart`
- `lib/core/utils/constants.dart`

Implementation notes:

- UI is bilingual Bangla/English throughout user-visible strings.
- Many screen headers are wrapped in `Semantics(header: true)`.
- Touch target constants:
  - min: `56.0`
  - large: `72.0`
- `SmartCaneApp` clamps text scaling to avoid layout breakage.
- Portrait-only orientation is configured in `main.dart`.
- Use existing `AppColors`, `AppTextStyles`, `AppConstants`, and `AppRoutes`
  before adding new tokens.

Reusable widgets:

- `accessible_action_button.dart`: large semantic navigation/action buttons.
- `colorful_waveform.dart`: bottom listening animation.
- `voice_indicator.dart`: animated voice indicator.
- `info_card.dart`: icon/title/value card used on location screen.
- `detection_list_tile.dart`: list item for YOLO detections.

## Known Disabled Or Partial Features

- Pi BLE alerts:
  - `BleService` exists.
  - Home UI/handlers are commented out.
  - `AppConstants.enablePiBle` is false.
- Native Gemma/LiteRT LLM:
  - `LlmService` is a block comment.
  - Native channel is stubbed.
  - Gradle dependency and model asset are not bundled.
- sherpa-onnx offline STT:
  - support files exist.
  - `sherpa.initBindings()` is commented in `main.dart`.
  - model copy and engine paths are commented.
  - current runtime uses `speech_to_text`.
- INT8 YOLO:
  - enum and UI toggle exist.
  - asset is not bundled until generated/uncommented.
- Settings controls beyond language:
  - speech rate, vibration, voice confirmation, and battery saver are mostly
    local UI state.
- Battery voice action:
  - returns hard-coded 85 percent from `HomeScreen`.
- Location save:
  - shows SnackBar only.

## Commands

Setup:

```bash
flutter pub get
```

Run:

```bash
flutter run
flutter run -d <device-id>
```

Post-change verification:

```bash
dart format .
flutter analyze
flutter test
```

Known test caveat:

- `flutter test` may fail because some plugins such as `flutter_blue_plus` are
  unsupported on the test platform. Prefer focused pure-Dart tests when adding
  logic, and document plugin limitations when full tests cannot run.

## Common Change Recipes

### Add Or Modify A Voice Command

Touch these files:

1. `assets/intents/intents.json`
2. `lib/core/config/api_config.dart`
3. `lib/services/voice_navigation_service.dart`
4. `lib/presentation/screens/home_screen.dart`

Checklist:

- Add phrases and bilingual responses.
- Add action to Groq system prompt.
- Add enum value to `VoiceAction`.
- Parse action string in `_parseAction`.
- Route or speak result in `_setupNavigationCallback`.

### Re-enable Pi Vision BLE

Touch these files:

1. `lib/core/utils/constants.dart`
2. `lib/presentation/screens/home_screen.dart`
3. `lib/services/ble_service.dart` if UUIDs or parsing changed.

Checklist:

- Set `enablePiBle = true`.
- Restore/comment-in HomeScreen Pi BLE initialization, listener, alert card,
  and vibration/speech handlers.
- Verify Pi GATT UUIDs match `AppConstants`.
- Verify alert string format still matches `BleAlert.parse`.

### Adjust ESP32 Distance Alerts

Touch these files:

1. `lib/core/utils/constants.dart`
2. `lib/services/esp_ble_service.dart` if verdict model changes.
3. `lib/presentation/screens/home_screen.dart` if haptic/audio behavior changes.

Checklist:

- Update thresholds in centimeters.
- Keep escalation-only speech unless intentionally changing alert philosophy.
- Preserve immediate vibration for safety.

### Re-enable Offline Bengali STT

Touch these files:

1. `pubspec.yaml`
2. `lib/main.dart`
3. `lib/presentation/screens/splash_screen.dart`
4. `lib/services/speech_service.dart`
5. `lib/services/stt/*`

Checklist:

- Bundle required sherpa model directory in `pubspec.yaml`.
- Restore `sherpa.initBindings()` in `main.dart`.
- Restore model copy in `SplashScreen`.
- Restore Bengali sherpa path in `SpeechService`.
- Test microphone permission, model extraction, and final transcript behavior
  on a physical Android device.

### Re-enable Native Gemma/LiteRT LLM

Touch these files:

1. `pubspec.yaml`
2. `lib/services/llm_service.dart`
3. `lib/services/voice_navigation_service.dart`
4. `android/app/build.gradle.kts`
5. `android/app/src/main/kotlin/com/example/test_app_1/MainActivity.kt`

Checklist:

- Resolve duplicate `libLiteRt.so` conflict with `ultralytics_yolo`.
- Bundle `.litertlm` model only if APK size is acceptable.
- Restore native engine initialization/inference.
- Decide whether `AppConstants.enableLlm` means native LLM, Groq fallback, or
  a new explicit split such as `enableCloudLlm` and `enableNativeLlm`.

### Add A New Screen

Touch these files:

1. `lib/core/navigation/app_routes.dart`
2. `lib/main.dart`
3. `lib/presentation/screens/<new_screen>.dart`
4. `lib/services/voice_navigation_service.dart` and
   `assets/intents/intents.json` if voice navigation should reach it.

Checklist:

- Add route constant.
- Add route builder in `SmartCaneApp.routes`.
- Use bilingual visible text and semantic labels.
- Use `AppConstants` spacing/touch targets.

### Work On Vision Demo Models

Touch these files:

1. `assets/models/README.md`
2. `export_yolo_models.py`
3. `pubspec.yaml`
4. `lib/services/detection_models.dart`
5. `lib/presentation/screens/vision_demo_screen.dart`

Checklist:

- Generate or copy target `.tflite`.
- Add asset to `pubspec.yaml`.
- Make sure model filename matches `ModelVariant.assetFile`.
- Verify camera permission and Android physical device behavior.

## Verification Notes For Future Agents

- Use `rg`/`rg --files` for source discovery.
- Avoid relying on older `README*.md` files for current implementation state;
  they contain phase/planning text and some stale assumptions.
- `ARCHITECTURE.md` is helpful cross-repo context but should be checked against
  current source for active/disabled status.
- Do not run destructive git commands in this workspace.
- `git status` currently shows `ARCHITECTURE.md` as untracked before this
  indexing change; do not treat that as your own edit unless you changed it.
