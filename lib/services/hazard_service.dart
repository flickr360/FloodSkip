import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import '../models/flood_zone.dart';
import '../logic/geo_utils.dart';

/// Talks to your own hazard backend, which is responsible for merging
/// the official feed (e.g. PAGASA/Project NOAH derived data, scraped or
/// ingested on a schedule) with crowdsourced reports and serving them
/// back as normalized [FloodZone] objects.
///
/// Point this at your own API. This class does not talk to PAGASA
/// directly — there's no stable public API for that, so ingestion needs
/// to happen server-side.
class HazardService {
  final Dio _dio;
  final String baseUrl;

  HazardService({required this.baseUrl, Dio? dio}) : _dio = dio ?? Dio();

  /// Fetch active hazards within a bounding box around the route.
Future<List<FloodZone>> getHazardsForPath(List<LatLng> path) async {
  final bbox = GeoUtils.boundingBox(path);

  final response = await _dio.get(
    '$baseUrl/hazards',
    queryParameters: {
      'south': bbox[0],
      'west': bbox[1],
      'north': bbox[2],
      'east': bbox[3],
    },
  );

  final List data = response.data['hazards'] as List;

  return data
      .map((e) => FloodZone.fromJson(e as Map<String, dynamic>))
      .where((z) => !z.isExpired)
      .toList();
}

  /// Submit a crowdsourced flood report. The backend should require
  /// authentication/rate-limiting here to discourage spam reports.
  Future<void> submitReport({
    required List<LatLng> polygon,
    required FloodSeverity severity,
  }) async {
    await _dio.post('$baseUrl/reports', data: {
      'polygon': polygon.map((p) => [p.longitude, p.latitude]).toList(),
      'severity': severity.name,
    });
  }
}
