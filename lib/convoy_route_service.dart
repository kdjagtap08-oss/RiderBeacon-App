import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Service to fetch turn-by-turn driving routing polylines and detect off-track deviation.
class ConvoyRouteService {
  static final Map<String, List<LatLng>> _routeCache = {};
  static final Distance _distance = const Distance();

  /// Fetches a driving route polyline between [start] and [destination] using OSRM.
  /// Falls back to a clean direct geodesic segment if network is unavailable or fails.
  static Future<List<LatLng>> fetchDrivingRoute({
    required LatLng start,
    required LatLng destination,
  }) async {
    final cacheKey =
        '${start.latitude.toStringAsFixed(4)},${start.longitude.toStringAsFixed(4)}->${destination.latitude.toStringAsFixed(4)},${destination.longitude.toStringAsFixed(4)}';

    if (_routeCache.containsKey(cacheKey)) {
      return _routeCache[cacheKey]!;
    }

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final coordinates =
              data['routes'][0]['geometry']['coordinates'] as List;
          final points = coordinates.map((c) {
            final lng = (c[0] as num).toDouble();
            final lat = (c[1] as num).toDouble();
            return LatLng(lat, lng);
          }).toList();

          if (points.isNotEmpty) {
            _routeCache[cacheKey] = points;
            return points;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Route fetch failed, falling back to direct line: $e');
      }
    }

    // Direct fallback
    final fallback = [start, destination];
    _routeCache[cacheKey] = fallback;
    return fallback;
  }

  /// Calculates the shortest distance (in meters) from a rider's [position] to the route polyline.
  ///
  /// Returns `0.0` if the route is empty.
  static double distanceToRoute({
    required LatLng position,
    required List<LatLng> routePoints,
  }) {
    if (routePoints.isEmpty) return 0.0;
    if (routePoints.length == 1) {
      return _distance.as(LengthUnit.Meter, position, routePoints.first);
    }

    double minDistance = double.infinity;

    for (int i = 0; i < routePoints.length - 1; i++) {
      final p1 = routePoints[i];
      final p2 = routePoints[i + 1];
      final dist = _distanceToSegment(position, p1, p2);
      if (dist < minDistance) {
        minDistance = dist;
      }
    }

    return minDistance;
  }

  /// Determines if a rider has deviated significantly from their planned route.
  /// Standard deviation threshold: 120 meters.
  static bool isRiderOffTrack({
    required LatLng position,
    required List<LatLng> routePoints,
    double thresholdMeters = 120.0,
  }) {
    if (routePoints.isEmpty) return false;
    final dist = distanceToRoute(position: position, routePoints: routePoints);
    return dist > thresholdMeters;
  }

  /// Calculates perpendicular distance from point P to line segment AB in meters.
  static double _distanceToSegment(LatLng p, LatLng a, LatLng b) {
    // Equirectangular approximation for fast local calculation
    final x = (b.longitude - a.longitude) * 111320.0 * 0.95; // rough cos(lat)
    final y = (b.latitude - a.latitude) * 110540.0;

    final lengthSq = x * x + y * y;
    if (lengthSq == 0.0) {
      return _distance.as(LengthUnit.Meter, p, a);
    }

    final px = (p.longitude - a.longitude) * 111320.0 * 0.95;
    final py = (p.latitude - a.latitude) * 110540.0;

    var t = (px * x + py * y) / lengthSq;
    t = t.clamp(0.0, 1.0);

    final projLat = a.latitude + t * (b.latitude - a.latitude);
    final projLng = a.longitude + t * (b.longitude - a.longitude);

    return _distance.as(LengthUnit.Meter, p, LatLng(projLat, projLng));
  }
}
