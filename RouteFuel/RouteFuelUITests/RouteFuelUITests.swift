import XCTest

final class RouteFuelUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("ROUTEFUEL_UI_TEST_MODE")
    }

    @MainActor
    func testHappyPathShowsMapRecommendationsAndGoogleMapsCTAAfterSelection() throws {
        app.launchEnvironment["ROUTEFUEL_UI_TEST_SCENARIO"] = "happy_path"
        app.launch()

        let destinationField = app.textFields["destination-query-field"]
        destinationField.tap()
        destinationField.typeText("Birmingham")

        app.buttons["destination-search-button"].tap()
        app.buttons["destination-result-Birmingham, UK"].tap()
        app.buttons["calculate-route-button"].tap()

        XCTAssertTrue(app.otherElements["route-map"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Finding fuel stops..."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Motorway Services South"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["open-google-maps-button"].exists)

        app.buttons["Motorway Services South"].tap()

        XCTAssertTrue(app.buttons["open-google-maps-button"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testGoogleMapsFailureShowsRetryableBlockingMessage() throws {
        app.launchEnvironment["ROUTEFUEL_UI_TEST_SCENARIO"] = "google_maps_failure"
        app.launch()

        let destinationField = app.textFields["destination-query-field"]
        destinationField.tap()
        destinationField.typeText("Birmingham")

        app.buttons["destination-search-button"].tap()
        app.buttons["destination-result-Birmingham, UK"].tap()
        app.buttons["calculate-route-button"].tap()

        XCTAssertTrue(app.staticTexts["Motorway Services South"].waitForExistence(timeout: 2))
        app.buttons["Motorway Services South"].tap()
        app.buttons["open-google-maps-button"].tap()

        XCTAssertTrue(app.staticTexts["Google Maps unavailable"].waitForExistence(timeout: 2))
        app.buttons["blocking-retry-button"].tap()
        XCTAssertFalse(app.staticTexts["Google Maps unavailable"].waitForExistence(timeout: 2))
    }
}
