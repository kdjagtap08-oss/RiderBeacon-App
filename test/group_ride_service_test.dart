import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:smart_kavach/convoy_calculator.dart';
import 'package:smart_kavach/group_ride_model.dart';
import 'package:smart_kavach/group_ride_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GroupRideService Helpers & Static Methods', () {
    test('generateRideCode produces 4-character non-ambiguous uppercase code', () {
      for (var i = 0; i < 20; i++) {
        final code = GroupRideService.generateRideCode();
        expect(code.length, equals(4));
        expect(code, matches(r'^[2-9A-HJ-NP-Z]{4}$'));
        expect(code.contains('0'), isFalse);
        expect(code.contains('O'), isFalse);
        expect(code.contains('1'), isFalse);
        expect(code.contains('I'), isFalse);
      }
    });

    test('generateInviteText creates clean WhatsApp formatted message', () {
      final ride = GroupRide(
        rideCode: 'SK99',
        title: 'Mumbai to Goa Express',
        leaderId: 'u1',
        leaderName: 'Parth',
        createdAt: DateTime.now(),
      );

      final text = GroupRideService.generateInviteText(ride);
      expect(text, contains('Mumbai to Goa Express'));
      expect(text, contains('SK99'));
      expect(text, contains('https://smartkavach.app/ride/SK99'));
    });
  });

  group('GroupRideService Core & Convoy Lifecycle', () {
    late InMemoryGroupRideBackend backend;
    late GroupRideService leaderService;
    late GroupRideService memberService;

    setUp(() {
      backend = InMemoryGroupRideBackend();
      leaderService = GroupRideService(backend: backend);
      memberService = GroupRideService(backend: backend);
    });

    tearDown(() {
      leaderService.dispose();
      memberService.dispose();
      backend.dispose();
    });

    test('Leader creates ride, initializes state and streams', () async {
      final ride = await leaderService.createRide(
        title: 'Lonavala Ghats Convoy',
        leaderId: 'leader_1',
        leaderName: 'Parth',
        phoneNumber: '+919988776655',
        initialPosition: const LatLng(18.7548, 73.4062),
        heading: 90.0,
      );

      expect(ride.title, equals('Lonavala Ghats Convoy'));
      expect(ride.members.length, equals(1));
      expect(ride.members['leader_1']?.isLeader, isTrue);

      expect(leaderService.currentRide?.rideCode, equals(ride.rideCode));
      expect(leaderService.currentUserId, equals('leader_1'));
      expect(leaderService.currentMetrics.length, equals(1));
      expect(leaderService.currentMetrics.first.position, equals(RelativePosition.here));
    });

    test('Member joins ride and receives real-time convoy stream', () async {
      final ride = await leaderService.createRide(
        title: 'Weekend Cruise',
        leaderId: 'leader_1',
        leaderName: 'Parth',
        initialPosition: const LatLng(18.7500, 73.4000),
        heading: 0.0, // Heading North
      );

      // Vikram joins positioned 500m North (ahead)
      final joinedRide = await memberService.joinRide(
        rideCode: ride.rideCode,
        userId: 'member_2',
        displayName: 'Vikram',
        phoneNumber: '+919876543210',
        initialPosition: const LatLng(18.7545, 73.4000),
        heading: 0.0,
      );

      expect(joinedRide.members.length, equals(2));
      expect(joinedRide.members.containsKey('member_2'), isTrue);

      // Verify leader gets the update from backend stream
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(leaderService.currentRide?.members.length, equals(2));
      expect(leaderService.currentMetrics.length, equals(2));

      // Leader should see Vikram ahead
      final vikramMetric = leaderService.currentMetrics.firstWhere(
        (m) => m.member.userId == 'member_2',
      );
      expect(vikramMetric.position, equals(RelativePosition.ahead));
      expect(vikramMetric.formattedDistance.startsWith('+'), isTrue);
    });

    test('Fails joining non-existent ride code with descriptive exception', () async {
      expect(
        () => memberService.joinRide(
          rideCode: 'ZZZZ',
          userId: 'u9',
          displayName: 'Ghost',
          initialPosition: const LatLng(0, 0),
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Ride code "ZZZZ" was not found'),
        )),
      );
    });

    test('Rider status update broadcasts to all convoy peers', () async {
      final ride = await leaderService.createRide(
        title: 'Western Coast Ride',
        leaderId: 'u1',
        leaderName: 'Parth',
        initialPosition: const LatLng(19.0, 72.8),
      );

      await memberService.joinRide(
        rideCode: ride.rideCode,
        userId: 'u2',
        displayName: 'Vikram',
        initialPosition: const LatLng(19.01, 72.8),
      );

      // Vikram updates status to Refueling
      await memberService.updateMyStatus(RiderStatus.refueling);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final updatedRide = leaderService.currentRide;
      expect(updatedRide?.members['u2']?.status, equals(RiderStatus.refueling));
    });

    test('Crash status update immediately broadcasts with zero throttle', () async {
      final ride = await leaderService.createRide(
        title: 'Highway 48 Run',
        leaderId: 'u1',
        leaderName: 'Parth',
        initialPosition: const LatLng(19.0, 72.8),
      );

      await memberService.joinRide(
        rideCode: ride.rideCode,
        userId: 'u2',
        displayName: 'Vikram',
        initialPosition: const LatLng(19.01, 72.8),
      );

      // Vikram triggers crash alert
      await memberService.updateMyStatus(RiderStatus.crashAlert);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final vikramOnLeader = leaderService.currentRide?.members['u2'];
      expect(vikramOnLeader?.status, equals(RiderStatus.crashAlert));
    });

    test('Telemetry update throttles normal updates but allows forced updates', () async {
      await leaderService.createRide(
        title: 'Throttle Test',
        leaderId: 'u1',
        leaderName: 'Parth',
        initialPosition: const LatLng(19.0, 72.8),
      );

      // Rapid successive update without force should be throttled
      await leaderService.updateMyTelemetry(
        position: const LatLng(19.001, 72.801),
        speedKmh: 45.0,
      );
      final lastTime1 = leaderService.myMember?.lastPing;

      // Second immediate call within 3s without force is ignored
      await leaderService.updateMyTelemetry(
        position: const LatLng(19.002, 72.802),
        speedKmh: 50.0,
      );
      final lastTime2 = leaderService.myMember?.lastPing;
      expect(lastTime1, equals(lastTime2));

      // With force: true it immediately updates
      await leaderService.updateMyTelemetry(
        position: const LatLng(19.005, 72.805),
        speedKmh: 60.0,
        force: true,
      );
      expect(leaderService.myMember?.position.latitude, equals(19.005));
    });

    test('Leaving ride detaches listener and resets state cleanly', () async {
      final ride = await leaderService.createRide(
        title: 'Departure Test',
        leaderId: 'u1',
        leaderName: 'Parth',
        initialPosition: const LatLng(19.0, 72.8),
      );

      await memberService.joinRide(
        rideCode: ride.rideCode,
        userId: 'u2',
        displayName: 'Vikram',
        initialPosition: const LatLng(19.01, 72.8),
      );

      await memberService.leaveRide();

      expect(memberService.currentRide, isNull);
      expect(memberService.currentUserId, isNull);
      expect(memberService.currentMetrics.isEmpty, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(leaderService.currentRide?.members.containsKey('u2'), isFalse);
    });
  });
}
