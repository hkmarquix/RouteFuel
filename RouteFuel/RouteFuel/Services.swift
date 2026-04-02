import CoreLocation
import Foundation
import MapKit
import UIKit

protocol DestinationSearchServicing {
    func searchDestinations(matching query: String) async throws -> [RawDestinationSearchItem]
}

protocol RouteServicing {
    func calculateRoute(origin: Coordinate, destination: DestinationSearchResult) async throws -> Route
}

protocol FuelStopServicing {
    func recommendedStops(for route: Route) async throws -> [FuelStop]
}

protocol LocationServicing {
    var isPermissionDenied: Bool { get }
    func requestCurrentLocation() async throws -> Coordinate
}

protocol MapsLaunching {
    var canOpenGoogleMaps: Bool { get async }
    func openInAppleMaps(origin: Coordinate, stop: FuelStop, destination: DestinationSearchResult) async -> Bool
    func openInGoogleMaps(origin: Coordinate, stop: FuelStop, destination: DestinationSearchResult) async -> Bool
}

protocol ClientLogging {
    func log(event: LogEvent)
}

struct LogEvent: Equatable, Sendable {
    let screenName: ScreenName
    let actionName: ActionName
    let errorCode: APIErrorCode?
    let clientStateCode: ClientStateCode?
    let requestId: String?

    init(screenName: ScreenName, actionName: ActionName, errorCode: APIErrorCode, requestId: String? = nil) {
        self.screenName = screenName
        self.actionName = actionName
        self.errorCode = errorCode
        self.clientStateCode = nil
        self.requestId = requestId
    }

    init(screenName: ScreenName, actionName: ActionName, clientStateCode: ClientStateCode, requestId: String? = nil) {
        self.screenName = screenName
        self.actionName = actionName
        self.errorCode = nil
        self.clientStateCode = clientStateCode
        self.requestId = requestId
    }
}

enum LocationServiceError: Error {
    case denied
    case unavailable
}

enum DestinationSearchServiceError: Error {
    case providerUnavailable
    case invalidResponse
}

enum APIServiceError: Error, Equatable {
    case api(code: APIErrorCode, requestId: String?)
    case invalidSuccessResponse(requestId: String?)
    case invalidErrorResponse(requestId: String?)
    case transport
}

final class MockDestinationSearchService: DestinationSearchServicing {
    private let destinations: [RawDestinationSearchItem] = [
        .init(label: "London, UK", latitude: 51.5072, longitude: -0.1276, countryCode: "GB"),
        .init(label: "Manchester, UK", latitude: 53.4808, longitude: -2.2426, countryCode: "GB"),
        .init(label: "Birmingham, UK", latitude: 52.4862, longitude: -1.8904, countryCode: "GB"),
        .init(label: "Leeds, UK", latitude: 53.8008, longitude: -1.5491, countryCode: "GB"),
        .init(label: "Edinburgh, UK", latitude: 55.9533, longitude: -3.1883, countryCode: "GB"),
        .init(label: "Belfast, UK", latitude: 54.5973, longitude: -5.9301, countryCode: "GB"),
        .init(label: "Dublin, Ireland", latitude: 53.3498, longitude: -6.2603, countryCode: "IE"),
        .init(label: nil, latitude: 51.5, longitude: -0.12, countryCode: "GB")
    ]

    func searchDestinations(matching query: String) async throws -> [RawDestinationSearchItem] {
        try await Task.sleep(for: .milliseconds(350))
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return destinations.filter { ($0.label ?? "").lowercased().contains(normalized) }
    }
}

final class MockRouteService: RouteServicing {
    func calculateRoute(origin: Coordinate, destination: DestinationSearchResult) async throws -> Route {
        try await Task.sleep(for: .milliseconds(500))

        let distanceMeters = Int((abs(origin.lat - destination.coordinate.lat) + abs(origin.lng - destination.coordinate.lng)) * 80_000) + 48_000
        let durationSeconds = max(2_700, distanceMeters / 22)
        let path = interpolatePath(from: origin, to: destination.coordinate)
        let bounds = RouteBounds(
            northEast: Coordinate(
                lat: max(origin.lat, destination.coordinate.lat) + 0.2,
                lng: max(origin.lng, destination.coordinate.lng) + 0.2
            ),
            southWest: Coordinate(
                lat: min(origin.lat, destination.coordinate.lat) - 0.2,
                lng: min(origin.lng, destination.coordinate.lng) - 0.2
            )
        )

        return Route(
            id: UUID().uuidString,
            origin: origin,
            destination: destination,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            polyline: PolylineCodec.encode(path),
            path: path,
            bounds: bounds
        )
    }

    private func interpolatePath(from origin: Coordinate, to destination: Coordinate) -> [Coordinate] {
        let waypoints = 24
        return (0 ... waypoints).map { index in
            let progress = Double(index) / Double(waypoints)
            let bend = sin(progress * .pi) * 0.6

            return Coordinate(
                lat: origin.lat + ((destination.lat - origin.lat) * progress) + (bend * 0.35),
                lng: origin.lng + ((destination.lng - origin.lng) * progress) - (bend * 0.35)
            )
        }
    }
}

final class MockFuelStopService: FuelStopServicing {
    func recommendedStops(for route: Route) async throws -> [FuelStop] {
        try await Task.sleep(for: .milliseconds(400))

        let path = route.path
        guard path.count >= 8 else {
            throw APIServiceError.api(code: .noStationsFound, requestId: nil)
        }

        return [
            FuelStop(
                id: UUID(),
                stationId: "st_001",
                name: "Motorway Services South",
                address: "M1 Southbound",
                countryCode: "GB",
                coordinate: path[path.count / 3],
                fuelType: "regular",
                priceMinorUnits: 142,
                currency: "GBP",
                priceTimestamp: "2026-04-01T08:00:00Z",
                distanceFromRouteMeters: 1100,
                detourDurationSeconds: 420,
                score: 0.120,
                rank: 1,
                isBestStop: true
            ),
            FuelStop(
                id: UUID(),
                stationId: "st_002",
                name: "A-Road Fuel Hub",
                address: "A14 Junction 7",
                countryCode: "GB",
                coordinate: path[path.count / 2],
                fuelType: "regular",
                priceMinorUnits: 145,
                currency: "GBP",
                priceTimestamp: "2026-04-01T08:00:00Z",
                distanceFromRouteMeters: 900,
                detourDurationSeconds: 360,
                score: 0.244,
                rank: 2,
                isBestStop: false
            ),
            FuelStop(
                id: UUID(),
                stationId: "st_003",
                name: "Ring Road Services",
                address: "Outer Ring Road",
                countryCode: "GB",
                coordinate: path[(path.count * 2) / 3],
                fuelType: "regular",
                priceMinorUnits: 147,
                currency: "GBP",
                priceTimestamp: "2026-04-01T08:00:00Z",
                distanceFromRouteMeters: 700,
                detourDurationSeconds: 300,
                score: 0.333,
                rank: 3,
                isBestStop: false
            )
        ]
    }
}

@MainActor
final class LiveLocationService: NSObject, LocationServicing, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var locationContinuation: CheckedContinuation<Coordinate, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isPermissionDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    func requestCurrentLocation() async throws -> Coordinate {
        try await ensureAuthorized()

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()

            Task { @MainActor in
                try await Task.sleep(for: .seconds(10))
                guard let locationContinuation else { return }
                self.locationContinuation = nil
                locationContinuation.resume(throwing: LocationServiceError.unavailable)
            }
        }
    }

    private func ensureAuthorized() async throws {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return
        case .notDetermined:
            try await withCheckedThrowingContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            throw LocationServiceError.denied
        @unknown default:
            throw LocationServiceError.unavailable
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let authorizationContinuation else { return }
        self.authorizationContinuation = nil

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            authorizationContinuation.resume()
        case .denied, .restricted:
            authorizationContinuation.resume(throwing: LocationServiceError.denied)
        case .notDetermined:
            self.authorizationContinuation = authorizationContinuation
        @unknown default:
            authorizationContinuation.resume(throwing: LocationServiceError.unavailable)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first, let locationContinuation else { return }
        self.locationContinuation = nil
        locationContinuation.resume(returning: Coordinate(lat: location.coordinate.latitude, lng: location.coordinate.longitude))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard let locationContinuation else { return }
        self.locationContinuation = nil
        locationContinuation.resume(throwing: LocationServiceError.unavailable)
    }
}

struct PreviewLocationService: LocationServicing {
    var isPermissionDenied: Bool { false }

    func requestCurrentLocation() async throws -> Coordinate {
        Coordinate(lat: 51.509865, lng: -0.118092)
    }
}

struct GoogleMapsLauncher: MapsLaunching {
    @MainActor
    var canOpenGoogleMaps: Bool {
        get async {
            guard let appURL = GoogleMapsDeepLinkBuilder.url(
                waypoint: Coordinate(lat: 0, lng: 0),
                destination: Coordinate(lat: 0, lng: 0)
            ) else {
                return false
            }
            return UIApplication.shared.canOpenURL(appURL)
        }
    }

    @MainActor
    func openInAppleMaps(origin: Coordinate, stop: FuelStop, destination: DestinationSearchResult) async -> Bool {
        let originItem = MKMapItem(placemark: MKPlacemark(coordinate: origin.locationCoordinate))
        originItem.name = "Start"

        let destinationItem = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate.locationCoordinate))
        destinationItem.name = destination.label

        let waypointItem = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate.locationCoordinate))
        waypointItem.name = stop.name

        return MKMapItem.openMaps(
            with: [originItem, waypointItem, destinationItem],
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ]
        )
    }

    @MainActor
    func openInGoogleMaps(origin: Coordinate, stop: FuelStop, destination: DestinationSearchResult) async -> Bool {
        guard let appURL = GoogleMapsDeepLinkBuilder.url(
            waypoint: stop.coordinate,
            destination: destination.coordinate
        ),
        let webURL = GoogleMapsDeepLinkBuilder.webURL(
            waypoint: stop.coordinate,
            destination: destination.coordinate
        ) else {
            return false
        }

        if UIApplication.shared.canOpenURL(appURL) {
            return await UIApplication.shared.open(appURL)
        }

        return await UIApplication.shared.open(webURL)
    }
}

struct PreviewMapsLauncher: MapsLaunching {
    var canOpenGoogleMaps: Bool { get async { true } }
    func openInAppleMaps(origin: Coordinate, stop: FuelStop, destination: DestinationSearchResult) async -> Bool { true }
    func openInGoogleMaps(origin: Coordinate, stop: FuelStop, destination: DestinationSearchResult) async -> Bool { true }
}

struct PrintLogger: ClientLogging {
    func log(event: LogEvent) {
        var payload: [String: String] = [
            "screenName": event.screenName.rawValue,
            "actionName": event.actionName.rawValue
        ]

        if let errorCode = event.errorCode {
            payload["errorCode"] = errorCode.rawValue
        }

        if let clientStateCode = event.clientStateCode {
            payload["clientStateCode"] = clientStateCode.rawValue
        }

        if let requestId = event.requestId {
            payload["requestId"] = requestId
        }

        print(payload)
    }
}

struct EndpointConfiguration {
    let apiBaseURL: URL
    let routeFuelAPIKey: String?
    let routeRequestTimeoutSeconds: TimeInterval
    let fuelStopRequestTimeoutSeconds: TimeInterval

    static func live() -> EndpointConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let bundledConfig: [String: String]? = {
            guard
                let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
                let config = NSDictionary(contentsOf: url) as? [String: String]
            else {
                return nil
            }
            return config
        }()

        let apiBaseURLString = environment["ROUTEFUEL_API_BASE_URL"]
            ?? bundledConfig?["AIServiceURL"]
            ?? "http://127.0.0.1:8080"
        let routeFuelAPIKey = environment["ROUTEFUEL_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? bundledConfig?["AuthToken"]
            ?? ""
        return EndpointConfiguration(
            apiBaseURL: URL(string: apiBaseURLString)!,
            routeFuelAPIKey: routeFuelAPIKey.isEmpty == false ? routeFuelAPIKey : nil,
            routeRequestTimeoutSeconds: 30,
            fuelStopRequestTimeoutSeconds: 250
        )
    }
}

final class AppleMapsDestinationSearchService: DestinationSearchServicing {
    func searchDestinations(matching query: String) async throws -> [RawDestinationSearchItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 54.5, longitude: -3.0),
            span: MKCoordinateSpan(latitudeDelta: 10.0, longitudeDelta: 10.0)
        )

        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch {
            throw DestinationSearchServiceError.providerUnavailable
        }

        return response.mapItems.map { item in
            let placemark = item.placemark
            let labelParts = [
                item.name,
                placemark.locality,
                placemark.countryCode == "GB" ? "UK" : placemark.country
            ]
            let label = labelParts
                .compactMap { value -> String? in
                    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                        return nil
                    }
                    return trimmed
                }
                .reduce(into: [String]()) { values, part in
                    if !values.contains(part) {
                        values.append(part)
                    }
                }
                .joined(separator: ", ")

            return RawDestinationSearchItem(
                label: label.isEmpty ? placemark.title : label,
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude,
                countryCode: placemark.countryCode
            )
        }
    }
}

final class LiveRouteService: RouteServicing {
    private let client: APIClient
    private let requestTimeoutSeconds: TimeInterval

    init(client: APIClient, requestTimeoutSeconds: TimeInterval) {
        self.client = client
        self.requestTimeoutSeconds = requestTimeoutSeconds
    }

    func calculateRoute(origin: Coordinate, destination: DestinationSearchResult) async throws -> Route {
        let payload = try await client.post(
            path: "/v1/routes",
            body: [
                "origin": ["lat": origin.lat, "lng": origin.lng],
                "destination": [
                    "lat": destination.coordinate.lat,
                    "lng": destination.coordinate.lng,
                    "label": destination.label
                ],
                "mode": "driving"
            ],
            timeoutInterval: requestTimeoutSeconds
        )

        return try RouteResponseValidator.validate(payload: payload, origin: origin, destination: destination)
    }
}

final class LiveFuelStopService: FuelStopServicing {
    private let client: APIClient
    private let requestTimeoutSeconds: TimeInterval

    init(client: APIClient, requestTimeoutSeconds: TimeInterval) {
        self.client = client
        self.requestTimeoutSeconds = requestTimeoutSeconds
    }

    func recommendedStops(for route: Route) async throws -> [FuelStop] {
        let payload = try await client.post(
            path: "/v1/fuel-stops/search",
            body: [
                "routeId": route.id,
                "fuelType": "regular",
                "currency": "GBP",
                "maxRecommendedStops": 3
            ],
            timeoutInterval: requestTimeoutSeconds
        )

        return try FuelStopsResponseValidator.validate(payload: payload)
    }
}

final class APIClient {
    private let session: URLSession
    private let baseURL: URL
    private let routeFuelAPIKey: String?

    init(session: URLSession = .shared, baseURL: URL, routeFuelAPIKey: String? = nil) {
        self.session = session
        self.baseURL = baseURL
        self.routeFuelAPIKey = routeFuelAPIKey
    }

    func post(path: String, body: [String: Any], timeoutInterval: TimeInterval) async throws -> ValidatedPayload {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval
        if let routeFuelAPIKey {
            request.setValue(routeFuelAPIKey, forHTTPHeaderField: "X-RouteFuel-Key")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIServiceError.transport
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIServiceError.transport
        }

        let requestId = httpResponse.value(forHTTPHeaderField: "X-Request-Id")

        if (200 ... 299).contains(httpResponse.statusCode) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw APIServiceError.invalidSuccessResponse(requestId: requestId)
            }

            return ValidatedPayload(object: object, requestId: requestId)
        }

        throw try APIErrorEnvelopeValidator.validate(data: data, requestId: requestId)
    }
}

struct ValidatedPayload {
    let object: [String: Any]
    let requestId: String?
}

enum APIErrorEnvelopeValidator {
    static func validate(data: Data, requestId: String?) throws -> APIServiceError {
        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let body = json as? [String: Any],
            Set(body.keys) == ["error"],
            let error = body["error"] as? [String: Any],
            Set(error.keys) == ["code", "message"],
            let codeString = error["code"] as? String,
            !codeString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let code = APIErrorCode(rawValue: codeString),
            let message = error["message"] as? String,
            !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw APIServiceError.invalidErrorResponse(requestId: requestId)
        }

        return .api(code: code, requestId: requestId)
    }
}

enum RouteResponseValidator {
    static func validate(payload: ValidatedPayload, origin: Coordinate, destination: DestinationSearchResult) throws -> Route {
        let object = payload.object
        guard Set(object.keys) == ["routeId", "distanceMeters", "durationSeconds", "polyline", "polylineEncoding", "polylinePrecision", "bounds"],
              let routeId = object["routeId"] as? String,
              !routeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let distanceMeters = object["distanceMeters"] as? Int,
              distanceMeters > 0,
              let durationSeconds = object["durationSeconds"] as? Int,
              durationSeconds > 0,
              let polyline = object["polyline"] as? String,
              !polyline.isEmpty,
              let polylineEncoding = object["polylineEncoding"] as? String,
              polylineEncoding == "encoded_polyline",
              let polylinePrecision = object["polylinePrecision"] as? Int,
              polylinePrecision == 5,
              let boundsObject = object["bounds"] as? [String: Any],
              let bounds = parseBounds(boundsObject),
              let path = PolylineCodec.decode(polyline)
        else {
            throw APIServiceError.invalidSuccessResponse(requestId: payload.requestId)
        }

        return Route(
            id: routeId,
            origin: origin,
            destination: destination,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            polyline: polyline,
            path: path,
            bounds: bounds
        )
    }

    private static func parseBounds(_ object: [String: Any]) -> RouteBounds? {
        guard Set(object.keys) == ["northEast", "southWest"],
              let northEastObject = object["northEast"] as? [String: Any],
              let southWestObject = object["southWest"] as? [String: Any],
              let northEast = parseCoordinate(northEastObject),
              let southWest = parseCoordinate(southWestObject),
              northEast.lat >= southWest.lat,
              northEast.lng >= southWest.lng
        else {
            return nil
        }

        return RouteBounds(northEast: northEast, southWest: southWest)
    }

    static func parseCoordinate(_ object: [String: Any]) -> Coordinate? {
        guard Set(object.keys) == ["lat", "lng"],
              let lat = object["lat"] as? Double,
              let lng = object["lng"] as? Double,
              (-90.0 ... 90.0).contains(lat),
              (-180.0 ... 180.0).contains(lng) else {
            return nil
        }

        return Coordinate(lat: lat, lng: lng)
    }
}

enum FuelStopsResponseValidator {
    static func validate(payload: ValidatedPayload) throws -> [FuelStop] {
        let object = payload.object
        let rankingExplanationKeys = [
            "strategy", "priceWeight", "detourWeight", "detourDefinition", "normalizationMethod",
            "singleEligibleStationScore", "equalValueComponentScore", "scoreScale", "routeCorridorMeters", "priceFreshnessHours"
        ]

        guard Set(object.keys) == ["recommendedStops", "rankingExplanation"],
              let recommendedStops = object["recommendedStops"] as? [Any],
              !recommendedStops.isEmpty,
              recommendedStops.count <= 3,
              let rankingExplanation = object["rankingExplanation"] as? [String: Any],
              Set(rankingExplanation.keys) == Set(rankingExplanationKeys),
              rankingExplanation["strategy"] as? String == "weighted_price_and_detour",
              doubleValue(rankingExplanation["priceWeight"]) == 0.6,
              doubleValue(rankingExplanation["detourWeight"]) == 0.4,
              rankingExplanation["detourDefinition"] as? String == "added_driving_time_seconds_origin_to_station_to_destination_minus_origin_to_destination_excluding_dwell_time",
              rankingExplanation["normalizationMethod"] as? String == "min_max_eligible_set",
              doubleValue(rankingExplanation["singleEligibleStationScore"]) == 0.0,
              doubleValue(rankingExplanation["equalValueComponentScore"]) == 0.0,
              rankingExplanation["scoreScale"] as? String == "numeric_rounded_3dp",
              rankingExplanation["routeCorridorMeters"] as? Int == 2000,
              rankingExplanation["priceFreshnessHours"] as? Int == 24
        else {
            throw APIServiceError.invalidSuccessResponse(requestId: payload.requestId)
        }

        let stops = try recommendedStops.enumerated().map { index, item in
            guard let stopObject = item as? [String: Any] else {
                throw APIServiceError.invalidSuccessResponse(requestId: payload.requestId)
            }
            return try parseStop(stopObject, expectedRank: index + 1, requestId: payload.requestId)
        }

        let bestStops = stops.filter(\.isBestStop)
        guard bestStops.count == 1, bestStops.first?.rank == 1 else {
            throw APIServiceError.invalidSuccessResponse(requestId: payload.requestId)
        }

        let stationIDs = Set(stops.map(\.stationId))
        guard stationIDs.count == stops.count else {
            throw APIServiceError.invalidSuccessResponse(requestId: payload.requestId)
        }

        return stops
    }

    private static func parseStop(_ object: [String: Any], expectedRank: Int, requestId: String?) throws -> FuelStop {
        let expectedKeys = [
            "stationId", "name", "address", "countryCode", "location", "fuelType", "priceMinorUnits",
            "currency", "priceTimestamp", "distanceFromRouteMeters", "detourDurationSeconds", "rank", "score", "isBestStop"
        ]

        guard Set(object.keys) == Set(expectedKeys),
              let stationId = object["stationId"] as? String, !stationId.isEmpty,
              let name = object["name"] as? String, !name.isEmpty,
              let address = object["address"] as? String, !address.isEmpty,
              let countryCode = object["countryCode"] as? String, countryCode == "GB",
              let locationObject = object["location"] as? [String: Any],
              let coordinate = RouteResponseValidator.parseCoordinate(locationObject),
              let fuelType = object["fuelType"] as? String, fuelType == "regular",
              let priceMinorUnits = object["priceMinorUnits"] as? Int, priceMinorUnits >= 0,
              let currency = object["currency"] as? String, currency == "GBP",
              let priceTimestamp = object["priceTimestamp"] as? String, isRFC3339UTC(priceTimestamp),
              let distanceFromRouteMeters = object["distanceFromRouteMeters"] as? Int, distanceFromRouteMeters >= 0,
              let detourDurationSeconds = object["detourDurationSeconds"] as? Int, detourDurationSeconds >= 0,
              let rank = object["rank"] as? Int, rank == expectedRank,
              let score = doubleValue(object["score"]), (0.0 ... 1.0).contains(score),
              let isBestStop = object["isBestStop"] as? Bool,
              (rank == 1) == isBestStop || !isBestStop
        else {
            throw APIServiceError.invalidSuccessResponse(requestId: requestId)
        }

        return FuelStop(
            id: UUID(),
            stationId: stationId,
            name: name,
            address: address,
            countryCode: countryCode,
            coordinate: coordinate,
            fuelType: fuelType,
            priceMinorUnits: priceMinorUnits,
            currency: currency,
            priceTimestamp: priceTimestamp,
            distanceFromRouteMeters: distanceFromRouteMeters,
            detourDurationSeconds: detourDurationSeconds,
            score: score,
            rank: rank,
            isBestStop: isBestStop
        )
    }

    private static func isRFC3339UTC(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return value.hasSuffix("Z") && formatter.date(from: value) != nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as Double:
            return number
        case let number as NSNumber:
            return number.doubleValue
        default:
            return nil
        }
    }
}
