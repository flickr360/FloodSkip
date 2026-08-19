import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import '../models/flood_zone.dart';
import '../logic/geo_utils.dart';

class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final bool avoidedHazard;

  RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.avoidedHazard = false,
  });
}

/// Computes routes using an OSRM server over OpenStreetMap data.
///
/// IMPORTANT: the public demo server (router.project-osrm.org) is fine
/// for prototyping but is rate-limited and has no uptime guarantee —
/// don't ship to production on it. For a real deployment, self-host
/// OSRM against an OSM extract of your region (e.g. via osrm-backend +
/// a Philippines .osm.pbf extract from Geofabrik). Self-hosting also
/// lets you write a custom Lua profile that bakes hazard avoidance
/// directly into the routing graph instead of the retry-based approach
/// below, which is a public-API-friendly workaround.
class OsrmRoutingService {
  final Dio _dio;
  final String osrmBaseUrl;

  OsrmRoutingService({
    this.osrmBaseUrl = 'https://router.project-osrm.org',
    Dio? dio,
  }) : _dio = dio ?? Dio();

  /// Get a route from [origin] to [destination] that avoids any active
  /// impassable [hazards]. Since the public OSRM API doesn't support
  /// excluding arbitrary polygons directly, this works by:
  ///   1. Requesting alternative routes and picking the first clean one.
  ///   2. If none are clean, inserting a detour waypoint around the
  ///      nearest blocking hazard and re-requesting.
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    List<FloodZone> hazards = const [],
  }) async {
    final direct = await _requestRoutes(
      waypoints: [origin, destination],
      alternatives: true,
    );

    for (final route in direct) {
      final blocked = hazards.any(
        (z) => GeoUtils.pathIntersectsZone(route.points, z),
      );
      if (!blocked) return route;
    }

    // No clean alternative — try a single detour around the worst offender.
    final blockingZone = _mostRelevantBlockingZone(direct.first.points, hazards);
    if (blockingZone == null) {
      // Shouldn't happen given the check above, but fail safe to the
      // shortest route rather than throwing.
      return direct.first;
    }

    final detourPoint = _detourWaypoint(blockingZone, origin, destination);
    final detoured = await _requestRoutes(
      waypoints: [origin, detourPoint, destination],
      alternatives: false,
    );

    final stillBlocked = hazards.any(
      (z) => GeoUtils.pathIntersectsZone(detoured.first.points, z),
    );

    return RouteResult(
      points: detoured.first.points,
      distanceMeters: detoured.first.distanceMeters,
      durationSeconds: detoured.first.durationSeconds,
      avoidedHazard: !stillBlocked,
    );
  }

  FloodZone? _mostRelevantBlockingZone(
    List<LatLng> path,
    List<FloodZone> hazards,
  ) {
    for (final z in hazards) {
      if (GeoUtils.pathIntersectsZone(path, z)) return z;
    }
    return null;
  }

  /// Picks a waypoint offset from the hazard's centroid, perpendicular
  /// to the origin->destination bearing, to nudge OSRM's routing away
  /// from the flooded segment. This is a heuristic, not a guarantee —
  /// for reliable avoidance, self-host OSRM with a custom profile.
  LatLng _detourWaypoint(FloodZone zone, LatLng origin, LatLng destination) {
    final center = GeoUtils.centroid(zone.polygon);
    const distance = Distance();
    final bearing = distance.bearing(origin, destination);
    final perpendicular = (bearing + 90) % 360;
    return distance.offset(center, 250, perpendicular); // 250m offset
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

    final routes = response.data['routes'] as List;
    return routes.map((r) {
      final coordsList = (r['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      return RouteResult(
        points: coordsList,
        distanceMeters: (r['distance'] as num).toDouble(),
        durationSeconds: (r['duration'] as num).toDouble(),
      );
    }).toList();
  }
}
