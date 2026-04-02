import Foundation

struct AppDependencies {
    let destinationSearchService: any DestinationSearchServicing
    let routeService: any RouteServicing
    let fuelStopService: any FuelStopServicing
    let locationService: any LocationServicing
    let mapsLauncher: any MapsLaunching
    let logger: any ClientLogging

    static func bootstrap(processInfo: ProcessInfo = .processInfo) -> AppDependencies {
        if processInfo.arguments.contains("ROUTEFUEL_UI_TEST_MODE") {
            return .uiTest(processInfo: processInfo)
        }

        return .live
    }

    static let live: AppDependencies = {
        let configuration = EndpointConfiguration.live()
        let sessionConfiguration = URLSessionConfiguration.default
        // Fuel-stop search can legitimately take longer than route creation.
        sessionConfiguration.timeoutIntervalForRequest = configuration.fuelStopRequestTimeoutSeconds
        sessionConfiguration.timeoutIntervalForResource = configuration.fuelStopRequestTimeoutSeconds
        sessionConfiguration.waitsForConnectivity = true

        let client = APIClient(
            session: URLSession(configuration: sessionConfiguration),
            baseURL: configuration.apiBaseURL,
            routeFuelAPIKey: configuration.routeFuelAPIKey
        )

        return AppDependencies(
            destinationSearchService: AppleMapsDestinationSearchService(),
            routeService: LiveRouteService(
                client: client,
                requestTimeoutSeconds: configuration.routeRequestTimeoutSeconds
            ),
            fuelStopService: LiveFuelStopService(
                client: client,
                requestTimeoutSeconds: configuration.fuelStopRequestTimeoutSeconds
            ),
            locationService: LiveLocationService(),
            mapsLauncher: GoogleMapsLauncher(),
            logger: PrintLogger()
        )
    }()

    static let preview = AppDependencies(
        destinationSearchService: MockDestinationSearchService(),
        routeService: MockRouteService(),
        fuelStopService: MockFuelStopService(),
        locationService: PreviewLocationService(),
        mapsLauncher: PreviewMapsLauncher(),
        logger: PrintLogger()
    )

    static func uiTest(processInfo: ProcessInfo = .processInfo) -> AppDependencies {
        let scenarioName = processInfo.environment["ROUTEFUEL_UI_TEST_SCENARIO"] ?? "happy_path"
        let scenario = UITestScenario(rawValue: scenarioName) ?? .happyPath

        return AppDependencies(
            destinationSearchService: UITestDestinationSearchService(scenario: scenario),
            routeService: UITestRouteService(),
            fuelStopService: UITestFuelStopService(),
            locationService: UITestLocationService(),
            mapsLauncher: UITestMapsLauncher(scenario: scenario),
            logger: PrintLogger()
        )
    }
}
