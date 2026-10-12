# Crash Detection Feature — Progress Tracker

This document tracks the step-by-step implementation of the SmartKavach Crash Detection System.

---

## Progress Overview

| Phase | Description | Status | Completion Date |
| :--- | :--- | :--- | :--- |
| **Setup & Toolchain** | Homebrew tools, Flutter SDK, Android SDK, and Phone Debugging | **DONE** | Oct 12, 2026 |
| **Milestone 1** | Core Crash Detection Fusion Engine (`lib/crash_detector.dart`) | **DONE** | Oct 12, 2026 |
| **Milestone 2** | 15s Safety Countdown Modal & Emergency Haptics | **IN PROGRESS** | — |
| **Milestone 3** | In-App Simulation & Testing Panel (Highway crash, pothole presets) | **NOT STARTED** | — |
| **Phase 3** | ESP32 Helmet Firmware (`smartkavach_helmet.ino`) | **NOT STARTED** | — |
| **Phase 4A** | Baseline ML Model using Public Datasets | **NOT STARTED** | — |
| **Phase 4B** | Empirical Synthetic Dataset & Fine-Tuned Model (Post-Hardware) | **QUEUED** | — |
| **Phase 5** | Background Foreground Service & Offline Incident Logs | **NOT STARTED** | — |

---

## Detailed Task Checklist

### Pre-requisites & Environment
- [x] Mac environment setup (OpenJDK 17, Android CLI tools, adb, Flutter 3.47.7).
- [x] Connected realme device (`RMX3710`) authorized and verified via USB debugging.
- [x] Patched `another_telephony` cross-plugin permission conflict on Android 14/15.
- [x] Created dedicated feature branch: `feature/accident-detection-system`.

---

### Phase 1: Core Detection Engine & Safety Modal
- [x] Add `sensors_plus` to `pubspec.yaml` for phone accelerometer stream.
- [x] Implement multi-sensor fusion state machine in `lib/crash_detector.dart`:
  - [x] Stage 1: Impact detection ($g \ge 3.0g$ AND gyro $\ge 200^\circ/\text{s}$).
  - [x] Stage 2: Speed drop confirmation ($\Delta v \ge 15\text{ km/h}$ within 2 seconds).
  - [x] Stage 3: Post-impact stillness verification (3 seconds).
- [x] Create automated unit tests in `test/crash_detector_test.dart` (6/6 passing).
- [ ] Build the full-screen **"CRASH DETECTED!"** 15-second countdown modal with circular indicator.
- [ ] Implement repeating emergency haptic feedback alarm during countdown.
- [ ] Add **"I AM OK — CANCEL"** button with a 30-second disarm cooldown.
- [ ] Connect countdown expiration to automated SOS trigger (silent SMS + auto-dial).

---

### Phase 2: In-App Simulation & Testing Panel
- [ ] Build collapsible Simulation & Debug card in Ride tab (`HomePage`).
- [ ] Add one-tap test scenarios:
  - [ ] **"Simulate Highway Crash"** (High speed $\rightarrow$ Impact $\rightarrow$ Stop $\rightarrow$ Stillness $\rightarrow$ Modal triggers).
  - [ ] **"Simulate Pothole"** (High $Z$-accel $\rightarrow$ No tumble $\rightarrow$ Speed maintained $\rightarrow$ Ignored).
  - [ ] **"Simulate Dropped Phone"** (Impact spike $\rightarrow$ Initial speed 0 $\rightarrow$ Ignored).
- [ ] Add manual sliders for real-time testing of Speed, $g$-force, and Gyro rotation.

---

### Phase 3: ESP32 Helmet Firmware
- [ ] Create `smartkavach_helmet/smartkavach_helmet.ino`.
- [ ] Implement MPU6050 I2C sensor reading with startup zero-offset calibration.
- [ ] Configure BLE GATT server with Service UUID `4fafc201-1fb5-459e-8fcc-c5c9c331914b` and Gyro UUID `beb5483e-36e1-4688-b7f5-ea07361b26a8`.
- [ ] Implement CSV formatting (`x,y,z\n`) streaming at 25 Hz.

---

### Phase 4A: Baseline ML Model (Public Datasets)
- [ ] Download & preprocess public IMU benchmark datasets (e.g. MobiFall / SisFall / motorcycle telematics).
- [ ] Extract time-series window features (RMS, Peak-to-Peak, Zero-Crossing, FFT energy).
- [ ] Train lightweight baseline classifier (1D-CNN / Random Forest).
- [ ] Convert and quantize to `crash_model.tflite` (<150 KB).
- [ ] Add `tflite_flutter` and integrate into the detection pipeline.

---

### Phase 4B: Empirical Synthetic Dataset & Fine-Tuning (Post-Hardware)
- [ ] Connect physical ESP32 + MPU6050 helmet unit.
- [ ] Measure physical baseline values: helmet pitch/roll limits, head vibration profiles.
- [ ] Generate helmet-specific synthetic dataset (10,000+ samples).
- [ ] Fine-tune the ML model to the physical helmet placement.

---

### Phase 5: Background Tracking & Incident Logs
- [ ] Implement Android Foreground Service (`flutter_foreground_task`) with persistent notification.
- [ ] Implement local storage logging for confirmed crash telemetry events.
