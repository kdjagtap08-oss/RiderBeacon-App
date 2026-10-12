import 'dart:async';
import 'package:flutter/material.dart';
import 'crash_detector.dart';

const kAccentOrange = Color(0xFFFF6B2C);
const kCardBg = Color(0xFF181D25);
const kGoodGreen = Color(0xFF3DDC97);
const kSosRed = Color(0xFFE5323B);

/// Interactive in-app simulator panel for testing crash scenarios,
/// adjusting sensor thresholds, and validating false-positive filters.
class SimulationPanel extends StatefulWidget {
  const SimulationPanel({super.key, required this.detector});

  final CrashDetector detector;

  @override
  State<SimulationPanel> createState() => _SimulationPanelState();
}

class _SimulationPanelState extends State<SimulationPanel> {
  bool _isExpanded = false;
  bool _isSimulating = false;

  double _sliderSpeed = 60.0;
  double _sliderAccelG = 1.0;
  double _sliderGyro = 0.0;

  /// Simulates a severe motorcycle highway crash scenario.
  Future<void> _simulateHighwayCrash() async {
    if (_isSimulating) return;
    setState(() => _isSimulating = true);

    final d = widget.detector;
    d.reset();

    // 1. Cruising speed at 70 km/h
    d.feedGpsSpeed(70.0);
    d.feedHelmetGyro(10.0, 5.0, 10.0);
    d.feedAccelerometer(0.0, 0.0, 9.81);
    await Future.delayed(const Duration(milliseconds: 300));

    // 2. Severe impact and violent helmet rotation
    d.feedHelmetGyro(180.0, 160.0, 120.0); // ~269 deg/s
    d.feedAccelerometer(20.0, 20.0, 32.0); // ~4.3g
    await Future.delayed(const Duration(milliseconds: 300));

    // 3. Speed drops to 0 km/h
    d.feedGpsSpeed(0.0);

    // 4. Wait for speed drop check window (2.1s)
    await Future.delayed(const Duration(milliseconds: 2100));

    // 5. Rider remains motionless during stillness window (3.1s)
    d.feedHelmetGyro(1.0, 1.0, 1.0);
    d.feedAccelerometer(0.0, 0.0, 9.81); // 1.0g

    if (mounted) {
      setState(() => _isSimulating = false);
    }
  }

  /// Simulates hitting a deep pothole or sharp speed bump at speed.
  Future<void> _simulatePothole() async {
    if (_isSimulating) return;
    setState(() => _isSimulating = true);

    final d = widget.detector;

    // Riding at 50 km/h
    d.feedGpsSpeed(50.0);
    d.feedHelmetGyro(2.0, 1.0, 2.0); // Minimal helmet rotation (3 deg/s)

    // Vertical g-force spike: 35 m/s^2 (~3.57g)
    d.feedAccelerometer(1.0, 1.0, 35.0);
    await Future.delayed(const Duration(milliseconds: 400));

    // Returns to normal riding
    d.feedAccelerometer(0.0, 0.0, 9.81);
    d.feedGpsSpeed(50.0);

    if (mounted) {
      setState(() => _isSimulating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pothole simulated: Ignored by gyro filter (0°/s)'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Simulates dropping the phone while stationary or dismounting.
  Future<void> _simulateDroppedPhone() async {
    if (_isSimulating) return;
    setState(() => _isSimulating = true);

    final d = widget.detector;

    // Stationary (speed = 0)
    d.feedGpsSpeed(0.0);
    d.feedHelmetGyro(0.0, 0.0, 0.0); // Helmet not rotating

    // High impact shock on phone: 36 m/s^2 (~3.67g)
    d.feedAccelerometer(25.0, 20.0, 15.0);
    await Future.delayed(const Duration(milliseconds: 400));

    d.feedAccelerometer(0.0, 0.0, 9.81);

    if (mounted) {
      setState(() => _isSimulating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dropped phone simulated: Ignored (0 initial speed)'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Color _stateColor(CrashState s) {
    switch (s) {
      case CrashState.idle:
        return Colors.white54;
      case CrashState.impactSeen:
        return kAccentOrange;
      case CrashState.confirming:
        return Colors.amber;
      case CrashState.alertTriggered:
        return kSosRed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detector;

    return ListenableBuilder(
      listenable: d,
      builder: (context, _) => Container(
        decoration: BoxDecoration(
          color: kCardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: d.state == CrashState.idle
                ? Colors.white10
                : _stateColor(d.state).withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            // Header Row (Clickable to expand/collapse)
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 14.0),
                child: Row(
                  children: [
                    const Icon(Icons.science_outlined,
                        color: kAccentOrange, size: 22),
                    const SizedBox(width: 10),
                    const Text(
                      'Crash Simulator & Diagnostics',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    // Engine State Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _stateColor(d.state).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        d.state.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _stateColor(d.state),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.white54,
                    ),
                  ],
                ),
              ),
            ),

            // Live Telemetry Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _telemetryItem('ACCEL', '${d.lastAccelG.toStringAsFixed(2)}g'),
                  _telemetryItem(
                      'GYRO', '${d.lastGyroMag.toStringAsFixed(0)}°/s'),
                  _telemetryItem(
                      'SPEED', '${d.currentSpeedKmh.toStringAsFixed(0)} km/h'),
                  _telemetryItem(
                    'COOLDOWN',
                    d.isCoolingDown ? 'ACTIVE' : 'OFF',
                    color: d.isCoolingDown ? Colors.amber : kGoodGreen,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Expanded Controls
            if (_isExpanded) ...[
              const Divider(color: Colors.white10, height: 1),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PRESET SCENARIOS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white54,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                _isSimulating ? null : _simulateHighwayCrash,
                            style: FilledButton.styleFrom(
                              backgroundColor: kSosRed,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: const Icon(Icons.car_crash, size: 18),
                            label: const Text('Crash Preset',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isSimulating ? null : _simulatePothole,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: const Icon(Icons.waves, size: 18),
                            label: const Text('Pothole',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                _isSimulating ? null : _simulateDroppedPhone,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: const Icon(Icons.phone_android, size: 18),
                            label: const Text('Dropped Phone',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () {
                              d.reset();
                              setState(() {
                                _sliderSpeed = 60;
                                _sliderAccelG = 1.0;
                                _sliderGyro = 0;
                              });
                            },
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Reset',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'MANUAL SENSOR INJECTION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white54,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),

                    _sliderControl(
                      label: 'Speed: ${_sliderSpeed.toStringAsFixed(0)} km/h',
                      value: _sliderSpeed,
                      min: 0,
                      max: 140,
                      onChanged: (v) {
                        setState(() => _sliderSpeed = v);
                        d.feedGpsSpeed(v);
                      },
                    ),
                    _sliderControl(
                      label: 'Impact G: ${_sliderAccelG.toStringAsFixed(2)}g',
                      value: _sliderAccelG,
                      min: 0.5,
                      max: 8.0,
                      onChanged: (v) {
                        setState(() => _sliderAccelG = v);
                        // Feed m/s^2 equivalent (g * 9.80665)
                        d.feedAccelerometer(0, 0, v * 9.80665);
                      },
                    ),
                    _sliderControl(
                      label: 'Gyro: ${_sliderGyro.toStringAsFixed(0)}°/s',
                      value: _sliderGyro,
                      min: 0,
                      max: 500,
                      onChanged: (v) {
                        setState(() => _sliderGyro = v);
                        d.feedHelmetGyro(0, 0, v);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _telemetryItem(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white38,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: color ?? Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _sliderControl({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: kAccentOrange,
            inactiveColor: Colors.white12,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
