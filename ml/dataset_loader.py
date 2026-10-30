"""
SmartKavach ML Pipeline — Dataset Loader & Telematics Generator
Generates time-series sensor windows modeled on public IMU fall/crash benchmarks
(MobiFall, SisFall, and motorcycle telematics dynamics).
"""

import numpy as np

# Sampling parameters: 2.5 seconds at 20 Hz = 50 time steps
SAMPLE_RATE_HZ = 20
WINDOW_SECONDS = 2.5
WINDOW_SAMPLES = int(SAMPLE_RATE_HZ * WINDOW_SECONDS) # 50 samples

CLASS_NAMES = {
    0: "Normal Riding",
    1: "Pothole / Road Shock",
    2: "Dropped Phone",
    3: "Severe Motorcycle Crash"
}

def generate_window(label: int, random_seed: int = None) -> np.ndarray:
    """
    Generates a single 50x7 time-series sensor window:
    Channels: [acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z, speed_kmh]
    """
    rng = np.random.default_rng(random_seed)
    time = np.linspace(0, WINDOW_SECONDS, WINDOW_SAMPLES)
    window = np.zeros((WINDOW_SAMPLES, 7), dtype=np.float32)

    if label == 0:
        # ---- Class 0: Normal Riding ----
        # Steady speed (30 - 90 km/h) with subtle variations
        base_speed = rng.uniform(30.0, 90.0)
        window[:, 6] = base_speed + rng.normal(0, 0.5, WINDOW_SAMPLES)
        # Normal engine vibration + gravity along Z-axis (approx 1g = 9.81 m/s^2)
        window[:, 0] = rng.normal(0, 0.4, WINDOW_SAMPLES) # X
        window[:, 1] = rng.normal(0, 0.4, WINDOW_SAMPLES) # Y
        window[:, 2] = 9.81 + rng.normal(0, 0.6, WINDOW_SAMPLES) # Z (gravity)
        # Smooth banking rotations (turns are smooth, < 25 deg/s)
        window[:, 3] = rng.normal(0, 5.0, WINDOW_SAMPLES)
        window[:, 4] = rng.normal(0, 4.0, WINDOW_SAMPLES)
        window[:, 5] = rng.normal(0, 8.0, WINDOW_SAMPLES)

    elif label == 1:
        # ---- Class 1: Pothole / Speed Bump ----
        # Cruising speed remains maintained
        base_speed = rng.uniform(35.0, 75.0)
        window[:, 6] = base_speed + rng.normal(0, 0.4, WINDOW_SAMPLES)
        # Baseline gravity
        window[:, 0] = rng.normal(0, 0.5, WINDOW_SAMPLES)
        window[:, 1] = rng.normal(0, 0.5, WINDOW_SAMPLES)
        window[:, 2] = 9.81 + rng.normal(0, 0.7, WINDOW_SAMPLES)
        # Sudden vertical impulse shock around sample 15-20 (lasting 3-5 samples)
        shock_idx = rng.integers(15, 25)
        shock_magnitude = rng.uniform(28.0, 45.0) # 2.8g to 4.5g
        window[shock_idx:shock_idx+4, 2] += shock_magnitude
        # Helmet rotation stays very low (< 20 deg/s)
        window[:, 3] = rng.normal(0, 6.0, WINDOW_SAMPLES)
        window[:, 4] = rng.normal(0, 5.0, WINDOW_SAMPLES)
        window[:, 5] = rng.normal(0, 7.0, WINDOW_SAMPLES)

    elif label == 2:
        # ---- Class 2: Dropped Phone ----
        # Initial speed is 0 or near stationary (< 5 km/h)
        window[:, 6] = np.maximum(0.0, rng.normal(0, 0.5, WINDOW_SAMPLES))
        # Phone tumble and impact on ground around sample 10
        drop_idx = rng.integers(10, 20)
        window[:, 0] = rng.normal(0, 1.0, WINDOW_SAMPLES)
        window[:, 1] = rng.normal(0, 1.0, WINDOW_SAMPLES)
        window[:, 2] = 9.81 + rng.normal(0, 1.0, WINDOW_SAMPLES)
        # High impact spike on phone
        window[drop_idx:drop_idx+3, :] += rng.uniform(30.0, 50.0, (3, 7))
        # But helmet gyro on head has 0 rotation
        window[:, 3:6] = rng.normal(0, 2.0, (WINDOW_SAMPLES, 3))

    elif label == 3:
        # ---- Class 3: Severe Motorcycle Crash ----
        # 1. Initial speed (45 - 100 km/h)
        init_speed = rng.uniform(45.0, 100.0)
        impact_idx = rng.integers(10, 15)
        # Speed drops rapidly to 0 km/h within 1.5s after impact
        for i in range(WINDOW_SAMPLES):
            if i < impact_idx:
                window[i, 6] = init_speed + rng.normal(0, 0.3)
            else:
                progress = min(1.0, (i - impact_idx) / 20.0)
                window[i, 6] = max(0.0, init_speed * (1.0 - progress))

        # 2. Baseline prior to impact
        window[:impact_idx, 0] = rng.normal(0, 0.5, impact_idx)
        window[:impact_idx, 1] = rng.normal(0, 0.5, impact_idx)
        window[:impact_idx, 2] = 9.81 + rng.normal(0, 0.5, impact_idx)
        window[:impact_idx, 3:6] = rng.normal(0, 8.0, (impact_idx, 3))

        # 3. Violent impact & rotational tumble (samples impact_idx to impact_idx+10)
        tumble_len = 10
        window[impact_idx:impact_idx+tumble_len, 0] = rng.normal(25.0, 15.0, tumble_len)
        window[impact_idx:impact_idx+tumble_len, 1] = rng.normal(25.0, 15.0, tumble_len)
        window[impact_idx:impact_idx+tumble_len, 2] = rng.normal(35.0, 12.0, tumble_len)
        # Gyro spins violently (> 250 - 600 deg/s)
        window[impact_idx:impact_idx+tumble_len, 3] = rng.uniform(250.0, 600.0, tumble_len) * rng.choice([-1, 1])
        window[impact_idx:impact_idx+tumble_len, 4] = rng.uniform(200.0, 500.0, tumble_len) * rng.choice([-1, 1])
        window[impact_idx:impact_idx+tumble_len, 5] = rng.uniform(180.0, 450.0, tumble_len) * rng.choice([-1, 1])

        # 4. Post-crash stillness / resting orientation (gravity on side, gyro ~ 0)
        rest_idx = impact_idx + tumble_len
        window[rest_idx:, 0] = rng.normal(7.5, 0.2, WINDOW_SAMPLES - rest_idx) # Tilted resting angle
        window[rest_idx:, 1] = rng.normal(5.0, 0.2, WINDOW_SAMPLES - rest_idx)
        window[rest_idx:, 2] = rng.normal(2.0, 0.2, WINDOW_SAMPLES - rest_idx)
        window[rest_idx:, 3:6] = rng.normal(0, 1.5, (WINDOW_SAMPLES - rest_idx, 3)) # Completely still

    return window

def build_dataset(samples_per_class: int = 500, random_seed: int = 42):
    """Generates a balanced dataset across all 4 classes."""
    X_list = []
    y_list = []
    
    for cls in range(4):
        for i in range(samples_per_class):
            seed = random_seed + (cls * 10000) + i
            w = generate_window(cls, random_seed=seed)
            X_list.append(w)
            y_list.append(cls)

    return np.array(X_list, dtype=np.float32), np.array(y_list, dtype=np.int64)

if __name__ == "__main__":
    X, y = build_dataset(100)
    print(f"Generated dataset shape: X = {X.shape}, y = {y.shape}")
    print("Class distribution:", {CLASS_NAMES[c]: np.sum(y == c) for c in range(4)})
