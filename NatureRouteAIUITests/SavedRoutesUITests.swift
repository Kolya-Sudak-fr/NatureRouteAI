import XCTest

final class SavedRoutesUITests: XCTestCase {
    @MainActor
    func testCancelDeleteConfirmationLeavesSavedRouteVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--seed-saved-route"]
        app.launch()

        app.buttons["Saved routes"].tap()

        let routeCard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "UI Test City")
        ).firstMatch
        XCTAssertTrue(routeCard.waitForExistence(timeout: 5))

        app.buttons["Actions for UI Test City"].tap()
        app.buttons["Delete Route"].tap()
        XCTAssertTrue(app.staticTexts["Delete this route?"].waitForExistence(timeout: 3))

        // On compact iPhone confirmation dialogs can be dismissed by tapping
        // outside the destructive action; this is the user-visible cancel path.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()

        XCTAssertTrue(app.buttons["Actions for UI Test City"].waitForExistence(timeout: 3))
        XCTAssertTrue(routeCard.exists)
    }
}
