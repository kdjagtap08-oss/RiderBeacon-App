# SmartKavach — Crash Detection Feature Blueprint

## 1. Executive Summary & Architecture

The **Crash Detection System** is the core safety engine of SmartKavach. It provides real-time, multi-sensor accident detection and automated emergency dispatch designed for low-connectivity environments.

The system uses a **2-Tier Hybrid Architecture**:
1. **Tier 1 (Helmet ESP32 + MPU6050):** Ultra-low-power edge monitoring on the helmet measuring rotational velocity and impact vectors, streaming via Bluetooth Low Energy (BLE).
2. **Tier 2 (Smartphone App):** Sensor fusion combining phone accelerometer, helmet gyroscope, and GPS speed telemetry, with a 2-stage verification engine (Rule-Based + Lightweight Machine Learning) and an automated safety countdown modal before SOS dispatch.

```
+-----------------------------------+        +-----------------------------------+
|      TIER 1: ESP32 Helmet         |        |         TIER 2: Smartphone        |
|  - MPU6050 Accel & Gyroscope      |  BLE   |  - Phone Accelerometer            |
|  - Low-power anomaly filter       | -----> |  - Phone GPS (Speed & Location)   |
|  - ASCII CSV Stream: "x,y,z"      |        |  - Crash Detection Engine         |
+-----------------------------------+        |  - 15s "Are You OK?" Countdown    |
                                             |  - Direct Call & Silent SMS       |
                                             +-----------------------------------+
```

---

## 2. Detection Logic & State Machine

The detection engine uses a 4-stage state machine to virtually eliminate false positives (such as potholes, speed bumps, or dropping the phone):

```
[ IDLE ] 
   │
   │ Phone Accel >= 3.0g  AND  Helmet Gyro >= 200°/s
   ▼
[ IMPACT DETECTED ]
   │
   │ Within 2.0s: GPS Speed drops by >= 15 km/h
   ▼
[ CONFIRMING ]
   │
   │ 3.0s of relative stillness (Accel ≈ 1g ± 0.3g, Gyro < 20°/s)
   ▼
[ ALERT TRIGGERED ] ──> Launch 15-Second "Are You OK?" Countdown Modal
```

- **Rider responds ("I AM OK"):** Disarms the system, logs the event as a false alarm, and enforces a 30-second cooldown.
- **Rider does not respond (Countdown reaches 0):** Automatically dispatches emergency SMS with Google Maps GPS link to all contacts and calls Emergency Contact #1.

---

## 3. Phased Implementation Roadmap

### Phase 1: Core Detection Engine & Safety Modal (Mobile)
1. **Sensor Ingestion:** Add `sensors_plus` to listen to phone linear acceleration.
2. **Unified Fusion Engine (`CrashDetector`):** Fuse phone accelerometer, helmet `GyroFeed`, and GPS `Tracker`.
3. **Decoupled Architecture:** Support both live device streams and simulated mock data streams.
4. **"Are You OK?" Full-Screen Modal:** 15-second animated countdown, continuous haptic vibration alert, and an "I AM OK" disarm button.
5. **SOS Dispatch Link:** Connect countdown expiration directly to the telephony silent SMS and direct phone call triggers.

---

### Phase 2: In-App Simulation & Testing Panel
*Allows full testing without physical MPU6050/ESP32 hardware or moving a bike.*
1. **Interactive Test Panel:** Collapsible drawer on the Ride dashboard.
2. **Scenario Presets:**
   - 💥 **Highway Crash Simulation:** $60\text{ km/h} \rightarrow 4.2g\text{ spike} \rightarrow 320^\circ/\text{s tumble} \rightarrow 0\text{ km/h} \rightarrow \text{stillness} \rightarrow \text{Triggers alert}$.
   - 🕳️ **Pothole / Bump Simulation:** $45\text{ km/h} \rightarrow 3.0g\text{ spike} \rightarrow 0^\circ/\text{s gyro} \rightarrow \text{speed maintained} \rightarrow \text{Ignored}$.
   - 📱 **Dropped Phone Simulation:** $0\text{ km/h} \rightarrow 3.5g\text{ spike} \rightarrow 0\text{ helmet gyro} \rightarrow \text{Ignored}$.
   - 🏍️ **Aggressive Cornering:** Lean angle high, but smooth rotation and constant speed $\rightarrow \text{Ignored}$.
3. **Manual Controls:** Sliders for Speed ($0–140\text{ km/h}$), Accel ($0–8g$), and Gyro ($0–500^\circ/\text{s}$).

---

### Phase 3: ESP32 Helmet Firmware
1. **I2C MPU6050 Driver:** Read 3-axis accelerometer and 3-axis gyroscope with initial zero-offset calibration.
2. **BLE GATT Server:** Advertise custom Service UUID (`4fafc201-1fb5-459e-8fcc-c5c9c331914b`) and Gyro Characteristic UUID (`beb5483e-36e1-4688-b7f5-ea07361b26a8`).
3. **Stream Formatting:** Send formatted ASCII CSV packets (`x,y,z\n`) at 25 Hz.
4. **Firmware Source:** Create [`smartkavach_helmet/smartkavach_helmet.ino`](smartkavach_helmet/smartkavach_helmet.ino) in the repository.

---

### Phase 4: Machine Learning Pipeline (2-Stage Approach)

#### Stage 4A: Baseline Model on Public Datasets (Current — Pre-Hardware)
- **Public Datasets:** Utilize open benchmark IMU datasets (e.g., MobiFall, SisFall, and motorcycle telematics datasets from Kaggle/UCI).
- **Feature Extraction:** Sliding window of 2.5 seconds (50 time steps @ 20 Hz):
  - Statistical: RMS, Peak-to-Peak amplitude, Mean, Variance, Zero-Crossing Rate.
  - Frequency domain: Spectral energy, dominant frequency via FFT.
- **Model Training:** Train a lightweight baseline model (1D-CNN / Random Forest / Tiny-MLP).
- **Export & Quantization:** Export to quantized TensorFlow Lite (`.tflite`) format (<150 KB).
- **Integration:** Integrate via `tflite_flutter` as an auxiliary inference check.

#### Stage 4B: Production Model on Empirical Synthetic Data (Post-Hardware)
- Once the physical ESP32 + MPU6050 helmet unit is built and mounted to the back of the helmet:
  1. Record extreme angles, helmet tilts, vibrations, and head motion boundaries.
  2. Use these empirical calibration boundaries to synthesize a large, helmet-specific dataset (10,000+ samples).
  3. Re-train and fine-tune the model to the exact physical helmet geometry.

---

### Phase 5: Background Execution & Telemetry Logging
1. **Android Foreground Service:** Integrate `flutter_foreground_task` so BLE streaming and crash monitoring continue when the screen is locked or another app is open.
2. **Local Incident Storage:** Log crash telemetry (timestamps, peak $g$-force, coordinates) to local storage.
