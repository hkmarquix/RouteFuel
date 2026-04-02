import Foundation

enum UITestScenario: String {
    case happyPath = "happy_path"
    case googleMapsFailure = "google_maps_failure"
}

struct UITestDestinationSearchService: DestinationSearchServicing {
    let scenario: UITestScenario

    func searchDestinations(matching query: String) async throws -> [RawDestinationSearchItem] {
        switch scenario {
        case .happyPath, .googleMapsFailure:
            return [
                .init(label: "Birmingham, UK", latitude: 52.4862, longitude: -1.8904, countryCode: "GB")
            ]
        }
    }
}

struct UITestRouteService: RouteServicing {
    func calculateRoute(origin: Coordinate, destination: DestinationSearchResult) async throws -> Route {
        let path = [
            Coordinate(lat: 51.5074, lng: -0.1278),
            Coordinate(lat: 51.9, lng: -0.7),
            Coordinate(lat: 52.2, lng: -1.2),
            Coordinate(lat: 52.4862, lng: -1.8904)
        ]

        return Route(
            id: "ui_test_route",
            origin: origin,
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
}

struct UITestFuelStopService: FuelStopServicing {
    func recommendedStops(for route: Route) async throws -> [FuelStop] {
        [
            FuelStop(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
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
            ),
            FuelStop(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                stationId: "st_002",
                name: "A-Road Fuel Hub",
                address: "A14 Junction 7",
                countryCode: "GB",
                coordinate: Coordinate(lat: 52.2, lng: -1.2),
                fuelType: "regular",
                priceMinorUnits: 145,
                currency: "GBP",
                priceTimestamp: "2026-04-01T08:00:00Z",
                distanceFromRouteMeters: 900,
                detourDurationSeconds: 360,
                score: 0.244,
                rank: 2,
                isBestStop: false
            )
        ]
    }
}

struct UITestLocationService: LocationServicing {
    var isPermissionDenied: Bool { false }

    func requestCurrentLocation() async throws -> Coordinate {
        Coordinate(lat: 51.5074, lng: -0.1278)
    }
}

actor UITestMapsLauncher: MapsLaunching {
    let scenario: UITestScenario
    private var attemptCount = 0

    init(scenario: UITestScenario) {
        self.scenario = scenario
    }

    var canOpenGoogleMaps: Bool {
        get async { true }
    }

    func openInAppleMaps(origin: Coordinate, stop: FuelStop, destination: DestinationSearchResult) async -> Bool {
        true
    }

    func openInGoogleMaps(origin: Coordinate, stop: FuelStop, destination: DestinationSearchResult) async -> Bool {
        attemptCount += 1

        switch scenario {
        case .happyPath:
            return true
        case .googleMapsFailure:
            return attemptCount > 1
        }
    }
}
