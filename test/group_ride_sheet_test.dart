import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:smart_kavach/convoy_calculator.dart';
import 'package:smart_kavach/convoy_rider_marker.dart';
import 'package:smart_kavach/group_ride_model.dart';
import 'package:smart_kavach/group_ride_sheet.dart';

void main() {
  group('ConvoyRiderMarker Widget Tests', () {
    testWidgets('renders initials avatar and relative distance for ahead rider',
        (tester) async {
      var tapped = false;
      final metric = ConvoyMemberMetric(
        member: RideMember(
          userId: 'u2',
          displayName: 'Vikram',
          position: const LatLng(19.0765, 72.8777),
          lastPing: DateTime.now(),
        ),
        distanceMeters: 470,
        position: RelativePosition.ahead,
        formattedDistance: '+470 m',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConvoyRiderMarker(
              metric: metric,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('V'), findsOneWidget);
      expect(find.text('+470 m'), findsOneWidget);

      await tester.tap(find.byType(ConvoyRiderMarker));
      expect(tapped, isTrue);
    });

    testWidgets('omits distance badge for self (here)', (tester) async {
      final metric = ConvoyMemberMetric(
        member: RideMember(
          userId: 'u1',
          displayName: 'Parth',
          position: const LatLng(19.0760, 72.8777),
          lastPing: DateTime.now(),
        ),
        distanceMeters: 0,
        position: RelativePosition.here,
        formattedDistance: 'You',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConvoyRiderMarker(
              metric: metric,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('P'), findsOneWidget);
      // "You" is omitted in marker badge when position == here
      expect(find.text('You'), findsNothing);
    });

    testWidgets('displays crash alert banner when status is crashAlert',
        (tester) async {
      final metric = ConvoyMemberMetric(
        member: RideMember(
          userId: 'u3',
          displayName: 'Rohan',
          position: const LatLng(19.0750, 72.8777),
          lastPing: DateTime.now(),
          status: RiderStatus.crashAlert,
        ),
        distanceMeters: 350,
        position: RelativePosition.behind,
        formattedDistance: '-350 m',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConvoyRiderMarker(
              metric: metric,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('CRASH!'), findsOneWidget);
      expect(find.text('-350 m'), findsOneWidget);
    });
  });

  group('GroupRideSheet Widget Tests', () {
    late GroupRide sampleRide;
    late List<ConvoyMemberMetric> sampleMetrics;

    setUp(() {
      sampleRide = GroupRide(
        rideCode: '5821',
        title: 'Lonavala Sunday Convoy',
        leaderId: 'u1',
        leaderName: 'Parth',
        createdAt: DateTime.now(),
        members: {
          'u1': RideMember(
            userId: 'u1',
            displayName: 'Parth',
            position: const LatLng(19.0760, 72.8777),
            lastPing: DateTime.now(),
            isLeader: true,
          ),
          'u2': RideMember(
            userId: 'u2',
            displayName: 'Vikram',
            position: const LatLng(19.0790, 72.8777),
            lastPing: DateTime.now(),
            phoneNumber: '+919876543210',
          ),
        },
      );

      sampleMetrics = [
        ConvoyMemberMetric(
          member: sampleRide.members['u2']!,
          distanceMeters: 470,
          position: RelativePosition.ahead,
          formattedDistance: '+470 m',
        ),
        ConvoyMemberMetric(
          member: sampleRide.members['u1']!,
          distanceMeters: 0,
          position: RelativePosition.here,
          formattedDistance: 'You',
        ),
      ];
    });

    testWidgets('renders header, ride code, and member list', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupRideSheet(
              ride: sampleRide,
              metrics: sampleMetrics,
              currentUserId: 'u1',
              onStatusChanged: (_) {},
              onShareInvite: () {},
              onNavigateToMember: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Lonavala Sunday Convoy'), findsOneWidget);
      expect(find.text('Code: 5821 • 2 Riders in Convoy'), findsOneWidget);
      expect(find.text('Invite'), findsOneWidget);
      expect(find.text('Parth (You)'), findsOneWidget);
      expect(find.text('Vikram'), findsOneWidget);
      expect(find.text('+470 m'), findsOneWidget);
    });

    testWidgets('triggers onShareInvite callback when Invite button is pressed',
        (tester) async {
      var shared = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupRideSheet(
              ride: sampleRide,
              metrics: sampleMetrics,
              currentUserId: 'u1',
              onStatusChanged: (_) {},
              onShareInvite: () => shared = true,
              onNavigateToMember: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Invite'));
      expect(shared, isTrue);
    });

    testWidgets('triggers onStatusChanged when a status chip is tapped',
        (tester) async {
      RiderStatus? changedStatus;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupRideSheet(
              ride: sampleRide,
              metrics: sampleMetrics,
              currentUserId: 'u1',
              onStatusChanged: (status) => changedStatus = status,
              onShareInvite: () {},
              onNavigateToMember: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Refueling'));
      expect(changedStatus, equals(RiderStatus.refueling));

      await tester.tap(find.text('Tea Break'));
      expect(changedStatus, equals(RiderStatus.teaBreak));
    });

    testWidgets('triggers onNavigateToMember when directions icon is tapped',
        (tester) async {
      RideMember? navigatedMember;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupRideSheet(
              ride: sampleRide,
              metrics: sampleMetrics,
              currentUserId: 'u1',
              onStatusChanged: (_) {},
              onShareInvite: () {},
              onNavigateToMember: (m) => navigatedMember = m,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.navigation));
      expect(navigatedMember?.userId, equals('u2'));
      expect(navigatedMember?.displayName, equals('Vikram'));
    });
  });
}
