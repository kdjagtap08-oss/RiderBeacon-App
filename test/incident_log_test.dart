import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_kavach/incident_log_service.dart';
import 'package:smart_kavach/incident_log_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('IncidentLogService Unit Tests', () {
    test('Logs an incident and retrieves it accurately', () async {
      final incident = IncidentRecord(
        id: '12345',
        timestamp: DateTime(2026, 10, 12, 14, 30, 0),
        type: IncidentType.crashAlert,
        latitude: 28.6139,
        longitude: 77.2090,
        speedKmh: 65.5,
        maxImpactG: 4.2,
        maxGyroDps: 320.0,
      );

      await IncidentLogService.logIncident(incident);

      final list = await IncidentLogService.getAllIncidents();
      expect(list.length, equals(1));
      expect(list.first.id, equals('12345'));
      expect(list.first.speedKmh, equals(65.5));
      expect(list.first.maxImpactG, equals(4.2));
      expect(list.first.type, equals(IncidentType.crashAlert));
    });

    test('Updates latest feedback and reassurance status on recent incident', () async {
      final incident = IncidentRecord(
        id: '100',
        timestamp: DateTime.now(),
        type: IncidentType.crashAlert,
        speedKmh: 45.0,
        maxImpactG: 3.5,
        maxGyroDps: 220.0,
      );

      await IncidentLogService.logIncident(incident);
      await IncidentLogService.updateLatestFeedback('Road bump / pothole', reassuranceSent: true);

      final list = await IncidentLogService.getAllIncidents();
      expect(list.first.riderFeedback, equals('Road bump / pothole'));
      expect(list.first.reassuranceSent, isTrue);
    });

    test('Clears all recorded incidents', () async {
      await IncidentLogService.logIncident(IncidentRecord(
        id: '1',
        timestamp: DateTime.now(),
        type: IncidentType.crashAlert,
        speedKmh: 30.0,
        maxImpactG: 3.1,
        maxGyroDps: 200.0,
      ));

      expect((await IncidentLogService.getAllIncidents()).length, equals(1));
      await IncidentLogService.clearAll();
      expect((await IncidentLogService.getAllIncidents()).isEmpty, isTrue);
    });
  });

  group('IncidentLogSheet Widget Tests', () {
    testWidgets('Renders empty state when no incidents recorded', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IncidentLogSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ride Incident Timeline'), findsOneWidget);
      expect(find.text('No Incident Records'), findsOneWidget);
      expect(find.textContaining('All telemetry logs'), findsOneWidget);
    });

    testWidgets('Renders incident card with telematic chips and feedback note', (tester) async {
      final incident = IncidentRecord(
        id: '999',
        timestamp: DateTime(2026, 10, 12, 18, 45, 10),
        type: IncidentType.cancelledByRider,
        speedKmh: 52.3,
        maxImpactG: 3.8,
        maxGyroDps: 260.0,
        riderFeedback: 'Road bump / pothole',
        reassuranceSent: true,
      );

      await IncidentLogService.logIncident(incident);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IncidentLogSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alert Cancelled (Rider Safe)'), findsOneWidget);
      expect(find.text('Speed: 52.3 km/h'), findsOneWidget);
      expect(find.text('Impact: 3.80g'), findsOneWidget);
      expect(find.text('Rotation: 260°/s'), findsOneWidget);
      expect(find.text('Rider Note: Road bump / pothole'), findsOneWidget);
      expect(find.text("'I'm Safe' SMS dispatched to contacts"), findsOneWidget);
    });
  });
}
