import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  /// Verify and request GPS runtime permissions
  static Future<bool> handlePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Get current instantaneous fix
  static Future<Position?> getCurrentPosition() async {
    final hasPerm = await handlePermission();
    if (!hasPerm) return null;
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 5),
      ),
    );
  }

  /// Continuous GPS stream (fires when moved at least 5 meters)
  static Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Triggers every 5 meters
      ),
    );
  }

  /// Off-route detector: checks if current GPS point is further than threshold from route polyline
  static bool isOffRoute(
    LatLng currentPos,
    List<LatLng> routePoints, {
    double thresholdMeters = 35.0,
  }) {
    if (routePoints.isEmpty) return false;
    const distance = Distance();

    double minDistance = double.infinity;
    for (int i = 0; i < routePoints.length - 1; i++) {
      final p1 = routePoints[i];
      final p2 = routePoints[i + 1];

      final d = _distanceToSegment(currentPos, p1, p2, distance);
      if (d < minDistance) {
        minDistance = d;
      }
    }
    return minDistance > thresholdMeters;
  }

  static double _distanceToSegment(
    LatLng p,
    LatLng v,
    LatLng w,
    Distance distance,
  ) {
    final l2 = distance.as(LengthUnit.Meter, v, w) *
        distance.as(LengthUnit.Meter, v, w);
    if (l2 == 0) return distance.as(LengthUnit.Meter, p, v);

    final t = ((p.latitude - v.latitude) * (w.latitude - v.latitude) +
            (p.longitude - v.longitude) * (w.longitude - v.longitude)) /
        ((w.latitude - v.latitude) * (w.latitude - v.latitude) +
            (w.longitude - v.longitude) * (w.longitude - v.longitude));

    final clampedT = t.clamp(0.0, 1.0);
    final projection = LatLng(
      v.latitude + clampedT * (w.latitude - v.latitude),
      v.longitude + clampedT * (w.longitude - v.longitude),
    );
    return distance.as(LengthUnit.Meter, p, projection);
  }
}