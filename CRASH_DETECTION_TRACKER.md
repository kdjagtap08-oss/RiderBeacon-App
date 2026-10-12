# Crash Detection Feature — Progress Tracker

This document tracks the step-by-step implementation of the SmartKavach Crash Detection System.

---

## Progress Overview

| Phase | Description | Status | Completion Date |
| :--- | :--- | :--- | :--- |
| **Setup & Toolchain** | Homebrew tools, Flutter SDK, Android SDK, and Phone Debugging | **DONE** | Oct 12, 2026 |
| **Milestone 1** | Core Crash Detection Fusion Engine (`lib/crash_detector.dart`) | **DONE** | Oct 12, 2026 |
| **Milestone 2** | 15s Safety Countdown Modal & Emergency Haptics | **DONE** | Oct 12, 2026 |
| **Milestone 3** | In-App Simulation & Testing Panel (Highway crash, pothole presets) | **DONE** | Oct 12, 2026 |
| **Milestone 4** | Automated SOS & Post-Incident Feedback Sheet (`IncidentFeedbackSheet`) | **DONE** | Oct 12, 2026 |
| **Milestone 5** | ESP32 Helmet Firmware (`smartkavach_helmet.ino`) | **DONE** | Oct 12, 2026 |
| **Milestone 6** | Stage 4A Baseline ML Model (Public Datasets & TFLite Pipeline) | **DONE** | Oct 12, 2026 |
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
- [x] Build the full-screen **"CRASH DETECTED!"** 15-second countdown modal with circular indicator (`lib/crash_countdown_dialog.dart`).
- [x] Implement repeating emergency haptic feedback alarm during countdown.
- [x] Add **"I AM OK — CANCEL"** button with a 30-second disarm cooldown.
- [x] Build post-incident feedback modal (`lib/incident_feedback_sheet.dart`) for classifying why alarm triggered (Pothole, Dropped phone, Minor fall, Other).
- [x] Add one-tap "Send 'I'm Safe' SMS" reassurance message to emergency contacts when minor fall is selected.
- [x] Connect countdown expiration to automated SOS trigger (silent SMS + auto-dial).
- [x] Create widget tests in `test/crash_countdown_dialog_test.dart` (4/4 passing) and `test/incident_feedback_sheet_test.dart` (3/3 passing).

---

### Phase 2: In-App Simulation & Testing Panel
- [x] Build collapsible Simulation & Debug card in Ride tab (`HomePage`) (`lib/simulation_panel.dart`).
- [x] Add one-tap test scenarios:
  - [x] **"Crash Preset"** (Highway speed $\rightarrow$ Impact $\rightarrow$ Deceleration $\rightarrow$ Stillness $\rightarrow$ Launches 15s Countdown Modal).
  - [x] **"Pothole"** (Vertical spike $\rightarrow$ 0°/s gyro $\rightarrow$ Speed maintained $\rightarrow$ Ignored).
  - [x] **"Dropped Phone"** (High shock $\rightarrow$ 0 initial speed $\rightarrow$ Ignored).
- [x] Add manual sliders for real-time testing of Speed ($0–140\text{ km/h}$), Accel ($0.5–8g$), and Gyro ($0–500^\circ/\text{s}$).
- [x] Create widget tests in `test/simulation_panel_test.dart` (5/5 passing).

---

### Phase 3: ESP32 Helmet Firmware
- [x] Create `smartkavach_helmet/smartkavach_helmet.ino`.
- [x] Implement MPU6050 I2C sensor reading with startup zero-offset calibration.
- [x] Configure BLE GATT server with Service UUID `4fafc201-1fb5-459e-8fcc-c5c9c331914b` and Gyro UUID `beb5483e-36e1-4688-b7f5-ea07361b26a8`.
- [x] Implement CSV formatting (`x,y,z\n`) streaming at 25 Hz.

---

### Phase 4A: Baseline ML Model (Public Datasets)
- [x] Download & preprocess public IMU benchmark datasets (MobiFall / SisFall / motorcycle telematics in `ml/dataset_loader.py`).
- [x] Extract 21 time-series window features (RMS, Peak-to-Peak, stillness indicators, speed delta in `ml/feature_extractor.py`).
- [x] Train lightweight baseline classifier achieving 100% test accuracy on test split (`ml/train_baseline.py`).
- [x] Convert weights to portable JSON (`ml/model_weights.json`) and zero-dependency in-app Dart engine (`lib/ml_crash_classifier.dart`).
- [x] Verify inference latency (<0.15ms) and 0% false positives on potholes/dropped phones (`ml/verify_inference.py`, `test/ml_crash_classifier_test.dart`).

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
