import 'package:latlong2/latlong.dart';
import '../models/flood_zone.dart';

/// Small self-contained geometry helpers so we don't need a heavier
/// geospatial package just for point-in-polygon and bbox checks.
class GeoUtils {
  /// Standard ray-casting point-in-polygon test.
  static bool pointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude, yi = polygon[i].latitude;
      final xj = polygon[j].longitude, yj = polygon[j].latitude;
      final intersects = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  /// Bounding box [south, west, north, east] around a list of points,
  /// padded slightly so nearby hazards just outside the exact route are
  /// still picked up.
  static List<double> boundingBox(List<LatLng> points, {double padDeg = 0.01}) {
    double south = points.first.latitude, north = points.first.latitude;
    double west = points.first.longitude, east = points.first.longitude;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    return [south - padDeg, west - padDeg, north + padDeg, east + padDeg];
  }

  /// Does any point along [path] fall inside an impassable [zone]?
  /// Checking route vertices is a reasonable approximation since OSRM
  /// route geometries are densely sampled; for sparser paths you'd want
  /// to also test midpoints of each segment.
  static bool pathIntersectsZone(List<LatLng> path, FloodZone zone) {
    if (zone.effectiveSeverity != FloodSeverity.impassable) return false;
    if (zone.isExpired) return false;
    for (final point in path) {
      if (pointInPolygon(point, zone.polygon)) return true;
    }
    return false;
  }

  /// Centroid of a polygon, used to pick a detour waypoint around a hazard.
  static LatLng centroid(List<LatLng> polygon) {
    double lat = 0, lng = 0;
    for (final p in polygon) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / polygon.length, lng / polygon.length);
  }
}
