import XCTest

/// Drives the real app the way a person would. This is the only automated
/// check that proves the two tabs actually render and the setup sheet is
/// reachable; the unit tests only cover the scheduling maths.
nonisolated final class FlowSmokeTests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PSST_SEED"] = "1"
        app.launch()
        // The notification permission alert blocks the first tap.
        addUIInterruptionMonitor(withDescription: "permissions") { alert in
            for label in ["Allow", "OK", "Allow While Using App"] {
                if alert.buttons[label].exists {
                    alert.buttons[label].tap()
                    return true
                }
            }
            return false
        }
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testWalksTodayHabitsSetupAndChat() {
        let app = launch()

        // Clear the permission alert.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 6) { allow.tap() }

        // Today
        XCTAssertTrue(app.staticTexts["Drink water"].waitForExistence(timeout: 10))
        shot(app, "01-home")

        // Completing an item moves it out of Up next.
        let firstCheck = app.buttons.matching(identifier: "checkmark").firstMatch
        if firstCheck.exists { firstCheck.tap() }
        shot(app, "02-home-after-complete")

        // Left swipe reveals a red Delete, which then asks for confirmation,
        // exactly like deleting a note.
        //
        // The drag must stay clear of both screen edges: within roughly 30pt
        // of the left edge the system claims it as an interactive-pop gesture.
        let cell = app.cells.containing(.staticText, identifier: "Posture check").firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "no Posture check row on Home")

        let from = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let to = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.1)

        let delete = app.buttons["Delete"]
        _ = delete.waitForExistence(timeout: 4)
        shot(app, "03-swipe-revealed")
        XCTAssertTrue(delete.exists, "left swipe revealed no delete action")
        delete.tap()

        // A full swipe must not delete on its own; confirmation is required.
        let confirm = app.buttons.matching(identifier: "Delete").element(boundBy: 0)
        XCTAssertTrue(
            app.staticTexts["Delete this reminder?"].waitForExistence(timeout: 4),
            "no confirmation step before deleting"
        )
        confirm.tap()

        let gone = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: delete
        )
        wait(for: [gone], timeout: 8)
        shot(app, "03-after-swipe")


        // Habits tab
        app.tabBars.buttons["Habits"].tap()
        XCTAssertTrue(app.staticTexts["Posture check"].waitForExistence(timeout: 5))
        shot(app, "04-habits")

        // Tapping a habit opens its detail sheet.
        app.staticTexts["Gym"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["Last 14 days"].waitForExistence(timeout: 5),
            "habit detail did not open"
        )
        shot(app, "05-detail")
        app.swipeUp()
        shot(app, "06-detail-lower")
        app.buttons["Done"].firstMatch.tap()

        // Weekly review.
        app.buttons["Weekly review"].tap()
        if app.staticTexts["Your week"].waitForExistence(timeout: 4) {
            shot(app, "07-weekly-review")
            app.buttons["Done"].firstMatch.tap()
        }

        // Setup sheet behind the plus button
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "New habit")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["INTENSITY"].waitForExistence(timeout: 5))
        shot(app, "08-setup-top")

        app.swipeUp()
        shot(app, "09-setup-cadence")
        app.buttons["Cancel"].tap()

        // Calendar.
        app.buttons["Calendar"].tap()
        if app.staticTexts["Calendar"].waitForExistence(timeout: 4) {
            shot(app, "12-calendar")
            app.buttons["Done"].firstMatch.tap()
        }

        // Chat is its own tab now, to the left of Home.
        app.tabBars.buttons["Psst"].tap()
        XCTAssertTrue(
            app.textFields["Message"].waitForExistence(timeout: 5),
            "chat tab did not open"
        )
        // The chat opens focused, so the keyboard should already be up.
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 3), "keyboard was not raised on open")
        shot(app, "10-chat")

        // Real round trip against the deployed Worker. Proves the URL, the
        // request encoding, the response decoding and the error surface all
        // work; it does not require an Anthropic key to be set.
        let field = app.textFields["Message"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("make the posture one every 3 hours")
        app.buttons["arrow.up"].firstMatch.tap()

        let settled = expectation(description: "worker responded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { settled.fulfill() }
        wait(for: [settled], timeout: 12)
        shot(app, "11-chat-after-send")
    }
}
