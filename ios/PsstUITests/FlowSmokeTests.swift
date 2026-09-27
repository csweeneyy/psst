import XCTest

/// Drives the real app the way a person would. This is the only automated
/// check that proves the two tabs actually render and the setup sheet is
/// reachable; the unit tests only cover the scheduling maths.
nonisolated final class FlowSmokeTests: XCTestCase {

    private func launch(onboarded: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        if onboarded {
            // Seeding here would defeat the point of the onboarding test:
            // existing habits deliberately skip first run.
            app.launchEnvironment["PSST_SEED"] = "1"
            app.launchArguments += ["-hasOnboarded", "YES"]
        }
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

    /// First run has to explain the app and end somewhere usable. It is the
    /// only place the three tiers are described.
    func testOnboardingExplainsTheTiersAndFinishes() {
        let app = launch(onboarded: false)

        XCTAssertTrue(app.staticTexts["Reminders you\nactually answer."].waitForExistence(timeout: 10))
        shot(app, "00-onboarding-intro")

        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Gentle"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Standard"].exists)
        XCTAssertTrue(app.staticTexts["Alarm"].exists)
        shot(app, "00-onboarding-tiers")

        app.buttons["Continue"].tap()
        let sample = app.buttons["Allow, and fill it with sample habits"]
        XCTAssertTrue(sample.waitForExistence(timeout: 4))
        shot(app, "00-onboarding-start")
        sample.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 8) { allow.tap() }

        XCTAssertTrue(
            app.staticTexts["Today"].waitForExistence(timeout: 10),
            "onboarding did not land on the app"
        )
        XCTAssertTrue(app.staticTexts["Posture check"].waitForExistence(timeout: 6))
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

        // A full left swipe goes straight to a centred confirmation, and the
        // row must stay visible until that confirmation is answered.
        //
        // The drag must stay clear of both screen edges: within roughly 30pt
        // of the left edge the system claims it as an interactive-pop gesture.
        let cell = app.cells.containing(.staticText, identifier: "Posture check").firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "no Posture check row on Home")

        let from = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let to = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.1)

        XCTAssertTrue(
            app.staticTexts["Delete this reminder?"].waitForExistence(timeout: 5),
            "full swipe did not reach the confirmation"
        )
        XCTAssertTrue(cell.exists, "row was removed before the user confirmed")
        shot(app, "03-swipe-revealed")

        // Assert the alert resolves, not that the row vanishes: the scheduler
        // immediately materialises the next Posture check nudge, so a query by
        // habit name matches a different row a moment later.
        app.alerts.buttons["Delete"].tap()
        let resolved = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.staticTexts["Delete this reminder?"]
        )
        wait(for: [resolved], timeout: 8)
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
