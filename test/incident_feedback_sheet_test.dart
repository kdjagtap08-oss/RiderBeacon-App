import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kavach/incident_feedback_sheet.dart';

void main() {
  group('IncidentFeedbackSheet Widget Tests', () {
    testWidgets('renders all feedback options and skip button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncidentFeedbackSheet(
              onFeedbackSelected: (_) {},
              onSendReassuranceText: () {},
            ),
          ),
        ),
      );

      expect(find.text("Glad you're safe!"), findsOneWidget);
      expect(find.text('Deep pothole or speed breaker'), findsOneWidget);
      expect(find.text('Phone dropped / Mount slipped'), findsOneWidget);
      expect(find.text('Minor fall / Dropped bike (Unhurt)'), findsOneWidget);
      expect(find.text('Other false alarm'), findsOneWidget);
      expect(find.text('Skip & Resume Ride'), findsOneWidget);
    });

    testWidgets('selecting Pothole triggers callback with pothole reason',
        (tester) async {
      IncidentReason? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncidentFeedbackSheet(
              onFeedbackSelected: (r) => selected = r,
              onSendReassuranceText: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Deep pothole or speed breaker'));
      await tester.pumpAndSettle();

      expect(selected, IncidentReason.pothole);
    });

    testWidgets('selecting Minor Fall opens reassurance prompt',
        (tester) async {
      IncidentReason? selected;
      var reassuranceSent = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncidentFeedbackSheet(
              onFeedbackSelected: (r) => selected = r,
              onSendReassuranceText: () => reassuranceSent = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Minor fall / Dropped bike (Unhurt)'));
      await tester.pumpAndSettle();

      expect(selected, IncidentReason.minorFallSafe);
      expect(find.text('Notify Contacts?'), findsOneWidget);

      await tester.tap(find.text("Send 'I'm Safe' SMS"));
      await tester.pumpAndSettle();

      expect(reassuranceSent, isTrue);
    });
  });
}
