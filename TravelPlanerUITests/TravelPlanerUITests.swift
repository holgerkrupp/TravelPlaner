import XCTest

@MainActor
final class TravelPlanerUITests: XCTestCase {
    func testLaunchShowsPrimaryTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.buttons["Trips"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Discover"].exists)
        XCTAssertTrue(app.buttons["Saved"].exists)
        XCTAssertTrue(app.buttons["Interests"].exists)
    }
}
