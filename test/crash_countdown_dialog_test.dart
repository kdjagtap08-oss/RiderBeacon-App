import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kavach/crash_countdown_dialog.dart';

void main() {
  group('CrashCountdownDialog Widget Tests', () {
    testWidgets('renders warning title and initial remaining seconds',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CrashCountdownDialog(
            totalSeconds: 15,
            onCancel: () {},
            onTimeout: () {},
          ),
        ),
      );

      expect(find.text('CRASH DETECTED!'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text("I'M OK — CANCEL SOS"), findsOneWidget);
    });

    testWidgets('ticks down every second', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CrashCountdownDialog(
            totalSeconds: 5,
            onCancel: () {},
            onTimeout: () {},
          ),
        ),
      );

      expect(find.text('5'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('4'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('calls onCancel when rider taps cancel button', (tester) async {
      var cancelled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: CrashCountdownDialog(
            totalSeconds: 10,
            onCancel: () => cancelled = true,
            onTimeout: () {},
          ),
        ),
      );

      await tester.tap(find.text("I'M OK — CANCEL SOS"));
      await tester.pump();

      expect(cancelled, isTrue);
    });

    testWidgets('calls onTimeout when countdown reaches 0', (tester) async {
      var timedOut = false;

      await tester.pumpWidget(
        MaterialApp(
          home: CrashCountdownDialog(
            totalSeconds: 3,
            onCancel: () {},
            onTimeout: () => timedOut = true,
          ),
        ),
      );

      // Advance 1s -> 2s left
      await tester.pump(const Duration(seconds: 1));
      // Advance 1s -> 1s left
      await tester.pump(const Duration(seconds: 1));
      // Advance 1s -> 0s left (timeout triggers)
      await tester.pump(const Duration(seconds: 1));

      expect(timedOut, isTrue);
    });
  });
}
