import XCTest

final class RulesModeUITests: XCTestCase {
    /// Requires the real bridge on localhost with the test connection key.
    @MainActor func testRulesConnectsAndUsesThePhonePlayInterface() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--rules-ui-test"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["start-host"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["start-join"].exists)
        app.buttons["start-rules"].tap()
        let address = app.textFields["rules-server-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        if let value = address.value as? String { address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        // RULES_UI_TEST_ADDRESS (TEST_RUNNER_RULES_UI_TEST_ADDRESS from xcodebuild) checks a LAN address instead.
        address.typeText(ProcessInfo.processInfo.environment["RULES_UI_TEST_ADDRESS"] ?? "ws://127.0.0.1:17180")
        let key = app.secureTextFields["rules-connection-key"]
        key.tap()
        if let value = key.value as? String { key.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        key.typeText("rules-local-verification-key")
        app.buttons["rules-connect"].tap()
        XCTAssertTrue(app.buttons["rules-start-ai"].waitForExistence(timeout: 30), app.debugDescription)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["rules-start-ai"])
        waitForExpectations(timeout: 10)
        app.buttons["rules-start-ai"].tap()
        XCTAssertTrue(app.staticTexts["rules-prompt-message"].waitForExistence(timeout: 30), app.debugDescription)
        // Phone Play hides the stack control while the engine stack is empty.
        XCTAssertTrue(app.buttons["phone-untap-local"].exists, "Rules mode must use Phone Play's phase/priority control")
        XCTAssertTrue(app.descendants(matching: .any)["phone-local-hand"].exists, "Rules mode must use Phone Play's hand")
        let message = app.staticTexts["rules-prompt-message"]
        if message.label.localizedCaseInsensitiveContains("starting player") {
            app.buttons["Magic Board"].tap()
        }
        let keep = app.buttons["Keep Hand"]
        XCTAssertTrue(keep.waitForExistence(timeout: 15), app.debugDescription)
        keep.tap()
        XCTAssertTrue(app.descendants(matching: .any)["phone-hand-0"].waitForExistence(timeout: 15), "The engine opening hand should appear in Phone Play's card fan")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Rules mode — shared Phone Play interface"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Exit Game"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Reset Decks and Life"].exists, "Rules games must not offer sandbox reset controls")
        app.buttons["Exit Game"].tap()
        XCTAssertTrue(app.buttons["start-host"].waitForExistence(timeout: 5))
    }
    /// Plays a land from the hand by dragging it onto the battlefield, as in normal Phone Play,
    /// and checks the real engine accepted it (the hand shrinks and the next prompt arrives).
    @MainActor func testRulesLandDraggedFromHandIsPlayedByTheEngine() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--rules-ui-test"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["start-rules"].waitForExistence(timeout: 15))
        app.buttons["start-rules"].tap()
        let address = app.textFields["rules-server-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        if let value = address.value as? String { address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        address.typeText(ProcessInfo.processInfo.environment["RULES_UI_TEST_ADDRESS"] ?? "ws://127.0.0.1:17180")
        let key = app.secureTextFields["rules-connection-key"]
        key.tap()
        if let value = key.value as? String { key.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        key.typeText("rules-local-verification-key")
        app.buttons["rules-connect"].tap()
        XCTAssertTrue(app.buttons["rules-start-ai"].waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["rules-start-ai"])
        waitForExpectations(timeout: 10)
        app.buttons["rules-start-ai"].tap()
        let message = app.staticTexts["rules-prompt-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 30))
        if message.label.localizedCaseInsensitiveContains("starting player") { app.buttons["Magic Board"].tap() }
        let keep = app.buttons["Keep Hand"]
        XCTAssertTrue(keep.waitForExistence(timeout: 15))
        keep.tap()
        // Pass priority (the main phase button) through the AI's turn until our main phase, where XMage
        // asks us to play spells and abilities. Who starts is the engine's choice.
        let next = app.buttons["phone-untap-local"]
        let deadline = Date().addingTimeInterval(90)
        while !message.label.localizedCaseInsensitiveContains("Play spells"), Date() < deadline {
            if next.isEnabled, message.label.localizedCaseInsensitiveContains("instants") { next.tap() }
            _ = message.waitForExistence(timeout: 1)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(message.label.localizedCaseInsensitiveContains("Play spells"), "Never reached our main phase: \(message.label)")
        let hand = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'phone-hand-'"))
        XCTAssertTrue(hand.firstMatch.waitForExistence(timeout: 10))
        let before = hand.count
        // Expand the fan first (as in Phone Play's own tests) so the card isn't under its neighbour.
        let fan = app.descendants(matching: .any).matching(identifier: "phone-local-hand").firstMatch
        if fan.value as? String != "Expanded" {
            hand.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
            expectation(for: NSPredicate(format: "value == 'Expanded'"), evaluatedWith: fan)
            waitForExpectations(timeout: 5)
        }
        guard let land = hand.allElementsBoundByIndex.first(where: { $0.label.contains("Plains") }) else {
            throw XCTSkip("The opening hand has no Plains to play")
        }
        land.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.3, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.35)), withVelocity: 300, thenHoldForDuration: 0.5)
        expectation(for: NSPredicate(format: "count == \(before - 1)"), evaluatedWith: hand)
        waitForExpectations(timeout: 15)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Rules mode — land played by the engine"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.staticTexts["This choice is not supported yet."].exists)
    }
}
