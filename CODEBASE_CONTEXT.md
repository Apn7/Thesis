# Smart Cane (test_app_1) Codebase Context

This document provides a comprehensive overview of the `test_app_1` project architecture, features, and technical stack.

---

## 1. Project Overview
A specialized assistive technology application for visually impaired users in Bangladesh. It integrates on-device AI, offline speech processing, and hardware connectivity to provide a voice-guided navigation and obstacle detection experience.

---

## 2. Core Architecture
- **Framework:** Flutter (Dart) for UI and service orchestration.
- **Native Integration:** Android (Kotlin) handles heavy-duty on-device LLM inference via the **LiteRT-LM SDK**.
- **Communication Bridge:** A `MethodChannel` (`com.example.test_app_1/llm`) connects Flutter to the native Android AI engine.

---

## 3. AI & Voice Stack
- **On-Device LLM:** Uses **Gemma 4 E2B-it** via LiteRT-LM. It runs entirely offline for privacy and low latency.
    - **Function:** Intent classification. Transcripts are converted to structured JSON (e.g., `{"action": "navigate_location", "spoken_response": "..."}`).
- **STT (Speech-to-Text):** 
    - **Offline:** uses `sherpa-onnx` for Bengali (Bangla) and English.
    - **System:** `speech_to_text` plugin for online/default recognition.
- **TTS (Text-to-Speech):** `flutter_tts` for voice guidance.

---

## 4. Key Services (`lib/services/`)
- **VoiceNavigationService:** The central hub coordinating speech input, AI analysis, and app navigation/feedback.
- **LlmService:** Manages the native LLM lifecycle, including the initial 2.6GB model deployment from assets to device storage.
- **EspBleService:** Connects to an ESP32-based smart cane via BLE. Translates raw distance data into safety "Verdicts" (Safe, Caution, Warning, Critical).
- **BleService:** Alternative BLE implementation for Raspberry Pi vision-based alerts (supports object name/position parsing).
- **LocationService:** Provides real-time GPS coordinates for user orientation.

---

## 5. Navigation & UI
- **Routes:** Centralized in `lib/core/navigation/app_routes.dart` (`Splash`, `Home`, `Location`, `Settings`, `Help`).
- **Main Hub:** `lib/presentation/screens/home_screen.dart` manages the "Voice Command" loop and displays hardware sensor status.
- **Accessibility:** 
    - High-contrast themes (`lib/core/theme/`).
    - Bilingual Semantic labels (Bangla/English).
    - Haptic feedback (Vibration patterns) for obstacle alerts.
    - Layout stability via `textScaler` clamping (0.8x to 2.0x).

---

## 6. Technical Specifications
- **Flutter SDK:** `^3.10.3`
- **Primary Dependencies:** `provider`, `flutter_blue_plus`, `geolocator`, `sherpa_onnx`, `flutter_dotenv`.
- **Environment:** Configured via `.env` for API keys and system prompts.

---

## 7. Intent System (API Config)
The AI handles specific actions defined in `lib/core/config/api_config.dart`:
- `navigate_home` / `navigate_location` / `navigate_settings` / `navigate_help`
- `speak_battery` / `speak_time`
- `none` (Natural language conversation)
