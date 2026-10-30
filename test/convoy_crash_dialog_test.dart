import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_kavach/auth_service.dart';
import 'package:smart_kavach/convoy_calculator.dart';
import 'package:smart_kavach/convoy_crash_dialog.dart';
import 'package:smart_kavach/convoy_join_dialog.dart';
import 'package:smart_kavach/group_ride_model.dart';
import 'package:smart_kavach/group_ride_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConvoyCrashDialog Widget Tests', () {
    testWidgets('renders crash alert details and triggers callbacks',
        (tester) async {
      var dismissed = false;

      final metric = ConvoyMemberMetric(
        member: RideMember(
          userId: 'u_crash',
          displayName: 'Vikram',
          position: const LatLng(19.0800, 72.8800),
          lastPing: DateTime.now(),
          phoneNumber: '+919876543210',
          status: RiderStatus.crashAlert,
        ),
        distanceMeters: 450,
        position: RelativePosition.ahead,
        formattedDistance: '+450 m',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConvoyCrashDialog(
              metric: metric,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      expect(find.text('CONVOY CRASH ALERT!'), findsOneWidget);
      expect(find.text('Vikram triggered an emergency crash alert!'), findsOneWidget);
      expect(find.text('+450 m'), findsOneWidget);
      expect(find.text('Ahead of you'), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Dismiss Alert'), findsOneWidget);

      await tester.tap(find.text('Dismiss Alert'));
      expect(dismissed, isTrue);
    });
  });

  group('ConvoyJoinDialog Widget Tests', () {
    late AuthService authService;
    late GroupRideService groupRideService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      authService = AuthService();
      groupRideService = GroupRideService();
    });

    tearDown(() {
      authService.dispose();
      groupRideService.dispose();
    });

    testWidgets('renders tabs and creates a new convoy ride', (tester) async {
      await authService.init();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConvoyJoinDialog(
              authService: authService,
              groupRideService: groupRideService,
              currentLocation: const LatLng(19.0760, 72.8777),
            ),
          ),
        ),
      );

      expect(find.text('Ride Together'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Join Convoy'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Create New'), findsOneWidget);

      // Switch to Create New tab
      await tester.tap(find.text('Create New'));
      await tester.pumpAndSettle();

      expect(find.text('Start Convoy'), findsOneWidget);

      await tester.tap(find.text('Start Convoy'));
      await tester.pumpAndSettle();

      // Ride should now be created in groupRideService with leader + 3 simulated bots
      expect(groupRideService.currentRide, isNotNull);
      expect(groupRideService.currentRide?.title, equals('Sunday Morning Convoy'));
      expect(groupRideService.currentRide?.members.length, equals(4));
    });
  });
}
