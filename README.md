# Flood-Aware Navigation

A flood-aware navigation application built with **Flutter, OpenStreetMap, OSRM, and a dedicated hazard backend**.

The application provides turn-by-turn route planning while considering active flood zones. It can detect newly reported hazards, warn users about dangerous areas, and request an alternative route when an existing route becomes unsafe.

> **Project status:** Production-oriented scaffold. The Flutter client, routing integration, hazard model, and rerouting architecture are included, but a production hazard backend and production map/routing infrastructure must be configured before deployment.

---

## Features

* 🗺️ OpenStreetMap-based map rendering
* 🚗 OSRM route calculation
* 🌊 Active flood-zone visualization
* 🚧 Impassable flood zones that trigger route avoidance
* ⚠️ Caution zones that generate warnings without automatically blocking routing
* 🔄 Automatic rerouting when hazards change
* 📡 Periodic hazard synchronization
* 👥 Crowdsourced flood reports
* 🏛️ Support for trusted/official flood information
* 📍 Bounding-box hazard queries
* 🧭 Point-in-polygon flood detection
* 🔐 Separation between the mobile client and hazard-data infrastructure
* 🐳 Suitable for containerized backend deployment

---

## Architecture

```text
                         ┌──────────────────────┐
                         │   Official Sources   │
                         │  PAGASA / LGUs / etc │
                         └──────────┬───────────┘
                                    │
                                    ▼
┌──────────────┐             ┌──────────────────┐
│ Mobile User  │             │ Hazard Backend   │
│   Flutter    │◄───────────►│                  │
└──────┬───────┘             │ • Hazard API     │
       │                     │ • Validation     │
       │                     │ • Aggregation    │
       │                     │ • Reports        │
       │                     └────────┬─────────┘
       │                              │
       │                              ▼
       │                     ┌──────────────────┐
       │                     │ Hazard Database  │
       │                     └──────────────────┘
       │
       ▼
┌─────────────────────┐
│ Routing Service     │
│                     │
│ OSRM                 │
│ Self-hosted / cloud │
└──────────┬──────────┘
           │
           ▼
     Route + Geometry
           │
           ▼
┌─────────────────────┐
│ Flood Intersection  │
│ / Detour Logic      │
└──────────┬──────────┘
           │
           ▼
      Safe Route
```

---

## Repository Structure

```text
lib/
├── logic/
│   ├── geo_utils.dart
│   └── reroute_manager.dart
│
├── models/
│   └── flood_zone.dart
│
├── services/
│   ├── hazard_service.dart
│   └── osrm_routing_service.dart
│
├── screens/
│   └── map_screen.dart
│
├── providers.dart
└── main.dart
```

### `models/flood_zone.dart`

Defines the application's flood-zone model, including:

* Geometry
* Severity
* Source
* Timestamp
* Confidence/trust information

Flood reports can originate from either:

* `official`
* `crowdsourced`

Official sources are treated as more trusted when conflicting reports are encountered.

### `services/hazard_service.dart`

Responsible for communicating with the hazard backend.

Responsibilities include:

* Fetching hazards inside a bounding box
* Submitting crowdsourced reports
* Converting API responses into application models

### `services/osrm_routing_service.dart`

Communicates with OSRM and calculates routes.

The current implementation uses hazard-aware detour logic because the standard OSRM HTTP API does not directly provide arbitrary polygon exclusion.

For production, consider integrating hazard information directly into the routing engine.

### `logic/geo_utils.dart`

Contains geographic helper functions such as:

* Point-in-polygon testing
* Bounding-box calculations
* Centroid calculations
* Geographic distance utilities

### `logic/reroute_manager.dart`

Monitors the current route and hazard state.

It is responsible for:

1. Polling the hazard service
2. Detecting hazards affecting the current route
3. Applying confirmation thresholds
4. Triggering a reroute when necessary

### `screens/map_screen.dart`

The primary Flutter map interface.

It displays:

* User location
* Route geometry
* Flood zones
* Hazard severity
* Navigation controls

### `providers.dart`

Riverpod dependency injection and application configuration.

### `main.dart`

Flutter application entry point.

---

# Requirements

## Development Environment

Install:

* Flutter SDK
* Dart SDK compatible with the Flutter version used by the project
* Android Studio or Android SDK for Android builds
* Xcode for iOS builds
* Git

Verify the Flutter installation:

```bash
flutter doctor
```

Then install dependencies:

```bash
flutter pub get
```

---

# Configuration

## 1. Hazard Backend

The application requires a running hazard backend.

Configure:

```dart
const kHazardBackendUrl = 'https://api.example.com';
```

in:

```text
lib/providers.dart
```

Do **not** commit production credentials or private API endpoints containing secrets to source control.

For production, configuration should preferably come from build-time environment variables or a generated configuration file.

---

## 2. OSRM

For development, the project can use the public OSRM demonstration server.

For production, use a dedicated OSRM instance.

Example:

```text
https://routing.example.com
```

Configure the base URL in:

```text
lib/services/osrm_routing_service.dart
```

### Why self-host OSRM?

The public OSRM demonstration service is intended for demonstration and development rather than providing guaranteed production availability.

A production routing service should provide:

* Dedicated capacity
* Predictable performance
* Monitoring
* Rate control
* Geographic coverage appropriate to your users
* Independent uptime from third-party demo infrastructure

---

# OpenStreetMap Tiles

The application uses OpenStreetMap data.

During development, raster tiles may be configured using:

```text
https://tile.openstreetmap.org/{z}/{x}/{y}.png
```

However, production applications should use a dedicated tile provider or operate infrastructure appropriate for their expected traffic.

Potential providers include:

* MapTiler
* Stadia Maps
* Thunderforest
* Self-hosted tile infrastructure

Before production deployment, review the provider's current:

* Usage limits
* Attribution requirements
* Caching requirements
* Commercial-use policy
* SLA
* API-key requirements

The application must provide appropriate OpenStreetMap attribution where required.

---

# Hazard Backend API

The Flutter application expects the backend to expose the following API.

## Get Hazards

```http
GET /hazards?south={south}&west={west}&north={north}&east={east}
```

Example:

```http
GET /hazards?south=14.55&west=120.95&north=14.75&east=121.10
```

Response:

```json
{
  "hazards": [
    {
      "id": "flood-123",
      "severity": "impassable",
      "source": "official",
      "confidence": 0.95,
      "reportedAt": "2026-08-20T03:30:00Z",
      "geometry": {
        "type": "Polygon",
        "coordinates": [
          [
            [121.0001, 14.6001],
            [121.0101, 14.6001],
            [121.0101, 14.6101],
            [121.0001, 14.6101],
            [121.0001, 14.6001]
          ]
        ]
      }
    }
  ]
}
```

Coordinates should follow the standard GeoJSON convention:

```text
longitude, latitude
```

---

# Submit Crowdsourced Report

```http
POST /reports
Content-Type: application/json
```

Example:

```json
{
  "latitude": 14.5995,
  "longitude": 120.9842,
  "severity": "caution",
  "description": "Flood water approximately 20 cm deep",
  "reportedAt": "2026-08-20T03:45:00Z"
}
```

The backend should validate and sanitize reports before making them available to other users.

---

# Hazard Data Pipeline

The backend should act as the source of truth for flood information.

A recommended pipeline is:

```text
Official Flood Data
       │
       ▼
 Data Ingestion
       │
       ▼
 Normalization
       │
       ▼
 Validation ──────► Invalid Data
       │
       ▼
 Hazard Database
       │
       ├───────────────┐
       ▼               ▼
Flutter API       Internal Processing
       │
       ▼
 Mobile Application
```

Potential official sources may include:

* PAGASA
* Local government units
* Disaster risk reduction offices
* Other authorized government feeds

Do not assume that a website has a stable public API simply because its data is publicly viewable. Confirm the source's terms, access method, and redistribution permissions before integrating it.

---

# Flood Severity

The application currently defines two severity levels:

```text
caution
impassable
```

### `caution`

The route may continue through the affected area, but the user should receive a warning.

### `impassable`

The routing system should attempt to avoid the affected area.

---

# Flood Source Trust

Flood reports can originate from different sources.

```text
official
crowdsourced
```

Official reports should generally receive higher trust than unverified crowdsourced reports.

A production backend should additionally consider:

* Report age
* Number of independent reports
* Historical reliability
* Geographic consistency
* Duplicate reports
* Conflicting reports
* Sensor confidence
* Official confirmation

Do not rely on a single crowdsourced report to automatically classify a road as permanently impassable.

---

# Rerouting

The application periodically checks for changes to hazards affecting the active route.

The default development behavior is approximately:

```text
Every 30 seconds
        │
        ▼
Fetch hazards
        │
        ▼
Check route intersection
        │
        ├── No hazard ──► Continue
        │
        └── Hazard
              │
              ▼
        Confirmation logic
              │
              ▼
           Reroute
```

The current confirmation threshold should be treated as a tunable operational parameter rather than a permanent value.

Production deployments should tune:

* Polling interval
* Confirmation count
* Hazard expiration time
* Minimum confidence
* Route deviation threshold
* Rerouting frequency

These values should balance safety, network usage, battery consumption, and route stability.

---

# Routing Strategy

The current implementation uses a **detour/waypoint strategy** to work around flood polygons.

Conceptually:

```text
Original route
───────────────────────
          🌊🌊🌊
          🌊🌊🌊
───────────────────────

              ↓

        ┌───────────────┐
        │ Flood polygon │
        └───────────────┘

              ↓

Rerouted path
───────────────╮
               │
               │
               ╰────────────────
```

This is suitable as an initial implementation, but it is not equivalent to routing with true polygon-based edge exclusion.

## Recommended Production Architecture

For a mature deployment, integrate hazard information directly into the routing graph.

For example:

```text
OSM road network
       │
       ▼
 Routing graph
       │
       ├── Normal road
       ├── Caution road
       └── Flooded road
               │
               ▼
         Dynamic weights
               │
               ▼
        Route calculation
```

A custom routing profile or a routing engine designed for dynamic edge costs can provide more reliable hazard-aware routing than repeatedly adding detour waypoints.

---

# Security

The mobile application should never contain privileged backend credentials.

## Recommended

```text
Flutter app
    │
    │ public authenticated API
    ▼
API Gateway / Backend
    │
    ├── Authentication
    ├── Rate limiting
    ├── Validation
    ├── Abuse protection
    └── Hazard database
```

## Do not

Commit secrets into:

```text
lib/
android/
ios/
assets/
.env
```

or source control generally.

Use environment-specific configuration and a secure secret-management system for production infrastructure.

---

# Crowdsourced Report Protection

Crowdsourced reporting is an abuse-sensitive endpoint.

The backend should implement:

* Authentication or anonymous session controls
* Rate limiting
* Request validation
* Payload-size limits
* Duplicate detection
* Spam detection
* Report expiration
* Abuse monitoring
* Audit logging

Consider requiring multiple independent reports before automatically upgrading a hazard's severity.

---

# Database Recommendations

A production hazard backend should use a database capable of geographic queries.

PostgreSQL with PostGIS is a strong default:

```text
PostgreSQL
     +
PostGIS
```

A simplified schema could contain:

```text
hazards
├── id
├── geometry
├── severity
├── source
├── confidence
├── reported_at
├── expires_at
├── created_at
└── updated_at

reports
├── id
├── geometry
├── severity
├── description
├── source
├── submitted_at
└── status
```

Spatial indexes should be used for bounding-box and intersection queries.

---

# Local Development

Clone the repository:

```bash
git clone <repository-url>
cd <repository-directory>
```

Install dependencies:

```bash
flutter pub get
```

Run static analysis:

```bash
flutter analyze
```

Run tests:

```bash
flutter test
```

Run the application:

```bash
flutter run
```

---

# Production Build

## Android

Build an Android App Bundle:

```bash
flutter build appbundle --release
```

The resulting bundle can be submitted through the Google Play Console.

For production:

* Configure application signing
* Configure release keystore
* Set the production API endpoint
* Configure Android permissions
* Verify location permissions
* Verify background-location behavior if used
* Test on physical devices

---

## iOS

Build the iOS application:

```bash
flutter build ipa --release
```

Before distribution:

* Configure Apple signing
* Configure provisioning profiles
* Configure location permissions
* Configure App Store metadata
* Test background behavior
* Test GPS accuracy
* Test poor-network scenarios

---

# Location Permissions

The application requires location access to provide navigation based on the user's current position.

Request only the permissions actually required by the application.

If background location is implemented, clearly explain to users:

* Why background location is needed
* When it is collected
* How it is used
* How users can disable it

Follow the current Google Play and Apple App Store requirements for location permissions.

---

# Production Deployment

A recommended deployment consists of:

```text
                    Internet
                       │
                       ▼
                 Load Balancer
                       │
                       ▼
                Hazard API
                 ┌─────┴─────┐
                 │           │
                 ▼           ▼
             API Server   API Server
                 │           │
                 └─────┬─────┘
                       │
                       ▼
                PostgreSQL +
                  PostGIS
                       │
                       ▲
                       │
              Hazard ingestion
                       │
                       ▼
              Official sources
```

OSRM can be deployed separately:

```text
                    ┌──────────────┐
Flutter ───────────►│ Hazard API   │
   │                └──────────────┘
   │
   └────────────────►┌──────────────┐
                     │ OSRM Server  │
                     └──────────────┘
```

For higher availability, run multiple API and routing instances behind a load balancer.

---

# OSRM Self-Hosting

Download an appropriate OSM extract from a provider such as Geofabrik.

Then process it with OSRM.

A typical OSRM Docker workflow is conceptually:

```bash
docker pull osrm/osrm-backend
```

Prepare the OSM data using the appropriate OSRM preprocessing commands for the selected profile.

Then start the routing service:

```bash
docker run --rm -p 5000:5000 \
  osrm/osrm-backend \
  osrm-routed \
  --algorithm ch /data/region.osrm
```

The exact preprocessing and runtime commands depend on:

* OSRM version
* Routing profile
* OSM extract
* Deployment environment

For production, pin the OSRM image/version instead of relying on an unversioned image.

---

# Monitoring

Production deployments should monitor at least:

### Mobile

* Crash rate
* Location failures
* Routing failures
* API latency
* Reroute frequency
* Battery/network usage

### Backend

* Request rate
* HTTP error rate
* API latency
* Database latency
* Hazard ingestion failures
* Stale hazard data
* Invalid reports
* Authentication failures

### OSRM

* Route request latency
* CPU usage
* Memory usage
* Request failures
* Routing coverage
* Instance availability

---

# Logging

Avoid logging sensitive user information.

Logs should contain enough information to diagnose failures without unnecessarily storing:

* Exact user movement history
* Personal information
* Authentication tokens
* API credentials

Use structured logging in production.

Example:

```json
{
  "event": "route_request",
  "duration_ms": 184,
  "status": "success",
  "hazards_checked": 12
}
```

---

# Reliability Considerations

Flood conditions can change quickly and network connectivity may be unreliable.

The application should gracefully handle:

* No GPS signal
* No internet connection
* Hazard API downtime
* OSRM downtime
* Stale hazard data
* Invalid hazard geometry
* Routing failures
* Conflicting flood reports

A routing failure should **not** silently appear to the user as a successful safe route.

The UI should clearly distinguish between:

```text
Route confirmed
Route calculated with warnings
Route unavailable
Hazard data unavailable
Location unavailable
```

---

# Safety Considerations

This application should be treated as an **assistive navigation system**, not as an authoritative guarantee that a road is safe.

Flood conditions can change faster than the application's data refresh interval.

The application should communicate that:

> A route being displayed does not guarantee that the road is passable or safe.

Users should follow instructions from local authorities and emergency responders.

---

# Testing

Run Flutter tests:

```bash
flutter test
```

Run static analysis:

```bash
flutter analyze
```

At minimum, test:

### Geographic logic

* Point inside polygon
* Point outside polygon
* Polygon boundary
* Invalid polygon
* Multi-polygon hazards
* Bounding-box calculations

### Routing

* Normal route
* Route intersecting caution zone
* Route intersecting impassable zone
* No alternative route
* OSRM timeout
* OSRM unavailable

### Hazard updates

* New hazard
* Removed hazard
* Expired hazard
* Conflicting reports
* Official vs crowdsourced reports
* Duplicate reports

### Mobile

* GPS unavailable
* Network unavailable
* App backgrounding
* Device rotation
* Low battery
* Slow network

---

# Deployment Checklist

Before releasing to users:

* [ ] Configure production hazard backend
* [ ] Configure production OSRM instance
* [ ] Replace development OSM tile configuration
* [ ] Verify map attribution
* [ ] Configure production API URLs
* [ ] Configure application signing
* [ ] Configure location permissions
* [ ] Enable backend authentication/rate limiting
* [ ] Enable database backups
* [ ] Configure monitoring
* [ ] Configure error reporting
* [ ] Configure logging
* [ ] Test routing failures
* [ ] Test hazard API failures
* [ ] Test stale hazard data
* [ ] Test crowdsourced-report abuse controls
* [ ] Test poor GPS conditions
* [ ] Test poor network conditions
* [ ] Verify hazard-source permissions
* [ ] Review privacy policy
* [ ] Review terms of service
* [ ] Perform production load testing
* [ ] Perform security review
* [ ] Perform real-world navigation testing

---

# Environment Configuration

Use separate environments:

```text
development
    │
    ├── public/demo OSRM
    ├── development hazard API
    └── development database

staging
    │
    ├── staging OSRM
    ├── staging hazard API
    └── staging database

production
    │
    ├── production OSRM
    ├── production hazard API
    └── production database
```

Do not point development builds at production databases.

---

# Production Readiness

The Flutter client is designed to be extended into a production navigation system, but the following components remain deployment-specific:

| Component            | Development         | Production                      |
| -------------------- | ------------------- | ------------------------------- |
| Map tiles            | OSM tile server     | Dedicated tile provider         |
| Routing              | Public OSRM         | Self-hosted OSRM                |
| Hazard API           | Local/backend URL   | Scalable HTTPS API              |
| Hazard database      | Development DB      | PostgreSQL + PostGIS            |
| Flood ingestion      | Manual/test data    | Scheduled ingestion             |
| Crowdsourced reports | Basic API           | Auth + validation + rate limits |
| Monitoring           | Optional            | Required                        |
| Backups              | Optional            | Required                        |
| Secrets              | Local configuration | Secret manager                  |
| TLS                  | Development         | HTTPS required                  |
| Scaling              | Single instance     | Load-balanced                   |

---

# Roadmap

## Phase 1 — Prototype

* [x] Flutter map
* [x] OSM integration
* [x] OSRM integration
* [x] Flood-zone model
* [x] Hazard overlay
* [x] Basic rerouting
* [x] Riverpod architecture

## Phase 2 — Backend

* [ ] Hazard API
* [ ] PostgreSQL/PostGIS
* [ ] Official data ingestion
* [ ] Crowdsourced reports
* [ ] Authentication
* [ ] Rate limiting
* [ ] Hazard expiration

## Phase 3 — Production Routing

* [ ] Self-hosted OSRM
* [ ] Production OSM extract
* [ ] Routing monitoring
* [ ] Improved flood-edge detection
* [ ] Dynamic routing costs
* [ ] Improved alternative-route selection

## Phase 4 — Production Mobile

* [ ] Destination search
* [ ] Turn-by-turn navigation
* [ ] Voice guidance
* [ ] Background navigation
* [ ] Offline fallback
* [ ] Push hazard notifications
* [ ] Production analytics
* [ ] Crash reporting

---

# Contributing

1. Fork the repository.
2. Create a feature branch.

```bash
git checkout -b feature/my-feature
```

3. Make your changes.
4. Run formatting:

```bash
dart format .
```

5. Run analysis:

```bash
flutter analyze
```

6. Run tests:

```bash
flutter test
```

7. Commit your changes and open a pull request.

---

# License

Add the project's license here.

If the project combines OpenStreetMap data, OSRM, third-party map tiles, or external datasets, also review and comply with the licenses and attribution requirements applicable to each dependency.

---

# Disclaimer

This project is provided for navigation and flood-awareness purposes.

Flood information may be incomplete, delayed, inaccurate, or unavailable. Neither the application nor its routing system can guarantee that a road is safe or passable.

Users must exercise independent judgment and follow instructions issued by relevant authorities during flooding and other emergencies.

---

## Quick Start

```bash
git clone <repository-url>
cd <repository-directory>

flutter pub get

flutter analyze
flutter test

flutter run
```

Before deploying, configure:

```text
1. Production hazard API
2. Production OSRM
3. Production map tile provider
4. Location permissions
5. Application signing
6. Monitoring and error reporting
7. Database and hazard ingestion infrastructure
```

Once those services are configured, the Flutter application can be built for Android and iOS using the standard Flutter release tooling.
