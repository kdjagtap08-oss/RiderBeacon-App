import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Lifecycle states of the crash detection engine.
enum CrashState {
  /// Monitoring live telemetry normally.
  idle,

  /// Detected a concurrent g-force impact spike and helmet angular tumble.
  impactSeen,

  /// Verifying post-impact speed deceleration and stillness window.
  confirming,

  /// Crash pattern confirmed; triggers the safety countdown modal.
  alertTriggered,
}

/// Core Sensor Fusion & Crash Detection Engine.
///
/// Fuses:
/// 1. Phone 3-axis Accelerometer (via sensors_plus or mock input) -> G-force
/// 2. Helmet 3-axis Gyroscope (via BLE stream or mock input) -> deg/sec
/// 3. Phone GPS Speed (via Tracker or mock input) -> km/h
class CrashDetector extends ChangeNotifier {
  // ---- Tunable Threshold Constants ----
  static const double kImpactG = 3.0; // Minimum impact threshold (in g's)
  static const double kGyroSpikeDegPerSec = 200.0; // Minimum helmet rotation tumble (°/s)
  static const double kSpeedDropKmh = 15.0; // Minimum required speed drop after impact
  static const double kStillAccelToleranceG = 0.35; // Allowable deviation from 1.0g during stillness
  static const double kStillGyroMaxDegPerSec = 25.0; // Maximum rotation threshold during stillness

  static const Duration kSpeedDropWindow = Duration(milliseconds: 2000);
  static const Duration kStillnessDuration = Duration(milliseconds: 3000);
  static const Duration kCooldownDuration = Duration(seconds: 30);

  // ---- State & Telemetry ----
  CrashState _state = CrashState.idle;
  CrashState get state => _state;

  double _lastAccelG = 1.0;
  double get lastAccelG => _lastAccelG;

  double _lastGyroMag = 0.0;
  double get lastGyroMag => _lastGyroMag;

  double _currentSpeedKmh = 0.0;
  double get currentSpeedKmh => _currentSpeedKmh;

  double _speedAtImpact = 0.0;
  double get speedAtImpact => _speedAtImpact;

  DateTime? _impactTimestamp;
  DateTime? get impactTimestamp => _impactTimestamp;

  bool _isCoolingDown = false;
  bool get isCoolingDown => _isCoolingDown;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _speedCheckTimer;
  Timer? _stillnessTimer;
  Timer? _cooldownTimer;

  bool _isLiveHardwareEnabled = false;
  bool get isLiveHardwareEnabled => _isLiveHardwareEnabled;

  /// When true, physical phone sensor noise and stationary GPS do not override simulation.
  bool isSimulationActive = false;

  /// Immediately triggers the alert state for direct UI/countdown testing.
  void triggerSimulatedAlert() {
    _cancelAllTimers();
    _isCoolingDown = false;
    _state = CrashState.alertTriggered;
    _notifyThrottled(immediate: true);
  }

  /// Starts listening to phone hardware sensors (if enabled).
  void startHardwareFeed() {
    if (_isLiveHardwareEnabled) return;
    _isLiveHardwareEnabled = true;

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      if (isSimulationActive) return;
      feedAccelerometer(event.x, event.y, event.z);
    });
  }

  /// Stops listening to physical phone hardware sensors.
  void stopHardwareFeed() {
    _accelSub?.cancel();
    _accelSub = null;
    _isLiveHardwareEnabled = false;
  }

  DateTime _lastUiNotify = DateTime.fromMillisecondsSinceEpoch(0);

  void _notifyThrottled({bool immediate = false}) {
    final now = DateTime.now();
    if (immediate || now.difference(_lastUiNotify).inMilliseconds >= 120) {
      _lastUiNotify = now;
      notifyListeners();
    }
  }

  /// Feed linear accelerometer data in m/s^2 (from phone or simulator).
  void feedAccelerometer(double ax, double ay, double az) {
    // Convert m/s^2 to g-force magnitude (Earth gravity = 9.80665 m/s^2)
    final g = sqrt(ax * ax + ay * ay + az * az) / 9.80665;
    _lastAccelG = g;

    if (_isCoolingDown) {
      _notifyThrottled();
      return;
    }

    final prevState = _state;
    _evaluateMotion(g);
    // If state transitioned (e.g. idle -> impactSeen -> confirming), notify immediately
    _notifyThrottled(immediate: _state != prevState);
  }

  /// Feed helmet gyroscope data in deg/sec (from BLE or simulator).
  void feedHelmetGyro(double gx, double gy, double gz) {
    _lastGyroMag = sqrt(gx * gx + gy * gy + gz * gz);
    _notifyThrottled();
  }

  /// Feed live GPS speed in km/h (from phone GPS Tracker or simulator).
  void feedGpsSpeed(double kmh, {bool isSimulated = false}) {
    if (isSimulationActive && !isSimulated) return;
    _currentSpeedKmh = kmh < 0 ? 0 : kmh;
    _notifyThrottled();
  }

  void _evaluateMotion(double currentG) {
    switch (_state) {
      case CrashState.idle:
        // Gate 1: Check for simultaneous g-force spike AND violent helmet rotation
        if (currentG >= kImpactG && _lastGyroMag >= kGyroSpikeDegPerSec) {
          _impactTimestamp = DateTime.now();
          _speedAtImpact = _currentSpeedKmh;
          _state = CrashState.impactSeen;

          // Schedule speed drop verification window
          _speedCheckTimer?.cancel();
          _speedCheckTimer = Timer(kSpeedDropWindow, _verifySpeedDrop);
        }
        break;

      case CrashState.impactSeen:
        // Waiting for speed drop check timer to fire
        break;

      case CrashState.confirming:
        // Gate 3: Check stillness during the confirmation window.
        // If high motion persists, the rider has either recovered or it was a false alarm.
        final isAccelNearRest = (currentG - 1.0).abs() <= kStillAccelToleranceG;
        final isGyroNearRest = _lastGyroMag <= kStillGyroMaxDegPerSec;

        if (!isAccelNearRest || !isGyroNearRest) {
          _resetToIdle();
        }
        break;

      case CrashState.alertTriggered:
        // Already triggered, waiting for user response or SOS dispatch
        break;
    }
  }

  void _verifySpeedDrop() {
    if (_state != CrashState.impactSeen) return;

    // Gate 2: Speed must drop by at least kSpeedDropKmh (or come to an absolute stop)
    final speedDelta = _speedAtImpact - _currentSpeedKmh;
    final droppedAdequately = speedDelta >= kSpeedDropKmh || _currentSpeedKmh <= 5.0;

    if (!droppedAdequately) {
      // Bike kept traveling at speed -> false alarm (pothole or bump)
      _resetToIdle();
      return;
    }

    // Impact + speed drop confirmed. Now enter stillness confirmation phase.
    _state = CrashState.confirming;
    notifyListeners();

    _stillnessTimer?.cancel();
    _stillnessTimer = Timer(kStillnessDuration, () {
      if (_state == CrashState.confirming) {
        _state = CrashState.alertTriggered;
        notifyListeners();
      }
    });
  }

  /// Rider confirmed they are OK or SOS disarmed. Enforces a 30s cooldown.
  void acknowledge() {
    _cancelAllTimers();
    _resetToIdle();
    _startCooldown();
  }

  /// Full manual reset.
  void reset() {
    _cancelAllTimers();
    _isCoolingDown = false;
    _resetToIdle();
  }

  void _resetToIdle() {
    _state = CrashState.idle;
    _impactTimestamp = null;
    _speedAtImpact = 0.0;
    notifyListeners();
  }

  void _startCooldown() {
    _isCoolingDown = true;
    notifyListeners();

    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(kCooldownDuration, () {
      _isCoolingDown = false;
      notifyListeners();
    });
  }

  void _cancelAllTimers() {
    _speedCheckTimer?.cancel();
    _speedCheckTimer = null;
    _stillnessTimer?.cancel();
    _stillnessTimer = null;
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
  }

  @override
  void dispose() {
    stopHardwareFeed();
    _cancelAllTimers();
    super.dispose();
  }
}
