import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// Must match the UUIDs in the ESP32 firmware.
const kSvcUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
const kGyroUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';

/// Live gyroscope values (degrees/second) sent by the helmet's ESP32.
class GyroFeed extends ChangeNotifier {
  List<double>? values; // [x, y, z], null when no data
  StreamSubscription? _sub;

  double get angularVelocity {
    final v = values;
    if (v == null || v.length < 3) return 0.0;
    return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  }

  /// Maximum absolute value across X, Y, or Z individual axes
  double get maxAxisVelocity {
    final v = values;
    if (v == null || v.length < 3) return 0.0;
    return math.max(v[0].abs(), math.max(v[1].abs(), v[2].abs()));
  }

  /// Highest rotation rate detected (either total 3D magnitude or peak single axis)
  double get effectiveRotationRate => math.max(angularVelocity, maxAxisVelocity);

  /// Call once after the helmet is connected.
  Future<void> attach(BluetoothDevice d) async {
    try {
      for (final s in await d.discoverServices()) {
        if (s.uuid != Guid(kSvcUuid)) continue;
        for (final c in s.characteristics) {
          if (c.uuid != Guid(kGyroUuid)) continue;
          await c.setNotifyValue(true);
          _sub?.cancel();
          _sub = c.onValueReceived.listen(_onData);
        }
      }
    } catch (_) {}
  }

  void _onData(List<int> bytes) {
    final p = String.fromCharCodes(bytes).split(',').map(double.tryParse).toList();
    if (p.length == 3 && !p.contains(null)) {
      values = [p[0]!, p[1]!, p[2]!];
      notifyListeners();
    }
  }

  void clear() {
    _sub?.cancel();
    _sub = null;
    values = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class GyroPanel extends StatelessWidget {
  const GyroPanel({super.key, required this.g});
  final GyroFeed g;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: g,
        builder: (context, _) {
          final v = g.values;
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: const Color(0xFF181D25),
                borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.threed_rotation, color: Color(0xFFFF6B2C)),
                const SizedBox(width: 8),
                const Text('Gyroscope',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(v == null ? 'NO DATA' : 'LIVE',
                    style: TextStyle(
                        fontSize: 12,
                        color: v == null
                            ? Colors.white38
                            : const Color(0xFF3DDC97))),
              ]),
              const SizedBox(height: 12),
              if (v == null)
                const Text('Connect your helmet to see readings',
                    style: TextStyle(color: Colors.white54))
              else
                Row(children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(child: _axis(['X', 'Y', 'Z'][i], v[i])),
                ]),
            ]),
          );
        },
      );

  Widget _axis(String name, double v) => Column(children: [
        Text(name, style: const TextStyle(color: Colors.white54)),
        Text(v.toStringAsFixed(1),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const Text('°/s', style: TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: LinearProgressIndicator(
            value: ((v / 500 + 1) / 2).clamp(0.0, 1.0), // -500..+500 -> 0..1
            backgroundColor: Colors.white10,
            color: const Color(0xFFFF6B2C),
          ),
        ),
      ]);
}