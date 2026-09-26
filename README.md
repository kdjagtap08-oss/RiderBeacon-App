# SmartKavach

A smart helmet safety system for riders on long rides through remote areas with little or no internet or network coverage. SmartKavach pairs a Flutter Android app with a helmet unit built on an ESP32 + MPU6050, and works toward automatic accident detection and alerting using only phone signal (SMS/calls) — no internet required.

## What it does

- **Live GPS tracking** — shows the rider's position on a map using the phone's own GPS
- **Speed tracking** — read directly from the phone's GPS fix, shown on a live speedometer
- **Helmet connection (BLE)** — connects to the helmet's ESP32 over Bluetooth Low Energy
- **Gyroscope readings** — live rotation data (X/Y/Z, °/s) streamed from the helmet's MPU6050
- **Manual SOS** — one long-press calls the rider's emergency contact directly and sends their live location by SMS
- **SOS settings** — add and manage up to 3 emergency contact numbers, stored on the phone

## In progress

- **Automatic accident detection** — a rule-based fusion of accelerometer, gyroscope and GPS-speed data to detect a likely crash and trigger SOS automatically, with a countdown to cancel false alarms (see the `feature/accident-detection` branch)
- **SOS SMS delivery** — currently being debugged on some devices/carriers; the automatic phone call works

## Why phone-based, not external sensors

An earlier version of this project used external GPS and speed sensors on the helmet. That approach was dropped in favor of using the rider's own phone for GPS, speed and connectivity, keeping the helmet hardware minimal (just the ESP32 + MPU6050 for motion sensing).

## Tech stack

| Part | Tech |
|---|---|
| App | Flutter (Android) |
| Location & speed | Phone GPS via `geolocator` |
| Map | `flutter_map` (OpenStreetMap) |
| Helmet link | Bluetooth Low Energy via `flutter_blue_plus` |
| Helmet hardware | ESP32 + MPU6050 (accelerometer + gyroscope) |
| SOS call | `flutter_phone_direct_caller` |
| SOS SMS | `another_telephony` |
| Local storage | `shared_preferences` |

## Project structure

```
lib/
  main.dart            # App entry point, dashboard, helmet screen, SOS
  gyro.dart            # BLE gyroscope feed from the helmet's ESP32
  crash_detector.dart  # Rule-based accident detection (in progress, separate branch)
smartkavach_helmet/
  smartkavach_helmet.ino  # ESP32 + MPU6050 firmware
```

## Getting started

1. Install Flutter and the Android SDK.
2. Clone the repo and run:
   ```
   flutter pub get
   ```
3. Connect an Android phone (USB debugging on) and run:
   ```
   flutter run
   ```
4. For the helmet unit: open `smartkavach_helmet.ino` in the Arduino IDE, wire an MPU6050 to an ESP32 (VCC→3V3, GND→GND, SDA→GPIO21, SCL→GPIO22, AD0→GND), and upload.

### Permissions required (Android)

The app needs location, Bluetooth, phone and SMS permissions — see `AndroidManifest.xml`.

## Roadmap

- Reliable automatic crash detection with a confirm/cancel countdown
- Store-and-forward SOS for areas with zero signal
- Possible LoRa-based relay between riders for group rides in dead zones
- On-device ML model to improve crash-detection accuracy over the current rule-based approach

## Status

Built as a student project (Flutter + ESP32). Core tracking, helmet connection and manual SOS are working; automatic accident detection is the current focus.