import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'group_ride_model.dart';

/// Relative spatial position of a member with respect to current user.
enum RelativePosition {
  ahead,
  behind,
  here,
}

/// Computed telemetry and distance metric for a single convoy member.
class ConvoyMemberMetric {
  final RideMember member;
  final double distanceMeters;
  final RelativePosition position;
  final String formattedDistance; // e.g., "+470 m", "-1.1 km", "You"

  const ConvoyMemberMetric({
    required this.member,
    required this.distanceMeters,
    required this.position,
    required this.formattedDistance,
  });
}

/// Geometry and Convoy Progression Calculator.
///
/// Determines relative ahead/behind positioning based on current user position,
/// user heading (or travel bearing), and geodesic distance.
class ConvoyCalculator {
  static const Distance _distance = Distance();

  /// Calculates the initial forward azimuth/bearing (in degrees 0..360) from [p1] to [p2].
  static double calculateBearing(LatLng p1, LatLng p2) {
    final lat1 = p1.latitude * math.pi / 180.0;
    final lat2 = p2.latitude * math.pi / 180.0;
    final dLon = (p2.longitude - p1.longitude) * math.pi / 180.0;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final bearingRad = math.atan2(y, x);
    final bearingDeg = (bearingRad * 180.0 / math.pi + 360.0) % 360.0;
    return bearingDeg;
  }

  /// Determines whether [targetPos] is ahead or behind [userPos] based on the user's travel direction [userHeadingDeg].
  ///
  /// If angular deviation between bearing to target and travel heading is within ±90°, target is considered ahead.
  /// Otherwise, target is considered behind.
  static RelativePosition determineRelativePosition({
    required LatLng userPos,
    required double userHeadingDeg,
    required LatLng targetPos,
    double closeThresholdMeters = 5.0,
  }) {
    final dist = _distance.as(LengthUnit.Meter, userPos, targetPos);
    if (dist <= closeThresholdMeters) {
      return RelativePosition.here;
    }

    final bearingToTarget = calculateBearing(userPos, targetPos);
    var angleDiff = (bearingToTarget - userHeadingDeg).abs() % 360.0;
    if (angleDiff > 180.0) {
      angleDiff = 360.0 - angleDiff;
    }

    return angleDiff <= 90.0 ? RelativePosition.ahead : RelativePosition.behind;
  }

  /// Formats distance into clean reel-style labels ("+470 m", "-350 m", "-1.1 km").
  static String formatDistance(double meters, RelativePosition pos) {
    if (pos == RelativePosition.here) {
      return 'You';
    }

    final prefix = pos == RelativePosition.ahead ? '+' : '-';
    if (meters >= 1000) {
      final km = meters / 1000.0;
      return '$prefix${km.toStringAsFixed(1)} km';
    } else {
      return '$prefix${meters.round()} m';
    }
  }

  /// Computes metrics for all members and sorts them from front to back of the convoy.
  static List<ConvoyMemberMetric> computeConvoyMetrics({
    required LatLng myPos,
    required double myHeadingDeg,
    required String myUserId,
    required List<RideMember> members,
  }) {
    final metrics = <ConvoyMemberMetric>[];

    for (final member in members) {
      if (member.userId == myUserId) {
        metrics.add(ConvoyMemberMetric(
          member: member,
          distanceMeters: 0,
          position: RelativePosition.here,
          formattedDistance: 'You',
        ));
        continue;
      }

      final dist = _distance.as(LengthUnit.Meter, myPos, member.position);
      final relPos = determineRelativePosition(
        userPos: myPos,
        userHeadingDeg: myHeadingDeg,
        targetPos: member.position,
      );

      final label = formatDistance(dist, relPos);

      metrics.add(ConvoyMemberMetric(
        member: member,
        distanceMeters: dist,
        position: relPos,
        formattedDistance: label,
      ));
    }

    // Sort order:
    // 1. Ahead riders (farthest ahead first -> closest ahead)
    // 2. Current user ('You')
    // 3. Behind riders (closest behind -> farthest behind)
    metrics.sort((a, b) {
      if (a.position == RelativePosition.ahead && b.position == RelativePosition.ahead) {
        return b.distanceMeters.compareTo(a.distanceMeters); // Farthest ahead at top
      }
      if (a.position == RelativePosition.ahead) return -1;
      if (b.position == RelativePosition.ahead) return 1;

      if (a.position == RelativePosition.here) return -1;
      if (b.position == RelativePosition.here) return 1;

      // Both behind: closest behind first
      return a.distanceMeters.compareTo(b.distanceMeters);
    });

    return metrics;
  }
}
