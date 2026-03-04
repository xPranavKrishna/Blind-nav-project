# Vazhikaatti (AI Blind Navigation Assistant)

Vazhikaatti (Malayalam for "Guide") is an intelligent Android mobile application specifically designed to assist visually impaired individuals with independent navigation. It integrates advanced artificial intelligence, Bluetooth Low Energy (BLE) wearables, and cloud infrastructure to deliver real-time environmental awareness, directional guidance, and safety features.

## Key Features

- **Obstacle Detection & Alerts:** Real-time environmental monitoring leveraging Firebase Realtime Database for rapid haptic and audio alerts when obstacles are detected.
- **Continuous Background Auto-Reconnection:** Aggressive BLE service to ensure the wearable device stays seamlessly connected at all times.
- **Voice Commands & TTS:** Fully hand-free interactive experience via Speech-To-Text (STT) and Flutter TTS.
- **Smart Navigation:** Cloud-synchronized routes and checkpoints using Cloud Firestore.
- **Haptic Feedback:** Direct vibration notifications indicating turns or immediate physical dangers.
- **Emergency Protocols:** Integrated instant emergency stop and SOS messaging capabilities.

## Architecture & Technologies

- **Frontend:** Flutter SDK (Dart)
- **Backend Services:** Firebase (Firestore, Realtime Database)
- **Hardware Integration:** `flutter_blue_plus` for BLE connection
- **Permissions:** Robust location, Bluetooth, and microphone requirement handling

## Getting Started

### Prerequisites

- Flutter SDK `^3.9.2`
- Android Studio / VS Code
- A physical Android device for proper BLE functionality testing.

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/xPranavKrishna/Blind-nav-project.git
   ```
2. Navigate to the project directory:
   ```bash
   cd Blind-nav-project
   ```
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Run the app:
   ```bash
   flutter run
   ```

## Development & Contribution

- The main application entry point is `lib/main.dart` with routing in `lib/pages/`.
- Device connection services are maintained in `lib/services/`.
- Ensure you have correctly configured Firebase for Android before deploying `google-services.json`.

## License

This project is licensed under the MIT License.
