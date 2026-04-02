import Combine
import Foundation

@MainActor
final class RoutePlannerViewModel: ObservableObject {
    @Published var originQuery = ""
    @Published var destinationQuery = ""
    @Published private(set) var originResults: [DestinationSearchResult] = []
    @Published private(set) var destinationResults: [DestinationSearchResult] = []
    @Published private(set) var originUsesCurrentLocation = true
    @Published private(set) var selectedOrigin: DestinationSearchResult?
    @Published private(set) var selectedDestination: DestinationSearchResult?
    @Published private(set) var destinationSearchLoading = false
    @Published private(set) var routeLoading = false
    @Published private(set) var recommendationsLoading = false
    @Published private(set) var blockingMessage: BlockingMessage?
    @Published private(set) var zeroResultsVisible = false
    @Published private(set) var tripPlan: TripPlan?
    @Published private(set) var canOpenGoogleMaps = false
    @Published private(set) var appleMapsOpening = false
    @Published private(set) var googleMapsOpening = false
    @Published private(set) var activeSearchTarget: SearchTarget = .destination

    private let dependencies: AppDependencies
    private var latestSubmittedSearch: (target: SearchTarget, query: String)?
    private var lastOrigin: Coordinate?
    private var lastFuelStopRouteID: String?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies

        Task { @MainActor in
            canOpenGoogleMaps = await dependencies.mapsLauncher.canOpenGoogleMaps
        }
    }

    static let preview = RoutePlannerViewModel(dependencies: .preview)

    var canSubmitSearch: Bool {
        !destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !destinationSearchLoading
    }

    var canCalculateRoute: Bool {
        (originUsesCurrentLocation || selectedOrigin != nil) && selectedDestination != nil && !routeLoading && !destinationSearchLoading
    }

    var visibleSearchResults: [DestinationSearchResult] {
        activeSearchTarget == .origin ? originResults : destinationResults
    }

    var selectedSearchResult: DestinationSearchResult? {
        activeSearchTarget == .origin ? selectedOrigin : selectedDestination
    }

    func originQueryChanged(_ newValue: String) {
        originQuery = newValue
        selectedOrigin = nil
        originUsesCurrentLocation = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blockingMessage = nil
        }
    }

    func destinationQueryChanged(_ newValue: String) {
        destinationQuery = newValue
        selectedDestination = nil

        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blockingMessage = nil
        }
    }

    func submitDestinationSearch() async {
        activeSearchTarget = .destination
        await submitSearch(target: .destination, query: destinationQuery)
    }

    func submitOriginSearch() async {
        activeSearchTarget = .origin
        await submitSearch(target: .origin, query: originQuery)
    }

    private func submitSearch(target: SearchTarget, query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !destinationSearchLoading else { return }

        latestSubmittedSearch = (target: target, query: trimmed)
        destinationSearchLoading = true
        zeroResultsVisible = false
        blockingMessage = nil
        clearSearchResults(for: target)

        do {
            let rawItems = try await dependencies.destinationSearchService.searchDestinations(matching: trimmed)
            guard isCurrentSearchResponse(for: target, query: trimmed) else {
                finishDestinationSearch()
                return
            }

            let filtered = DestinationSearchValidator.filterSelectableResults(rawItems)
            assignSearchResults(filtered, for: target)
            zeroResultsVisible = filtered.isEmpty

            if filtered.isEmpty {
                log(clientStateCode: .searchZeroResults, screenName: .searchScreen, actionName: .destinationSearchRequest)
            }
        } catch DestinationSearchServiceError.invalidResponse {
            guard isCurrentSearchResponse(for: target, query: trimmed) else {
                finishDestinationSearch()
                return
            }

            log(clientStateCode: .invalidDestinationSearchResponse, screenName: .searchScreen, actionName: .destinationSearchRequest)
            blockingMessage = BlockingMessage(
                title: "Search unavailable",
                body: "Destination search is temporarily unavailable. Try again.",
                retryAction: .destinationSearch
            )
        } catch {
            guard isCurrentSearchResponse(for: target, query: trimmed) else {
                finishDestinationSearch()
                return
            }

            log(clientStateCode: .searchProviderUnavailable, screenName: .searchScreen, actionName: .destinationSearchRequest)
            blockingMessage = BlockingMessage(
                title: "Search unavailable",
                body: "Destination search is temporarily unavailable. Try again.",
                retryAction: .destinationSearch
            )
        }

        finishDestinationSearch()
    }

    func selectOrigin(_ result: DestinationSearchResult) {
        originUsesCurrentLocation = false
        selectedOrigin = result
    }

    func selectDestination(_ result: DestinationSearchResult) {
        selectedDestination = result
    }

    func selectSearchResult(_ result: DestinationSearchResult) {
        switch activeSearchTarget {
        case .origin:
            selectOrigin(result)
        case .destination:
            selectDestination(result)
        }
    }

    func activateSearchTarget(_ target: SearchTarget) {
        activeSearchTarget = target
        zeroResultsVisible = false
        blockingMessage = nil
    }

    func calculateRoute() async {
        guard let destination = selectedDestination, !routeLoading else { return }

        routeLoading = true
        recommendationsLoading = false
        blockingMessage = nil
        tripPlan = nil

        do {
            let origin = try await resolveOrigin()
            lastOrigin = origin

            do {
                let route = try await dependencies.routeService.calculateRoute(origin: origin, destination: destination)
                tripPlan = TripPlan(route: route, recommendedStops: [], selectedStop: nil)
                routeLoading = false
                await loadRecommendations(for: route)
            } catch let error as APIServiceError {
                routeLoading = false
                handleRouteError(error)
            } catch {
                routeLoading = false
                handleRouteError(.transport)
            }
        } catch LocationServiceError.denied {
            routeLoading = false
            log(clientStateCode: .locationPermissionDenied, screenName: .searchScreen, actionName: .routeStartTap)
            blockingMessage = BlockingMessage(
                title: "Location required",
                body: "Current location is required to plan a route.",
                retryAction: nil
            )
        } catch {
            routeLoading = false
            log(clientStateCode: .currentLocationUnavailable, screenName: .searchScreen, actionName: .routeStartTap)
            blockingMessage = BlockingMessage(
                title: "Current location unavailable",
                body: "Current location is temporarily unavailable. Try again.",
                retryAction: .location
            )
        }
    }

    private func resolveOrigin() async throws -> Coordinate {
        if originUsesCurrentLocation {
            return try await dependencies.locationService.requestCurrentLocation()
        }

        guard let selectedOrigin else {
            throw LocationServiceError.unavailable
        }

        return selectedOrigin.coordinate
    }

    func selectCurrentLocation() {
        originUsesCurrentLocation = true
        selectedOrigin = nil
        blockingMessage = nil
    }

    private func clearSearchResults(for target: SearchTarget) {
        switch target {
        case .origin:
            originResults = []
            selectedOrigin = nil
            originUsesCurrentLocation = false
        case .destination:
            destinationResults = []
            selectedDestination = nil
        }
    }

    private func assignSearchResults(_ results: [DestinationSearchResult], for target: SearchTarget) {
        switch target {
        case .origin:
            originResults = results
        case .destination:
            destinationResults = results
        }
    }

    private func isCurrentSearchResponse(for target: SearchTarget, query: String) -> Bool {
        guard let latestSubmittedSearch else { return false }
        let currentQuery = target == .origin ? originQuery : destinationQuery
        return latestSubmittedSearch.target == target
            && latestSubmittedSearch.query == query
            && currentQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query
    }

    func loadRecommendations(for route: Route) async {
        guard !recommendationsLoading else { return }

        recommendationsLoading = true
        blockingMessage = nil

        if var tripPlan {
            tripPlan.recommendedStops = []
            tripPlan.selectedStop = nil
            self.tripPlan = tripPlan
        }

        do {
            let stops = try await dependencies.fuelStopService.recommendedStops(for: route)
            lastFuelStopRouteID = route.id
            tripPlan = TripPlan(route: route, recommendedStops: Array(stops.prefix(3)), selectedStop: nil)
        } catch let error as APIServiceError {
            handleFuelStopError(error, route: route)
        } catch {
            handleFuelStopError(.transport, route: route)
        }

        recommendationsLoading = false
    }

    func selectStop(_ stop: FuelStop) {
        guard var tripPlan else { return }
        tripPlan.selectedStop = stop
        self.tripPlan = tripPlan
    }

    func openInGoogleMaps() async {
        guard
            !googleMapsOpening,
            let tripPlan,
            let stop = tripPlan.selectedStop,
            let origin = lastOrigin
        else {
            return
        }

        blockingMessage = nil
        googleMapsOpening = true

        let success = await dependencies.mapsLauncher.openInGoogleMaps(
            origin: origin,
            stop: stop,
            destination: tripPlan.route.destination
        )
        googleMapsOpening = false

        if !success {
            log(clientStateCode: .googleMapsUnavailable, screenName: .resultsScreen, actionName: .googleMapsOpen)
            blockingMessage = BlockingMessage(
                title: "Google Maps unavailable",
                body: "Google Maps could not be opened. Try again.",
                retryAction: .openGoogleMaps
            )
        }
    }

    func openInAppleMaps() async {
        guard
            !appleMapsOpening,
            let tripPlan,
            let stop = tripPlan.selectedStop,
            let origin = lastOrigin
        else {
            return
        }

        blockingMessage = nil
        appleMapsOpening = true

        let success = await dependencies.mapsLauncher.openInAppleMaps(
            origin: origin,
            stop: stop,
            destination: tripPlan.route.destination
        )
        appleMapsOpening = false

        if !success {
            blockingMessage = BlockingMessage(
                title: "Apple Maps unavailable",
                body: "Apple Maps could not be opened. Try again.",
                retryAction: .openAppleMaps
            )
        }
    }

    func retry() async {
        let retryAction = blockingMessage?.retryAction
        blockingMessage = nil

        switch retryAction {
        case .destinationSearch:
            await submitDestinationSearch()
        case .location:
            await calculateRoute()
        case .route:
            await calculateRoute()
        case .fuelStops:
            if let route = tripPlan?.route {
                await loadRecommendations(for: route)
            }
        case .openAppleMaps:
            await openInAppleMaps()
        case .openGoogleMaps:
            await openInGoogleMaps()
        case nil:
            break
        }
    }

    func resetTrip() {
        tripPlan = nil
        recommendationsLoading = false
        blockingMessage = nil
        appleMapsOpening = false
        googleMapsOpening = false
    }

    private func finishDestinationSearch() {
        destinationSearchLoading = false
    }

    private func handleRouteError(_ error: APIServiceError) {
        switch error {
        case .api(let code, let requestId):
            log(errorCode: code, screenName: .searchScreen, actionName: .routeRequest, requestId: requestId)
            blockingMessage = routeMessage(for: code)
        case .invalidSuccessResponse(let requestId):
            log(clientStateCode: .invalidSuccessResponse, screenName: .searchScreen, actionName: .routeRequest, requestId: requestId)
            blockingMessage = unexpectedResponseMessage()
        case .invalidErrorResponse(let requestId):
            log(clientStateCode: .invalidErrorResponse, screenName: .searchScreen, actionName: .routeRequest, requestId: requestId)
            blockingMessage = unexpectedResponseMessage()
        case .transport:
            log(errorCode: .upstreamProviderUnavailable, screenName: .searchScreen, actionName: .routeRequest, requestId: nil)
            blockingMessage = routeMessage(for: .upstreamProviderUnavailable)
        }
    }

    private func handleFuelStopError(_ error: APIServiceError, route: Route) {
        switch error {
        case .api(let code, let requestId):
            log(errorCode: code, screenName: .resultsScreen, actionName: .fuelStopRequest, requestId: requestId)
            blockingMessage = fuelStopMessage(for: code)
        case .invalidSuccessResponse(let requestId):
            log(clientStateCode: .invalidSuccessResponse, screenName: .resultsScreen, actionName: .fuelStopRequest, requestId: requestId)
            blockingMessage = unexpectedResponseMessage()
        case .invalidErrorResponse(let requestId):
            log(clientStateCode: .invalidErrorResponse, screenName: .resultsScreen, actionName: .fuelStopRequest, requestId: requestId)
            blockingMessage = unexpectedResponseMessage()
        case .transport:
            log(errorCode: .upstreamProviderUnavailable, screenName: .resultsScreen, actionName: .fuelStopRequest, requestId: nil)
            blockingMessage = fuelStopMessage(for: .upstreamProviderUnavailable)
        }

        if var tripPlan {
            tripPlan.recommendedStops = []
            tripPlan.selectedStop = nil
            self.tripPlan = tripPlan
        } else {
            tripPlan = TripPlan(route: route, recommendedStops: [], selectedStop: nil)
        }
    }

    private func routeMessage(for code: APIErrorCode) -> BlockingMessage {
        switch code {
        case .invalidJSONBody:
            return .init(title: "Route request invalid", body: "The route request was invalid.", retryAction: nil)
        case .invalidRouteRequestFields:
            return .init(title: "Route request invalid", body: "The route request fields were invalid.", retryAction: nil)
        case .invalidCoordinates:
            return .init(title: "Route request invalid", body: "The route request used invalid coordinates.", retryAction: nil)
        case .invalidDestination:
            return .init(title: "Destination unavailable", body: "Choose a different destination.", retryAction: nil)
        case .outOfScopeGeography:
            return .init(title: "Route out of scope", body: "Current location and destination must both be in the United Kingdom.", retryAction: nil)
        case .unsupportedMode:
            return .init(title: "Route request invalid", body: "The route request used an unsupported mode.", retryAction: nil)
        case .routeNotFound:
            return .init(title: "Route unavailable", body: "A route could not be found for this destination.", retryAction: nil)
        case .upstreamProviderUnavailable:
            return .init(title: "Service unavailable", body: "Route data is temporarily unavailable. Try again.", retryAction: .route)
        default:
            return unexpectedResponseMessage()
        }
    }

    private func fuelStopMessage(for code: APIErrorCode) -> BlockingMessage {
        switch code {
        case .invalidJSONBody:
            return .init(title: "Fuel stop request invalid", body: "The fuel stop request was invalid.", retryAction: nil)
        case .invalidFuelStopRequestFields:
            return .init(title: "Fuel stop request invalid", body: "The fuel stop request fields were invalid.", retryAction: nil)
        case .invalidRouteID:
            return .init(title: "Route unavailable", body: "Route data is invalid or no longer available. Calculate the route again.", retryAction: nil)
        case .unsupportedFuelType:
            return .init(title: "Fuel stop request invalid", body: "The fuel type is unsupported.", retryAction: nil)
        case .invalidCurrency:
            return .init(title: "Fuel stop request invalid", body: "The currency is invalid.", retryAction: nil)
        case .invalidMaxRecommendedStops:
            return .init(title: "Fuel stop request invalid", body: "The requested number of fuel stops is invalid.", retryAction: nil)
        case .noStationsFound:
            return .init(title: "No fuel stops found", body: "No ranked fuel stops are available for this route. Try again.", retryAction: .fuelStops)
        case .upstreamProviderUnavailable:
            return .init(title: "Service unavailable", body: "Fuel stop data is temporarily unavailable. Try again.", retryAction: .fuelStops)
        default:
            return unexpectedResponseMessage()
        }
    }

    private func unexpectedResponseMessage() -> BlockingMessage {
        .init(
            title: "Unexpected service response",
            body: "The app received an unexpected response. Try again later.",
            retryAction: nil
        )
    }

    private func log(errorCode: APIErrorCode, screenName: ScreenName, actionName: ActionName, requestId: String?) {
        dependencies.logger.log(event: LogEvent(screenName: screenName, actionName: actionName, errorCode: errorCode, requestId: requestId))
    }

    private func log(clientStateCode: ClientStateCode, screenName: ScreenName, actionName: ActionName, requestId: String? = nil) {
        dependencies.logger.log(event: LogEvent(screenName: screenName, actionName: actionName, clientStateCode: clientStateCode, requestId: requestId))
    }
}
