import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/hazard_service.dart';
import 'services/osrm_routing_service.dart';
import 'logic/reroute_manager.dart';

// Point this at your own hazard backend (see lib/services/hazard_service.dart).
const kHazardBackendUrl = 'http://192.168.1.42:8000';

final hazardServiceProvider = Provider<HazardService>((ref) {
  return HazardService(baseUrl: kHazardBackendUrl);
});

// Swap osrmBaseUrl for your self-hosted OSRM instance in production —
// see the warning in osrm_routing_service.dart.
final routingServiceProvider = Provider<OsrmRoutingService>((ref) {
  return OsrmRoutingService();
});

final rerouteManagerProvider = Provider<RerouteManager>((ref) {
  final manager = RerouteManager(
    hazardService: ref.watch(hazardServiceProvider),
    routingService: ref.watch(routingServiceProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});
