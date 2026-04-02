# RouteFuel Handoff

## Current State

The iOS app has been moved to a map-first layout.

Implemented changes:

1. Destination search now uses Apple Maps `MKLocalSearch` instead of the old local `/destination-search` dependency.
2. The Search screen is now map-dominant, with search controls and result cards overlaid on the map.
3. The Results screen is also map-dominant, with route and stop selection controls overlaid on the map.
4. A standalone backend contract document was added in `SERVER_SPEC.md`.

Build status:

1. `xcodebuild build -project RouteFuel/RouteFuel.xcodeproj -scheme RouteFuel -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/RouteFuelDerivedData` succeeds.
2. Simulator-backed UI tests could not be run in this environment because `CoreSimulatorService` was unavailable.

## Important Backend Status

The UK government Fuel Finder API exists, but the endpoint integration is not ready for backend implementation yet.

Current situation:

1. We have confirmed the Fuel Finder service, OAuth 2.0 client-credentials auth model, and rate-limit guidance.
2. Public documentation is not sufficient to lock the final RouteFuel ingestion implementation.
3. We do not yet have a finalized, implementation-ready upstream endpoint contract for pulling forecourt and fuel-price data into the backend.
4. Because of that, the RouteFuel backend should not yet be built around a hardcoded Fuel Finder ingestion workflow.

## What `SERVER_SPEC.md` Means Right Now

`SERVER_SPEC.md` now includes Fuel Finder as the intended primary upstream source, but that should be treated as an architectural direction, not a fully executable integration plan yet.

Use it as:

1. the RouteFuel public API contract for the iOS app
2. the ranking and validation contract for the backend
3. a placeholder upstream-source direction pending final Fuel Finder endpoint readiness

Do not assume:

1. exact upstream Fuel Finder paths are finalized
2. exact upstream response schema is finalized
3. ingestion frequency and storage model are locked

## Recommended Next Steps

### iOS

1. Keep the current Apple Maps destination search path.
2. Polish the map-first UI:
   - draggable bottom sheets
   - show all recommended stops on the result map
   - improve Apple Maps result labeling
3. Re-run UI tests in a working simulator environment.

### Backend

1. Build the RouteFuel public API surface first:
   - `POST /api/routefuel/abc/v1/routes`
   - `POST /api/routefuel/abc/v1/fuel-stops/search`
2. Keep the fuel-station data source abstracted behind an internal provider interface.
3. Stub or fixture the fuel-station repository while Fuel Finder endpoint details are still pending.
4. Implement ranking, validation, error mapping, and test coverage independently of live Fuel Finder ingestion.
5. Plug in Fuel Finder later when the upstream endpoint contract is ready.

## Suggested Backend Abstraction

Use an internal boundary like:

1. `RouteProvider`
2. `FuelStationRepository`
3. `FuelPriceSource`
4. `RouteRankingService`

This avoids coupling the RouteFuel public API to a not-yet-final Fuel Finder upstream integration.

## Known Technical Notes

1. The Apple Maps destination search implementation currently builds with an iOS 26 SDK deprecation warning around `MKMapItem.placemark`.
2. This is not blocking, but it should be updated to the newer MapKit API in a cleanup pass.
3. The app currently still depends on the RouteFuel backend for:
   - route calculation
   - fuel-stop recommendations
4. Only destination search was decoupled from backend search.

## Files To Review First

1. `SPEC.md`
2. `SERVER_SPEC.md`
3. `RouteFuel/RouteFuel/SearchView.swift`
4. `RouteFuel/RouteFuel/ResultsView.swift`
5. `RouteFuel/RouteFuel/Services.swift`
6. `RouteFuel/RouteFuel/AppDependencies.swift`
