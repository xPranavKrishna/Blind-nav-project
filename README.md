# Vazhikaatti (AI Blind Navigation Assistant)

Vazhikaatti (Malayalam for "Guide") is an intelligent Android mobile application and hardware ecosystem specifically designed to assist visually impaired individuals with independent navigation. It integrates advanced artificial intelligence, Bluetooth Low Energy (BLE) wearables, and indoor BLE beacons to deliver real-time environmental awareness, directional guidance, and safety features.

## Key Features

- **Obstacle Detection & Alerts:** Wearable hardware equipped with ultrasonic sensors detects obstacles in real-time. Feedback is sent instantly to the app via BLE for haptic and audio alerts.
- **Indoor BLE Navigation:** Dynamic room-by-room indoor navigation powered by stationary BLE beacons (`Room1-Beacon`, `Room2-Beacon`, `Hallway-Beacon`).
- **Continuous Background Auto-Reconnection:** Robust BLE background services ensure the wearable device and beacons stay seamlessly connected at all times.
- **Voice Commands & TTS:** Fully hands-free interactive experience via Speech-To-Text (STT) and Flutter TTS (Text-to-Speech) for issuing navigation commands mid-route.
- **Emergency Protocols:** Integrated instant emergency caretaker calls and SOS features.

## Architecture & Technologies

- **Frontend:** Flutter SDK (Dart)
- **Hardware Integrations:** ESP32 Microcontrollers (Wearable + Beacons), HC-SR04 Ultrasonic Sensors.
- **Connectivity:** `flutter_blue_plus` for BLE communication.

## Hardware Setup (ESP32 / Arduino IDE)

The project includes custom firmware for ESP32 microcontrollers. All hardware code is neatly organized in the `hardware/` directory. 
*Note: To flash these devices, open the respective `.ino` files in the Arduino IDE and upload to your ESP32 boards.*

### 1. Wearable Device (`hardware/wearable_device/BlindNavESP/`)
The wearable acts as a BLE Server and connects to the HC-SR04 ultrasonic sensor to measure distances.
- **Microcontroller:** ESP32
- **Sensor:** HC-SR04 (Trig: Pin 5, Echo: Pin 18)

### 2. Navigation Beacons (`hardware/beacons/`)
Stationary ESP32 devices acting as BLE advertisers that the app uses for indoor triangulation/localization. 
You can find individual firmware for each beacon here:
- `Room1_Beacon`
- `Room2_Beacon`
- `Hallway_Beacon`

## Getting Started

### Prerequisites

- Flutter SDK `^3.10.0` (or newer recommended)
- Android Studio / VS Code
- Arduino IDE (for flashing hardware)
- A physical Android device (BLE features do not work on emulators)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/xPranavKrishna/Blind-nav-project.git
   ```

2. **Navigate to the project directory:**
   ```bash
   cd Blind-nav-project
   ```

3. **Install dependencies:**
   ```bash
   flutter pub get
   ```

4. **Run the app:**
   ```bash
   flutter run
   ```

## Development & Contribution

- The main application entry point is `lib/main.dart` with routing in `lib/pages/`.
- Device connection and navigation services are maintained in `lib/services/`.
- Hardware firmware is managed in `hardware/`.

## License

This project is licensed under the MIT License.
