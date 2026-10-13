import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:smart_kavach/group_ride_model.dart';
import 'package:smart_kavach/convoy_calculator.dart';

void main() {
  group('ConvoyCalculator Unit Tests', () {
    test('Calculates cardinal forward bearing accurately', () {
      final pune = LatLng(18.5204, 73.8567);
      // Directly north
      final northPoint = LatLng(18.6204, 73.8567);
      final bearingNorth = ConvoyCalculator.calculateBearing(pune, northPoint);
      expect(bearingNorth, closeTo(0.0, 1.0));

      // Directly east
      final eastPoint = LatLng(18.5204, 73.9567);
      final bearingEast = ConvoyCalculator.calculateBearing(pune, eastPoint);
      expect(bearingEast, closeTo(90.0, 1.0));
    });

    test('Classifies ahead vs behind relative to travel heading', () {
      final user = LatLng(18.5204, 73.8567);
      const headingNorth = 0.0; // Traveling due North

      final targetAhead = LatLng(18.5304, 73.8567); // Further north
      final targetBehind = LatLng(18.5104, 73.8567); // South of user

      final aheadRel = ConvoyCalculator.determineRelativePosition(
        userPos: user,
        userHeadingDeg: headingNorth,
        targetPos: targetAhead,
      );
      expect(aheadRel, equals(RelativePosition.ahead));

      final behindRel = ConvoyCalculator.determineRelativePosition(
        userPos: user,
        userHeadingDeg: headingNorth,
        targetPos: targetBehind,
      );
      expect(behindRel, equals(RelativePosition.behind));
    });

    test('Formats distance into clean reel-style labels (+470 m, -1.1 km, You)', () {
      expect(
        ConvoyCalculator.formatDistance(470, RelativePosition.ahead),
        equals('+470 m'),
      );
      expect(
        ConvoyCalculator.formatDistance(350, RelativePosition.behind),
        equals('-350 m'),
      );
      expect(
        ConvoyCalculator.formatDistance(1100, RelativePosition.behind),
        equals('-1.1 km'),
      );
      expect(
        ConvoyCalculator.formatDistance(0, RelativePosition.here),
        equals('You'),
      );
    });

    test('Orders convoy roster accurately from front leader to trailing rider', () {
      final mePos = LatLng(18.5204, 73.8567);
      const myHeading = 0.0; // Heading north

      final members = [
        RideMember(
          userId: 'user_me',
          displayName: 'Parth (You)',
          position: mePos,
          lastPing: DateTime.now(),
        ),
        RideMember(
          userId: 'user_lead',
          displayName: 'Manav',
          position: LatLng(18.5244, 73.8567), // ~440m ahead
          lastPing: DateTime.now(),
        ),
        RideMember(
          userId: 'user_trail1',
          displayName: 'Aditya',
          position: LatLng(18.5174, 73.8567), // ~330m behind
          lastPing: DateTime.now(),
        ),
        RideMember(
          userId: 'user_trail2',
          displayName: 'John',
          position: LatLng(18.5104, 73.8567), // ~1.1km behind
          lastPing: DateTime.now(),
        ),
      ];

      final metrics = ConvoyCalculator.computeConvoyMetrics(
        myPos: mePos,
        myHeadingDeg: myHeading,
        myUserId: 'user_me',
        members: members,
      );

      expect(metrics.length, equals(4));
      // First must be Manav (farthest ahead)
      expect(metrics[0].member.displayName, equals('Manav'));
      expect(metrics[0].position, equals(RelativePosition.ahead));
      expect(metrics[0].formattedDistance.startsWith('+'), isTrue);

      // Second must be You
      expect(metrics[1].member.displayName, equals('Parth (You)'));
      expect(metrics[1].position, equals(RelativePosition.here));
      expect(metrics[1].formattedDistance, equals('You'));

      // Third must be Aditya (closest behind)
      expect(metrics[2].member.displayName, equals('Aditya'));
      expect(metrics[2].position, equals(RelativePosition.behind));
      expect(metrics[2].formattedDistance.startsWith('-'), isTrue);

      // Fourth must be John (farthest behind)
      expect(metrics[3].member.displayName, equals('John'));
      expect(metrics[3].position, equals(RelativePosition.behind));
      expect(metrics[3].formattedDistance.contains('km'), isTrue);
    });
  });

  group('GroupRide Model JSON Serialization', () {
    test('Serializes and deserializes cleanly', () {
      final now = DateTime.now();
      final ride = GroupRide(
        rideCode: 'SK-8492',
        title: 'Highway Convoy',
        leaderId: 'lead_1',
        leaderName: 'Parth',
        createdAt: now,
        members: {
          'lead_1': RideMember(
            userId: 'lead_1',
            displayName: 'Parth',
            phoneNumber: '+919876543210',
            position: LatLng(18.5204, 73.8567),
            speedKmh: 68.0,
            status: RiderStatus.riding,
            lastPing: now,
            isLeader: true,
          ),
        },
      );

      final json = ride.toJson();
      final restored = GroupRide.fromJson(json);

      expect(restored.rideCode, equals('SK-8492'));
      expect(restored.members.length, equals(1));
      expect(restored.members['lead_1']!.displayName, equals('Parth'));
      expect(restored.members['lead_1']!.isLeader, isTrue);
      expect(restored.members['lead_1']!.status, equals(RiderStatus.riding));
    });
  });
}
