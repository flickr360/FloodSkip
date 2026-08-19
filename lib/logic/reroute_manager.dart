import 'dart:async';
import 'package:latlong2/latlong.dart';
import '../models/flood_zone.dart';
import '../services/hazard_service.dart';
import '../services/osrm_routing_service.dart';
import 'geo_utils.dart';

/// Owns the "am I still on a safe route" loop during active navigation.
///
/// Usage: call [startNavigating] once a route is chosen, feed it live
/// location updates via [updateCurrentLocation], and listen to
/// [routeUpdates] for new routes (including the very first one).
class RerouteManager {
  final HazardService hazardService;
  final OsrmRoutingService routingService;
  final Duration pollInterval;

  RerouteManager({
    required this.hazardService,
    required this.routingService,
    this.pollInterval = const Duration(seconds: 30),
  });

  final _routeController = StreamController<RouteResult>.broadcast();
  final _hazardAlertController = StreamController<FloodZone>.broadcast();

  Stream<RouteResult> get routeUpdates => _routeController.stream;
  Stream<FloodZone> get hazardAlerts => _hazardAlertController.stream;

  Timer? _pollTimer;
  RouteResult? _currentRoute;
  LatLng? _destination;
  LatLng? _currentLocation;

  Future<void> startNavigating({
    required LatLng origin,
    required LatLng destination,
  }) async {
    _destination = destination;
    _currentLocation = origin;

    final hazards = await hazardService.getHazardsForPath([origin, destination]);
    final route = await routingService.getRoute(
      origin: origin,
      destination: destination,
      hazards: hazards,
    );
    _currentRoute = route;
    _routeController.add(route);

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) => _checkForHazards());
  }

  /// Call this from your location stream (e.g. geolocator's
  /// getPositionStream) so the manager always knows where the user is.
  void updateCurrentLocation(LatLng location) {
    _currentLocation = location;
  }

  Future<void> _checkForHazards() async {
    final route = _currentRoute;
    final destination = _destination;
    final location = _currentLocation;
    if (route == null || destination == null || location == null) return;

    // Only check the remaining, un-walked portion of the route so a
    // hazard behind the user doesn't trigger a pointless reroute.
    final remaining = _remainingPoints(route.points, location);

    final hazards = await hazardService.getHazardsForPath(remaining);
    final blockingZone = hazards.firstWhere(
      (z) => GeoUtils.pathIntersectsZone(remaining, z),
      orElse: () => FloodZone(
        id: '',
        polygon: const [],
        severity: FloodSeverity.caution,
        source: FloodSource.crowdsourced,
        reportedAt: DateTime.now(),
      ),
    );

    if (blockingZone.id.isEmpty) return; // nothing blocking, no-op

    _hazardAlertController.add(blockingZone);

    final newRoute = await routingService.getRoute(
      origin: location,
      destination: destination,
      hazards: hazards,
    );
    _currentRoute = newRoute;
    _routeController.add(newRoute);
  }

  /// Naive "remaining path" approximation: points from the closest
  /// vertex to the user's current location onward. Good enough given
  /// OSRM's densely sampled route geometry; for production, snap the
  /// user's location to the route line properly.
  List<LatLng> _remainingPoints(List<LatLng> routePoints, LatLng current) {
    const distance = Distance();
    var closestIndex = 0;
    var closestDist = double.infinity;
    for (var i = 0; i < routePoints.length; i++) {
      final d = distance(current, routePoints[i]);
      if (d < closestDist) {
        closestDist = d;
        closestIndex = i;
      }
    }
    return routePoints.sublist(closestIndex);
  }

  void dispose() {
    _pollTimer?.cancel();
    _routeController.close();
    _hazardAlertController.close();
  }
}
