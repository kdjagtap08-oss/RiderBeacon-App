"""
SmartKavach ML Pipeline — Feature Extractor
Extracts statistical, kinematic, and time-domain features from 50x7 sensor windows.
Channels: [0:acc_x, 1:acc_y, 2:acc_z, 3:gyro_x, 4:gyro_y, 5:gyro_z, 6:speed_kmh]
"""

import numpy as np

FEATURE_NAMES = [
    # Accel resultant
    "acc_mag_max", "acc_mag_rms", "acc_mag_p2p", "acc_mag_std",
    # Gyro resultant
    "gyro_mag_max", "gyro_mag_rms", "gyro_mag_p2p", "gyro_mag_std",
    # Speed kinematics
    "speed_init", "speed_final", "speed_delta", "speed_post_var",
    # Per-axis accelerometer peaks
    "acc_x_p2p", "acc_y_p2p", "acc_z_p2p",
    # Per-axis gyroscope peaks
    "gyro_x_p2p", "gyro_y_p2p", "gyro_z_p2p",
    # Post-event stillness indicators (last 15 samples)
    "post_acc_std", "post_gyro_std", "post_speed_mean"
]

def extract_features(window: np.ndarray) -> np.ndarray:
    """
    Extracts a 21-dimensional feature vector from a single (50, 7) window.
    window shape: (50, 7)
    """
    acc = window[:, 0:3]     # (50, 3) in m/s^2
    gyro = window[:, 3:6]    # (50, 3) in deg/s
    speed = window[:, 6]     # (50,) in km/h

    # 1. Resultant magnitudes
    acc_mag = np.linalg.norm(acc, axis=1) # (50,)
    gyro_mag = np.linalg.norm(gyro, axis=1) # (50,)

    # 2. Accel resultant statistics
    acc_mag_max = float(np.max(acc_mag))
    acc_mag_rms = float(np.sqrt(np.mean(acc_mag ** 2)))
    acc_mag_p2p = float(np.ptp(acc_mag))
    acc_mag_std = float(np.std(acc_mag))

    # 3. Gyro resultant statistics
    gyro_mag_max = float(np.max(gyro_mag))
    gyro_mag_rms = float(np.sqrt(np.mean(gyro_mag ** 2)))
    gyro_mag_p2p = float(np.ptp(gyro_mag))
    gyro_mag_std = float(np.std(gyro_mag))

    # 4. Speed kinematics
    speed_init = float(np.mean(speed[:10]))
    speed_final = float(np.mean(speed[-10:]))
    speed_delta = float(speed_init - speed_final)
    speed_post_var = float(np.var(speed[-15:]))

    # 5. Per-axis peak-to-peak
    acc_x_p2p = float(np.ptp(acc[:, 0]))
    acc_y_p2p = float(np.ptp(acc[:, 1]))
    acc_z_p2p = float(np.ptp(acc[:, 2]))

    gyro_x_p2p = float(np.ptp(gyro[:, 0]))
    gyro_y_p2p = float(np.ptp(gyro[:, 1]))
    gyro_z_p2p = float(np.ptp(gyro[:, 2]))

    # 6. Post-event stillness indicators (last 15 samples / 0.75s)
    post_acc_std = float(np.std(acc[-15:, :]))
    post_gyro_std = float(np.std(gyro[-15:, :]))
    post_speed_mean = float(np.mean(speed[-15:]))

    return np.array([
        acc_mag_max, acc_mag_rms, acc_mag_p2p, acc_mag_std,
        gyro_mag_max, gyro_mag_rms, gyro_mag_p2p, gyro_mag_std,
        speed_init, speed_final, speed_delta, speed_post_var,
        acc_x_p2p, acc_y_p2p, acc_z_p2p,
        gyro_x_p2p, gyro_y_p2p, gyro_z_p2p,
        post_acc_std, post_gyro_std, post_speed_mean
    ], dtype=np.float32)

def extract_features_batch(windows: np.ndarray) -> np.ndarray:
    """
    Extracts feature vectors for a batch of windows.
    windows shape: (N, 50, 7) -> returns (N, 21)
    """
    return np.array([extract_features(w) for w in windows], dtype=np.float32)
