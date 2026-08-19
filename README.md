# Flood-aware navigation (Flutter + OpenStreetMap)

A starter scaffold for a navigation app that reroutes users around
active flood zones, built entirely on the open-source/OSM stack:

- **Map rendering**: `flutter_map` with OSM raster tiles
- **Routing**: OSRM (`router.project-osrm.org` for dev, self-hosted for prod)
- **Hazard data**: your own backend, merging official flood feeds with
  crowdsourced reports (see `lib/services/hazard_service.dart`)

## What's here

```
lib/
  models/flood_zone.dart        Hazard data model + trust rules
  services/hazard_service.dart  Talks to your hazard backend
  services/osrm_routing_service.dart  Talks to OSRM, avoids hazards
  logic/geo_utils.dart          Point-in-polygon, bbox, centroid helpers
  logic/reroute_manager.dart    Polls hazards, triggers rerouting
  screens/map_screen.dart       Map UI, route + hazard overlay
  providers.dart                Riverpod wiring
  main.dart                     Entry point
```

## Before this runs for real

1. **Set `kHazardBackendUrl`** in `lib/providers.dart` to your backend.
   This scaffold has no backend included — you need an API that:
   - Serves `GET /hazards?south=&west=&north=&east=` returning
     `{"hazards": [FloodZone JSON, ...]}`
   - Accepts `POST /reports` for crowdsourced submissions
   - Ingests official flood data server-side. There's no clean public
     API for PAGASA/Project NOAH data, so this typically means scraping
     or partnering for a feed, run on a schedule.

2. **Self-host OSRM for production.** The public demo server used by
   default is rate-limited and has no uptime guarantee. Steps:
   - Download an OSM extract for your region from Geofabrik
   - Run `osrm-backend` against it (Docker image is the easiest path)
   - Point `osrmBaseUrl` in `OsrmRoutingService` at your instance
   - Optionally write a custom Lua profile that reads hazard data
     directly into edge weights — this is more robust than this
     scaffold's retry/detour-waypoint approach, which is a workaround
     for the fact that the public OSRM API can't exclude arbitrary
     polygons.

3. **Swap the raw OSM tile server** for a provider with a real usage
   policy (MapTiler, Stadia Maps, Thunderforest, etc.) before shipping —
   `tile.openstreetmap.org` is meant for light development use only.

4. **Tune the reroute-check cadence and confirmation thresholds** in
   `RerouteManager` and `FloodZone` — 30s polling and 2 confirmations
   are reasonable starting points, not fixed values.

## Running it

```
flutter pub get
flutter run
```

The demo "Start navigation" button routes from your current location to
a hardcoded point in Quezon City — wire it up to a real destination
search once you're ready.
