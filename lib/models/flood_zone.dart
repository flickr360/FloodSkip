import 'package:latlong2/latlong.dart';

/// How severe a reported flood zone is. Only [impassable] zones block
/// routing outright; [caution] zones are surfaced as warnings but the
/// router is still allowed to route through them.
enum FloodSeverity { caution, impassable }

/// Where a hazard report originated. Official sources are trusted more
/// than crowdsourced ones when they conflict.
enum FloodSource { official, crowdsourced }

/// A single flood hazard zone, represented as a simple polygon.
///
/// Keep the backend responsible for producing these — normalize both the
/// government feed (PAGASA / Project NOAH derived data) and crowdsourced
/// reports into this same shape so the app doesn't care where a hazard
/// came from.
class FloodZone {
  final String id;
  final List<LatLng> polygon; // closed or open ring, in order
  final FloodSeverity severity;
  final FloodSource source;
  final DateTime reportedAt;
  final DateTime? expiresAt;
  final int confirmations; // relevant for crowdsourced reports only

  FloodZone({
    required this.id,
    required this.polygon,
    required this.severity,
    required this.source,
    required this.reportedAt,
    this.expiresAt,
    this.confirmations = 0,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Crowdsourced reports need enough independent confirmations before
  /// they're trusted as impassable rather than just a caution flag.
  static const int minConfirmationsForImpassable = 2;

  /// Effective severity after applying trust rules. Use this instead of
  /// [severity] directly when deciding whether to block a route.
  FloodSeverity get effectiveSeverity {
    if (source == FloodSource.official) return severity;
    if (severity == FloodSeverity.impassable &&
        confirmations < minConfirmationsForImpassable) {
      return FloodSeverity.caution;
    }
    return severity;
  }

  factory FloodZone.fromJson(Map<String, dynamic> json) {
    final coords = (json['polygon'] as List)
        .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
        .toList();
    return FloodZone(
      id: json['id'] as String,
      polygon: coords,
      severity: FloodSeverity.values.byName(json['severity'] as String),
      source: FloodSource.values.byName(json['source'] as String),
      reportedAt: DateTime.parse(json['reportedAt'] as String),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      confirmations: json['confirmations'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        // GeoJSON convention is [lng, lat]
        'polygon': polygon.map((p) => [p.longitude, p.latitude]).toList(),
        'severity': severity.name,
        'source': source.name,
        'reportedAt': reportedAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'confirmations': confirmations,
      };
}
