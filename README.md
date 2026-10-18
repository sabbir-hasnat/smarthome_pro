# SmartHome Pro

Lightweight Flutter smart-home app for ESP32 relay devices with BLE + MQTT control.

## Features

- Multi-device management (save/edit/delete ESP32 devices)
- BLE local control + MQTT cloud fallback
- English/Bangla in-app language switch (persisted)
- Theme mode switch: Light / Dark / System default (persisted)
- Live in-app clock with locale-aware formatting
- Device telemetry and firmware metadata panel
- ESP32 command compatibility with retained MQTT state/availability topics

## Repository Structure

- `/lib` - Flutter app source
- `/lib/l10n` - English/Bangla ARB translations
- `/test` - focused parser/settings/widget tests
- `/android` - Android build configuration
- `/esp32 codes` - ESP32 firmware source

## Android Compatibility

Current Android app configuration:

- `minSdk`: 23 (Android 6.0)
- `targetSdk`: 35 (Android 15)
- `compileSdk`: 35

This configuration is intended to support Android 6 through Android 15, subject to device vendor BLE/MQTT networking behavior.

## Flutter App Setup

1. Install Flutter and Android SDK.
2. From repository root:

```bash
flutter pub get
flutter analyze
flutter test
```

3. Build release APK:

```bash
flutter build apk --release
```

Release APK path:

- `build/app/outputs/flutter-apk/app-release.apk`

## MQTT Topic Contract (App + ESP32)

For `DEVICE_ID = SHN-XXXXXXXX`:

- Command topic: `iot/smarthome/<DEVICE_ID>/cmd`
- State topic: `iot/smarthome/<DEVICE_ID>/state` (retained)
- Availability topic: `iot/smarthome/<DEVICE_ID>/availability` (retained)

Supported command payload examples:

```json
{"cmd":"login","pin":"123456"}
{"cmd":"get_status","pin":"123456"}
{"cmd":"control","light":true,"fan":false,"pin":"123456"}
{"cmd":"set_wifi","ssid":"MyWifi","pass":"MyPass","pin":"123456"}
{"cmd":"set_pin","new_pin":"9876","pin":"123456"}
{"cmd":"set_mqtt","server":"broker.hivemq.com","port":1883,"user":"","password":"","pin":"123456"}
```

## ESP32 Firmware Notes

- Firmware file: `/esp32 codes`
- Device ID and MQTT topics are generated from ESP32 chip MAC and remain compatible with app expectations.
- Default credentials are no longer hardcoded for private Wi-Fi/broker settings.
- MQTT settings (`server`, `port`, optional `user/password`) are persisted in NVS and can be updated via `set_mqtt`.
- Wi-Fi SSID/password are persisted in NVS and updateable via `set_wifi`.
- Availability uses LWT (`OFFLINE`) and publishes `ONLINE` on successful MQTT connect.

## ESP32 Flashing (Arduino IDE)

1. Open `/esp32 codes` in Arduino IDE.
2. Select ESP32 board and COM port.
3. Install required libraries:
   - PubSubClient
   - ArduinoJson
   - ESP32 BLE libraries (BLEDevice/BLEServer)
4. Upload firmware.
5. Pair/use app with device ID shown by serial logs (format `SHN-...`).

## Limitations

- TLS on ESP32 currently uses `setInsecure()` when MQTT port is `8883`; for production, configure CA certificates.
- BLE support depends on Android device chipset/permissions.
- If your CI or local machine lacks Flutter SDK, build/test commands cannot run until Flutter is installed.
