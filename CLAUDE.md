# CLAUDE.md

Guidance for working in this repository.

## What this is

**RouteFuel** is an iOS (SwiftUI) MVP that plans a UK driving trip and recommends a single
cheap petrol stop along the route, then hands off to Google Maps with that stop inserted as a
waypoint. The app depends on a backend API (a Laravel service, not in this repo) for routing and
fuel-stop ranking. Destination search is handled **on-device** via Apple Maps `MKLocalSearch`.

Core flow: current location (origin) → search/select a UK destination → `POST /v1/routes` →
`POST /v1/fuel-stops/search` → show 1–3 ranked stops ("Best Stop" = `rank 1`) → select one →
open in Google Maps via `comgooglemaps://`.

`SPEC.md` is the authoritative product/behavior contract (validation, error codes, stale-data
rules, logging). `ROUTE_FUEL_SERVER_SPEC.md` is the backend API contract. When in doubt about
intended client behavior, defer to `SPEC.md`.

> Note: the code has grown slightly beyond `SPEC.md`'s fixed MVP — it also supports a
> user-selected origin (not just current location) and an Apple Maps launch option alongside
> Google Maps. Treat the spec as intent, the code as current reality.

## Layout

The Xcode project lives one level down at `RouteFuel/RouteFuel.xcodeproj`.

- `RouteFuel/RouteFuel/` — app sources
  - `RoutePlannerViewModel.swift` — `@MainActor` state machine: search, route, fuel-stop, retry, logging
  - `RoutePlannerModels.swift` — domain models + `ClientStateCode` / `APIErrorCode` / log enums
  - `Services.swift` — networking, response validators, polyline codec, location, maps launchers,
    `EndpointConfiguration`, and all service protocols + Live/Mock/Preview implementations
  - `Validators.swift` — destination-search result filtering / payload validation
  - `SearchView.swift`, `ResultsView.swift` — map-first SwiftUI screens; `ContentView.swift`, `BlockingMessageCard.swift`
  - `AppDependencies.swift` — DI container (`bootstrap` picks live vs UI-test deps)
  - `UITestSupport.swift` — stubbed services for UI tests
  - `Config.plist` — bundled server URL + auth token (see below)
- `RouteFuel/RouteFuelTests/` — unit tests; `RouteFuel/RouteFuelUITests/` — UI tests
- `VerificationArtifacts/` — named test-suite definitions referenced by `SPEC.md`

## Build / run / test

Scheme: `RouteFuel`. Targets: `RouteFuel`, `RouteFuelTests`, `RouteFuelUITests`.
**Deployment target is iOS 26.2** — the app only installs on iOS 26.2 simulators/devices.

```bash
cd RouteFuel

# Build for a booted iOS 26.2 simulator
xcodebuild -project RouteFuel.xcodeproj -scheme RouteFuel -configuration Debug \
  -destination 'id=<SIM_UDID>' -derivedDataPath /tmp/RouteFuelDD build

# Test
xcodebuild -project RouteFuel.xcodeproj -scheme RouteFuel \
  -destination 'id=<SIM_UDID>' test

# Install + launch on a booted simulator
xcrun simctl install <SIM_UDID> /tmp/RouteFuelDD/Build/Products/Debug-iphonesimulator/RouteFuel.app
xcrun simctl launch <SIM_UDID> com.traland.RouteFuel
```

When running the route flow, set the simulator origin to a UK coordinate or the route may look
nonsensical (the live backend is permissive and does **not** reject non-UK origins):

```bash
xcrun simctl location <SIM_UDID> set 51.5074,-0.1278   # London
```

## Server configuration (important)

`EndpointConfiguration.live()` (`Services.swift`) resolves the base URL/key in this order:

1. env vars `ROUTEFUEL_API_BASE_URL` / `ROUTEFUEL_API_KEY` (Xcode scheme can set these — they
   **override** the plist; check here first when the app hits the "wrong" server)
2. `Config.plist` → `AIServiceURL` / `AuthToken`
3. fallback `http://127.0.0.1:8080`

The auth token is sent as the `X-RouteFuel-Key` header.

`Config.plist` is the live/dev toggle:
- **prod / live**: `https://aiservices.traland.com/api/routefuel` (current committed value)
- **dev**: `http://devaiservices.traland.com/api/routefuel` — the dev origin's TLS cert is
  self-signed, so use **http** (the app's `NSAllowsArbitraryLoads` in `RouteFuel-App-Info.plist`
  permits it); dev resolves to a LAN host.

So "the app isn't reaching the intended server" is almost always a config/build issue (env override,
stale build, or `Config.plist` pointing at the other environment) — not a dead server. Endpoints are
`POST {base}/v1/routes` and `POST {base}/v1/fuel-stops/search`.

## Conventions / things to know

- **Strict response validation.** `RouteResponseValidator` / `FuelStopsResponseValidator`
  (`Services.swift`) reject any 200 payload with missing/undocumented keys, wrong JSON types,
  out-of-range numbers, bad polyline, rank discontinuity, etc. A valid-looking response that adds
  an extra field is treated as `INVALID_SUCCESS_RESPONSE`. Keep client and backend schemas in lockstep.
- **Service boundaries are protocols** (`*Servicing`, `MapsLaunching`, `ClientLogging`) with
  `Live*`, `Mock*`, and `Preview*` implementations. Inject through `AppDependencies`; prefer adding
  a new protocol-backed service over hard-coding dependencies in the view model.
- **UI-test mode:** launching with argument `ROUTEFUEL_UI_TEST_MODE` swaps in stubbed services
  (`AppDependencies.bootstrap` → `UITestSupport.swift`); no real network/location in UI tests.
- **The view model is `@MainActor`** and owns all flow/error/loading state. New user-facing error
  states should follow the existing `BlockingMessage` + `RetryAction` + structured `log(...)` pattern
  and the exact titles/bodies/codes in `SPEC.md` §7.
- **Client supplies the road geometry.** `LiveRouteService.calculateRoute` computes the driving
  route on-device via MapKit `MKDirections` (`calculateDisplayRoute`) **before** calling
  `POST /v1/routes`, and sends that encoded road polyline as the optional `routePolyline` field.
  The backend stores it and builds its fuel-stop corridor against the **real road** (not a straight
  line); the same MapKit geometry is what the app draws. If on-device routing yields nothing,
  `routePolyline` is omitted and the backend falls back to a straight origin→destination line.
- **Corridor width is server-tuned.** The backend echoes `rankingExplanation.routeCorridorMeters`
  (default 5000, set via `ROUTEFUEL_CORRIDOR_METERS`). The client validates it is a sane positive
  integer — it no longer hard-asserts `2000`. Note the coupling: a released client that pins a
  specific value will reject a different one, so change the prod value only alongside a client that
  accepts it.
- **Fuel brand filter (client-only).** `FuelBrand` (`RoutePlannerModels.swift`) derives a station's
  brand from its name (whole-word token match, so "BP" won't match inside words). `ResultsView`
  shows a brand badge per stop plus a chip row that filters `RoutePlannerViewModel.filteredStops`;
  the backend has no brand field, so this is purely a display-side filter over the ranked stops.
- **Coordinate formatting** for the Google Maps deep link is exact (6 decimals, no grouping) — see
  `Coordinate.googleMapsValue` and `SPEC.md` §7.7. Don't change formatting casually.

## Security note

`Config.plist` contains a real API token in plaintext and is tracked in git. The live backend's
`.env` also holds several production secrets. Don't add new secrets to the repo; prefer scheme env
vars or untracked config, and rotate anything that has been committed.
