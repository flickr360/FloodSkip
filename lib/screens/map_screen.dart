import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../logic/reroute_manager.dart';
import '../models/flood_zone.dart';
import '../providers.dart';
import '../services/osrm_routing_service.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = MapController();
  List<LatLng> _routePoints = [];
  List<FloodZone> _visibleHazards = [];
  LatLng? _currentLocation;

  RerouteManager? _manager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    _manager = ref.read(rerouteManagerProvider);

    _manager!.routeUpdates.listen((RouteResult route) {
      setState(() => _routePoints = route.points);
    });

    _manager!.hazardAlerts.listen((zone) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route updated — flooding reported ahead')),
      );
    });

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(distanceFilter: 15),
    ).listen((position) {
      final loc = LatLng(position.latitude, position.longitude);
      setState(() => _currentLocation = loc);
      _manager?.updateCurrentLocation(loc);
    });
  }

  /// Wire this up to your destination search UI. For demo purposes this
  /// starts navigation from the current location to a fixed example point.
  Future<void> _startDemoNavigation() async {
    if (_currentLocation == null) return;
    const destination = LatLng(14.6091, 121.0223); // example: Quezon City
    await _manager!.startNavigating(
      origin: _currentLocation!,
      destination: destination,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flood-aware navigation')),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _currentLocation ?? const LatLng(14.5995, 120.9842),
          initialZoom: 14,
        ),
        children: [
          // Standard OSM raster tiles. For production, use a tile
          // provider with a proper usage policy / API key (e.g.
          // MapTiler, Stadia Maps) rather than the raw OSM tile server,
          // which has strict usage limits.
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.flood_nav_flutter',
          ),
          PolygonLayer(
            polygons: _visibleHazards.map((z) {
              final blocked = z.effectiveSeverity == FloodSeverity.impassable;
              return Polygon(
                points: z.polygon,
                color: (blocked ? Colors.red : Colors.orange).withOpacity(0.3),
                borderColor: blocked ? Colors.red : Colors.orange,
                borderStrokeWidth: 2,
              );
            }).toList(),
          ),
          if (_routePoints.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(points: _routePoints, strokeWidth: 5, color: Colors.blue),
              ],
            ),
          if (_currentLocation != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: _currentLocation!,
                  child: const Icon(Icons.navigation, color: Colors.blue),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startDemoNavigation,
        label: const Text('Start navigation'),
        icon: const Icon(Icons.directions),
      ),
    );
  }
}
