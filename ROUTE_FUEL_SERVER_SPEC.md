# Server API Requirement Spec: RouteFuel MVP

## 1. Scope

This document defines the backend API contract for the RouteFuel MVP.

This server is responsible for:

1. Calculating a driving route between origin and destination in the United Kingdom.
2. Returning ranked route-based fuel stop recommendations for that route.
3. Enforcing the request, response, validation, error, ranking, geography, and performance rules described below.

This server is not responsible for:

1. Destination text search.
2. In-app navigation.
3. Multiple fuel stops per trip.
4. EV charging.
5. User accounts, saved trips, or payments.

## 2. Base Path

All RouteFuel API endpoints are prefixed with:

`/api/routefuel/abc`

The full MVP endpoints are therefore:

1. `POST /api/routefuel/abc/v1/routes`
2. `POST /api/routefuel/abc/v1/fuel-stops/search`

## 3. Fixed MVP Decisions

1. Geography: United Kingdom only.
2. Currency: GBP only.
3. Fuel type: regular petrol only.
4. Transport mode: driving only.
5. Ranking inputs: `priceMinorUnits` and `detourDurationSeconds` only.
6. Ranking execution: backend only.
7. Route corridor threshold: 2,000 meters from the route polyline.
8. Price freshness threshold: `priceTimestamp` no older than 24 hours at backend request time.
9. Missing or stale price data: excluded from recommendations.
10. `priceMinorUnits` is integer pence.
11. `routeId` minimum validity: at least 30 minutes from route creation time.
12. Unknown request fields are rejected with exact endpoint-specific codes.
13. Unknown success-response fields are invalid and must not be emitted.
14. Unknown error-response fields are invalid and must not be emitted.
15. A well-formed `routeId` that is expired, unknown, or otherwise unavailable must return `INVALID_ROUTE_ID`.
16. Route geometry uses encoded polyline format with precision `5` and latitude,longitude point order.
17. `detourDurationSeconds` means added driving time caused by inserting the station as a waypoint, excluding dwell time.

## 4. Common API Rules

1. All request and response bodies must use JSON.
2. All successful response bodies must be top-level JSON objects.
3. If a request body is malformed JSON, return HTTP `400` with `INVALID_JSON_BODY`.
4. If a request body is syntactically valid JSON but the top-level value is not an object, return HTTP `400` with `INVALID_JSON_BODY`.
5. All non-2xx responses must use the error envelope defined in Section 9.
6. Coordinate fields must be JSON numbers.
7. Any returned latitude must be in `[-90, 90]`.
8. Any returned longitude must be in `[-180, 180]`.
9. Integer fields must be encoded as JSON integers.
10. The backend may include an `X-Request-Id` response header.

## 5. Supported Geography

1. The sprint supports only trips and recommended fuel stops inside the United Kingdom.
2. The backend must classify whether a coordinate is inside supported geography using WGS84 point-in-polygon containment against versioned fixture `uk_boundary_v1`.
3. Included areas are England, Scotland, Wales, and Northern Ireland.
4. Excluded areas are the Republic of Ireland, Crown Dependencies, and all non-UK territory.
5. The same `uk_boundary_v1` fixture and rule must be used by backend implementation and API tests.

## 6. `POST /api/routefuel/abc/v1/routes`

### 6.1 Purpose

Calculate a driving route from current location to destination.

### 6.2 Request

```json
{
  "origin": {
    "lat": 51.5074,
    "lng": -0.1278
  },
  "destination": {
    "lat": 52.4862,
    "lng": -1.8904,
    "label": "Birmingham"
  },
  "mode": "driving"
}
```

### 6.3 Request Rules

1. After common JSON body checks pass, the top-level keys must be exactly `origin`, `destination`, `mode`.
2. `origin` keys must be exactly `lat`, `lng`.
3. `destination` keys must be exactly `lat`, `lng`, `label`.
4. `origin.lat`, `origin.lng`, `destination.lat`, and `destination.lng` are required numeric coordinates in valid ranges.
5. `destination.label` is required and must be a non-empty string after trimming.
6. `mode` is required and must equal `driving`.
7. If either origin or destination is outside supported geography under `uk_boundary_v1`, return `OUT_OF_SCOPE_GEOGRAPHY`.

### 6.4 Unknown Field Mapping

1. Any undocumented top-level field in the request body must return HTTP `400` with `INVALID_ROUTE_REQUEST_FIELDS`.
2. Any undocumented nested field inside `origin` must return HTTP `400` with `INVALID_ROUTE_REQUEST_FIELDS`.
3. Any undocumented nested field inside `destination` must return HTTP `400` with `INVALID_ROUTE_REQUEST_FIELDS`.
4. Unknown-field handling for this endpoint must not use fallback inference by field group.

### 6.5 Success Response

```json
{
  "routeId": "route_123",
  "distanceMeters": 203450,
  "durationSeconds": 9410,
  "polyline": "encoded_polyline",
  "polylineEncoding": "encoded_polyline",
  "polylinePrecision": 5,
  "bounds": {
    "northEast": { "lat": 52.6, "lng": -1.7 },
    "southWest": { "lat": 51.4, "lng": -0.2 }
  }
}
```

### 6.6 Success Rules

1. HTTP status must be `200`.
2. The response body must be a top-level JSON object.
3. Top-level keys must be exactly `routeId`, `distanceMeters`, `durationSeconds`, `polyline`, `polylineEncoding`, `polylinePrecision`, `bounds`.
4. `routeId` must be a non-empty string.
5. `distanceMeters` must be an integer greater than `0`.
6. `durationSeconds` must be an integer greater than `0`.
7. `polyline` must be a non-empty string.
8. `polylineEncoding` must equal `encoded_polyline`.
9. `polylinePrecision` must equal `5`.
10. `polyline` must be encoded using the Google Encoded Polyline Algorithm Format.
11. Decoding must use latitude,longitude point order and precision factor `10^5`.
12. The decoded polyline must contain at least 2 points.
13. Every decoded point must be within latitude and longitude valid ranges.
14. `bounds` must contain exactly `northEast` and `southWest`.
15. `bounds.northEast` and `bounds.southWest` must each contain exactly `lat` and `lng`.
16. Returned bound coordinates must be numeric and in valid ranges.
17. `bounds.northEast.lat >= bounds.southWest.lat`.
18. `bounds.northEast.lng >= bounds.southWest.lng`.
19. A successful `routeId` must remain valid for at least 30 minutes from route creation time.

### 6.7 Error Responses

1. HTTP `400` with `INVALID_JSON_BODY` for malformed JSON or non-object JSON body.
2. HTTP `400` with `INVALID_ROUTE_REQUEST_FIELDS` for any undocumented top-level or nested request field.
3. HTTP `400` with `INVALID_COORDINATES` for coordinate structure, missing-field, type, range, or null violations.
4. HTTP `400` with `INVALID_DESTINATION` for destination label structure, type, null, or emptiness violations.
5. HTTP `400` with `OUT_OF_SCOPE_GEOGRAPHY` when otherwise valid coordinates are outside supported geography.
6. HTTP `400` with `UNSUPPORTED_MODE` for mode structure, type, null, or enum violations.
7. HTTP `404` with `ROUTE_NOT_FOUND` when no route can be produced for otherwise valid inputs.
8. HTTP `503` with `UPSTREAM_PROVIDER_UNAVAILABLE` when a required upstream dependency fails.

## 7. `POST /api/routefuel/abc/v1/fuel-stops/search`

### 7.1 Purpose

Return ranked route-aware fuel stop recommendations for a route.

### 7.2 Request

```json
{
  "routeId": "route_123",
  "fuelType": "regular",
  "currency": "GBP",
  "maxRecommendedStops": 3
}
```

### 7.3 Request Rules

1. After common JSON body checks pass, the top-level keys must be exactly `routeId`, `fuelType`, `currency`, `maxRecommendedStops`.
2. `routeId` is required and must be a non-empty string.
3. `fuelType` is required and must equal `regular`.
4. `currency` is required and must equal `GBP`.
5. `maxRecommendedStops` is required and must be an integer from `1` to `3`.
6. `routeId` must reference an existing unexpired route.
7. If `routeId` is syntactically valid but does not reference an existing unexpired route, the backend must return HTTP `400` with `INVALID_ROUTE_ID`.

### 7.4 Unknown Field Mapping

1. Any undocumented top-level field in the request body must return HTTP `400` with `INVALID_FUEL_STOP_REQUEST_FIELDS`.
2. This endpoint has no documented nested request objects.
3. Unknown-field handling for this endpoint must not use fallback inference by field group.

### 7.5 Success Response

```json
{
  "recommendedStops": [
    {
      "stationId": "st_001",
      "name": "Shell Example",
      "address": "123 Example Rd",
      "countryCode": "GB",
      "location": { "lat": 51.9, "lng": -1.3 },
      "fuelType": "regular",
      "priceMinorUnits": 142,
      "currency": "GBP",
      "priceTimestamp": "2026-04-01T08:00:00Z",
      "distanceFromRouteMeters": 1100,
      "detourDurationSeconds": 360,
      "rank": 1,
      "score": 0.12,
      "isBestStop": true
    }
  ],
  "rankingExplanation": {
    "strategy": "weighted_price_and_detour",
    "priceWeight": 0.6,
    "detourWeight": 0.4,
    "detourDefinition": "added_driving_time_seconds_origin_to_station_to_destination_minus_origin_to_destination_excluding_dwell_time",
    "normalizationMethod": "min_max_eligible_set",
    "singleEligibleStationScore": 0.0,
    "equalValueComponentScore": 0.0,
    "scoreScale": "numeric_rounded_3dp",
    "routeCorridorMeters": 2000,
    "priceFreshnessHours": 24
  }
}
```

### 7.6 Success Rules

1. HTTP status must be `200`.
2. The response body must be a top-level JSON object.
3. Top-level keys must be exactly `recommendedStops` and `rankingExplanation`.
4. `recommendedStops` must be an array with length from `1` to `maxRecommendedStops`.
5. Every returned stop must contain exactly:
   - `stationId`
   - `name`
   - `address`
   - `countryCode`
   - `location`
   - `fuelType`
   - `priceMinorUnits`
   - `currency`
   - `priceTimestamp`
   - `distanceFromRouteMeters`
   - `detourDurationSeconds`
   - `rank`
   - `score`
   - `isBestStop`
6. `stationId`, `name`, and `address` must be non-empty strings.
7. `countryCode` must equal `GB`.
8. `location` must contain exactly `lat` and `lng`, both numeric and in valid ranges.
9. `fuelType` must equal `regular`.
10. `currency` must equal `GBP`.
11. `priceMinorUnits` must be an integer greater than or equal to `0`.
12. `priceTimestamp` must be an RFC 3339 UTC timestamp string ending in `Z`.
13. `distanceFromRouteMeters` must be an integer greater than or equal to `0`.
14. `detourDurationSeconds` must be an integer greater than or equal to `0`.
15. `detourDurationSeconds` must represent the added driving time introduced by inserting the station as a waypoint into the trip, excluding fueling dwell time.
16. `score` must be a JSON number in `[0, 1]` numerically equal to `rawScore` rounded to 3 decimal places.
17. `recommendedStops` must be sorted by ascending `rank`.
18. `rank` must start at `1` and increment by `1` without gaps.
19. `stationId` values must be unique within `recommendedStops`.
20. Exactly one stop must have `rank = 1`.
21. The only stop with `rank = 1` must also be the only stop with `isBestStop = true`.
22. Every stop with `rank > 1` must have `isBestStop = false`.
23. `rankingExplanation` must contain exactly:
   - `strategy`
   - `priceWeight`
   - `detourWeight`
   - `detourDefinition`
   - `normalizationMethod`
   - `singleEligibleStationScore`
   - `equalValueComponentScore`
   - `scoreScale`
   - `routeCorridorMeters`
   - `priceFreshnessHours`
24. `rankingExplanation.strategy` must equal `weighted_price_and_detour`.
25. `rankingExplanation.priceWeight` must equal `0.6`.
26. `rankingExplanation.detourWeight` must equal `0.4`.
27. `rankingExplanation.detourDefinition` must equal `added_driving_time_seconds_origin_to_station_to_destination_minus_origin_to_destination_excluding_dwell_time`.
28. `rankingExplanation.normalizationMethod` must equal `min_max_eligible_set`.
29. `rankingExplanation.singleEligibleStationScore` must equal `0.0`.
30. `rankingExplanation.equalValueComponentScore` must equal `0.0`.
31. `rankingExplanation.scoreScale` must equal `numeric_rounded_3dp`.
32. `rankingExplanation.routeCorridorMeters` must equal `2000`.
33. `rankingExplanation.priceFreshnessHours` must equal `24`.

### 7.7 Error Responses

1. HTTP `400` with `INVALID_JSON_BODY` for malformed JSON or non-object JSON body.
2. HTTP `400` with `INVALID_FUEL_STOP_REQUEST_FIELDS` for any undocumented top-level request field.
3. HTTP `400` with `INVALID_ROUTE_ID` for route ID structure, missing-field, type, emptiness, or null violations, and for a syntactically valid `routeId` that is expired, unknown, or otherwise does not reference an existing unexpired route.
4. HTTP `400` with `UNSUPPORTED_FUEL_TYPE` for fuel type structure, type, null, missing, or enum violations.
5. HTTP `400` with `INVALID_CURRENCY` for currency structure, type, null, missing, or enum violations.
6. HTTP `400` with `INVALID_MAX_RECOMMENDED_STOPS` for stop-count structure, type, null, missing, or range violations.
7. HTTP `404` with `NO_STATIONS_FOUND` when no eligible stations exist.
8. HTTP `503` with `UPSTREAM_PROVIDER_UNAVAILABLE` when a required upstream dependency fails.

## 8. Deterministic Ranking And Detour Algorithm

1. Let `baselineDurationSeconds` equal the driving duration in whole seconds for the successful route returned by `POST /api/routefuel/abc/v1/routes`, from origin to destination, using the same routing provider, driving mode, and routing snapshot used to generate that route.
2. For each candidate station, let `waypointDurationSeconds` equal the driving duration in whole seconds for the route from the same origin to the same destination with that station inserted as a single waypoint, using the same routing provider, driving mode, and routing snapshot as the baseline route.
3. Compute `detourDurationSeconds = max(0, waypointDurationSeconds - baselineDurationSeconds)`.
4. `detourDurationSeconds` excludes any fueling dwell time, parking time, or user stop duration. It represents driving-time increase only.
5. Build the eligible candidate set for the route by applying all of these filters before scoring:
   - station is within 2,000 meters of the route polyline
   - station is inside supported geography under `uk_boundary_v1`
   - station `countryCode = GB`
   - station has `priceTimestamp` no older than 24 hours at backend request time
   - station has non-null `priceMinorUnits` and non-null `detourDurationSeconds`
6. Compute normalization inputs using only the eligible candidate set for that route, including candidates not returned because of `maxRecommendedStops`.
7. Let:
   - `minPrice = minimum(priceMinorUnits)` across the eligible candidate set
   - `maxPrice = maximum(priceMinorUnits)` across the eligible candidate set
   - `minDetour = minimum(detourDurationSeconds)` across the eligible candidate set
   - `maxDetour = maximum(detourDurationSeconds)` across the eligible candidate set
8. Compute `normalizedPrice` for each eligible station as:
   - `0.0` if `maxPrice = minPrice`
   - otherwise `(priceMinorUnits - minPrice) / (maxPrice - minPrice)`
9. Compute `normalizedDetour` for each eligible station as:
   - `0.0` if `maxDetour = minDetour`
   - otherwise `(detourDurationSeconds - minDetour) / (maxDetour - minDetour)`
10. If there is exactly one eligible station, both normalized components for that station must be `0.0`.
11. Compute `rawScore = 0.6 * normalizedPrice + 0.4 * normalizedDetour`.
12. Compute returned `score` as the JSON number equal to `rawScore` rounded to 3 decimal places using round-half-up.
13. Rank stations by ascending `rawScore`.
14. Resolve ties in this exact order:
   - lower `priceMinorUnits`
   - lower `detourDurationSeconds`
   - lexicographically smaller `stationId`
15. Return the first `maxRecommendedStops` stations after ranking.
16. Assign returned `rank` values from `1` upward in returned order.
17. Set `isBestStop = true` only on the returned stop with `rank = 1`.

## 9. Error Envelope

All non-2xx API responses must use:

```json
{
  "error": {
    "code": "NO_STATIONS_FOUND",
    "message": "No fuel stations were found near the route."
  }
}
```

Rules:

1. The body must be a top-level JSON object.
2. The body must contain exactly one top-level key: `error`.
3. `error` must be a non-null object.
4. `error` must contain exactly `code` and `message`.
5. `error.code` must be a non-empty string and one of:
   - `INVALID_JSON_BODY`
   - `INVALID_ROUTE_REQUEST_FIELDS`
   - `INVALID_COORDINATES`
   - `INVALID_DESTINATION`
   - `OUT_OF_SCOPE_GEOGRAPHY`
   - `UNSUPPORTED_MODE`
   - `ROUTE_NOT_FOUND`
   - `INVALID_FUEL_STOP_REQUEST_FIELDS`
   - `INVALID_ROUTE_ID`
   - `UNSUPPORTED_FUEL_TYPE`
   - `INVALID_CURRENCY`
   - `INVALID_MAX_RECOMMENDED_STOPS`
   - `NO_STATIONS_FOUND`
   - `UPSTREAM_PROVIDER_UNAVAILABLE`
6. `error.message` must be a non-empty string after trimming.

## 10. Performance Requirement

Deterministic performance requirement for `POST /api/routefuel/abc/v1/fuel-stops/search`:

1. Measured metric: server-side application-processing time only.
2. Fixed dataset: `performance_route_fixture_v1` with 1 route and 500 station records, of which 120 are eligible.
3. Fixed environment: `performance_env_v1` single backend instance with 2 vCPU, 4 GB RAM, no debug instrumentation, warm process, and local in-memory fixture data.
4. Fixed concurrency: 8 parallel requests.
5. Fixed run length: 200 total successful requests collected after 20 warm-up requests.
6. Pass threshold: p95 application-processing time under 3,000 ms across the 200 measured requests.

## 11. Upstream Fuel Data Source Requirements

The RouteFuel backend must use the UK government Fuel Finder service as the primary upstream source for forecourt and fuel price data.

### 11.1 Source

1. Primary upstream source: Fuel Finder Public API operated by the UK government.
2. The API covers filling stations in the United Kingdom.
3. The API provides:
   - current retail prices by fuel grade
   - forecourt details including address, operator, and brand
   - site amenities and opening hours
   - update timestamps for price and site data
4. Fuel Finder documentation states data is updated within 30 minutes of any changes.

### 11.2 Authentication

1. Access to the Fuel Finder API requires OAuth 2.0 client credentials.
2. The backend must perform OAuth on the server side only.
3. Client secret and access token values must never be exposed to the iOS app.
4. The backend must request and use the minimum required scope for read access.
5. Example documented token request format:

```text
POST <token-endpoint>
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials&client_id=YOUR_CLIENT_ID&client_secret=YOUR_CLIENT_SECRET&scope=fuelfinder.read
```

6. Example documented token response shape:

```json
{
  "access_token": "eyJhbGciOi...",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

7. The backend must send the access token in the `Authorization: Bearer <token>` header for Fuel Finder API calls.

### 11.3 Read Integration Model

1. The RouteFuel backend must retrieve upstream data by issuing authenticated `GET` requests to Fuel Finder read endpoints.
2. Public Fuel Finder documentation shows example read paths under `/v1/prices`, including:
   - `GET /v1/prices/GB-12345`
   - `GET /v1/prices?fuel_type=unleaded`
3. Exact upstream resource inventory and query parameter rules must be finalized against the authenticated Fuel Finder API specification during implementation.
4. The backend must normalize upstream records into the internal station model used for route ranking.

### 11.4 Mapping Requirements

The backend must map upstream Fuel Finder data into internal station records sufficient to support the RouteFuel contract:

1. A unique station identifier.
2. Station name or brand.
3. Address.
4. Country code.
5. Latitude and longitude.
6. Fuel grade prices.
7. Price update timestamp.
8. Any optional metadata used for operational filtering, diagnostics, or enrichment.

For RouteFuel MVP ranking:

1. The backend must derive `priceMinorUnits` for regular petrol from the Fuel Finder grade representing standard unleaded petrol.
2. If the upstream source does not provide a valid current regular-petrol price for a station, that station is ineligible for RouteFuel recommendations.
3. If upstream country or location data is missing or invalid, that station is ineligible.
4. Upstream amenities and opening-hours data may be stored, but they must not affect MVP ranking.

### 11.5 Freshness And Caching

1. The backend must ensure returned station prices satisfy the RouteFuel freshness rule: `priceTimestamp` no older than 24 hours at RouteFuel request time.
2. Fuel Finder developer guidance recommends:
   - station data cache: 1 hour
   - price data cache: 15 minutes
3. The backend may cache upstream responses, but caching must not cause RouteFuel to return prices older than the 24-hour contract limit.
4. If the backend uses a local materialized store, it must preserve upstream update timestamps needed to enforce freshness rules.

### 11.6 Rate Limits And Concurrency

Fuel Finder developer guidance states:

1. Live environment limit: 30 requests per minute per client.
2. Live environment concurrency: 1 concurrent request allowed per client.
3. Exceeding limits may return HTTP `429`.

RouteFuel backend requirements:

1. The backend must not depend on per-user synchronous upstream calls for every app request if doing so risks violating Fuel Finder rate limits.
2. The backend should prefer cached or pre-ingested upstream data for route ranking.
3. The backend must implement retry with backoff for transient upstream failures where appropriate.
4. If required upstream data cannot be obtained or refreshed safely, RouteFuel must return `UPSTREAM_PROVIDER_UNAVAILABLE`.

### 11.7 Operational Security

1. Fuel Finder client credentials must be stored in environment variables or a secure secrets manager.
2. Credentials must not be committed to source control.
3. Access tokens and client secrets must not be logged.
4. Separate credentials must be used for test and production environments.
5. All upstream calls must use HTTPS.

### 11.8 Fallback

1. RouteFuel MVP should treat Fuel Finder as the authoritative upstream source.
2. Any fallback to older retailer-hosted JSON feeds or other non-Fuel Finder sources must be explicitly approved as a product decision.
3. If fallback sources are used, they must be normalized into the same internal station model and remain subject to all RouteFuel validation, geography, and freshness rules.

## 12. Backend Test Requirements

The backend must have deterministic API coverage for:

1. Malformed JSON and non-object JSON handling.
2. Exact unknown-field-to-error-code mapping.
3. Route success schema correctness.
4. Fuel-stop success schema correctness.
5. Error envelope correctness for every non-2xx response.
6. `routeId` validity for at least 30 minutes.
7. `INVALID_ROUTE_ID` handling for malformed, expired, and unknown route IDs.
8. UK geography enforcement using `uk_boundary_v1`.
9. Route polyline format and decodability.
10. Corridor filtering correctness.
11. Price freshness cutoff correctness.
12. Detour calculation correctness.
13. Ranking normalization, scoring, rounding, and tie-break correctness.
14. Performance verification under the fixed workload.

## 13. Definition Of Done

The server side is done when:

1. Both prefixed endpoints are implemented exactly as documented.
2. All request validation and error mappings are exact.
3. All success payloads are closed-world and contain no undocumented fields.
4. Ranking behavior is deterministic and matches Section 8 exactly.
5. Geography validation uses the shared immutable fixture `uk_boundary_v1`.
6. `routeId` lifecycle behavior matches this contract.
7. All deterministic API and performance checks pass.
