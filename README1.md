Autonomous Smart Cane: An IoT-Enabled, Vision- and Voice-Assisted Navigation Aid

    Thesis Project | Status: Phase 1 (Software Core) | Focus: Edge AI, Embedded Systems, Assistive Technology

1. Project Context & Motivation

This project aims to develop a hybrid assistive system for the visually impaired that decouples safety sensors from intelligent processing.

Most existing solutions rely either heavily on expensive, bulky hardware or purely on smartphone apps that require internet connectivity. This project bridges that gap by creating an "Autonomous" system where:

    The Hardware Unit (The Cane): Handles immediate proximity safety (via distance sensors) and tactile feedback.

    The Software Unit (The App): Handles sophisticated object detection, scene understanding, and voice interaction using the smartphone's superior processing power.

Key Differentiator: The system is designed to work Offline and supports Localized Natural Language Processing (NLP) (specifically Bangla), addressing the lack of assistive tools for non-English speakers.
2. System Architecture

The system follows a distributed computing model where the heavy processing is offloaded to the user's smartphone to keep the physical device lightweight and cost-effective.
Code snippet

graph TD
    User((User))
    
    subgraph "Hardware Unit (The Stick)"
        Controller[Microcontroller]
        Sensors[Proximity & Environment Sensors]
        Location[Positioning Module]
        Camera[Image Capture Module]
        Haptic[Vibration Feedback]
    end
    
    subgraph "Processing Unit (The App)"
        MobileApp[Mobile Application]
        VisionEngine[Offline Object Detection Model]
        VoiceInput[Offline Speech-to-Text]
        VoiceOutput[Localized Text-to-Speech]
    end
    
    User -->|Voice Command| MobileApp
    MobileApp -->|Audio Feedback| User
    
    Controller -->|Video Stream & Sensor Data| MobileApp
    MobileApp -->|Navigation Logic| Controller
    Controller -->|Haptic Alert| User

3. Functional Modules
A. Mobile Application (The "Brain")

This unit serves as the central processing hub.

    Computer Vision: Analyzes video feed in real-time to identify obstacles (e.g., persons, vehicles, furniture) using on-device inference.

    Voice Interaction: Processes user commands in the local language (e.g., "Where am I?") and provides audio feedback.

    Localization Mapping: Translates generic object labels into localized terms (e.g., "Car" -> "Gari") for the user.

    Connectivity: Manages the wireless data stream from the hardware unit.

B. Embedded System (The "Body")

This unit handles physical sensing and immediate safety.

    Proximity Detection: Uses sensors to detect immediate hazards (walls, drop-offs) and triggers instant vibration.

    Image Streaming: Captures and transmits video frames to the mobile application for analysis.

    Location Tracking: Acquires geospatial coordinates for emergency alerts and navigation.

4. Current Work Objectives (Phase 1: App-Centric Navigation)

We are currently building the "Vision and Voice" module of the thesis title.

    [ ] Real-time Object Detection: Implement a camera view that detects and classifies objects without requiring an internet connection.

    [ ] Localization Layer: Create a logic map to translate detected object labels into the target local language (Bangla).

    [ ] Speech Synthesis: Integrate a Text-to-Speech engine to vocalize navigation alerts and object descriptions.

    [ ] Visual Distance Estimation: Implement a heuristic algorithm to estimate the distance of an object based on its bounding box size relative to the screen frame.

5. Development Workflow
Environment Setup

    Mobile Development Environment: Configure the SDK and IDE for cross-platform mobile app development.

    Vision Library Integration: Integrate a machine learning library capable of running quantized models on mobile edge devices.

    Voice Engine Configuration: Set up the speech synthesis engine to support the specific language locale (Bangla).

Execution Steps

    Initialize Project: Create the project structure and configure necessary permissions (Camera, Microphone).

    Implement Vision: Connect the camera stream to the object detection analyzer.

    Implement Logic: Write the middleware that filters detection confidence scores and triggers voice output.

    Test & Iterate: Validate detection accuracy and response latency on a physical device.