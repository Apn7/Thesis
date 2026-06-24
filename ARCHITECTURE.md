# Smart Cane — Architecture Index

Assistive navigation system for visually impaired users (Bangladesh). Three hardware/software components communicate over BLE; this file is a map of how they fit together. Each subdirectory's own `CLAUDE.md` is the source of truth for commands and details — this is an index, not a replacement.

## Components

| Component | Path | Role | Platform |
|---|---|---|---|
| Mobile app | `Test_app/test_app_1/` | Flutter companion app: bilingual voice UI, BLE client, GPS, on-device LLM | Android, Windows |
| Vision backend | `Thesis_pie/Thesis-pie/` | YOLOv8 obstacle detection, BLE GATT server | Raspberry Pi 5 (Linux/BlueZ only) |
| Cane firmware | `Thesis_esp/` | ESP32 sketches: BLE GATT peripheral + ultrasonic distance sensing | ESP32 / ESP32-S3 |

## Data Flow

```
[Raspberry Pi 5]                              [ESP32 cane hardware]
 main.py (multiprocess)                         smart_cane_ble.ino
 ├─ Proc 1: BlueZ GATT server ─┐                 (distance sensor,
 └─ Proc 2: YOLOv8 + OpenCV    │  BLE GATT        BLE notify)
      detector.py → Queue       │                      │
                                 ▼                      ▼
                         ┌─────────────────────────────────┐
                         │   Flutter app (Android/Windows)  │
                         │   BleService / EspBleService     │
                         └─────────────────┬─────────────────┘
                                            ▼
                                  VoiceNavigationService
                                  ├─ SpeechService (STT, bn/en)
                                  ├─ LlmService (on-device Gemma)
                                  └─ TtsService (announces alerts)
```

- Pi alert string: `"LEVEL:OBJECT:CONFIDENCE:POSITION"` (e.g. `CRITICAL:person:0.87:center`), produced by `config.py:generate_alert_message()`, parsed by `BleService`.
- ESP32 cane sends raw distance readings over its own GATT service (`a1b2c3d4-...-1000-8000-00805f9b34fb`), consumed by `EspBleService`.
- **BLE UUIDs and alert format are duplicated across Pi/ESP32 firmware and `lib/core/config/api_config.dart`** — changes to either must be mirrored on both ends.

## Mobile App (`Test_app/test_app_1/`)

Layered: `lib/core/` (config, theme, routing, accessibility utils) → `lib/services/` → `lib/presentation/` (screens, widgets). State via Provider/`ChangeNotifier`; services are singletons.

Key services:
- `VoiceNavigationService` — orchestrates voice pipeline, exposes navigation callback
- `SpeechService` — dual-engine STT: sherpa-onnx Zipformer (offline Bengali) vs Android built-in (English)
- `LlmService` — on-device Gemma 4 E2B via LiteRT-LM (Kotlin native channel); `GroqService` is a legacy cloud fallback
- `BleService` / `EspBleService` — BLE clients for the Pi vision system and ESP32 cane hardware respectively
- `TtsService` — abstract; `tts_service_impl.dart` (mobile) vs `tts_service_stub.dart` (Windows, logs only — `flutter_tts` removed due to CMake issues)
- `LocationService` — GPS + OpenStreetMap Nominatim reverse geocoding

## Vision Backend (`Thesis_pie/Thesis-pie/`)

Three files: `config.py` (constants, COCO class → danger-level mapping, BLE UUIDs), `detector.py` (`ObstacleDetector` + `FrameAnnotator`), `main.py` (two processes — BlueZ GATT server on GLib loop, OpenCV/YOLO vision loop — kept separate because GLib and Qt event loops are incompatible). 3s alert cooldown prevents BLE queue flooding.

Danger levels: **CRITICAL** (person, vehicles), **WARNING** (furniture, animals), **CAUTION** (signs, small obstacles).

## Cane Firmware (`Thesis_esp/`)

Three Arduino sketches, not yet documented in a subdirectory `CLAUDE.md`:
- `smart_cane_ble/` — BLE GATT peripheral, notifies distance readings
- `smart_cane_distance/` — ultrasonic distance sensing (standalone, no BLE)
- `smart_cane_distance_s3/` — ESP32-S3 variant

## Cross-Cutting Notes

- Two independent BLE links exist on the phone: one to the Pi (vision alerts), one to the ESP32 (distance/cane hardware) — different services, different UUIDs.
- Changing BLE UUIDs or the alert string format requires updating both the producer (Pi `config.py` or ESP32 `.ino`) and the consumer (`api_config.dart` / `BleService`/`EspBleService`).
- `Thesis_esp/` has no `CLAUDE.md` yet — worth adding if firmware work becomes frequent.
