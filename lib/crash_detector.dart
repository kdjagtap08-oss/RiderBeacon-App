import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// States the detector moves through for one possible crash event.
enum CrashState { idle, impactSeen, confirming, confirmed }

/// Fuses phone accelerometer + helmet gyroscope + GPS speed to flag a
/// possible crash. Feed it live speed and gyro values each time they
/// update; it listens to the accelerometer on its own.
///
/// This is a first, tunable version — thresholds below are starting
/// points, not final numbers. They need real-ride testing to calibrate.
class CrashDetector extends ChangeNotifier {
  // ---- Tunable thresholds ----
  static const double kImpactG = 3.0; // g-force spike that counts as "impact"
  static const double kGyroSpikeDegPerSec = 250; // sharp rotation during impact
  static const double kSpeedDropKmh = 15; // speed must fall by at least this much
  static const double kStillAccelG = 1.3; // "at rest" accel band (gravity ≈1g)
  static const double kStillGyroDegPerSec = 20; // "not rotating" band

  static const _speedDropWindow = Duration(seconds: 2); // look for the drop within this long after impact
  static const _stillCheckDuration = Duration(seconds: 3); // must stay still this long to confirm
  static const _cooldown = Duration(seconds: 30); // ignore new impacts right after one, win or lose

  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _windowTimer;

  CrashState state = CrashState.idle;
  double lastAccelG = 0;
  double lastGyroMag = 0;
  DateTime? _impactAt;
  double _speedAtImpact = 0;

  double _speedKmh = 0; // fed in from Tracker
  double _gyroMag = 0; // fed in from GyroFeed
  bool _coolingDown = false;

  /// Called by the UI whenever Tracker's speed updates.
  void updateSpeed(double kmh) => _speedKmh = kmh;

  /// Called by the UI whenever GyroFeed gets new x,y,z (deg/s).
  void updateGyro(List<double>? xyz) {
    _gyroMag = xyz == null
        ? 0
        : sqrt(xyz[0] * xyz[0] + xyz[1] * xyz[1] + xyz[2] * xyz[2]);
    lastGyroMag = _gyroMag;
  }

  void start() {
    _accelSub ??= accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval, // ~20ms, good enough for impact spikes
    ).listen(_onAccel);
  }

  void _onAccel(AccelerometerEvent e) {
    // magnitude in g (accelerometer gives m/s^2, gravity = 9.81)
    final g = sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / 9.81;
    lastAccelG = g;

    if (_coolingDown) return;

    switch (state) {
      case CrashState.idle:
        if (g >= kImpactG && _gyroMag >= kGyroSpikeDegPerSec) {
          // Both accel and gyro spiked together — much less likely to be
          // a dropped phone (which rarely also spins violently) or a
          // pure pothole hit (which rarely also tumbles hard).
          _impactAt = DateTime.now();
          _speedAtImpact = _speedKmh;
          state = CrashState.impactSeen;
          notifyListeners();
          _windowTimer?.cancel();
          _windowTimer = Timer(_speedDropWindow, _checkSpeedDrop);
        }
        break;

      case CrashState.confirming:
        // Must stay near-still (little accel change, little rotation)
        // for the whole confirm window, or we abandon the crash guess.
        final stillNow =
            (g - 1.0).abs() <= (kStillAccelG - 1.0) && _gyroMag <= kStillGyroDegPerSec;
        if (!stillNow) {
          _reset();
        }
        break;

      case CrashState.impactSeen:
      case CrashState.confirmed:
        break;
    }
  }

  void _checkSpeedDrop() {
    if (state != CrashState.impactSeen) return;
    final dropped = (_speedAtImpact - _speedKmh) >= kSpeedDropKmh;
    if (!dropped) {
      _reset();
      return;
    }
    // Speed dropped as expected after the impact — now require a period
    // of stillness before treating this as a real crash.
    state = CrashState.confirming;
    notifyListeners();
    _windowTimer = Timer(_stillCheckDuration, () {
      if (state == CrashState.confirming) {
        state = CrashState.confirmed;
        notifyListeners();
        _startCooldown();
      }
    });
  }

  void _reset() {
    state = CrashState.idle;
    _impactAt = null;
    notifyListeners();
  }

  void _startCooldown() {
    _coolingDown = true;
    Timer(_cooldown, () {
      _coolingDown = false;
      state = CrashState.idle;
      notifyListeners();
    });
  }

  /// Call this after the rider cancels via the "I'm OK" countdown, or
  /// after SOS has been sent, to go back to watching for the next event.
  void acknowledge() {
    _windowTimer?.cancel();
    _reset();
    _startCooldown();
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _windowTimer?.cancel();
    super.dispose();
  }
}
class TestingPanel extends StatelessWidget {
  const TestingPanel({super.key, required this.d});
  final CrashDetector d;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: d,
        builder: (context, _) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: const Color(0xFF181D25),
              borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.bug_report, size: 16, color: Colors.white54),
              const SizedBox(width: 6),
              const Text('Crash detector (debug)',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
              const Spacer(),
              Text(d.state.name.toUpperCase(),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            Text(
              'accel: ${d.lastAccelG.toStringAsFixed(2)}g   gyro: ${d.lastGyroMag.toStringAsFixed(0)}°/s',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ]),
        ),
      );
}