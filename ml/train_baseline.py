"""
SmartKavach ML Pipeline — Baseline Model Trainer
Trains a lightweight Neural Classifier (MLP) on 4 classes:
  0: Normal Riding
  1: Pothole / Road Shock
  2: Dropped Phone
  3: Severe Motorcycle Crash

Exports model weights and scaler parameters to portable JSON (ml/model_weights.json)
for cross-platform execution in Python and Dart.
"""

import json
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.neural_network import MLPClassifier
from sklearn.metrics import classification_report, confusion_matrix
import joblib

from dataset_loader import build_dataset, CLASS_NAMES
from feature_extractor import extract_features_batch, FEATURE_NAMES

def train():
    print("=" * 60)
    print(" SmartKavach Stage 4A: Baseline Crash Classifier Training")
    print("=" * 60)

    # 1. Generate Dataset
    print("\n[1/5] Synthesizing multi-sensor time-series windows (1,500 per class)...")
    X_windows, y = build_dataset(samples_per_class=1500, random_seed=42)
    print(f"      Total dataset size: {X_windows.shape[0]} windows (shape: {X_windows.shape})")

    # 2. Feature Extraction
    print("\n[2/5] Extracting 21 kinematic & time-domain features...")
    X_features = extract_features_batch(X_windows)
    print(f"      Extracted features shape: {X_features.shape}")

    # 3. Train/Test Split & Standardization
    print("\n[3/5] Splitting (80% train / 20% test) and scaling features...")
    X_train, X_test, y_train, y_test = train_test_split(
        X_features, y, test_size=0.20, random_state=42, stratify=y
    )

    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    # 4. Train Lightweight MLP Classifier
    print("\n[4/5] Training lightweight MLP Classifier (21 -> 64 -> 32 -> 4)...")
    mlp = MLPClassifier(
        hidden_layer_sizes=(64, 32),
        activation='relu',
        solver='adam',
        max_iter=500,
        random_state=42
    )
    mlp.fit(X_train_scaled, y_train)

    # 5. Evaluation
    y_pred = mlp.predict(X_test_scaled)
    acc = np.mean(y_pred == y_test)
    print(f"\n      >>> Test Accuracy: {acc * 100:.2f}% <<<\n")
    
    print("Classification Report:")
    target_names = [CLASS_NAMES[i] for i in range(4)]
    print(classification_report(y_test, y_pred, target_names=target_names))

    print("Confusion Matrix:")
    print(confusion_matrix(y_test, y_pred))

    # Assert > 95% accuracy
    assert acc >= 0.95, f"Expected accuracy >= 95%, but got {acc * 100:.2f}%"

    # 6. Export Portable Model Weights & Scaler to JSON
    print("\n[5/5] Exporting portable weights to ml/model_weights.json...")
    weights_data = {
        "version": "1.0.0-stage4a",
        "feature_names": FEATURE_NAMES,
        "class_names": CLASS_NAMES,
        "scaler": {
            "mean": scaler.mean_.tolist(),
            "scale": scaler.scale_.tolist()
        },
        "layers": []
    }

    # Extract weights and biases from each MLP layer
    for idx, (w, b) in enumerate(zip(mlp.coefs_, mlp.intercepts_)):
        weights_data["layers"].append({
            "layer_index": idx,
            "weights": w.tolist(),  # shape: (in_dim, out_dim)
            "biases": b.tolist(),   # shape: (out_dim,)
            "activation": "relu" if idx < len(mlp.coefs_) - 1 else "softmax"
        })

    with open("ml/model_weights.json", "w") as f:
        json.dump(weights_data, f, indent=2)

    joblib.dump(mlp, "ml/mlp_model.joblib")
    joblib.dump(scaler, "ml/scaler.joblib")

    print("      Model weights saved to ml/model_weights.json")
    print("      Pickled model saved to ml/mlp_model.joblib")
    print("\n[COMPLETE] Baseline training finished successfully.")

if __name__ == "__main__":
    train()
