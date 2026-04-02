import Combine
import Foundation
import MapKit
import Testing
@testable import RouteFuel

@MainActor
struct RouteFuelTests {

    @Test func destinationSearchFiltersMalformedAndNonUKItems() {
        let results = DestinationSearchValidator.filterSelectableResults([
            .init(label: " London ", latitude: 51.5072, longitude: -0.1276, countryCode: "GB"),
            .init(label: "Dublin", latitude: 53.3498, longitude: -6.2603, countryCode: "IE"),
            .init(label: nil, latitude: 51.5, longitude: -0.12, countryCode: "GB"),
            .init(label: "Bad Lng", latitude: 51.5, longitude: 200, countryCode: "GB")
        ])

        #expect(results.count == 1)
        #expect(results.first?.label == "London")
        #expect(results.first?.countryCode == "GB")
    }

    @Test func googleMapsDeepLinkUsesCanonicalFormat() {
        let waypoint = Coordinate(lat: 52.4862, lng: -1.8904)
        let destination = Coordinate(lat: 53.4808, lng: -2.2426)

        let url = GoogleMapsDeepLinkBuilder.url(waypoint: waypoint, destination: destination)

        #expect(
            url?.absoluteString
                == "comgooglemaps:?saddr=Current%20Location&daddr=52.486200,-1.890400+to:53.480800,-2.242600&directionsmode=driving"
        )
    }

    @Test func googleMapsWebFallbackUsesDirectionsFormat() {
        let waypoint = Coordinate(lat: 52.4862, lng: -1.8904)
        let destination = Coordinate(lat: 53.4808, lng: -2.2426)

        let url = GoogleMapsDeepLinkBuilder.webURL(waypoint: waypoint, destination: destination)

        #expect(
            url?.absoluteString
                == "https://www.google.com/maps/dir/?api=1&origin=Current%20Location&destination=53.480800,-2.242600&waypoints=52.486200,-1.890400&travelmode=driving"
        )
    }

    @Test func fuelPriceFormattingKeepsTwoDecimalPlaces() {
        let stop = FuelStop(
            id: UUID(),
            stationId: "st_001",
            name: "Shell Example",
            address: "123 Example Rd",
            countryCode: "GB",
            coordinate: Coordinate(lat: 51.9, lng: -1.3),
            fuelType: "regular",
            priceMinorUnits: 140,
            currency: "GBP",
            priceTimestamp: "2026-04-01T08:00:00Z",
            distanceFromRouteMeters: 100,
            detourDurationSeconds: 359,
            score: 0.12,
            rank: 1,
            isBestStop: true
        )

        #expect(stop.priceText == "£1.40")
        #expect(stop.detourText == "5 min detour")
    }

    @Test func routeApiFailureShowsRouteSpecificMessage() async {
        let logger = SpyLogger()
        let dependencies = AppDependencies(
            destinationSearchService: StubDestinationSearchService(),
            routeService: FailingRouteService(error: .api(code: .routeNotFound, requestId: "req-1")),
            fuelStopService: StubFuelStopService(),
            locationService: StubLocationService(),
            mapsLauncher: StubMapsLauncher(),
            logger: logger
        )

        let viewModel = RoutePlannerViewModel(dependencies: dependencies)
        let destination = DestinationSearchResult(
            id: UUID(),
            label: "Birmingham, UK",
            coordinate: Coordinate(lat: 52.4862, lng: -1.8904),
            countryCode: "GB"
        )

        viewModel.selectDestination(destination)
        await viewModel.calculateRoute()

        #expect(viewModel.blockingMessage?.title == "Route unavailable")
        #expect(viewModel.blockingMessage?.body == "A route could not be found for this destination.")
        #expect(logger.events == [
            LogEvent(screenName: .searchScreen, actionName: .routeRequest, errorCode: .routeNotFound, requestId: "req-1")
        ])
    }

    @Test func fuelStopInvalidSuccessResponseClearsRecommendationsButKeepsRoute() async {
        let logger = SpyLogger()
        let route = makeRoute()
        let dependencies = AppDependencies(
            destinationSearchService: StubDestinationSearchService(),
            routeService: StubRouteService(route: route),
            fuelStopService: FailingFuelStopService(error: .invalidSuccessResponse(requestId: "req-2")),
            locationService: StubLocationService(),
            mapsLauncher: StubMapsLauncher(),
            logger: logger
        )

        let viewModel = RoutePlannerViewModel(dependencies: dependencies)
        viewModel.selectDestination(route.destination)

        await viewModel.calculateRoute()

        #expect(viewModel.tripPlan?.route.id == route.id)
        #expect(viewModel.tripPlan?.recommendedStops.isEmpty == true)
        #expect(viewModel.blockingMessage?.title == "Unexpected service response")
        #expect(logger.events.contains(LogEvent(
            screenName: .resultsScreen,
            actionName: .fuelStopRequest,
            clientStateCode: .invalidSuccessResponse,
            requestId: "req-2"
        )))
    }

    @Test func routeMapViewportKeepsAxisAlignedRoutesRenderable() {
        let northSouthRoute = [
            Coordinate(lat: 51.5, lng: -1.2),
            Coordinate(lat: 52.0, lng: -1.2),
            Coordinate(lat: 52.5, lng: -1.2)
        ]

        let region = RouteMapViewport.region(for: northSouthRoute)

        #expect(region.center.latitude == 52.0)
        #expect(region.center.longitude == -1.2)
        #expect(region.span.latitudeDelta > 1.0)
        #expect(region.span.longitudeDelta == 0.05)
    }

    @Test func googleMapsOpenSuppressesDuplicateAttemptsWhileInFlight() async {
        let route = makeRoute()
        let stop = makeStop()
        let launcher = RecordingMapsLauncher(results: [true], delayNanoseconds: 150_000_000)
        let dependencies = AppDependencies(
            destinationSearchService: StubDestinationSearchService(),
            routeService: StubRouteService(route: route),
            fuelStopService: StubFuelStopService(),
            locationService: StubLocationService(),
            mapsLauncher: launcher,
            logger: SpyLogger()
        )

        let viewModel = RoutePlannerViewModel(dependencies: dependencies)
        viewModel.selectDestination(route.destination)
        await viewModel.calculateRoute()
        viewModel.selectStop(stop)

        async let firstOpen: Void = viewModel.openInGoogleMaps()
        async let secondOpen: Void = viewModel.openInGoogleMaps()
        _ = await (firstOpen, secondOpen)

        #expect(await launcher.callCount == 1)
        #expect(viewModel.blockingMessage == nil)
        #expect(viewModel.googleMapsOpening == false)
    }

    @Test func googleMapsFailureLogsRetryableMessageAndRetryMakesOneNewAttempt() async {
        let logger = SpyLogger()
        let route = makeRoute()
        let stop = makeStop()
        let launcher = RecordingMapsLauncher(results: [false, true], delayNanoseconds: 80_000_000)
        let dependencies = AppDependencies(
            destinationSearchService: StubDestinationSearchService(),
            routeService: StubRouteService(route: route),
            fuelStopService: StubFuelStopService(),
            locationService: StubLocationService(),
            mapsLauncher: launcher,
            logger: logger
        )

        let viewModel = RoutePlannerViewModel(dependencies: dependencies)
        viewModel.selectDestination(route.destination)
        await viewModel.calculateRoute()
        viewModel.selectStop(stop)

        await viewModel.openInGoogleMaps()

        #expect(viewModel.blockingMessage?.title == "Google Maps unavailable")
        #expect(viewModel.tripPlan?.selectedStop == stop)
        #expect(logger.events.contains(LogEvent(
            screenName: .resultsScreen,
            actionName: .googleMapsOpen,
            clientStateCode: .googleMapsUnavailable
        )))

        async let firstRetry: Void = viewModel.retry()
        async let secondRetry: Void = viewModel.retry()
        _ = await (firstRetry, secondRetry)

        #expect(await launcher.callCount == 2)
        #expect(viewModel.blockingMessage == nil)
        #expect(viewModel.tripPlan?.selectedStop == stop)
    }

    @Test func liveEndpointConfigurationUsesFuelStopFriendlyTimeouts() {
        let previousBaseURL = ProcessInfo.processInfo.environment["ROUTEFUEL_API_BASE_URL"]
        let previousAPIKey = ProcessInfo.processInfo.environment["ROUTEFUEL_API_KEY"]
        unsetenv("ROUTEFUEL_API_BASE_URL")
        unsetenv("ROUTEFUEL_API_KEY")
        defer {
            restoreEnvironmentVariable("ROUTEFUEL_API_BASE_URL", to: previousBaseURL)
            restoreEnvironmentVariable("ROUTEFUEL_API_KEY", to: previousAPIKey)
        }

        let configuration = EndpointConfiguration.live()

        #expect(configuration.apiBaseURL.absoluteString == "http://devaiservices.traland.com/api/routefuel")
        #expect(configuration.routeFuelAPIKey == "uwe7892sdfjxzcv98092134jskd")
        #expect(configuration.routeRequestTimeoutSeconds == 30)
        #expect(configuration.fuelStopRequestTimeoutSeconds == 250)
    }

    @Test func fuelStopValidatorAcceptsEquivalentJsonNumberTypes() throws {
        let payload = ValidatedPayload(
            object: [
                "recommendedStops": [
                    [
                        "stationId": "st_001",
                        "name": "SHELL THIRSK",
                        "address": "THIRSK, YO7 3HL",
                        "countryCode": "GB",
                        "location": ["lat": 54.194661, "lng": -1.364059],
                        "fuelType": "regular",
                        "priceMinorUnits": 155,
                        "currency": "GBP",
                        "priceTimestamp": "2026-04-02T10:47:03Z",
                        "distanceFromRouteMeters": 283,
                        "detourDurationSeconds": 0,
                        "rank": 1,
                        "score": 0.3,
                        "isBestStop": true
                    ]
                ],
                "rankingExplanation": [
                    "strategy": "weighted_price_and_detour",
                    "priceWeight": 0.6,
                    "detourWeight": 0.4,
                    "detourDefinition": "added_driving_time_seconds_origin_to_station_to_destination_minus_origin_to_destination_excluding_dwell_time",
                    "normalizationMethod": "min_max_eligible_set",
                    "singleEligibleStationScore": 0,
                    "equalValueComponentScore": 0,
                    "scoreScale": "numeric_rounded_3dp",
                    "routeCorridorMeters": 2000,
                    "priceFreshnessHours": 24
                ]
            ],
            requestId: "req-3"
        )

        let stops = try FuelStopsResponseValidator.validate(payload: payload)

        #expect(stops.count == 1)
        #expect(stops.first?.stationId == "st_001")
        #expect(stops.first?.score == 0.3)
    }

    @Test func calculateRouteUsesSelectedOriginWithoutRequestingCurrentLocation() async {
        let route = makeRoute()
        let routeService = RecordingRouteService(route: route)
        let locationService = RecordingLocationService()
        let dependencies = AppDependencies(
            destinationSearchService: StubDestinationSearchService(),
            routeService: routeService,
            fuelStopService: StubFuelStopService(),
            locationService: locationService,
            mapsLauncher: StubMapsLauncher(),
            logger: SpyLogger()
        )

        let viewModel = RoutePlannerViewModel(dependencies: dependencies)
        let origin = DestinationSearchResult(
            id: UUID(),
            label: "Leeds, UK",
            coordinate: Coordinate(lat: 53.8008, lng: -1.5491),
            countryCode: "GB"
        )

        viewModel.selectOrigin(origin)
        viewModel.selectDestination(route.destination)
        await viewModel.calculateRoute()

        let capturedOrigin = await routeService.capturedOrigin
        #expect(capturedOrigin == origin.coordinate)
        #expect(await locationService.callCount == 0)
    }
}

private func restoreEnvironmentVariable(_ name: String, to previousValue: String?) {
    if let previousValue {
        setenv(name, previousValue, 1)
    } else {
        unsetenv(name)
    }
}

private struct StubDestinationSearchService: DestinationSearchServicing {
    func searchDestinations(matching query: String) async throws -> [RawDestinationSearchItem] { [] }
}

private struct StubRouteService: RouteServicing {
    let route: Route

    func calculateRoute(origin: Coordinate, destination: DestinationSearchResult) async throws -> Route { route }
}

private struct FailingRouteService: RouteServicing {
    let error: APIServiceError

    func calculateRoute(origin: Coordinate, destination: DestinationSearchResult) async throws -> Route { throw error }
}

private struct StubFuelStopService: FuelStopServicing {
    func recommendedStops(for route: Route) async throws -> [FuelStop] { [] }
}

private struct FailingFuelStopService: FuelStopServicing {
    let error: APIServiceError

    func recommendedStops(for route: Route) async throws -> [FuelStop] { throw error }
}

private struct StubLocationService: LocationServicing {
    var isPermissionDenied: Bool { false }

    func requestCurrentLocation() async throws -> Coordinate {
        Coordinate(lat: 51.5074, lng: -0.1278)
    }
}

private struct StubMapsLauncher: MapsLaunching {
    var canOpenGoogleMaps: Bool { get async { true } }
    func openInAppleMaps(origin: Coordinate, stop: FuelStop, destination: DestinationSearchResult) async -> Bool { true }
    func openInGoogleMaps(origin: Coordinate, stop: FuelStop, destination: DestinationSearchResult) async -> Bool { true }
}

private actor RecordingRouteService: RouteServicing {
    let route: Route
    private(set) var capturedOrigin: Coordinate?

    init(route: Route) {
        self.route = route
    }

    func calculateRoute(origin: Coordinate, destination: DestinationSearchResult) async throws -> Route {
        capturedOrigin = origin
        return route
    }
}

private actor RecordingLocationService: LocationServicing {
    var isPermissionDenied: Bool { false }
    private(set) var callCount = 0

    func requestCurrentLocation() async throws -> Coordinate {
        callCount += 1
        return Coordinate(lat: 51.5074, lng: -0.1278)
    }
}

private actor RecordingMapsLauncher: MapsLaunching {
    private let results: [Bool]
    private let delayNanoseconds: UInt64
    private var index = 0
    private(set) var callCount = 0

    init(results: [Bool], delayNanoseconds: UInt64) {
        self.results = results
        self.delayNanoseconds = delayNanoseconds
    }

    var canOpenGoogleMaps: Bool {
        get async { true }
    }

    func openInAppleMaps(origin: Coordinate, stop: FuelStop, destination: DestinationSearchResult) async -> Bool {
        true
    }

    func openInGoogleMaps(origin: Coordinate, stop: FuelStop, destination: DestinationSearchResult) async -> Bool {
        callCount += 1

        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }

        let result = index < results.count ? results[index] : results.last ?? false
        index += 1
        return result
    }
}

private final class SpyLogger: ClientLogging {
    private(set) var events: [LogEvent] = []

    func log(event: LogEvent) {
        events.append(event)
    }
}

@MainActor
private func makeRoute() -> Route {
    let destination = DestinationSearchResult(
        id: UUID(),
        label: "Birmingham, UK",
        coordinate: Coordinate(lat: 52.4862, lng: -1.8904),
        countryCode: "GB"
    )
    let path = [
        Coordinate(lat: 51.5074, lng: -0.1278),
        Coordinate(lat: 51.9, lng: -0.7),
        Coordinate(lat: 52.4862, lng: -1.8904)
    ]

    return Route(
        id: "route_123",
        origin: Coordinate(lat: 51.5074, lng: -0.1278),
        destination: destination,
        distanceMeters: 203_450,
        durationSeconds: 9_410,
        polyline: PolylineCodec.encode(path),
        path: path,
        bounds: RouteBounds(
            northEast: Coordinate(lat: 52.6, lng: -0.1),
            southWest: Coordinate(lat: 51.4, lng: -1.9)
        )
    )
}

private func makeStop() -> FuelStop {
    FuelStop(
        id: UUID(),
        stationId: "st_001",
        name: "Motorway Services South",
        address: "M1 Southbound",
        countryCode: "GB",
        coordinate: Coordinate(lat: 51.9, lng: -0.7),
        fuelType: "regular",
        priceMinorUnits: 142,
        currency: "GBP",
        priceTimestamp: "2026-04-01T08:00:00Z",
        distanceFromRouteMeters: 1100,
        detourDurationSeconds: 420,
        score: 0.12,
        rank: 1,
        isBestStop: true
    )
}
