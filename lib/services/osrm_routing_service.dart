// services/osrm_routing_service.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/flood_zone.dart';

class RouteResult {
  final String label;
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final bool avoidedHazard;
  final int hazardIntersections;

  RouteResult({
    required this.label,
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.avoidedHazard = false,
    this.hazardIntersections = 0,
  });
}

class OsrmRoutingService {
  final Dio _dio;
  final String osrmBaseUrl;

  OsrmRoutingService({
    this.osrmBaseUrl = 'https://router.project-osrm.org',
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 6),
              ),
            );

  Future<List<RouteResult>> getMultipleRoutes({
    required LatLng origin,
    required LatLng destination,
    List<FloodZone> hazards = const [],
  }) async {
    final List<RouteResult> candidatePool = [];

    try {
      // 1. Fetch direct route + standard OSRM alternatives
      final baseRoutes = await _requestRoutes(
        waypoints: [origin, destination],
        alternatives: true,
      );

      final impassableHazards = hazards
          .where((h) => h.effectiveSeverity == FloodSeverity.impassable && !h.isExpired)
          .toList();

      for (int i = 0; i < baseRoutes.length; i++) {
        final r = baseRoutes[i];
        final hitCount = _countHazardIntersections(r.points, impassableHazards);
        candidatePool.add(RouteResult(
          label: hitCount == 0 ? "Fastest (Safe)" : "Fastest (Crosses Flood)",
          points: r.points,
          distanceMeters: r.distanceMeters,
          durationSeconds: r.durationSeconds,
          avoidedHazard: hitCount == 0 && impassableHazards.isNotEmpty,
          hazardIntersections: hitCount,
        ));
      }

      // 2. Discover lateral bypass routes if hazards exist
      if (impassableHazards.isNotEmpty) {
        final offsets = [600.0, 1200.0, 1800.0];
        final angles = [90.0, -90.0];

        for (final offset in offsets) {
          for (final angle in angles) {
            for (final zone in impassableHazards.take(2)) {
              final bypassPt = _calculateBypassPoint(
                zone: zone,
                origin: origin,
                destination: destination,
                offsetMeters: offset,
                angleOffset: angle,
              );

              final detourRoutes = await _requestRoutes(
                waypoints: [origin, bypassPt, destination],
                alternatives: false,
              );

              for (final dr in detourRoutes) {
                final hits = _countHazardIntersections(dr.points, impassableHazards);
                final label = hits == 0
                    ? (angle > 0 ? "Safe Bypass (East)" : "Safe Bypass (West)")
                    : "Partial Detour";

                // Avoid duplicate geometry entries
                final isDuplicate = candidatePool.any(
                  (c) => (c.distanceMeters - dr.distanceMeters).abs() < 100,
                );

                if (!isDuplicate) {
                  candidatePool.add(RouteResult(
                    label: label,
                    points: dr.points,
                    distanceMeters: dr.distanceMeters,
                    durationSeconds: dr.durationSeconds,
                    avoidedHazard: hits == 0,
                    hazardIntersections: hits,
                  ));
                }
              }
            }
          }
        }
      }

      // 3. Sort routes: Safest first (0 intersections), then fastest duration
      candidatePool.sort((a, b) {
        if (a.hazardIntersections != b.hazardIntersections) {
          return a.hazardIntersections.compareTo(b.hazardIntersections);
        }
        return a.durationSeconds.compareTo(b.durationSeconds);
      });

      return candidatePool.take(3).toList();
    } catch (e) {
      debugPrint("Multiple routing error: $e");
      return [
        RouteResult(
          label: "Direct",
          points: [origin, destination],
          distanceMeters: 0,
          durationSeconds: 0,
        )
      ];
    }
  }

  int _countHazardIntersections(List<LatLng> routePoints, List<FloodZone> hazards) {
    int count = 0;
    for (final h in hazards) {
      if (_doesRouteIntersectPolygon(routePoints, h.polygon)) {
        count++;
      }
    }
    return count;
  }

  bool _doesRouteIntersectPolygon(List<LatLng> routePoints, List<LatLng> polyVertices) {
    if (polyVertices.length < 3) return false;
    for (final pt in routePoints) {
      if (_isPointInPolygon(pt, polyVertices)) return true;
    }
    for (int i = 0; i < routePoints.length - 1; i++) {
      for (int j = 0; j < polyVertices.length; j++) {
        if (_lineSegmentsIntersect(
          routePoints[i],
          routePoints[i + 1],
          polyVertices[j],
          polyVertices[(j + 1) % polyVertices.length],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> vertices) {
    int intersectCount = 0;
    for (int i = 0; i < vertices.length; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % vertices.length];
      if ((a.latitude > point.latitude) != (b.latitude > point.latitude)) {
        final intersectLon =
            (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) +
                a.longitude;
        if (point.longitude < intersectLon) intersectCount++;
      }
    }
    return (intersectCount % 2) == 1;
  }

  bool _lineSegmentsIntersect(LatLng p1, LatLng p2, LatLng q1, LatLng q2) {
    double ccw(LatLng a, LatLng b, LatLng c) {
      return (c.latitude - a.latitude) * (b.longitude - a.longitude) -
          (b.latitude - a.latitude) * (c.longitude - a.longitude);
    }

    double o1 = ccw(p1, p2, q1), o2 = ccw(p1, p2, q2);
    double o3 = ccw(q1, q2, p1), o4 = ccw(q1, q2, p2);

    return ((o1 > 0 && o2 < 0 || o1 < 0 && o2 > 0) && (o3 > 0 && o4 < 0 || o3 < 0 && o4 > 0));
  }

  LatLng _calculateBypassPoint({
    required FloodZone zone,
    required LatLng origin,
    required LatLng destination,
    required double offsetMeters,
    required double angleOffset,
  }) {
    double latSum = 0, lonSum = 0;
    for (var p in zone.polygon) {
      latSum += p.latitude;
      lonSum += p.longitude;
    }
    final center = LatLng(latSum / zone.polygon.length, lonSum / zone.polygon.length);
    const distance = Distance();
    final directBearing = distance.bearing(origin, destination);
    return distance.offset(center, offsetMeters, (directBearing + angleOffset) % 360);
  }

  Future<List<RouteResult>> _requestRoutes({
    required List<LatLng> waypoints,
    required bool alternatives,
  }) async {
    final coords = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
    final response = await _dio.get(
      '$osrmBaseUrl/route/v1/driving/$coords',
      queryParameters: {
        'alternatives': alternatives,
        'overview': 'full',
        'geometries': 'geojson',
      },
    );

    final routes = response.data['routes'] as List? ?? [];
    return routes.map((r) {
      final coordsList = (r['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      return RouteResult(
        label: "Alternative",
        points: coordsList,
        distanceMeters: (r['distance'] as num).toDouble(),
        durationSeconds: (r['duration'] as num).toDouble(),
      );
    }).toList();
  }
}