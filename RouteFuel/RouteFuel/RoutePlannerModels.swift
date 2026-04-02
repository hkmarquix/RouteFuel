import CoreLocation
import Foundation

struct Coordinate: Codable, Equatable, Hashable, Sendable {
    let lat: Double
    let lng: Double

    init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }

    init(latitude: Double, longitude: Double) {
        self.init(lat: latitude, lng: longitude)
    }

    var latitude: Double { lat }
    var longitude: Double { lng }
    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var googleMapsValue: String {
        "\(Self.googleMapsFormatter.string(from: NSNumber(value: lat))!),\(Self.googleMapsFormatter.string(from: NSNumber(value: lng))!)"
    }

    private static let googleMapsFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 6
        formatter.maximumFractionDigits = 6
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false
        return formatter
    }()
}

struct DestinationSearchResult: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let label: String
    let coordinate: Coordinate
    let countryCode: String
}

struct RouteBounds: Equatable, Sendable {
    let northEast: Coordinate
    let southWest: Coordinate
}

struct Route: Equatable, Sendable {
    let id: String
    let origin: Coordinate
    let destination: DestinationSearchResult
    let distanceMeters: Int
    let durationSeconds: Int
    let polyline: String
    let path: [Coordinate]
    let bounds: RouteBounds

    var distanceText: String {
        let kilometers = Double(distanceMeters) / 1_000
        return kilometers.formatted(.number.precision(.fractionLength(1))) + " km"
    }

    var durationText: String {
        let minutes = durationSeconds / 60
        return "\(minutes) min"
    }
}

struct FuelStop: Identifiable, Equatable, Sendable {
    let id: UUID
    let stationId: String
    let name: String
    let address: String
    let countryCode: String
    let coordinate: Coordinate
    let fuelType: String
    let priceMinorUnits: Int
    let currency: String
    let priceTimestamp: String
    let distanceFromRouteMeters: Int
    let detourDurationSeconds: Int
    let score: Double
    let rank: Int
    let isBestStop: Bool

    var priceText: String {
        "\(priceMinorUnits)p"
    }

    var detourText: String {
        "\(detourDurationSeconds / 60) min detour"
    }
}

struct TripPlan: Equatable, Sendable {
    let route: Route
    var recommendedStops: [FuelStop]
    var selectedStop: FuelStop?
}

struct RawDestinationSearchItem: Sendable {
    let label: String?
    let latitude: Double?
    let longitude: Double?
    let countryCode: String?
}

enum ScreenName: String, Sendable {
    case searchScreen = "search_screen"
    case resultsScreen = "results_screen"
}

enum ActionName: String, Sendable {
    case destinationSearchRequest = "destination_search_request"
    case routeStartTap = "route_start_tap"
    case routeRequest = "route_request"
    case fuelStopRequest = "fuel_stop_request"
    case googleMapsOpen = "google_maps_open"
}

enum ClientStateCode: String, Sendable {
    case locationPermissionDenied = "LOCATION_PERMISSION_DENIED"
    case currentLocationUnavailable = "CURRENT_LOCATION_UNAVAILABLE"
    case searchZeroResults = "SEARCH_ZERO_RESULTS"
    case searchProviderUnavailable = "SEARCH_PROVIDER_UNAVAILABLE"
    case invalidDestinationSearchResponse = "INVALID_DESTINATION_SEARCH_RESPONSE"
    case googleMapsUnavailable = "GOOGLE_MAPS_UNAVAILABLE"
    case invalidSuccessResponse = "INVALID_SUCCESS_RESPONSE"
    case invalidErrorResponse = "INVALID_ERROR_RESPONSE"
}

enum APIErrorCode: String, Sendable, CaseIterable {
    case invalidJSONBody = "INVALID_JSON_BODY"
    case invalidRouteRequestFields = "INVALID_ROUTE_REQUEST_FIELDS"
    case invalidCoordinates = "INVALID_COORDINATES"
    case invalidDestination = "INVALID_DESTINATION"
    case outOfScopeGeography = "OUT_OF_SCOPE_GEOGRAPHY"
    case unsupportedMode = "UNSUPPORTED_MODE"
    case routeNotFound = "ROUTE_NOT_FOUND"
    case invalidFuelStopRequestFields = "INVALID_FUEL_STOP_REQUEST_FIELDS"
    case invalidRouteID = "INVALID_ROUTE_ID"
    case unsupportedFuelType = "UNSUPPORTED_FUEL_TYPE"
    case invalidCurrency = "INVALID_CURRENCY"
    case invalidMaxRecommendedStops = "INVALID_MAX_RECOMMENDED_STOPS"
    case noStationsFound = "NO_STATIONS_FOUND"
    case upstreamProviderUnavailable = "UPSTREAM_PROVIDER_UNAVAILABLE"
}

enum SearchTarget: String, Sendable {
    case origin
    case destination
}

struct BlockingMessage: Equatable {
    let title: String
    let body: String
    let retryAction: RetryAction?

    enum RetryAction: Equatable {
        case destinationSearch
        case location
        case route
        case fuelStops
        case openAppleMaps
        case openGoogleMaps
    }
}
