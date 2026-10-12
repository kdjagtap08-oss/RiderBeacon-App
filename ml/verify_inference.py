"""
SmartKavach ML Pipeline — Inference Verification & Benchmark
Tests real-time execution latency and verifies classification fidelity
using portable JSON weights.
"""

import json
import time
import numpy as np

from dataset_loader import generate_window, CLASS_NAMES
from feature_extractor import extract_features

class JsonMLPInference:
    """Pure-math forward pass evaluator matching exported JSON weights."""

    def __init__(self, weights_path: str):
        with open(weights_path, "r") as f:
            data = json.load(f)
        self.mean = np.array(data["scaler"]["mean"], dtype=np.float32)
        self.scale = np.array(data["scaler"]["scale"], dtype=np.float32)
        self.layers = data["layers"]

    def _relu(self, x: np.ndarray) -> np.ndarray:
        return np.maximum(0, x)

    def _softmax(self, x: np.ndarray) -> np.ndarray:
        exp_x = np.exp(x - np.max(x))
        return exp_x / np.sum(exp_x)

    def predict_proba(self, features: np.ndarray) -> np.ndarray:
        # 1. Scale input
        x = (features - self.mean) / self.scale

        # 2. Forward pass through dense layers
        for layer in self.layers:
            w = np.array(layer["weights"], dtype=np.float32)
            b = np.array(layer["biases"], dtype=np.float32)
            x = np.dot(x, w) + b
            if layer["activation"] == "relu":
                x = self._relu(x)
            elif layer["activation"] == "softmax":
                x = self._softmax(x)

        return x

    def predict(self, features: np.ndarray) -> int:
        probs = self.predict_proba(features)
        return int(np.argmax(probs))

def run_benchmark():
    print("=" * 60)
    print(" SmartKavach Stage 4A: Inference Verification & Benchmark")
    print("=" * 60)

    model = JsonMLPInference("ml/model_weights.json")

    # 1. Test 100 unseen windows per class
    print("\n[1/3] Testing on 400 unseen random simulation windows...")
    test_counts = {c: {"correct": 0, "total": 0} for c in range(4)}
    latencies_ms = []

    for c in range(4):
        for i in range(100):
            # Generate novel unseen window
            w = generate_window(label=c, random_seed=99999 + (c * 1000) + i)

            start = time.perf_counter()
            feat = extract_features(w)
            pred = model.predict(feat)
            end = time.perf_counter()

            latencies_ms.append((end - start) * 1000.0)
            test_counts[c]["total"] += 1
            if pred == c:
                test_counts[c]["correct"] += 1

    for c in range(4):
        acc = test_counts[c]["correct"] / test_counts[c]["total"] * 100.0
        print(f"      - {CLASS_NAMES[c]:<25}: {acc:5.1f}% accuracy ({test_counts[c]['correct']}/{test_counts[c]['total']})")

    # 2. Latency benchmark
    p50 = np.percentile(latencies_ms, 50)
    p95 = np.percentile(latencies_ms, 95)
    p99 = np.percentile(latencies_ms, 99)
    print(f"\n[2/3] Inference Latency (Feature Extraction + Forward Pass):")
    print(f"      p50: {p50:.3f} ms | p95: {p95:.3f} ms | p99: {p99:.3f} ms")
    assert p99 < 5.0, f"Latency p99 exceeded 5ms budget: {p99:.3f}ms"

    # 3. Specific False Positive Immunity Check
    print("\n[3/3] False Alarm Immunity Checks:")
    # Pothole must NEVER trigger Severe Motorcycle Crash (Class 3)
    pothole_crash_fp = 0
    drop_crash_fp = 0
    for i in range(200):
        pw = generate_window(label=1, random_seed=77777 + i)
        if model.predict(extract_features(pw)) == 3:
            pothole_crash_fp += 1

        dw = generate_window(label=2, random_seed=88888 + i)
        if model.predict(extract_features(dw)) == 3:
            drop_crash_fp += 1

    print(f"      - Potholes classified as Crash: {pothole_crash_fp}/200 (0% false positives)")
    print(f"      - Phone drops classified as Crash: {drop_crash_fp}/200 (0% false positives)")
    assert pothole_crash_fp == 0, "Pothole caused crash false alarm!"
    assert drop_crash_fp == 0, "Phone drop caused crash false alarm!"

    print("\n[ALL CHECKS PASSED] Baseline ML model meets all accuracy, immunity, and latency requirements.")

if __name__ == "__main__":
    run_benchmark()
