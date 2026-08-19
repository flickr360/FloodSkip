// services/hazard_service.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/flood_zone.dart';
import '../logic/geo_utils.dart';

class HazardService {
  final Dio _dio;
  final String baseUrl;

  HazardService({required this.baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 6),
              ),
            );

  Future<List<FloodZone>> getHazardsForEnvelope({
    required LatLng origin,
    required LatLng destination,
    List<List<LatLng>>? candidatePaths,
    double? simulateRain,
    double bufferMeters = 800.0, // Wider corridor to cover lateral bypasses
    String vehicleType = 'sedan',
  }) async {
    // Collect all points across all candidate paths + origin/destination
    final allPoints = <LatLng>[origin, destination];
    if (candidatePaths != null) {
      for (final pList in candidatePaths) {
        allPoints.addAll(pList);
      }
    }

    final bbox = GeoUtils.boundingBox(allPoints);

    // Build sampled path representation
    final sampleList = <LatLng>[];
    final int step = (allPoints.length / 50).ceil().clamp(1, allPoints.length);
    for (int i = 0; i < allPoints.length; i += step) {
      sampleList.add(allPoints[i]);
    }

    final pathParam = sampleList
        .map((p) =>
            '${p.longitude.toStringAsFixed(5)},${p.latitude.toStringAsFixed(5)}')
        .join(';');

    final queryParams = <String, dynamic>{
      'south': bbox[0],
      'west': bbox[1],
      'north': bbox[2],
      'east': bbox[3],
      'path': pathParam,
      'buffer_meters': bufferMeters,
      'vehicle_type': vehicleType,
    };

    if (simulateRain != null) {
      queryParams['simulate_rain'] = simulateRain;
    }

    try {
      final response = await _dio.get(
        '$baseUrl/hazards',
        queryParameters: queryParams,
      );

      final dynamic responseData = response.data;
      final List features =
          (responseData['features'] ?? responseData['hazards'] ?? []) as List;
      final List<FloodZone> zones = [];

      for (int i = 0; i < features.length; i++) {
        final item = features[i];
        if (item is! Map<String, dynamic>) continue;

        if (item.containsKey('geometry')) {
          final geometry = item['geometry'] as Map<String, dynamic>;
          final properties = item['properties'] as Map<String, dynamic>? ?? {};
          final geomType = geometry['type'] as String;
          final coordinates = geometry['coordinates'] as List;

          final zoneId = item['id']?.toString() ??
              properties['id']?.toString() ??
              'hazard_cluster_$i';
          final severity = _parseSeverity(properties['severity']);
          final source = _parseSource(properties['source']);

          if (geomType == 'Polygon') {
            final List exteriorRing = coordinates[0] as List;
            final List<LatLng> polygonPoints = exteriorRing.map((coord) {
              return LatLng(
                  (coord[1] as num).toDouble(), (coord[0] as num).toDouble());
            }).toList();

            if (polygonPoints.isNotEmpty) {
              zones.add(FloodZone(
                id: zoneId,
                polygon: polygonPoints,
                severity: severity,
                source: source,
                reportedAt: DateTime.now(),
              ));
            }
          } else if (geomType == 'MultiPolygon') {
            for (int pIdx = 0; pIdx < coordinates.length; pIdx++) {
              final List polyCoords = coordinates[pIdx] as List;
              final List exteriorRing = polyCoords[0] as List;
              final List<LatLng> polygonPoints = exteriorRing.map((coord) {
                return LatLng(
                    (coord[1] as num).toDouble(), (coord[0] as num).toDouble());
              }).toList();

              if (polygonPoints.isNotEmpty) {
                zones.add(FloodZone(
                  id: '${zoneId}_$pIdx',
                  polygon: polygonPoints,
                  severity: severity,
                  source: source,
                  reportedAt: DateTime.now(),
                ));
              }
            }
          }
        }
      }

      return zones;
    } catch (e) {
      debugPrint('HazardService error: $e');
      return [];
    }
  }

  FloodSeverity _parseSeverity(dynamic severityStr) {
    if (severityStr?.toString().toLowerCase() == 'impassable') {
      return FloodSeverity.impassable;
    }
    return FloodSeverity.caution;
  }

  FloodSource _parseSource(dynamic sourceStr) {
    final s = sourceStr?.toString().toLowerCase() ?? '';
    return s.contains('crowd')
        ? FloodSource.crowdsourced
        : FloodSource.official;
  }
}
