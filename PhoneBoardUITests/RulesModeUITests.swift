import XCTest

final class RulesModeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
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
        let fresh = app.buttons["rules-connect-new"]
        (fresh.exists ? fresh : app.buttons["rules-connect"]).tap()
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
        let fresh = app.buttons["rules-connect-new"]
        (fresh.exists ? fresh : app.buttons["rules-connect"]).tap()
        XCTAssertTrue(app.buttons["rules-start-ai"].waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["rules-start-ai"])
        waitForExpectations(timeout: 10)
        app.buttons["rules-start-ai"].tap()
        let message = app.descendants(matching: .any)["rules-prompt-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 30))
        // Pass priority (the main phase button) through the AI's turn until our main phase, where XMage
        // asks us to play spells and abilities. Who starts is the engine's choice.
        // There's no instruction text during normal play (Arena): the main button's label tells us
        // where we are. "Pass" is the opponent's turn; "Next" or "To Attackers" is our main phase.
        let next = app.buttons["phone-untap-local"]
        let deadline = Date().addingTimeInterval(90)
        func inOurMainPhase() -> Bool {
            next.isEnabled && (next.label.contains("Next") || next.label.contains("Attackers"))
                && message.exists && message.label.localizedCaseInsensitiveContains("Play spells")
        }
        while !inOurMainPhase(), Date() < deadline {
            if app.buttons["Keep Hand"].exists { app.buttons["Keep Hand"].tap() }
            else if message.exists, message.label.localizedCaseInsensitiveContains("starting player"), app.buttons["Magic Board"].exists { app.buttons["Magic Board"].tap() }
            else if next.isEnabled { next.tap() } // pass every other stop (opponent's steps, our upkeep and draw)
            Thread.sleep(forTimeInterval: 0.75)
        }
        XCTAssertTrue(inOurMainPhase(), "Never reached our main phase: \(next.label)")
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
    /// Plays a whole game against the XMage AI through the Phone Play interface, the way a person
    /// would: keep, drag playable cards from the hand, tap lands to pay, tap creatures to attack,
    /// and press the main button for everything else. Fails on any stuck or unsupported prompt.
    @MainActor func testRulesFullGameAgainstTheAIThroughTheInterface() throws {
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
        let fresh = app.buttons["rules-connect-new"]
        (fresh.exists ? fresh : app.buttons["rules-connect"]).tap()
        XCTAssertTrue(app.buttons["rules-start-ai"].waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["rules-start-ai"])
        waitForExpectations(timeout: 10)
        app.buttons["rules-start-ai"].tap()

        let message = app.descendants(matching: .any)["rules-prompt-message"]
        let next = app.buttons["phone-untap-local"]
        let hand = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'phone-hand-'"))
        let fan = app.descendants(matching: .any).matching(identifier: "phone-local-hand").firstMatch
        var played = 0, attacked = 0, stuck = 0, lastState = "", blocked = 0, blocks = 0
        let deadline = Date().addingTimeInterval(12 * 60)
        while Date() < deadline {
            guard app.state == .runningForeground else {
                XCTFail("The app left the foreground during a game gesture")
                break
            }
            if app.staticTexts["Victory"].exists || app.staticTexts["Defeat"].exists || app.staticTexts["Game Over"].exists { break }
            XCTAssertFalse(app.staticTexts["This choice is not supported yet."].exists, "Unsupported prompt: \(message.exists ? message.label : "")")
            let text = message.exists ? message.label : ""
            let state = text + "|" + (next.exists ? next.label : "")
            stuck = state == lastState ? stuck + 1 : 0
            lastState = state
            XCTAssertLessThan(stuck, 40, "Stuck at: \(state)")
            if stuck >= 40 { break }
            if app.alerts.firstMatch.exists {
                XCTFail("Unexpected alert: \(app.alerts.firstMatch.label) \(app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map(\.label))")
                app.alerts.firstMatch.buttons.firstMatch.tap(); continue
            }
            if app.buttons["Keep Hand"].exists { app.buttons["Keep Hand"].tap(); continue }
            if text.localizedCaseInsensitiveContains("starting player"), app.buttons["Magic Board"].exists { app.buttons["Magic Board"].tap(); continue }
            if text.hasPrefix("Pay") {
                // Tap an untapped land to pay, as a person would.
                // Ours are in the lower half (the opponent's lands are at the top).
                let land = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ', untapped'"))
                    .allElementsBoundByIndex.first { $0.frame.midY > app.frame.midY }
                if let land { land.tap(); Thread.sleep(forTimeInterval: 0.6); continue }
            }
            if next.exists, next.isEnabled {
                if next.label.contains("Attack") && !next.label.contains("Attackers") && text.localizedCaseInsensitiveContains("select attackers") && attacked == 0 {
                    // Declare attackers: tap our creatures (the lower half of the screen).
                    let ours = app.buttons.matching(identifier: "phone-creature-card").allElementsBoundByIndex.filter { $0.frame.midY > app.frame.midY }
                    // Keep a creature untapped until a block has been verified. Attacking with all
                    // creatures made the old probe try to block with a tapped creature.
                    for creature in (blocks == 0 ? Array(ours.dropFirst()) : ours) { creature.tap(); Thread.sleep(forTimeInterval: 0.4) }
                    if !ours.isEmpty { attacked += 1 }
                } else if text.localizedCaseInsensitiveContains("select blockers"), blocked < 2, next.label.contains("No") {
                    // Block: drag one of our untapped creatures onto an attacking creature (Phone Play's gesture).
                    let creatures = app.buttons.matching(identifier: "phone-creature-card").allElementsBoundByIndex
                    // An attacking creature carries the orange combat outline ("Attacking").
                    let attacking = app.descendants(matching: .any).matching(identifier: "phone-combat-glow")
                        .matching(NSPredicate(format: "value == 'Attacking'")).firstMatch
                    if let blocker = creatures.first(where: { $0.isHittable && $0.frame.midY > app.frame.midY && ($0.value as? String) == "Untapped" }), attacking.exists {
                        let origin = app.coordinate(withNormalizedOffset: .zero)
                        let target = origin.withOffset(CGVector(dx: attacking.frame.midX, dy: attacking.frame.midY))
                        // A 0.35-second hold opens the card menu; start moving before that threshold.
                        blocker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                            .press(forDuration: 0.1, thenDragTo: target, withVelocity: 300, thenHoldForDuration: 0.8)
                        blocked += 1
                        Thread.sleep(forTimeInterval: 1.0)
                        if next.label.contains("Block") && !next.label.contains("No") { blocks += 1 }
                        continue
                    }
                } else if text.localizedCaseInsensitiveContains("Play spells"),
                          let card = hand.allElementsBoundByIndex.first(where: { ($0.value as? String) == "Playable" }) {
                    if fan.value as? String != "Expanded" { card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap(); Thread.sleep(forTimeInterval: 0.6) }
                    if let target = hand.allElementsBoundByIndex.first(where: { ($0.value as? String) == "Playable" }) {
                        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                            .press(forDuration: 0.3, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.35)), withVelocity: 300, thenHoldForDuration: 0.4)
                        played += 1
                        Thread.sleep(forTimeInterval: 1.0)
                        continue
                    }
                }
                if attacked > 0, !text.localizedCaseInsensitiveContains("select attackers") { attacked = 0 }
                next.tap()
            }
            Thread.sleep(forTimeInterval: 0.6)
        }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Rules mode — end of a full game"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(app.staticTexts["Victory"].exists || app.staticTexts["Defeat"].exists, "The game didn't finish in time (played \(played) cards)")
        XCTAssertGreaterThan(played, 0)
        if blocked > 0 { XCTAssertGreaterThan(blocks, 0, "Dragging a blocker onto an attacker never declared a block") }
        if !text(blocked: blocked, blocks: blocks).isEmpty { print(text(blocked: blocked, blocks: blocks)) }
    }

    /// Uses a deterministic protocol fixture with two attackers, so the drag must answer both
    /// the blocker selection and the subsequent attacker-target prompt.
    @MainActor func testRulesBlockDragAnswersTheFollowUpTarget() throws {
        guard let endpoint = ProcessInfo.processInfo.environment["RULES_BLOCK_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Start BlockPromptFixture and provide RULES_BLOCK_FIXTURE_ADDRESS")
        }
        let app = startFixtureGame(endpoint: endpoint)
        let next = app.buttons["phone-untap-local"]
        expectation(for: NSPredicate(format: "label CONTAINS 'No'"), evaluatedWith: next)
        waitForExpectations(timeout: 5)
        let creatures = app.buttons.matching(identifier: "phone-creature-card").allElementsBoundByIndex
        let blocker = try XCTUnwrap(creatures.first { ($0.value as? String) == "Untapped" && $0.isHittable })
        let attacker = try XCTUnwrap(creatures.first { ($0.value as? String) == "Attacking" && $0.isHittable })
        blocker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: attacker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: 300, thenHoldForDuration: 0.7)
        expectation(for: NSPredicate(format: "label CONTAINS 'Block' AND NOT label CONTAINS 'No'"), evaluatedWith: next)
        waitForExpectations(timeout: 8)
        XCTAssertEqual(next.value as? String, "1 blocking assignments")
        XCTAssertEqual(app.state, .runningForeground)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Rules — blocker assigned by drag through a target prompt"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Exit Game"].waitForExistence(timeout: 5))
        app.buttons["Exit Game"].tap()
        XCTAssertTrue(app.buttons["start-rules"].waitForExistence(timeout: 5))
    }

    @MainActor func testRulesReconnectsAfterAppRelaunchAndClearsSeatOnExit() throws {
        guard let endpoint = ProcessInfo.processInfo.environment["RULES_BLOCK_FIXTURE_ADDRESS"] else { throw XCTSkip("Requires BlockPromptFixture") }
        let app = startFixtureGame(endpoint: endpoint)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["start-rules"].waitForExistence(timeout: 15))
        app.buttons["start-rules"].tap()
        XCTAssertTrue(app.buttons["rules-connect-new"].waitForExistence(timeout: 5), "The relaunched process should load its saved seat")
        app.buttons["rules-connect"].tap()
        XCTAssertTrue(app.buttons["phone-untap-local"].waitForExistence(timeout: 15), "Reconnect should reopen the existing game without creating a new one")
        XCTAssertEqual(app.buttons.matching(identifier: "phone-creature-card").count, 3)
        exitFixtureGame(app)
        app.buttons["start-rules"].tap()
        XCTAssertTrue(app.buttons["rules-connect"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["rules-connect-new"].exists, "Explicit Exit Game must delete the retained seat")
    }

    @MainActor func testRulesFullControlMenuReflectsEngineSetting() throws {
        guard let endpoint = ProcessInfo.processInfo.environment["RULES_BLOCK_FIXTURE_ADDRESS"] else { throw XCTSkip("Requires BlockPromptFixture") }
        let app = startFixtureGame(endpoint: endpoint)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Hold Full Control"].waitForExistence(timeout: 5))
        app.buttons["Hold Full Control"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Release Full Control"].waitForExistence(timeout: 5))
        app.buttons["Release Full Control"].tap()
        exitFixtureGame(app)
    }

    @MainActor private func startFixtureGame(endpoint: String) -> XCUIApplication {
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
        address.typeText(endpoint)
        let key = app.secureTextFields["rules-connection-key"]
        key.tap()
        if let value = key.value as? String { key.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        key.typeText("rules-local-verification-key")
        let fresh = app.buttons["rules-connect-new"]
        (fresh.exists ? fresh : app.buttons["rules-connect"]).tap()
        XCTAssertTrue(app.buttons["rules-start-ai"].waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["rules-start-ai"])
        waitForExpectations(timeout: 5)
        app.buttons["rules-start-ai"].tap()
        let next = app.buttons["phone-untap-local"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        return app
    }

    @MainActor private func exitFixtureGame(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Exit Game"].waitForExistence(timeout: 5))
        app.buttons["Exit Game"].tap()
        XCTAssertTrue(app.buttons["start-rules"].waitForExistence(timeout: 5))
    }

    private func text(blocked: Int, blocks: Int) -> String { "Block attempts \(blocked), blocks declared \(blocks)" }
}
