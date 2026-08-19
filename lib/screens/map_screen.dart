// screens/map_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import '../models/flood_zone.dart';
import '../services/hazard_service.dart';
import '../services/osrm_routing_service.dart';
import '../services/location_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  late final HazardService _hazardService;
  late final OsrmRoutingService _routingService;

  // Real-time GPS Tracking State
  bool _followUserLocation = false;
  StreamSubscription<Position>? _positionStreamSub;
  LatLng? _currentLiveLocation;
  double _currentHeading = 0.0;
  DateTime? _lastRerouteTime;

  // Default coordinate boundaries (e.g., Manila City Hall to Quezon City Hall)
  LatLng _origin = const LatLng(14.5896, 120.9815);
  LatLng _destination = const LatLng(14.6464, 121.0503);

  final TextEditingController _originCtrl =
      TextEditingController(text: "Manila City Hall");
  final TextEditingController _destCtrl =
      TextEditingController(text: "Quezon City Hall");

  String _selectedVehicle = "sedan";
  final List<Map<String, dynamic>> _vehicleTypes = [
    {
      "id": "motorcycle",
      "label": "Motorcycle",
      "icon": Icons.two_wheeler,
      "clearance": "20 cm"
    },
    {
      "id": "sedan",
      "label": "Sedan",
      "icon": Icons.directions_car,
      "clearance": "30 cm"
    },
    {
      "id": "suv",
      "label": "SUV / 4x4",
      "icon": Icons.directions_car_filled,
      "clearance": "50 cm"
    },
    {
      "id": "truck",
      "label": "Truck",
      "icon": Icons.local_shipping,
      "clearance": "80 cm"
    },
  ];

  List<RouteResult> _availableRoutes = [];
  int _selectedRouteIndex = 0;
  List<FloodZone> _activeHazards = [];
  bool _isLoading = false;
  bool _isMapReady = false;

  @override
  void initState() {
    super.initState();
    // Replace with your local FastAPI host/IP
    _hazardService = HazardService(baseUrl: "http://192.168.1.42:8000");
    _routingService = OsrmRoutingService();
    _initLiveLocationTracking();
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    super.dispose();
  }

  /// Initialize continuous GPS streaming & permission
  Future<void> _initLiveLocationTracking() async {
    final hasPerm = await LocationService.handlePermission();
    if (!hasPerm) return;

    final initialPos = await LocationService.getCurrentPosition();
    if (initialPos != null && mounted) {
      setState(() {
        _currentLiveLocation =
            LatLng(initialPos.latitude, initialPos.longitude);
        _origin = _currentLiveLocation!;
        _originCtrl.text = "My Current Location";
      });
      if (_isMapReady) {
        _calculateFloodAwareRoute();
      }
    }

    _positionStreamSub = LocationService.getPositionStream().listen((pos) {
      if (!mounted) return;

      final newLocation = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _currentLiveLocation = newLocation;
        _currentHeading = pos.heading;
      });

      if (_followUserLocation && _isMapReady) {
        _mapController.move(newLocation, _mapController.camera.zoom);
      }

      _checkDynamicReroute(newLocation);
    });
  }

  /// Trigger recalculation when moving > 35m off track
  void _checkDynamicReroute(LatLng userPos) {
    if (_isLoading || _availableRoutes.isEmpty) return;

    final now = DateTime.now();
    if (_lastRerouteTime != null &&
        now.difference(_lastRerouteTime!).inSeconds < 6) {
      return;
    }

    final activeRoute = _availableRoutes[_selectedRouteIndex];
    if (LocationService.isOffRoute(userPos, activeRoute.points,
        thresholdMeters: 35.0)) {
      debugPrint(">>> Off-route detected! Recalculating from GPS fix...");
      _lastRerouteTime = now;
      setState(() => _origin = userPos);
      _calculateFloodAwareRoute();
    }
  }

  Future<void> _calculateFloodAwareRoute() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 1. First Pass: Fetch raw exploratory candidate routes
      final rawRoutes = await _routingService.getMultipleRoutes(
        origin: _origin,
        destination: _destination,
        hazards: const [],
      );

      final candidatePolylines = rawRoutes.map((r) => r.points).toList();

      // 2. Fetch hazards covering both primary and detour side corridors (800m)
      final allEnvelopeHazards = await _hazardService.getHazardsForEnvelope(
        origin: _origin,
        destination: _destination,
        candidatePaths: candidatePolylines,
        simulateRain: null,
        bufferMeters: 800.0,
        vehicleType: _selectedVehicle,
      );

      // 3. Second Pass: Verify all alternative routes strictly against envelope hazards
      final rankedRoutes = await _routingService.getMultipleRoutes(
        origin: _origin,
        destination: _destination,
        hazards: allEnvelopeHazards,
      );

      if (mounted) {
        setState(() {
          _availableRoutes = rankedRoutes;
          _selectedRouteIndex = 0;
          _activeHazards = allEnvelopeHazards;
        });

        if (_isMapReady && rankedRoutes.isNotEmpty && !_followUserLocation) {
          _mapController.fitCamera(
            CameraFit.coordinates(
              coordinates: rankedRoutes.first.points,
              padding: const EdgeInsets.all(60.0),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Routing computation error: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openSearchDialog(bool isOrigin) {
    showDialog(
      context: context,
      builder: (ctx) {
        final searchCtrl = TextEditingController();
        List<Map<String, dynamic>> places = [];

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title:
                  Text(isOrigin ? "Set Starting Location" : "Set Destination"),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: "Search location in Metro Manila...",
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () async {
                            final results =
                                await _searchNominatim(searchCtrl.text);
                            setDialogState(() => places = results);
                          },
                        ),
                      ),
                      onSubmitted: (val) async {
                        final results = await _searchNominatim(val);
                        setDialogState(() => places = results);
                      },
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: places.length,
                        itemBuilder: (c, i) {
                          final p = places[i];
                          return ListTile(
                            dense: true,
                            leading:
                                const Icon(Icons.place, color: Colors.blueGrey),
                            title: Text(p['display_name'] ?? '',
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () {
                              final lat = double.parse(p['lat']);
                              final lon = double.parse(p['lon']);
                              setState(() {
                                if (isOrigin) {
                                  _origin = LatLng(lat, lon);
                                  _originCtrl.text =
                                      p['display_name'].split(',')[0];
                                  _followUserLocation = false;
                                } else {
                                  _destination = LatLng(lat, lon);
                                  _destCtrl.text =
                                      p['display_name'].split(',')[0];
                                }
                              });
                              Navigator.pop(ctx);
                              _calculateFloodAwareRoute();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _searchNominatim(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final res = await Dio().get(
        "https://nominatim.openstreetmap.org/search",
        queryParameters: {
          'q': query,
          'format': 'json',
          'countrycodes': 'ph',
          'limit': 5
        },
        options: Options(headers: {'User-Agent': 'FloodNavApp/1.0'}),
      );
      return (res.data as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeRoute = _availableRoutes.isNotEmpty
        ? _availableRoutes[_selectedRouteIndex]
        : null;
    final isAvoided = activeRoute?.avoidedHazard ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Flood-Aware Navigation"),
        backgroundColor:
            isAvoided ? Colors.deepOrange.shade800 : Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _origin,
              initialZoom: 13.0,
              onMapReady: () {
                _isMapReady = true;
                _calculateFloodAwareRoute();
              },
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture && _followUserLocation) {
                  setState(() => _followUserLocation = false);
                }
              },
              onTap: (tapPosition, point) {
                setState(() {
                  _destination = point;
                  _destCtrl.text =
                      "${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}";
                });
                _calculateFloodAwareRoute();
              },
            ),
            children: [
              // Minimal Positron Basemap
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.flood_nav_flutter',
              ),

              // Generalized Discrete Flood Hazards
              PolygonLayer(
                polygons: _activeHazards.map((hazard) {
                  final isImpassable =
                      hazard.effectiveSeverity == FloodSeverity.impassable;
                  return Polygon(
                    points: hazard.polygon,
                    color: isImpassable
                        ? Colors.red.withOpacity(0.35)
                        : Colors.amber.withOpacity(0.30),
                    borderColor: isImpassable
                        ? Colors.red.shade900
                        : Colors.orange.shade800,
                    borderStrokeWidth: 2.0,
                  );
                }).toList(),
              ),

              // Unselected Alternative Routes (Muted Gray Polylines)
              PolylineLayer(
                polylines: [
                  for (int i = 0; i < _availableRoutes.length; i++)
                    if (i != _selectedRouteIndex)
                      Polyline(
                        points: _availableRoutes[i].points,
                        color: Colors.blueGrey.withOpacity(0.40),
                        strokeWidth: 4.0,
                      ),
                ],
              ),

              // Selected Active Route (Blue, Orange Detour, or Red Warning)
              if (activeRoute != null && activeRoute.points.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: activeRoute.points,
                      color: activeRoute.hazardIntersections > 0
                          ? Colors.red.shade700
                          : isAvoided
                              ? Colors.deepOrange.shade800
                              : Colors.blue.shade700,
                      strokeWidth: 6.0,
                    ),
                  ],
                ),

              // Markers
              MarkerLayer(
                markers: [
                  Marker(
                    point: _destination,
                    child: const Icon(Icons.location_on,
                        color: Colors.red, size: 36),
                  ),

                  // User Current Live Location Puck
                  if (_currentLiveLocation != null)
                    Marker(
                      point: _currentLiveLocation!,
                      width: 44,
                      height: 44,
                      child: Transform.rotate(
                        angle: (_currentHeading * (3.141592653589793 / 180)),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.blue.withOpacity(0.25),
                              ),
                            ),
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.blue.shade700,
                                border:
                                    Border.all(color: Colors.white, width: 2.5),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black26, blurRadius: 4)
                                ],
                              ),
                            ),
                            const Positioned(
                              top: 2,
                              child: Icon(Icons.navigation,
                                  size: 12, color: Colors.blueAccent),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 1. Origin & Destination Input Card
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _currentLiveLocation != null &&
                                _origin == _currentLiveLocation
                            ? Icons.my_location
                            : Icons.radio_button_checked,
                        color: Colors.green,
                        size: 18,
                      ),
                      title: Text(_originCtrl.text,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.search, size: 20),
                      onTap: () => _openSearchDialog(true),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.location_on,
                          color: Colors.red, size: 20),
                      title: Text(_destCtrl.text,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.search, size: 20),
                      onTap: () => _openSearchDialog(false),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. Vehicle Selector Bar
          Positioned(
            top: 130,
            left: 12,
            right: 12,
            child: Card(
              color: Colors.white.withOpacity(0.95),
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: _vehicleTypes.map((v) {
                    final isSelected = _selectedVehicle == v["id"];
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _isLoading
                          ? null
                          : () {
                              setState(() => _selectedVehicle = v["id"]);
                              _calculateFloodAwareRoute();
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.blue.shade800
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(v["icon"],
                                size: 18,
                                color:
                                    isSelected ? Colors.white : Colors.black87),
                            const SizedBox(width: 4),
                            Text(
                              v["label"],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color:
                                    isSelected ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

          // 3. Recenter on GPS Floating Action Button
          Positioned(
            right: 16,
            bottom: 128,
            child: FloatingActionButton.small(
              heroTag: 'recenter_gps',
              backgroundColor:
                  _followUserLocation ? Colors.blue.shade800 : Colors.white,
              foregroundColor:
                  _followUserLocation ? Colors.white : Colors.black87,
              onPressed: () {
                if (_currentLiveLocation != null) {
                  setState(() => _followUserLocation = !_followUserLocation);
                  _mapController.move(_currentLiveLocation!, 15.0);
                }
              },
              child: Icon(
                  _followUserLocation ? Icons.gps_fixed : Icons.gps_not_fixed),
            ),
          ),

          // 4. Horizontal Multi-Route Choice Cards (Bottom)
          if (_availableRoutes.isNotEmpty)
            Positioned(
              bottom: 16,
              left: 12,
              right: 12,
              child: SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _availableRoutes.length,
                  itemBuilder: (context, idx) {
                    final r = _availableRoutes[idx];
                    final isSelected = _selectedRouteIndex == idx;
                    final isSafe = r.hazardIntersections == 0;

                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedRouteIndex = idx);
                        _mapController.fitCamera(
                          CameraFit.coordinates(
                            coordinates: r.points,
                            padding: const EdgeInsets.all(60.0),
                          ),
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 170,
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isSafe
                                  ? Colors.blue.shade900
                                  : Colors.red.shade900)
                              : Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? Colors.white
                                : Colors.grey.shade300,
                            width: isSelected ? 2.0 : 1.0,
                          ),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4)
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isSafe
                                      ? Icons.check_circle
                                      : Icons.warning_amber_rounded,
                                  size: 16,
                                  color: isSelected
                                      ? Colors.white
                                      : (isSafe
                                          ? Colors.green.shade700
                                          : Colors.red.shade700),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    r.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "${(r.durationSeconds / 60).toStringAsFixed(0)} mins • ${(r.distanceMeters / 1000).toStringAsFixed(1)} km",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color:
                                    isSelected ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              isSafe
                                  ? "100% Flood-Free"
                                  : "${r.hazardIntersections} Flood Zone Crossing",
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected
                                    ? Colors.white70
                                    : (isSafe
                                        ? Colors.green.shade700
                                        : Colors.red.shade700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
