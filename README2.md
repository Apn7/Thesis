Autonomous Smart Cane: An IoT-Enabled, Vision and Voice-Assisted Navigation Aid for the Visually Impaired

# 🦯 Autonomous Smart Cane
### An IoT-Enabled, Vision and Voice-Assisted Navigation Aid for the Visually Impaired

This project is the mobile software component of a smart assistive system designed to help **visually impaired individuals** navigate their environment using **voice guidance**, **on-device AI**, and **GPS-based awareness**.

The focus of this phase is to build an accessible **Android app** using **Flutter** that retrieves live **GPS location** and provides real-time **text-to-speech (TTS)** guidance in both **Bangla and English**.

> 🎯 Thesis project — Department of CSE, [Your University]  
> 👨‍💼 Supervisor: [Supervisor Name]  
> 📅 Timeline: 2025–2026  

---

## 🔧 Key Features (Phase 1 - TTS Navigation)

- ✅ Real-time GPS tracking
- 🔊 Offline text-to-speech navigation cues (English/Bangla)
- 📶 No internet required for core functionality
- ♿ Fully screen reader (TalkBack) compatible
- 🌐 Designed to communicate with a Raspberry Pi (future phases)

---

## 📌 Future Capabilities (Planned)

- 🧠 On-device object and face detection using camera (YOLO / MediaPipe)
- 🎙️ Offline Bangla speech command recognition (Gemma / Whisper)
- 🆘 Emergency SOS with GPS-based alert
- 🔗 IoT connectivity with Raspberry Pi for camera feed or remote data
- 🧭 Offline navigation to preset landmarks

---

## 🚀 Getting Started

### Prerequisites

- Flutter (v3.10 or newer)
- Android Studio or VS Code
- Android phone with GPS and TTS engine (Bangla TTS installed)

### Run the Project

```bash
git clone https://github.com/yourusername/autonomous-smart-cane.git
cd autonomous-smart-cane
flutter pub get
flutter run

📁 Project Structure
lib/
├── main.dart
├── ui/
│   └── home_page.dart
├── services/
│   ├── gps_service.dart
│   └── tts_service.dart
├── models/
│   └── location_model.dart
└── utils/
    └── permissions.dart

📦 Dependencies
dependencies:
  flutter:
    sdk: flutter
  geolocator: ^10.0.1
  flutter_tts: ^4.0.2
  permission_handler: ^11.0.0

✅ App Workflow

Request Permissions → Location & audio access

Fetch GPS Coordinates → Using geolocator

Speak Location → Via flutter_tts in Bangla or English

Accessibility Layer → UI supports screen readers

💡 Use Case Example

The user launches the app → It announces “You are at Road 12, Dhanmondi” in Bangla → The location is updated every 10 seconds → Future: User says “আমি কোথায় আছি?” and receives a voice reply.

🛠️ System Integration Plan
Component	Role
Android App	UI + GPS + TTS + voice commands
Raspberry Pi	Camera + object detection
Communication	REST API / Bluetooth / Wi-Fi
Cloud (optional)	Emergency alert, future updates
🧪 In Development

Bangla voice command integration (offline)

Object detection on-device (via TFLite)

Location tagging and landmark recognition

Family/caregiver live tracking (optional)

🙌 Contributors

Developer: [Your Name], CSE Undergrad, [Your University]

Supervisor: [Supervisor Name]

Special Thanks: Open-source communities working on Flutter, TFLite, Bangla NLP

📖 License

This project is open source under the MIT License