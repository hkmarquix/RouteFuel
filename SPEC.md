# Sprint Contract: iOS Route-Based Fuel Stop Planner MVP

## 1. Header

- Status: Revised Draft
- Author: Project Manager
- Date: 2026-04-01
- Target: iOS app and backend API contract
- Sprint Goal: ship one deterministic MVP flow that lets a user select a United Kingdom destination, receive ranked route-based fuel stop recommendations, and open Google Maps with the selected stop inserted between origin and destination

## 2. Scope

This sprint covers one end-to-end trip-planning flow only:

1. Use current device location as trip origin.
2. Let the user search for a destination by text and select one resolved United Kingdom result.
3. Calculate one driving route from origin to destination.
4. Request ranked fuel stop recommendations for that route.
5. Show 1 to 3 recommended stops.
6. Let the user select one recommended stop.
7. Open Google Maps with origin, selected stop waypoint, and destination.
8. Define the destination-search provider adapter contract required by the iOS client.
9. Define the backend API contract required by the iOS client.

## 3. Out Of Scope

The following are not part of this sprint:

1. Backend infrastructure, deployment, and provider implementation details
2. In-app turn-by-turn navigation
3. More than one fuel stop per trip
4. EV charging
5. User accounts, saved trips, favorites, or history
6. In-app payments or loyalty features
7. CarPlay
8. Apple Maps handoff
9. Alternate navigation apps when Google Maps is unavailable
10. Personalized ranking
11. Multiple countries, currencies, or fuel types
12. Client-side reranking of backend results
13. Manual QA as the only proof of any in-scope requirement

## 4. Fixed MVP Decisions

To keep scope minimal and testable, MVP is fixed to:

1. Geography: United Kingdom only
2. Currency: GBP only
3. Fuel type: regular petrol only
4. Transport mode: driving only
5. Origin: current device location only
6. Destination: one selected place only
7. Recommendation count: 1 to 3 stops
8. Ranking inputs: `priceMinorUnits` and `detourDurationSeconds` only
9. Ranking execution: backend only
10. Route corridor threshold: 2,000 meters from the route polyline
11. Price freshness threshold: `priceTimestamp` no older than 24 hours at backend request time
12. Missing or stale price data: excluded from recommendations
13. API price field: `priceMinorUnits` integer pence
14. Displayed price format: GBP with exactly 2 decimal places
15. Displayed detour format: `floor(detourDurationSeconds / 60)` whole minutes
16. Google Maps unavailable behavior: blocking error on Results Screen, retry allowed, no fallback app
17. `routeId` minimum validity: at least 30 minutes from route creation time
18. Unknown request fields are rejected with exact endpoint-specific codes defined in Sections 10.2 and 10.3
19. Unknown success-response fields are invalid response data
20. Unknown error-response fields are invalid error data
21. `rank = 1` is the sole source of truth for the top recommendation, and `isBestStop` must match it
22. Ranking normalization uses only the eligible candidate set for the current route
23. `score` is a JSON number equal to `rawScore` rounded to 3 decimal places using round-half-up
24. Malformed JSON request bodies and syntactically valid non-object JSON request bodies use the shared API error code `INVALID_JSON_BODY`
25. Retry UX is defined uniformly by Section 7.8
26. Destination search is an explicit adapter contract defined in Section 9
27. The Search Screen owns all route-request loading UI, route-request error UI, and route-request logging before route success
28. Invalid route success payload handling uses the same stale-state rule as other route failures
29. Invalid fuel-stop success payload handling uses the same stale-state rule as other fuel-stop failures
30. Invalid API error payload handling uses the endpoint-specific stale-state rules in Section 7.10
31. Destination-search responses are renderable only if they still match the latest submitted query state under Section 7.1
32. Performance verification is limited to the deterministic suite defined in Sections 8.1 and 13.4
33. A well-formed `routeId` that is expired, unknown, or otherwise unavailable must return the exact backend error mapping defined in Section 10.3
34. The route geometry contract is the encoded polyline algorithm format defined in Section 10.2, with precision 5 and latitude,longitude point order
35. A route success payload is invalid unless its `polyline` decodes into at least 2 valid coordinate points under Section 7.9
36. `detourDurationSeconds` means added driving time caused by inserting the station as a waypoint, excluding any fueling dwell time, exactly as defined in Section 10.4

## 5. Problem Statement

Drivers currently combine navigation and fuel-price tools manually. They plan a route in one app, search for stations in another, estimate which stations are acceptably close to the route, compare prices, and then restart navigation with a stop added.

The MVP must reduce that manual work by giving the user a route-aware fuel recommendation flow with deterministic ranking and a direct Google Maps handoff.

## 6. User Flow

1. User opens the app.
2. App requests location permission.
3. User enters destination text on the Search Screen.
4. User submits a destination search.
5. App requests destination-search results from the provider adapter.
6. App immediately clears any previously displayed destination results, search zero-results state, and retryable search error state.
7. App shows search loading, filtered results, zero-results, or search-error state.
8. User selects one resolved UK destination result from the rendered results.
9. App enables route calculation only after a resolved UK result is selected.
10. If destination text changes after selection, the app immediately clears the selected result and disables route calculation.
11. If destination text changes while a destination-search request is still in flight, the app keeps the newer text, leaves route calculation disabled, and must not render the later-arriving stale response.
12. User starts route calculation from the Search Screen.
13. App acquires current location.
14. If current location is unavailable, app sends no route request and shows a retryable blocking error on the Search Screen.
15. If current location is available, app sends `POST /v1/routes` and keeps route loading and route error ownership on the Search Screen until route success.
16. If route succeeds, app navigates to or renders the Results Screen, validates the geometry payload, renders route summary and route polyline, then sends `POST /v1/fuel-stops/search`.
17. If fuel-stop search succeeds, app renders 1 to 3 recommended stops and labels the top stop `Best Stop`.
18. No stop is selected by default.
19. User selects one recommended stop.
20. App shows exactly one `Open in Google Maps` CTA.
21. User taps `Open in Google Maps`.
22. App generates the canonical Google Maps deep link and calls the OS open-URL API once.
23. If the deep link cannot be opened, app remains on the Results Screen and shows a retryable blocking error.

## 7. Functional Requirements

### 7.1 Destination Search And Selection

1. The app must provide destination text search on the Search Screen.
2. The app must send exactly one destination-search provider request for each explicit destination-search user action.
3. The app must not send a destination-search provider request for an empty trimmed query.
4. When a new destination search starts, the app must immediately clear all prior destination-search derived UI from any earlier search:
   - rendered destination results
   - prior selected destination result
   - route-calculation enabled state
   - prior zero-results state
   - prior retryable search error state
5. While destination search is in flight, the app must show visible loading text `Searching destinations...`.
6. While destination search is in flight, prior rendered destination results, prior zero-results state, and prior retryable search error state must not remain visible.
7. While destination search is in flight, additional destination-search submit actions and retry taps must be ignored.
8. The provider payload may contain a mix of valid, malformed, and out-of-scope result items.
9. The app must evaluate each returned result item independently before rendering it.
10. A rendered selectable result must include non-null `label`, `location.lat`, `location.lng`, and `countryCode`.
11. `label` must be a non-empty string after trimming.
12. `location.lat` must be a number in `[-90, 90]`.
13. `location.lng` must be a number in `[-180, 180]`.
14. `countryCode` must equal `GB`.
15. Only result items that satisfy items 10 to 14 may be rendered.
16. Malformed result items and out-of-scope result items must be filtered out before display and must not be rendered, disabled, or tappable.
17. Route calculation must remain disabled until the user selects one rendered resolved UK result.
18. Unresolved freeform text must not be used as destination coordinates.
19. If the provider returns zero selectable results after filtering, the app must show:
   - title: `No destinations found`
   - body text: `Try a different search.`
   - no retry action
20. If the provider request fails, the app must show:
   - title: `Search unavailable`
   - body text: `Destination search is temporarily unavailable. Try again.`
   - retry action labeled `Retry`
21. If the provider returns a payload that violates Section 9 at the top level, the app must:
   - render no results from that payload
   - log `INVALID_DESTINATION_SEARCH_RESPONSE`
   - show title: `Search unavailable`
   - show body text: `Destination search is temporarily unavailable. Try again.`
   - show retry action labeled `Retry`
22. After zero results, provider failure, or invalid provider response, the user must be able to issue a new destination search from the same screen.
23. If destination text changes after a result has been selected, the app must immediately:
   - clear the selected result
   - disable route calculation
   - prevent any future route request from using the previously selected coordinates
24. Each destination-search request must capture the exact trimmed query string used to issue that request.
25. A destination-search response is current only if both are true when it is received:
   - its captured request query equals the latest submitted destination-search query still owned by the screen
   - the current destination text, after trimming, still equals that same query
26. If a destination-search response is not current under item 25, the app must discard it completely:
   - render no results from that response
   - show no zero-results or search-error state from that response
   - keep route calculation disabled unless a valid selection already exists from the latest current query
27. If destination text changes while a destination-search request is in flight, the app must:
   - immediately clear any prior selected result
   - disable route calculation
   - preserve the edited text
   - prevent the in-flight older response from rendering unless item 25 is still satisfied when it returns

### 7.2 Location

1. The app must use the device's current location as origin.
2. If location permission is denied, route planning must be blocked and no route request may be sent.
3. The location-denied state must show:
   - title: `Location required`
   - body text: `Current location is required to plan a route.`
   - no retry action
4. After permission is granted, the app must attempt to acquire current location before each route request.
5. Current-location acquisition timeout is 10 seconds.
6. If current location cannot be obtained because services are off, accuracy is unavailable, or the timeout expires, the app must:
   - send no route request
   - show title: `Current location unavailable`
   - show body text: `Current location is temporarily unavailable. Try again.`
   - show retry action labeled `Retry`
7. Tapping `Retry` from `Current location unavailable` must trigger exactly one new current-location acquisition attempt.
8. A retried acquisition attempt may send a route request only if location acquisition succeeds.

### 7.3 Supported Geography

1. The sprint supports only trips and recommended fuel stops inside the United Kingdom.
2. The client must block route calculation unless the selected destination is a resolved UK result under Section 7.1.
3. The backend must classify whether a coordinate is inside supported geography using WGS84 point-in-polygon containment against versioned fixture `uk_boundary_v1`.
4. Included areas are England, Scotland, Wales, and Northern Ireland.
5. Excluded areas are the Republic of Ireland, Crown Dependencies, and all non-UK territory.
6. The same `uk_boundary_v1` fixture and rule must be used by backend implementation and API tests.

### 7.4 Route Request Behavior And Stale Data Rules

1. The Search Screen is the sole owner of route loading UI, route error UI, and route logging until a route response succeeds.
2. The app must send exactly one `POST /v1/routes` request for each route-calculation user action.
3. The app must not send any fuel-stop request until the route request succeeds.
4. While `POST /v1/routes` is in flight, the app must show visible loading text `Calculating route...` on the Search Screen.
5. While `POST /v1/routes` is in flight, additional route-start taps and retry taps must be ignored.
6. When a new route request starts, the app must immediately clear all prior results-screen derived data from any earlier route:
   - route summary
   - route polyline
   - recommendation cards
   - selected stop state
   - `Open in Google Maps` CTA
   - prior route or fuel-stop error banner
7. If the route request succeeds, the app must validate the payload under Section 7.9 before rendering the route. If validation succeeds, the app must navigate to or render the Results Screen, render the returned route summary and decoded route polyline there, then start fuel-stop search.
8. If the route request fails, including invalid success payload handling and invalid error payload handling under Sections 7.9 and 7.10, the app must remain on the Search Screen and render no stale route summary, no stale polyline, no stale recommendations, no selected stop, and no `Open in Google Maps` CTA.
9. If `POST /v1/routes` returns HTTP `400` with `INVALID_JSON_BODY`, the app must:
   - show title: `Route request invalid`
   - show body text: `The route request was invalid.`
   - show no retry action
   - remain on the Search Screen
   - keep no route summary, no polyline, no recommendations, no selected stop, and no CTA visible
10. If `POST /v1/routes` returns HTTP `400` with `INVALID_ROUTE_REQUEST_FIELDS`, the app must:
    - show title: `Route request invalid`
    - show body text: `The route request fields were invalid.`
    - show no retry action
    - remain on the Search Screen
    - keep no route summary, no polyline, no recommendations, no selected stop, and no CTA visible
11. If `POST /v1/routes` returns HTTP `400` with `INVALID_COORDINATES`, the app must:
    - show title: `Route request invalid`
    - show body text: `The route request used invalid coordinates.`
    - show no retry action
    - remain on the Search Screen
    - keep no route summary, no polyline, no recommendations, no selected stop, and no CTA visible
12. If `POST /v1/routes` returns HTTP `400` with `INVALID_DESTINATION`, the app must:
    - show title: `Destination unavailable`
    - show body text: `Choose a different destination.`
    - show no retry action
    - remain on the Search Screen
    - keep no route summary, no polyline, no recommendations, no selected stop, and no CTA visible
13. If `POST /v1/routes` returns HTTP `400` with `OUT_OF_SCOPE_GEOGRAPHY`, the app must:
    - show title: `Route out of scope`
    - show body text: `Current location and destination must both be in the United Kingdom.`
    - show no retry action
    - remain on the Search Screen
    - keep no route summary, no polyline, no recommendations, no selected stop, and no CTA visible
14. If `POST /v1/routes` returns HTTP `400` with `UNSUPPORTED_MODE`, the app must:
    - show title: `Route request invalid`
    - show body text: `The route request used an unsupported mode.`
    - show no retry action
    - remain on the Search Screen
    - keep no route summary, no polyline, no recommendations, no selected stop, and no CTA visible
15. If `POST /v1/routes` returns HTTP `404` with `ROUTE_NOT_FOUND`, the app must:
    - show title: `Route unavailable`
    - show body text: `A route could not be found for this destination.`
    - show no retry action
    - remain on the Search Screen
    - keep no route summary, no polyline, no recommendations, no selected stop, and no CTA visible
16. If `POST /v1/routes` returns HTTP `503` with `UPSTREAM_PROVIDER_UNAVAILABLE`, the app must:
    - show title: `Service unavailable`
    - show body text: `Route data is temporarily unavailable. Try again.`
    - show retry action labeled `Retry`
    - remain on the Search Screen
    - keep no route summary, no polyline, no recommendations, no selected stop, and no CTA visible
17. Tapping `Retry` from a route error state must trigger exactly one new route attempt only for retryable route errors.
18. Retrying a route error must reacquire current location before sending the next route request.

### 7.5 Fuel-Stop Request Behavior And Stale Data Rules

1. After a successful route response, the app must send exactly one `POST /v1/fuel-stops/search` request using:
   - returned `routeId`
   - `fuelType = regular`
   - `currency = GBP`
   - `maxRecommendedStops = 3`
2. While `POST /v1/fuel-stops/search` is in flight, the app must show visible loading text `Finding fuel stops...`.
3. While `POST /v1/fuel-stops/search` is in flight, additional taps that would otherwise create another fuel-stop request or retry taps must be ignored.
4. When a new fuel-stop request starts, the app must immediately clear all prior fuel-stop derived UI from any earlier fuel-stop response for that route:
   - recommendation cards
   - selected stop state
   - `Open in Google Maps` CTA
   - prior fuel-stop error banner
5. When a new fuel-stop request starts after route success, the current route summary and route polyline must remain visible.
6. If the fuel-stop request succeeds, the app must validate the payload under Section 7.9 before rendering recommendations. If validation succeeds, the app must render 1 to 3 recommended stops and no placeholders.
7. If the fuel-stop request fails, including invalid success payload handling and invalid error payload handling under Sections 7.9 and 7.10, the app must keep the current route summary and route polyline visible, but must render no stale recommendation cards, no selected stop, and no `Open in Google Maps` CTA.
8. If `POST /v1/fuel-stops/search` returns HTTP `400` with `INVALID_JSON_BODY`, the app must:
   - show title: `Fuel stop request invalid`
   - show body text: `The fuel stop request was invalid.`
   - show no retry action
   - keep current route summary and polyline visible
   - show no recommendations, no selected stop, and no CTA
9. If `POST /v1/fuel-stops/search` returns HTTP `400` with `INVALID_FUEL_STOP_REQUEST_FIELDS`, the app must:
   - show title: `Fuel stop request invalid`
   - show body text: `The fuel stop request fields were invalid.`
   - show no retry action
   - keep current route summary and polyline visible
   - show no recommendations, no selected stop, and no CTA
10. If `POST /v1/fuel-stops/search` returns HTTP `400` with `INVALID_ROUTE_ID`, the app must:
    - show title: `Route unavailable`
    - show body text: `Route data is invalid or no longer available. Calculate the route again.`
    - show no retry action
    - keep current route summary and polyline visible
    - show no recommendations, no selected stop, and no CTA
11. If `POST /v1/fuel-stops/search` returns HTTP `400` with `UNSUPPORTED_FUEL_TYPE`, the app must:
    - show title: `Fuel stop request invalid`
    - show body text: `The fuel type is unsupported.`
    - show no retry action
    - keep current route summary and polyline visible
    - show no recommendations, no selected stop, and no CTA
12. If `POST /v1/fuel-stops/search` returns HTTP `400` with `INVALID_CURRENCY`, the app must:
    - show title: `Fuel stop request invalid`
    - show body text: `The currency is invalid.`
    - show no retry action
    - keep current route summary and polyline visible
    - show no recommendations, no selected stop, and no CTA
13. If `POST /v1/fuel-stops/search` returns HTTP `400` with `INVALID_MAX_RECOMMENDED_STOPS`, the app must:
    - show title: `Fuel stop request invalid`
    - show body text: `The requested number of fuel stops is invalid.`
    - show no retry action
    - keep current route summary and polyline visible
    - show no recommendations, no selected stop, and no CTA
14. If `POST /v1/fuel-stops/search` returns HTTP `404` with `NO_STATIONS_FOUND`, the app must:
    - show title: `No fuel stops found`
    - show body text: `No ranked fuel stops are available for this route. Try again.`
    - show retry action labeled `Retry`
    - keep current route summary and polyline visible
    - show no recommendations, no selected stop, and no CTA
15. If `POST /v1/fuel-stops/search` returns HTTP `503` with `UPSTREAM_PROVIDER_UNAVAILABLE`, the app must:
    - show title: `Service unavailable`
    - show body text: `Fuel stop data is temporarily unavailable. Try again.`
    - show retry action labeled `Retry`
    - keep current route summary and polyline visible
    - show no recommendations, no selected stop, and no CTA
16. If a fuel-stop request fails with a retryable error and the user taps `Retry`, the app must send exactly one new `POST /v1/fuel-stops/search` request using the same request parameters as the immediately preceding failed fuel-stop request unless the route has been recalculated.
17. Retrying a fuel-stop error must not start a new route request.

### 7.6 Recommendation Rendering

1. The app must render every returned recommended stop as selectable.
2. The app must render returned order exactly as received.
3. The app must clearly distinguish the stop with `rank = 1` using label `Best Stop`.
4. No stop is selected by default.
5. The app must not render `Open in Google Maps` while no stop is selected.
6. The app must show exactly one `Open in Google Maps` CTA after one stop is selected.
7. The app must display price from `priceMinorUnits` formatted as GBP with exactly 2 decimal places.
8. The app must display detour as `floor(detourDurationSeconds / 60)` whole minutes with no seconds shown.
9. User-facing detour text must represent the added driving time caused by inserting the station as a waypoint, excluding any fueling dwell time.
10. The client must treat `rank = 1` as the only valid top recommendation.
11. Every returned recommended stop must include `isBestStop`.
12. The client must reject the payload as `INVALID_SUCCESS_RESPONSE` unless:
    - exactly one stop has `rank = 1`
    - that same stop is the only stop with `isBestStop = true`
    - every other stop has `isBestStop = false`

### 7.7 Google Maps Handoff

1. The handoff must use the Google Maps URL scheme `comgooglemaps://`.
2. The app must generate the deep link in this exact parameter order and with no additional query parameters:
   - `saddr`
   - `daddr`
   - `directionsmode`
3. The canonical deep link string format is:
   `comgooglemaps://?saddr=Current%20Location&daddr={waypoint_lat},{waypoint_lng}+to:{destination_lat},{destination_lng}&directionsmode=driving`
4. Waypoint coordinates must come from the selected fuel stop.
5. Destination coordinates must come from the selected destination.
6. Every coordinate in the URL must be serialized using:
   - decimal notation only
   - exactly 6 digits after the decimal point
   - trailing zeros preserved
   - `.` as decimal separator
   - no scientific notation
   - no leading `+` sign
7. The app must call the OS open-URL API exactly once per user tap.
8. If the OS reports that the URL cannot be opened, the app must:
   - remain on the Results Screen
   - keep the current stop selected
   - show title: `Google Maps unavailable`
   - show body text: `Google Maps could not be opened. Try again.`
   - show retry action labeled `Retry`
9. If the user taps `Retry` from `Google Maps unavailable`, the app must:
   - keep the same selected stop
   - regenerate the deep link from current selected stop and current destination
   - produce the identical canonical deep link string if selected stop and destination are unchanged
   - call the OS open-URL API exactly once for that retry tap

### 7.8 Retry UX Contract

1. Every retryable state in this sprint must use a visible `Retry` action labeled exactly `Retry`.
2. Retryable states are limited to:
   - `SEARCH_PROVIDER_UNAVAILABLE`
   - `INVALID_DESTINATION_SEARCH_RESPONSE`
   - `CURRENT_LOCATION_UNAVAILABLE`
   - route `UPSTREAM_PROVIDER_UNAVAILABLE`
   - fuel-stop `NO_STATIONS_FOUND`
   - fuel-stop `UPSTREAM_PROVIDER_UNAVAILABLE`
   - `GOOGLE_MAPS_UNAVAILABLE`
3. When the user taps `Retry`, the currently displayed retryable error must be cleared immediately.
4. After the retryable error is cleared, the UI must transition immediately into the loading state for the retried operation.
5. During the retried operation, the cleared error must not remain visible together with the loading state.
6. Each retry tap must start exactly one retry attempt.
7. Additional retry taps must be ignored while the retried operation is in flight.
8. If a retried operation succeeds, the retry error state must stay cleared.
9. If a retried operation fails, the app must show only the latest resulting error state.
10. Retrying destination search must use the same trimmed query as the immediately preceding failed or invalid search request unless the user has edited the query.
11. Retrying current location acquisition must start one new location attempt and may proceed to a route request only if location succeeds.
12. Retrying a route error must reacquire current location and then start one new route request.
13. Retrying a fuel-stop error must start one new fuel-stop request and must not start a new route request.
14. Retrying Google Maps handoff must start one new open-URL attempt and must preserve the currently selected stop.

### 7.9 Client Validation Scope And Invalid Success Payload Handling

1. Client validation of HTTP `200` success payloads must be limited to fields and invariants observable in the received payload.
2. Client payload validation may check only:
   - required keys
   - absence of undocumented keys
   - nullability
   - JSON types
   - numeric ranges
   - string non-emptiness
   - enum values
   - ordering and rank continuity within the payload
   - uniqueness within the payload
   - exact equality rules explicitly expressible from returned fields
   - route polyline decodability under the documented encoding contract
3. Client payload validation must not require the client to infer or prove backend-only guarantees that are not derivable from the payload.
4. Backend-only guarantees that are not client validation rules include:
   - `routeId` 30-minute validity
   - route-corridor filtering correctness
   - price freshness cutoff correctness at backend request time
   - ranking correctness against excluded candidates
   - score correctness against non-returned candidates
   - detour calculation correctness against upstream routing internals
5. For `POST /v1/routes`, the client must reject the payload as `INVALID_SUCCESS_RESPONSE` if any documented route success rule is violated, including any of these geometry cases:
   - `polyline` is not a string
   - `polylineEncoding` is not `encoded_polyline`
   - `polylinePrecision` is not `5`
   - the `polyline` string cannot be decoded using the Google Encoded Polyline Algorithm Format
   - the decoded point list has fewer than 2 points
   - any decoded point falls outside latitude or longitude valid ranges
6. For `POST /v1/fuel-stops/search`, the client must reject the payload as `INVALID_SUCCESS_RESPONSE` if any documented fuel-stop success rule is violated.
7. If `POST /v1/routes` returns HTTP `200` with a payload that violates the documented observable success schema, the client must:
   - log `INVALID_SUCCESS_RESPONSE`
   - show title: `Unexpected service response`
   - show body text: `The app received an unexpected response. Try again later.`
   - show no retry action
   - remain on the Search Screen
   - keep no route summary, no polyline, no recommendations, no selected stop, and no CTA visible
8. If `POST /v1/fuel-stops/search` returns HTTP `200` with a payload that violates the documented observable success schema, the client must:
   - log `INVALID_SUCCESS_RESPONSE`
   - show title: `Unexpected service response`
   - show body text: `The app received an unexpected response. Try again later.`
   - show no retry action
   - keep the current route summary and polyline visible
   - show no recommendations, no selected stop, and no CTA

### 7.10 Error Handling And Invalid Error Payload Handling

Client-only state codes are:

1. `LOCATION_PERMISSION_DENIED`
2. `CURRENT_LOCATION_UNAVAILABLE`
3. `SEARCH_ZERO_RESULTS`
4. `SEARCH_PROVIDER_UNAVAILABLE`
5. `INVALID_DESTINATION_SEARCH_RESPONSE`
6. `GOOGLE_MAPS_UNAVAILABLE`
7. `INVALID_SUCCESS_RESPONSE`
8. `INVALID_ERROR_RESPONSE`

Retryability rules are:

1. `LOCATION_PERMISSION_DENIED`: not retryable within the error state
2. `CURRENT_LOCATION_UNAVAILABLE`: retryable
3. `SEARCH_ZERO_RESULTS`: no retry button, but user may issue a new search
4. `SEARCH_PROVIDER_UNAVAILABLE`: retryable
5. `INVALID_DESTINATION_SEARCH_RESPONSE`: retryable
6. `GOOGLE_MAPS_UNAVAILABLE`: retryable
7. `INVALID_SUCCESS_RESPONSE`: not retryable
8. `INVALID_ERROR_RESPONSE`: not retryable
9. `INVALID_JSON_BODY`: not retryable
10. `INVALID_ROUTE_REQUEST_FIELDS`: not retryable
11. `INVALID_COORDINATES`: not retryable
12. `INVALID_DESTINATION`: not retryable
13. `OUT_OF_SCOPE_GEOGRAPHY`: not retryable
14. `UNSUPPORTED_MODE`: not retryable
15. `ROUTE_NOT_FOUND`: not retryable
16. `INVALID_FUEL_STOP_REQUEST_FIELDS`: not retryable
17. `INVALID_ROUTE_ID`: not retryable
18. `UNSUPPORTED_FUEL_TYPE`: not retryable
19. `INVALID_CURRENCY`: not retryable
20. `INVALID_MAX_RECOMMENDED_STOPS`: not retryable
21. `NO_STATIONS_FOUND`: retryable
22. `UPSTREAM_PROVIDER_UNAVAILABLE`: retryable

For client handling, a non-2xx API body is an invalid error payload if it violates any Section 10.5 rule, including any of these cases:

1. top-level body is not a JSON object
2. top-level body does not contain exactly `error`
3. `error` is missing, null, or not a JSON object
4. `error.code` is missing, null, not a string, empty, or not one of the supported codes
5. `error.message` is missing, null, not a string, or empty after trimming
6. the body contains undocumented top-level or nested error fields

If `POST /v1/routes` returns a non-2xx response with an invalid error payload, the client must:

1. log `INVALID_ERROR_RESPONSE`
2. show title: `Unexpected service response`
3. show body text: `The app received an unexpected response. Try again later.`
4. show no retry action
5. remain on the Search Screen
6. keep no route summary, no polyline, no recommendations, no selected stop, and no CTA visible

If `POST /v1/fuel-stops/search` returns a non-2xx response with an invalid error payload, the client must:

1. log `INVALID_ERROR_RESPONSE`
2. show title: `Unexpected service response`
3. show body text: `The app received an unexpected response. Try again later.`
4. show no retry action
5. keep the current route summary and polyline visible
6. show no recommendations, no selected stop, and no CTA

## 8. Non-Functional Requirements

### 8.1 General

1. The core user flow must work without authentication.
2. Deterministic performance requirement for `POST /v1/fuel-stops/search`:
   - measured metric: server-side application-processing time only
   - fixed dataset: `performance_route_fixture_v1` with 1 route and 500 station records, of which 120 are eligible under Section 10.4
   - fixed environment: `performance_env_v1` single backend instance with 2 vCPU, 4 GB RAM, no debug instrumentation, warm process, and local in-memory fixture data
   - fixed concurrency: 8 parallel requests
   - fixed run length: 200 total successful requests collected after 20 warm-up requests
   - pass threshold: p95 application-processing time under 3,000 ms across the 200 measured requests
3. Every API requirement in this spec must be testable by API tests or the named deterministic performance suite.
4. Every client requirement in this spec must be testable by automated UI tests, automated integration tests, or a named deterministic verification artifact listed in Section 13.3.
5. Generic manual QA alone is not an acceptable verification method for any in-scope requirement.
6. The `uk_boundary_v1` geography fixture must be versioned and immutable for the duration of the sprint.

### 8.2 Client Logging Contract

The client must emit one structured log event for each required failure case using exactly these keys:

1. `screenName`
2. `actionName`
3. exactly one of `errorCode` or `clientStateCode`
4. optional `requestId`

Canonical `screenName` values are:

1. `search_screen`
2. `results_screen`

Canonical `actionName` values are:

1. `destination_search_request`
2. `route_start_tap`
3. `route_request`
4. `fuel_stop_request`
5. `google_maps_open`

Required log mappings are:

1. location permission denied:
   - `screenName = search_screen`
   - `actionName = route_start_tap`
   - `clientStateCode = LOCATION_PERMISSION_DENIED`
2. current-location acquisition failure after permission grant:
   - `screenName = search_screen`
   - `actionName = route_start_tap`
   - `clientStateCode = CURRENT_LOCATION_UNAVAILABLE`
3. destination search zero results:
   - `screenName = search_screen`
   - `actionName = destination_search_request`
   - `clientStateCode = SEARCH_ZERO_RESULTS`
4. destination search provider failure:
   - `screenName = search_screen`
   - `actionName = destination_search_request`
   - `clientStateCode = SEARCH_PROVIDER_UNAVAILABLE`
5. invalid destination-search provider response:
   - `screenName = search_screen`
   - `actionName = destination_search_request`
   - `clientStateCode = INVALID_DESTINATION_SEARCH_RESPONSE`
6. valid API error from route endpoint before route success:
   - `screenName = search_screen`
   - `actionName = route_request`
   - `errorCode =` returned route error code
7. valid API error from fuel-stop endpoint:
   - `screenName = results_screen`
   - `actionName = fuel_stop_request`
   - `errorCode =` returned fuel-stop error code
8. invalid HTTP `200` route response before route success:
   - `screenName = search_screen`
   - `actionName = route_request`
   - `clientStateCode = INVALID_SUCCESS_RESPONSE`
9. invalid HTTP `200` fuel-stop response:
   - `screenName = results_screen`
   - `actionName = fuel_stop_request`
   - `clientStateCode = INVALID_SUCCESS_RESPONSE`
10. invalid non-2xx route response before route success:
    - `screenName = search_screen`
    - `actionName = route_request`
    - `clientStateCode = INVALID_ERROR_RESPONSE`
11. invalid non-2xx fuel-stop response:
    - `screenName = results_screen`
    - `actionName = fuel_stop_request`
    - `clientStateCode = INVALID_ERROR_RESPONSE`
12. Google Maps handoff failure:
    - `screenName = results_screen`
    - `actionName = google_maps_open`
    - `clientStateCode = GOOGLE_MAPS_UNAVAILABLE`

## 9. Destination Search Provider Adapter Contract

### 9.1 Purpose

The destination-search provider adapter is the client dependency that resolves user-entered destination text into selectable places for the MVP route flow.

### 9.2 Request Contract

1. Each destination-search request must be driven by one explicit user search action.
2. The adapter request must include exactly one input field, `query`.
3. `query` must be the user's destination text after trimming leading and trailing whitespace.
4. `query` must be a non-empty string.
5. Unknown request fields to the adapter contract are invalid.
6. The app must treat adapter transport failure, timeout, or provider exception as `SEARCH_PROVIDER_UNAVAILABLE`.

Example adapter request shape:

```json
{
  "query": "Birmingham"
}
```

### 9.3 Success Contract

Success payload:

```json
{
  "results": [
    {
      "label": "Birmingham, UK",
      "location": {
        "lat": 52.4862,
        "lng": -1.8904
      },
      "countryCode": "GB"
    }
  ]
}
```

Success rules:

1. The top-level payload must be a JSON object.
2. Top-level keys must be exactly `results`.
3. `results` must be an array.
4. The payload is a valid top-level success payload if and only if items 1 to 3 are satisfied.
5. Each result item must be evaluated independently.
6. A result item is selectable only if:
   - it is a JSON object
   - its keys are exactly `label`, `location`, and `countryCode`
   - `label` is a non-empty string after trimming
   - `location` is a JSON object with exactly `lat` and `lng`
   - `location.lat` is a number in `[-90, 90]`
   - `location.lng` is a number in `[-180, 180]`
   - `countryCode` is a non-empty string and equals `GB`
7. Result items that do not satisfy item 6 must be filtered out before display.
8. If the payload violates items 1 to 3, the app must treat it as `INVALID_DESTINATION_SEARCH_RESPONSE`.
9. If the payload is valid at the top level but zero selectable results remain after filtering, the app must treat it as `SEARCH_ZERO_RESULTS`.
10. If the payload is valid at the top level and one or more selectable results remain after filtering, the app must render only those selectable results.
11. A valid top-level success payload must still be discarded by the client if it fails the response-correlation rule in Section 7.1 items 24 to 27.

### 9.4 Failure Handling Contract

1. Provider transport failure, timeout, SDK exception, or unavailable upstream dependency must be handled as `SEARCH_PROVIDER_UNAVAILABLE`.
2. A syntactically valid payload with an invalid top-level schema must be handled as `INVALID_DESTINATION_SEARCH_RESPONSE`.
3. Retry behavior for both retryable search states is defined by Section 7.8.
4. The client must not route using any destination data from a failed, invalid, or stale provider response.

## 10. Backend API Contract

### 10.1 Common API Rules

1. All request and response bodies must use JSON.
2. All successful response bodies must be top-level JSON objects.
3. If a request body is syntactically invalid JSON, the backend must return HTTP `400` with `INVALID_JSON_BODY`.
4. If a request body is syntactically valid JSON but the top-level JSON value is not an object, the backend must return HTTP `400` with `INVALID_JSON_BODY`.
5. All non-2xx responses must use the error body in Section 10.5.
6. Coordinate fields must be JSON numbers.
7. Any returned latitude must be in `[-90, 90]`.
8. Any returned longitude must be in `[-180, 180]`.
9. Integer fields must be encoded as JSON integers.
10. Unknown success-response fields must not be emitted.
11. Unknown error-response fields must not be emitted.
12. The backend may include an `X-Request-Id` response header.

### 10.2 `POST /v1/routes`

Purpose: calculate a driving route from current location to destination.

Request:

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

Request rules:

1. After the Section 10.1 body checks pass, the top-level keys must be exactly `origin`, `destination`, `mode`.
2. `origin` keys must be exactly `lat`, `lng`.
3. `destination` keys must be exactly `lat`, `lng`, `label`.
4. `origin.lat`, `origin.lng`, `destination.lat`, and `destination.lng` are required numeric coordinates in valid ranges.
5. `destination.label` is required, must be a non-empty string after trimming.
6. `mode` is required and must equal `driving`.
7. If either origin or destination is outside supported geography under `uk_boundary_v1`, backend must return `OUT_OF_SCOPE_GEOGRAPHY`.

Unknown request-field mapping for this endpoint is exact:

1. Any undocumented top-level field in the request body must return HTTP `400` with `INVALID_ROUTE_REQUEST_FIELDS`.
2. Any undocumented nested field inside `origin` must return HTTP `400` with `INVALID_ROUTE_REQUEST_FIELDS`.
3. Any undocumented nested field inside `destination` must return HTTP `400` with `INVALID_ROUTE_REQUEST_FIELDS`.
4. Unknown-field handling for this endpoint must not use fallback inference by field group.

Success response:

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

Success rules:

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

Error responses:

1. HTTP `400` with `INVALID_JSON_BODY` for malformed JSON or non-object JSON body
2. HTTP `400` with `INVALID_ROUTE_REQUEST_FIELDS` for any undocumented top-level or nested request field
3. HTTP `400` with `INVALID_COORDINATES` for coordinate structure, missing-field, type, range, or null violations
4. HTTP `400` with `INVALID_DESTINATION` for destination label structure, type, null, or emptiness violations
5. HTTP `400` with `OUT_OF_SCOPE_GEOGRAPHY` when otherwise valid coordinates are outside supported geography
6. HTTP `400` with `UNSUPPORTED_MODE` for mode structure, type, null, or enum violations
7. HTTP `404` with `ROUTE_NOT_FOUND` when no route can be produced for otherwise valid inputs
8. HTTP `503` with `UPSTREAM_PROVIDER_UNAVAILABLE` when a required upstream dependency fails

### 10.3 `POST /v1/fuel-stops/search`

Purpose: return ranked route-aware fuel stop recommendations for a route.

Request:

```json
{
  "routeId": "route_123",
  "fuelType": "regular",
  "currency": "GBP",
  "maxRecommendedStops": 3
}
```

Request rules:

1. After the Section 10.1 body checks pass, the top-level keys must be exactly `routeId`, `fuelType`, `currency`, `maxRecommendedStops`.
2. `routeId` is required and must be a non-empty string.
3. `fuelType` is required and must equal `regular`.
4. `currency` is required and must equal `GBP`.
5. `maxRecommendedStops` is required and must be an integer from `1` to `3`.
6. `routeId` must reference an existing unexpired route.
7. If `routeId` is syntactically valid but does not reference an existing unexpired route, the backend must return HTTP `400` with `INVALID_ROUTE_ID`.

Unknown request-field mapping for this endpoint is exact:

1. Any undocumented top-level field in the request body must return HTTP `400` with `INVALID_FUEL_STOP_REQUEST_FIELDS`.
2. This endpoint has no documented nested request objects.
3. Unknown-field handling for this endpoint must not use fallback inference by field group.

Success response:

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

Success rules:

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
15. `detourDurationSeconds` must represent the added driving time introduced by inserting the station as a waypoint into the trip, excluding fueling dwell time, exactly as defined in Section 10.4.
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

Error responses:

1. HTTP `400` with `INVALID_JSON_BODY` for malformed JSON or non-object JSON body
2. HTTP `400` with `INVALID_FUEL_STOP_REQUEST_FIELDS` for any undocumented top-level request field
3. HTTP `400` with `INVALID_ROUTE_ID` for route ID structure, missing-field, type, emptiness, or null violations, and for a syntactically valid `routeId` that is expired, unknown, or otherwise does not reference an existing unexpired route
4. HTTP `400` with `UNSUPPORTED_FUEL_TYPE` for fuel type structure, type, null, missing, or enum violations
5. HTTP `400` with `INVALID_CURRENCY` for currency structure, type, null, missing, or enum violations
6. HTTP `400` with `INVALID_MAX_RECOMMENDED_STOPS` for stop-count structure, type, null, missing, or range violations
7. HTTP `404` with `NO_STATIONS_FOUND` when no eligible stations exist
8. HTTP `503` with `UPSTREAM_PROVIDER_UNAVAILABLE` when a required upstream dependency fails

### 10.4 Deterministic Ranking And Detour Algorithm

1. Let `baselineDurationSeconds` equal the driving duration in whole seconds for the successful route returned by `POST /v1/routes`, from origin to destination, using the same routing provider, driving mode, and routing snapshot used to generate that route.
2. For each candidate station, let `waypointDurationSeconds` equal the driving duration in whole seconds for the route from the same origin to the same destination with that station inserted as a single waypoint, using the same routing provider, driving mode, and routing snapshot as the baseline route.
3. Compute `detourDurationSeconds = max(0, waypointDurationSeconds - baselineDurationSeconds)`.
4. `detourDurationSeconds` excludes any fueling dwell time, parking time, or user stop duration. It represents driving-time increase only.
5. The user-facing detour minutes displayed by the client must be derived only from this `detourDurationSeconds` value using `floor(detourDurationSeconds / 60)`.
6. Build the eligible candidate set for the route by applying all of these filters before scoring:
   - station is within 2,000 meters of the route polyline
   - station is inside supported geography under `uk_boundary_v1`
   - station `countryCode = GB`
   - station has `priceTimestamp` no older than 24 hours at backend request time
   - station has non-null `priceMinorUnits` and non-null `detourDurationSeconds`
7. Compute normalization inputs using only the eligible candidate set for that route, including candidates not returned because of `maxRecommendedStops`.
8. Let:
   - `minPrice = minimum(priceMinorUnits)` across the eligible candidate set
   - `maxPrice = maximum(priceMinorUnits)` across the eligible candidate set
   - `minDetour = minimum(detourDurationSeconds)` across the eligible candidate set
   - `maxDetour = maximum(detourDurationSeconds)` across the eligible candidate set
9. Compute `normalizedPrice` for each eligible station as:
   - `0.0` if `maxPrice = minPrice`
   - otherwise `(priceMinorUnits - minPrice) / (maxPrice - minPrice)`
10. Compute `normalizedDetour` for each eligible station as:
    - `0.0` if `maxDetour = minDetour`
    - otherwise `(detourDurationSeconds - minDetour) / (maxDetour - minDetour)`
11. If there is exactly one eligible station, both normalized components for that station must be `0.0`.
12. Compute `rawScore = 0.6 * normalizedPrice + 0.4 * normalizedDetour`.
13. Compute returned `score` as the JSON number equal to `rawScore` rounded to 3 decimal places using round-half-up.
14. Rank stations by ascending `rawScore`.
15. Resolve ties in this exact order:
    - lower `priceMinorUnits`
    - lower `detourDurationSeconds`
    - lexicographically smaller `stationId`
16. Return the first `maxRecommendedStops` stations after ranking.
17. Assign returned `rank` values from `1` upward in returned order.
18. Set `isBestStop = true` only on the returned stop with `rank = 1`.

Backend conformance rules enforced by API tests:

1. Only stations within 2,000 meters of the route polyline are eligible.
2. Only stations inside supported geography under `uk_boundary_v1` are eligible.
3. Only stations with `countryCode = GB` are eligible.
4. Only stations with `priceTimestamp` no older than 24 hours at backend request time are eligible.
5. `detourDurationSeconds` must equal the added driving time caused by inserting the station as a waypoint, excluding dwell time.
6. Ranking must use only `priceMinorUnits` and `detourDurationSeconds`.
7. Score must be computed from the exact normalization and rounding rules above.
8. Ties must resolve by lower `priceMinorUnits`, then lower `detourDurationSeconds`, then lexicographically smaller `stationId`.

### 10.5 Error Format

All non-2xx API responses must use:

```json
{
  "error": {
    "code": "NO_STATIONS_FOUND",
    "message": "No fuel stations were found near the route."
  }
}
```

Error format rules:

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

## 11. Client Requirements By Screen

### 11.1 Search Screen

The Search Screen owns destination selection, the route-start action, and all route loading and route error states before route success. The screen must allow:

1. destination text input
2. destination search submission
3. destination result selection
4. route-start action
5. loading state with visible text `Searching destinations...`
6. zero-results state
7. retryable search-error state
8. blocked progression until a resolved UK result is selected
9. immediate selection invalidation when destination text changes after selection
10. immediate clearing of prior rendered results, zero-results state, and retryable search error when a new destination search starts
11. rendering only filtered selectable UK results from a mixed provider payload
12. discarding stale destination-search responses that no longer match the latest submitted query and current trimmed text
13. location-denied and current-location-unavailable route-start failures before any successful route response
14. route loading state with visible text `Calculating route...`
15. route request error states before any successful route response

### 11.2 Results Screen

The Results Screen must show, when applicable:

1. route distance
2. route duration
3. decoded route polyline on map
4. recommended stops list
5. `Best Stop` label on `rank = 1` only
6. price formatted from `priceMinorUnits` as GBP with exactly 2 decimal places
7. detour minutes displayed as `floor(detourDurationSeconds / 60)`
8. selected stop state
9. no `Open in Google Maps` CTA before stop selection
10. exactly one `Open in Google Maps` CTA after stop selection
11. visible loading text `Finding fuel stops...` while fuel-stop request is in flight

### 11.3 Error States

The app must provide explicit UI states for:

1. location denied
2. current location unavailable
3. search zero results
4. search provider unavailable
5. invalid destination-search response
6. route request invalid for `INVALID_JSON_BODY`
7. route request invalid for `INVALID_ROUTE_REQUEST_FIELDS`
8. route request invalid for `INVALID_COORDINATES`
9. destination unavailable for `INVALID_DESTINATION`
10. route out of scope for `OUT_OF_SCOPE_GEOGRAPHY`
11. route request invalid for `UNSUPPORTED_MODE`
12. route unavailable
13. route service unavailable
14. fuel stop request invalid for `INVALID_JSON_BODY`
15. fuel stop request invalid for `INVALID_FUEL_STOP_REQUEST_FIELDS`
16. route unavailable for fuel-stop `INVALID_ROUTE_ID`
17. fuel stop request invalid for `UNSUPPORTED_FUEL_TYPE`
18. fuel stop request invalid for `INVALID_CURRENCY`
19. fuel stop request invalid for `INVALID_MAX_RECOMMENDED_STOPS`
20. no fuel stops found
21. fuel-stop service unavailable
22. Google Maps launch failure
23. unexpected service response

## 12. Acceptance Criteria

1. Given `POST /v1/routes` receives a request containing any undocumented top-level field or any undocumented field inside `origin` or `destination`, when the backend validates the request, then it returns HTTP `400` with `INVALID_ROUTE_REQUEST_FIELDS`, and deterministic API tests assert that exact mapping.
2. Given `POST /v1/fuel-stops/search` receives a request containing any undocumented top-level field, when the backend validates the request, then it returns HTTP `400` with `INVALID_FUEL_STOP_REQUEST_FIELDS`, and deterministic API tests assert that exact mapping.
3. Given destination search returns a mix of valid, malformed, or out-of-scope results, when the client renders the results, then only contract-valid UK results are rendered and selectable, malformed and out-of-scope items are filtered out before display, route calculation remains disabled until a rendered valid UK result is selected, and the behavior is covered by deterministic UI or integration tests.
4. Given the search screen has prior results, zero-results, or a retryable search error, when the user starts a new destination search, then the prior search state is cleared immediately, only the loading state remains visible during the in-flight request, and no ambiguous coexistence of old and new search state remains.
5. Given either API endpoint receives malformed JSON or a non-object JSON body, when the backend validates the request, then it returns HTTP `400` with `INVALID_JSON_BODY`, and this behavior is covered by deterministic API tests.
6. Given `POST /v1/routes` returns HTTP `200`, when the client validates and renders the route, then `polyline` conforms to the documented encoded polyline contract, decodes into at least 2 valid points, and can be rendered; otherwise the payload is handled as `INVALID_SUCCESS_RESPONSE` with deterministic UI coverage.
7. Given a route with a deterministic eligible-station fixture, when `POST /v1/fuel-stops/search` is executed, then the backend returns `detourDurationSeconds` values that match the exact added-driving-time definition in Section 10.4, and ranking tests plus UI tests verify both ranking inputs and displayed detour minutes against that definition.
8. Given a route with a deterministic eligible-station fixture, when `POST /v1/fuel-stops/search` is executed, then the backend returns `score` values numerically equal to `rawScore` rounded per Section 10.4, and rank order and tie-breaks are reproducible across repeated test runs with the same fixture.
9. Given a successful fuel-stop response, when the client validates the payload, then every returned stop includes `isBestStop`, exactly one stop has `rank = 1`, that same stop is the only stop with `isBestStop = true`, and any mismatch is treated as `INVALID_SUCCESS_RESPONSE`.
10. Given either endpoint returns HTTP `200`, when the client validates the payload, then it validates only observable fields, types, ranges, required keys, ordering rules, uniqueness rules, enum values, exact equality rules defined in the payload, closed-world schema constraints in that payload, and route-polyline decodability where applicable.
11. Given backend behavioral rules such as route TTL, route-corridor filtering, price freshness cutoff timing, ranking correctness, detour calculation correctness, and performance workload definition, when the contract is verified, then those rules are enforced by deterministic API tests or the named performance suite and are not described as mandatory client-side validation steps.
12. Given destination search is exercised in the MVP flow, when the client receives provider results, then only results matching the documented item-level schema are rendered, malformed top-level provider responses trigger the documented search-unavailable UX state, and provider failure and zero-results behavior are covered by deterministic UI or integration tests.
13. Given any retryable error state, when the user taps `Retry`, then the prior error state is cleared immediately, the contract-defined loading state replaces it, exactly one retry attempt is started, and additional retry taps are ignored until that attempt completes.
14. Given the app has previously rendered a successful route or recommendation result, when a new route request begins, then prior route summary, route polyline, recommendation cards, selected stop state, CTA, and prior error banner are cleared immediately and that behavior is covered by automated UI tests.
15. Given the app has previously rendered a successful route result, when a new fuel-stop request begins, then route summary and route polyline remain visible, prior recommendation cards are cleared, prior stop selection is cleared, CTA is hidden, prior fuel-stop error banner is cleared, and that behavior is covered by automated UI tests.
16. Given the app has previously rendered a successful route or recommendation result, when the next route request fails, then no stale route summary, polyline, recommendations, selected stop, or CTA remain visible.
17. Given the app has previously rendered a successful route result, when the next fuel-stop request fails, then the current route summary and polyline remain visible but stale recommendations, selected stop, and CTA do not remain visible.
18. Given location permission is granted and the user starts route calculation once from the Search Screen, when current location is acquired successfully, then the app sends exactly one `POST /v1/routes` request and ignores additional taps during loading.
19. Given one route request succeeds, when the app processes the response, then it keeps route loading and route error ownership on the Search Screen until success, then navigates to or renders the Results Screen, renders route distance, route duration, and decoded route polyline, and only then starts fuel-stop search.
20. Given one successful route result, when the app requests fuel-stop recommendations, then it sends exactly one `POST /v1/fuel-stops/search` request using returned `routeId`, `fuelType = regular`, `currency = GBP`, and `maxRecommendedStops = 3`.
21. Given a successful fuel-stop response, when the app renders recommendations, then it renders 1 to 3 selectable stops in returned order, labels only `rank = 1` as `Best Stop`, and shows no placeholders.
22. Given no stop is selected, when recommendations are displayed, then `Open in Google Maps` is not shown.
23. Given one stop is selected, when recommendations are displayed, then exactly one `Open in Google Maps` CTA is shown.
24. Given the user taps `Open in Google Maps`, when the deep link is generated, then the URL string exactly matches the canonical format in Section 7.7 and is deterministic for unchanged state.
25. Given any documented valid non-2xx API error code from either endpoint, when the client receives the response, then it shows the contract-defined title, body text, retryability, screen ownership, and stale-state behavior for that exact code, and that behavior is covered by deterministic UI tests.
26. Given either API endpoint returns a non-2xx body that violates any Section 10.5 rule, including wrong types, nulls, empty `error.message`, non-object top-level body, non-object `error`, or undocumented fields, when the client validates the response, then it logs `INVALID_ERROR_RESPONSE`, shows `Unexpected service response`, and applies the endpoint-specific stale-state rule, and this is covered by deterministic UI tests.
27. Given a successful HTTP `200` payload with missing required fields, wrong types, invalid observable ranges, duplicate station IDs, non-consecutive ranks, missing `isBestStop`, zero `rank = 1`, multiple `rank = 1`, mismatch between `rank = 1` and `isBestStop`, multiple best stops, zero best stops, undocumented fields, or invalid route-geometry encoding, when the client validates the response, then it logs `INVALID_SUCCESS_RESPONSE`, shows `Unexpected service response`, and applies the contract-defined stale-state rule for the affected endpoint.
28. Given any client-only failure state code defined in Section 7.10, when the client emits a structured log, then the log uses the contract-defined `screenName`, `actionName`, and exactly one of `errorCode` or `clientStateCode`, and that mapping is covered by a deterministic test.
29. Given `POST /v1/routes` is in flight or fails before route success, when the client shows loading, error UI, or emits route logs, then the owning screen is the Search Screen and never the Results Screen, and this state is covered by deterministic UI and logging tests.
30. Given any in-scope client requirement in this sprint contract, when sprint completion is assessed, then there is a named automated test or deterministic verification artifact that proves pass or fail for that requirement, and no requirement relies on generic manual QA wording alone.
31. Given a destination-search request is in flight, when the user changes the query text before the response returns, then the app must not render results, zero-results UI, or error UI from the stale request, must keep route calculation disabled until a result from the current query is selected, and this behavior is covered by deterministic UI or integration tests.
32. Given the app previously rendered successful route or fuel-stop data, when the next API response is invalid under the documented success or error schema, then the client must show `Unexpected service response`, apply the endpoint-specific stale-state rule in Sections 7.9 or 7.10, and that rule is covered by deterministic UI tests.
33. Given a request to either API endpoint includes any unknown field, when the backend validates the request, then it returns the exact documented endpoint-specific error code for that endpoint, and this mapping is covered by deterministic API tests.
34. Given the performance suite runs `POST /v1/fuel-stops/search` against the contract-defined workload and environment, when at least the contract-defined sample size is collected, then p95 server-side application-processing time is under 3 seconds, and the result is recorded by a named deterministic performance artifact.

## 13. Test Plan

### 13.1 API Tests

1. `POST /v1/routes` returns HTTP `400` with `INVALID_JSON_BODY` for malformed JSON request bodies.
2. `POST /v1/routes` returns HTTP `400` with `INVALID_JSON_BODY` for syntactically valid non-object JSON request bodies.
3. `POST /v1/routes` returns HTTP `400` with `INVALID_ROUTE_REQUEST_FIELDS` for any undocumented top-level request field.
4. `POST /v1/routes` returns HTTP `400` with `INVALID_ROUTE_REQUEST_FIELDS` for any undocumented field inside `origin`.
5. `POST /v1/routes` returns HTTP `400` with `INVALID_ROUTE_REQUEST_FIELDS` for any undocumented field inside `destination`.
6. `POST /v1/routes` returns HTTP `200` with a top-level JSON object containing exactly the documented success fields for a valid request.
7. `POST /v1/routes` rejects missing, null, wrong-type, or out-of-range coordinate fields with HTTP `400` and `INVALID_COORDINATES`.
8. `POST /v1/routes` rejects invalid destination labels with HTTP `400` and `INVALID_DESTINATION`.
9. `POST /v1/routes` rejects non-`driving` mode with HTTP `400` and `UNSUPPORTED_MODE`.
10. `POST /v1/routes` rejects origin or destination outside supported geography with HTTP `400` and `OUT_OF_SCOPE_GEOGRAPHY`.
11. `POST /v1/routes` returns a success payload whose `polyline` decodes under the documented encoded-polyline contract to at least 2 valid points.
12. `POST /v1/routes` returns HTTP `404` and `ROUTE_NOT_FOUND` when no route can be generated.
13. `POST /v1/routes` returns HTTP `503` and `UPSTREAM_PROVIDER_UNAVAILABLE` on upstream failure.
14. A `routeId` returned by `POST /v1/routes` remains accepted by `POST /v1/fuel-stops/search` for at least 30 minutes after route creation time.
15. `POST /v1/fuel-stops/search` returns HTTP `400` with `INVALID_JSON_BODY` for malformed JSON request bodies.
16. `POST /v1/fuel-stops/search` returns HTTP `400` with `INVALID_JSON_BODY` for syntactically valid non-object JSON request bodies.
17. `POST /v1/fuel-stops/search` returns HTTP `400` with `INVALID_FUEL_STOP_REQUEST_FIELDS` for any undocumented top-level request field.
18. `POST /v1/fuel-stops/search` returns HTTP `200` with a top-level JSON object containing exactly the documented success fields for a valid request.
19. `POST /v1/fuel-stops/search` rejects invalid `routeId`, including malformed, missing, empty, expired, and unknown route IDs, and rejects invalid `fuelType`, `currency`, and `maxRecommendedStops` with the documented exact error codes.
20. `POST /v1/fuel-stops/search` returns 1 to 3 stops for a valid route with eligible stations.
21. `POST /v1/fuel-stops/search` returns unique `stationId` values, ascending consecutive ranks, exactly one `rank = 1`, and exactly one `isBestStop = true` on that same stop, and includes `isBestStop` on every returned stop.
22. `POST /v1/fuel-stops/search` enforces `countryCode = GB`, valid location ranges, `fuelType = regular`, `currency = GBP`, integer `priceMinorUnits >= 0`, RFC 3339 UTC `priceTimestamp`, integer `distanceFromRouteMeters >= 0`, and integer `detourDurationSeconds >= 0`.
23. `POST /v1/fuel-stops/search` excludes stations more than 2,000 meters from the route polyline.
24. `POST /v1/fuel-stops/search` excludes stations outside supported geography under `uk_boundary_v1`.
25. `POST /v1/fuel-stops/search` excludes stations whose `countryCode != GB`.
26. `POST /v1/fuel-stops/search` excludes stations older than the 24-hour freshness threshold at backend request time.
27. `POST /v1/fuel-stops/search` computes `detourDurationSeconds` as the exact added driving time in Section 10.4.
28. `POST /v1/fuel-stops/search` computes `normalizedPrice` with the exact min-max eligible-set rule in Section 10.4.
29. `POST /v1/fuel-stops/search` computes `normalizedDetour` with the exact min-max eligible-set rule in Section 10.4.
30. `POST /v1/fuel-stops/search` sets both normalized components to `0.0` when there is exactly one eligible station.
31. `POST /v1/fuel-stops/search` sets a normalized component to `0.0` when all eligible stations have identical values for that component.
32. `POST /v1/fuel-stops/search` computes `rawScore = 0.6 * normalizedPrice + 0.4 * normalizedDetour`.
33. `POST /v1/fuel-stops/search` returns `score` as a JSON number numerically equal to `rawScore` rounded to 3 decimal places using round-half-up.
34. `POST /v1/fuel-stops/search` applies tie-breakers in the documented order.
35. `POST /v1/fuel-stops/search` returns HTTP `404` and `NO_STATIONS_FOUND` when no eligible stations exist.
36. `POST /v1/fuel-stops/search` returns HTTP `503` and `UPSTREAM_PROVIDER_UNAVAILABLE` on upstream failure.
37. Every non-2xx response from both endpoints matches the Section 10.5 error envelope exactly.

### 13.2 iOS UI And Integration Tests

1. User cannot continue with unresolved destination text.
2. Starting a new destination search immediately clears prior rendered results, prior zero-results state, prior retryable search error state, prior selected destination result, and route-calculation enabled state.
3. Search loading state appears while destination search is in progress and old search content does not remain visible during loading.
4. Selecting a valid resolved UK result enables route calculation.
5. A mixed destination-search payload renders only valid UK results and filters malformed and out-of-scope items before display.
6. Editing destination text after selection clears selection immediately and disables route calculation.
7. Editing destination text while a destination-search request is in flight causes any later stale response for the older query to be discarded without rendering results, zero-results, or error UI from that stale request.
8. Invalid destination-search provider response shows `Search unavailable`, logs `INVALID_DESTINATION_SEARCH_RESPONSE`, and renders no selectable results.
9. Search retry clears the prior search error immediately, shows `Searching destinations...`, starts exactly one retry request, and ignores duplicate retry taps while in flight.
10. If location permission is denied, the app shows `Location required`, sends no route request, and emits the mapped log event from `search_screen`.
11. If current location cannot be acquired, the app sends no route request and shows `Current location unavailable` with `Retry` on the Search Screen.
12. Retrying current-location acquisition clears the prior error immediately, starts exactly one new location attempt, and ignores duplicate retry taps while in flight.
13. Starting route calculation once sends exactly one route request when location acquisition succeeds.
14. While route request is in flight, the Search Screen shows `Calculating route...`, the Results Screen is not the owner of that loading state, and duplicate taps are ignored.
15. Starting a new route request after prior success immediately clears route summary, polyline, recommendations, selected stop, CTA, and prior error banner.
16. If the new route request then fails, stale success data does not reappear and the app remains on the Search Screen.
17. Route error handling shows the exact contract-defined UI on the Search Screen for `INVALID_JSON_BODY`, `INVALID_ROUTE_REQUEST_FIELDS`, `INVALID_COORDINATES`, `INVALID_DESTINATION`, `OUT_OF_SCOPE_GEOGRAPHY`, `UNSUPPORTED_MODE`, `ROUTE_NOT_FOUND`, and `UPSTREAM_PROVIDER_UNAVAILABLE`.
18. Retrying a retryable route error clears the prior error immediately, shows `Calculating route...`, starts exactly one retry path, reacquires current location, and ignores duplicate retry taps while loading.
19. After one successful route result, the app validates route geometry, navigates to or renders the Results Screen, and sends exactly one fuel-stop request with the documented request values.
20. While fuel-stop request is in flight, the app shows `Finding fuel stops...` and ignores duplicate taps.
21. Starting a new fuel-stop request after prior success keeps route summary and polyline visible but clears recommendations, selected stop, CTA, and prior fuel-stop error banner.
22. If the new fuel-stop request then fails, route summary and polyline remain visible but stale recommendations and CTA do not.
23. Fuel-stop error handling shows the exact contract-defined UI for `INVALID_JSON_BODY`, `INVALID_FUEL_STOP_REQUEST_FIELDS`, `INVALID_ROUTE_ID`, `UNSUPPORTED_FUEL_TYPE`, `INVALID_CURRENCY`, `INVALID_MAX_RECOMMENDED_STOPS`, `NO_STATIONS_FOUND`, and `UPSTREAM_PROVIDER_UNAVAILABLE`.
24. Retrying a retryable fuel-stop error clears the prior error immediately, shows `Finding fuel stops...`, starts exactly one retry request, and ignores duplicate retry taps while loading.
25. Successful fuel-stop response renders 1 to 3 recommendation cards with `Best Stop` on `rank = 1` only.
26. No `Open in Google Maps` CTA is visible before stop selection.
27. Selecting one stop renders exactly one `Open in Google Maps` CTA.
28. Displayed stop cards show GBP price with exactly 2 decimal places and detour minutes as whole minutes derived from `detourDurationSeconds`.
29. Tapping `Open in Google Maps` issues one open-URL call with the exact canonical deep link string.
30. If Google Maps cannot be opened, the app keeps the selected stop and shows `Google Maps unavailable` with `Retry`.
31. Tapping `Retry` from `Google Maps unavailable` clears the prior error immediately, issues exactly one additional open-URL call, reproduces the same URL string for unchanged state, and ignores duplicate retry taps while the retry is in progress.
32. Invalid HTTP `200` route payload, including undecodable or non-renderable route geometry, logs `INVALID_SUCCESS_RESPONSE`, shows `Unexpected service response` on the Search Screen, and leaves no route summary, no polyline, no recommendations, no selection, and no CTA visible.
33. Invalid HTTP `200` fuel-stop payload logs `INVALID_SUCCESS_RESPONSE`, shows `Unexpected service response`, keeps the current route summary and polyline visible, and shows no recommendations, no selection, and no CTA.
34. Any non-2xx route payload that violates any Section 10.5 rule, including non-object top-level body, non-object `error`, wrong types, nulls, empty `error.message`, unsupported code, or undocumented fields, logs `INVALID_ERROR_RESPONSE`, shows `Unexpected service response` on the Search Screen, and leaves no route summary, no polyline, no recommendations, no selection, and no CTA visible.
35. Any non-2xx fuel-stop payload that violates any Section 10.5 rule, including non-object top-level body, non-object `error`, wrong types, nulls, empty `error.message`, unsupported code, or undocumented fields, logs `INVALID_ERROR_RESPONSE`, shows `Unexpected service response`, keeps the current route summary and polyline visible, and shows no recommendations, no selection, and no CTA.
36. Search zero-results state shows `No destinations found`, allows a new search, and emits the mapped log event.
37. A successful fuel-stop payload missing `isBestStop` on any returned stop is rejected as `INVALID_SUCCESS_RESPONSE`.

### 13.3 Deterministic Verification Artifacts

1. `api_contract_test_suite`
   - Covers all API requirements in Sections 10.1 to 10.5 and all API acceptance criteria.
2. `destination_search_contract_test_suite`
   - Covers the Section 9 request and top-level success schema, mixed-result filtering rules, provider failure handling, malformed top-level payload handling, stale-response discard rules, and selectable-result rules.
3. `ios_ui_contract_test_suite`
   - Covers all client UI behaviors in Sections 7, 11, and 12 that are observable through the app UI or open-URL boundary.
4. `client_logging_contract_test_suite`
   - Covers the exact key set and mapping rules in Section 8.2.
5. `ranking_fixture_suite`
   - Uses fixed eligible-station fixtures to prove detour calculation, normalization, score calculation, tie-breaks, score rounding, and reproducibility for Section 10.4.
6. `route_geometry_fixture_suite`
   - Verifies the route success payload uses the documented encoded polyline format, precision, decodability, minimum point count, and client invalid-response handling for geometry failures.
7. `google_maps_link_snapshot_suite`
   - Verifies canonical URL string generation and retry determinism for Section 7.7.

### 13.4 Performance Verification

1. `fuel_stop_performance_suite`
   - Uses `performance_route_fixture_v1` and `performance_env_v1`.
   - Sends 20 warm-up requests, then 200 measured successful requests to `POST /v1/fuel-stops/search`.
   - Runs at fixed concurrency of 8 parallel requests.
   - Records server-side application-processing time only.
   - Passes only if p95 across the 200 measured requests is under 3,000 ms.
   - Produces deterministic output artifact `fuel_stop_performance_report_v1` containing sample count, concurrency, fixture version, environment version, p50, p95, and pass/fail result.

### 13.5 Observability Verification

1. Verify each required failure emits one structured log event with exactly the keys defined in Section 8.2.
2. Verify `LOCATION_PERMISSION_DENIED`, `CURRENT_LOCATION_UNAVAILABLE`, `SEARCH_ZERO_RESULTS`, `SEARCH_PROVIDER_UNAVAILABLE`, `INVALID_DESTINATION_SEARCH_RESPONSE`, `INVALID_SUCCESS_RESPONSE`, `INVALID_ERROR_RESPONSE`, and `GOOGLE_MAPS_UNAVAILABLE` map to the documented `screenName` and `actionName`.
3. Verify valid API errors from route and fuel-stop endpoints log the returned `errorCode`.
4. Verify `requestId` is logged on failures when `X-Request-Id` is present.
5. Verify every pre-success `route_request` failure log uses `screenName = search_screen`.
6. Verify no pre-success route loading or route error log is attributed to `results_screen`.

## 14. Definition Of Done

This sprint is done when:

1. The iOS client can complete the full MVP flow from destination selection to Google Maps handoff.
2. Destination search gating is testable and only rendered resolved UK results can enable route calculation.
3. Destination search has an explicit adapter contract for request triggering, top-level response schema, mixed-result filtering, malformed top-level payload handling, provider failure behavior, stale-response discard behavior, and deterministic test coverage.
4. Editing destination text after selection clears the prior selection immediately and prevents stale-coordinate routing.
5. New destination searches clear prior search-state UI deterministically before loading.
6. Route and fuel-stop loading behavior is deterministic and duplicate requests are prevented while requests are in flight.
7. Retry behavior is deterministic for every retryable state, with immediate error clearing, loading-state replacement, exactly one retry attempt per tap, and duplicate retry suppression while in flight.
8. Stale-data handling for new route requests, new fuel-stop requests, route failures after prior success, fuel-stop failures after prior success, invalid route payloads, invalid fuel-stop payloads, and invalid API error payloads is deterministic and covered by automated UI tests.
9. Prior stop selection is cleared on route recalculation and on every new fuel-stop request.
10. Client validation is limited to observable payload rules and does not require backend-only inference.
11. Backend API tests enforce malformed-body handling, exact unknown-field mapping, TTL, corridor filtering, freshness cutoff timing, route-geometry format, route-geometry decodability, detour calculation, normalization, score calculation, score rounding, ranking correctness, and the exact `INVALID_ROUTE_ID` mapping for malformed, expired, and unknown route IDs.
12. The backend API matches the request, response, status-code, validation, geography, ranking, geometry, detour, error-format, and successful-response top-level-object contracts in this document.
13. Google Maps deep-link generation is canonical and exact-string testable.
14. `rank = 1` and `isBestStop` are consistent in every valid fuel-stop success payload, and `isBestStop` is present on every returned stop.
15. Client logging uses the exact keys and canonical enum values defined in Section 8.2 for every listed client-only failure state.
16. The Search Screen owns all route loading, route error UI, and route logging before route success.
17. The explicit Results Screen error inventory includes every fuel-stop and Google Maps error state required after route success.
18. The `OUT_OF_SCOPE_GEOGRAPHY` client UX is neutral and accurate for either origin or destination failure.
19. Every invalid non-2xx response that violates any Section 10.5 rule is handled deterministically as `INVALID_ERROR_RESPONSE`.
20. The deterministic performance suite and artifact defined in Sections 8.1 and 13.4 pass.
21. All acceptance criteria in Section 12 pass.
22. All tests and deterministic verification artifacts in Section 13 pass.
23. No open product or contract questions remain for any in-scope behavior.
