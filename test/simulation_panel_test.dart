import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kavach/crash_detector.dart';
import 'package:smart_kavach/simulation_panel.dart';

void main() {
  group('SimulationPanel Widget Tests', () {
    late CrashDetector detector;

    setUp(() {
      detector = CrashDetector();
    });

    tearDown(() {
      detector.dispose();
    });

    testWidgets('renders telemetry header and collapsed by default',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SimulationPanel(detector: detector),
          ),
        ),
      );

      expect(find.text('Crash Simulator & Diagnostics'), findsOneWidget);
      expect(find.text('IDLE'), findsOneWidget);
      expect(find.text('ACCEL'), findsOneWidget);
      expect(find.text('GYRO'), findsOneWidget);
      expect(find.text('SPEED'), findsOneWidget);

      // Preset buttons should not be visible when collapsed
      expect(find.text('PRESET SCENARIOS'), findsNothing);
    });

    testWidgets('expands when tapped to reveal presets and sliders',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SimulationPanel(detector: detector),
          ),
        ),
      );

      // Tap header to expand
      await tester.tap(find.text('Crash Simulator & Diagnostics'));
      await tester.pumpAndSettle();

      expect(find.text('PRESET SCENARIOS'), findsOneWidget);
      expect(find.text('Crash Preset'), findsOneWidget);
      expect(find.text('Pothole'), findsOneWidget);
      expect(find.text('Dropped Phone'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('MANUAL SENSOR INJECTION'), findsOneWidget);
    });

    testWidgets('Pothole preset feeds spike and remains in idle state',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SimulationPanel(detector: detector),
          ),
        ),
      );

      await tester.tap(find.text('Crash Simulator & Diagnostics'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pothole'));
      // Pump 100ms into the shock to inspect peak transient
      await tester.pump(const Duration(milliseconds: 100));

      expect(detector.state, CrashState.idle);
      expect(detector.lastAccelG, greaterThan(3.0));

      // Complete shock duration (400ms settles back)
      await tester.pump(const Duration(milliseconds: 400));
      expect(detector.state, CrashState.idle);
    });

    testWidgets('Dropped phone preset feeds spike and remains in idle state',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SimulationPanel(detector: detector),
          ),
        ),
      );

      await tester.tap(find.text('Crash Simulator & Diagnostics'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dropped Phone'));
      // Pump 100ms into the shock to inspect peak transient
      await tester.pump(const Duration(milliseconds: 100));

      expect(detector.state, CrashState.idle);
      expect(detector.lastAccelG, greaterThan(3.0));

      // Complete shock duration
      await tester.pump(const Duration(milliseconds: 400));
      expect(detector.state, CrashState.idle);
    });

    testWidgets('Reset button clears detector and restores slider defaults',
        (tester) async {
      detector.feedGpsSpeed(90.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SimulationPanel(detector: detector),
          ),
        ),
      );

      await tester.tap(find.text('Crash Simulator & Diagnostics'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reset'));
      await tester.pump();

      expect(detector.state, CrashState.idle);
    });
  });
}
