import XCTest

final class RulesModeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    /// Requires the real bridge on localhost with the test connection key.
    @MainActor func testRulesConnectsAndUsesThePhonePlayInterface() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--rules-ui-test", "--rules-manual-connect"]
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
        key.typeText(ProcessInfo.processInfo.environment["RULES_UI_TEST_KEY"] ?? "rules-local-verification-key")
        let fresh = app.buttons["rules-connect-new"]
        (fresh.exists ? fresh : app.buttons["rules-connect"]).tap()
        XCTAssertTrue(app.buttons["rules-start-ai"].waitForExistence(timeout: 30), app.debugDescription)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["rules-start-ai"])
        waitForExpectations(timeout: 10)
        app.buttons["rules-start-ai"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["rules-prompt-message"].waitForExistence(timeout: 30), app.debugDescription)
        // Phone Play hides the stack control while the engine stack is empty.
        XCTAssertTrue(app.buttons["phone-untap-local"].exists, "Rules mode must use Phone Play's phase/priority control")
        // (Phone Play's hand is hidden behind the opening-hand browser until we keep.)
        let message = app.descendants(matching: .any)["rules-prompt-message"]
        if message.label.localizedCaseInsensitiveContains("starting player") {
            app.buttons["Magic Board"].tap()
        }
        let keep = keepButton(app)
        XCTAssertTrue(keep.waitForExistence(timeout: 15), app.debugDescription)
        keep.tap()
        XCTAssertTrue(app.descendants(matching: .any)["phone-hand-0"].waitForExistence(timeout: 15), "The engine opening hand should appear in Phone Play's card fan")
        // Phase lights sit by each life total; only the active player's row shows a phase.
        let localPhases = app.descendants(matching: .any)["rules-phase-markers-local"]
        let opponentPhases = app.descendants(matching: .any)["rules-phase-markers-opponent"]
        XCTAssertTrue(localPhases.waitForExistence(timeout: 5) && opponentPhases.exists, app.debugDescription)
        let lit = [localPhases, opponentPhases].filter { ($0.value as? String) != "Inactive" }
        XCTAssertEqual(lit.count, 1, "\(localPhases.value ?? "") / \(opponentPhases.value ?? "")")
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
        app.launchArguments = ["--rules-ui-test", "--rules-manual-connect"]
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
        key.typeText(ProcessInfo.processInfo.environment["RULES_UI_TEST_KEY"] ?? "rules-local-verification-key")
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
        // where we are. "Pass" (with a "To …" caption) is the opponent's turn; "Next" is our main phase.
        let next = app.buttons["phone-untap-local"]
        let deadline = Date().addingTimeInterval(90)
        func inOurMainPhase() -> Bool {
            next.isEnabled && !next.label.contains("Pass") && (next.label.contains("Next") || next.label.contains("Attackers"))
                && message.exists && message.label.localizedCaseInsensitiveContains("Play spells")
        }
        while !inOurMainPhase(), Date() < deadline {
            if keepButton(app).exists { keepButton(app).tap() }
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
        // Arena's pass shortcuts: hold the main button and pass until our next turn.
        let main = app.buttons["phone-untap-local"]
        XCTAssertTrue(main.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: main)
        waitForExpectations(timeout: 15)
        main.press(forDuration: 1.0)
        let nextTurn = app.buttons["My Next Turn"]
        XCTAssertTrue(nextTurn.waitForExistence(timeout: 5), "Holding the main button should offer pass shortcuts")
        nextTurn.tap()
        // XMage skips ahead to our next turn: the opponent's turn passes without our input, and our
        // draw step adds a card to the hand before our main phase asks again.
        let handBefore = hand.count
        let turnLater = Date().addingTimeInterval(90)
        while Date() < turnLater {
            if hand.count > handBefore, message.exists, message.label.localizedCaseInsensitiveContains("Play spells") { break }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertGreaterThan(hand.count, handBefore, "Passing to our next turn should draw a card")
        XCTAssertTrue(message.exists && message.label.localizedCaseInsensitiveContains("Play spells"),
                      "Passing to our next turn should come back to our main phase: \(message.exists ? message.label : "")")
    }
    /// Plays a whole game against the XMage AI through the Phone Play interface, the way a person
    /// would: keep, drag playable cards from the hand, tap lands to pay, tap creatures to attack,
    /// and press the main button for everything else. Fails on any stuck or unsupported prompt.
    @MainActor func testRulesFullGameAgainstTheAIThroughTheInterface() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--rules-ui-test", "--rules-manual-connect"]
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
        key.typeText(ProcessInfo.processInfo.environment["RULES_UI_TEST_KEY"] ?? "rules-local-verification-key")
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
        var manualPayments = 0, played = 0, attacked = 0, stuck = 0, lastState = "", blocked = 0, blocks = 0
        // Arena's life-change cue on either player's life total.
        let lifeChange = app.descendants(matching: .any).matching(identifier: "life-change")
            .matching(NSPredicate(format: "label BEGINSWITH 'Life changed'")).firstMatch
        var sawLifeChange = false, cancelChecked = false
        let deadline = Date().addingTimeInterval(12 * 60)
        while Date() < deadline {
            guard app.state == .runningForeground else {
                XCTFail("The app left the foreground during a game gesture")
                break
            }
            if !sawLifeChange, lifeChange.exists {
                sawLifeChange = true
                let cue = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                cue.name = "Rules mode — life change (\(lifeChange.label))"
                cue.lifetime = .keepAlways
                add(cue)
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
            if keepButton(app).exists { keepButton(app).tap(); continue }
            if text.localizedCaseInsensitiveContains("starting player"), app.buttons["Magic Board"].exists { app.buttons["Magic Board"].tap(); continue }
            if text.hasPrefix("Pay") {
                // Basic lands are tapped automatically (Arena); only tap by hand if it doesn't happen.
                Thread.sleep(forTimeInterval: 2.0)
                if !(message.exists && message.label == text) { continue }
                manualPayments += 1
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
                    let attackers = blocks == 0 ? Array(ours.dropFirst()) : ours
                    for creature in attackers { creature.tap(); Thread.sleep(forTimeInterval: 0.4) }
                    // Once, with two or more declared: Cancel Attacks clears them all, then declare again.
                    if !cancelChecked, attackers.count >= 2, app.buttons["rules-secondary-action"].waitForExistence(timeout: 3),
                       app.buttons["rules-secondary-action"].label == "Cancel Attacks" {
                        cancelChecked = true
                        app.buttons["rules-secondary-action"].tap()
                        let cleared = NSPredicate(format: "label == 'All Attack' OR label == 'No Attacks'")
                        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: cleared, evaluatedWith: next)], timeout: 12), .completed,
                                       "Cancel Attacks left attackers declared: \(next.label)")
                        for creature in attackers { creature.tap(); Thread.sleep(forTimeInterval: 0.4) }
                    }
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
                    if fan.value as? String != "Expanded" {
                        try visibleHandPoint(card, in: app).tap()
                        let expanded = expectation(for: NSPredicate(format: "value == 'Expanded'"), evaluatedWith: fan)
                        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 4), .completed,
                                       "Tap the visible hand image, not the overlapping fast-forward menu")
                    }
                    if let target = hand.allElementsBoundByIndex.first(where: { ($0.value as? String) == "Playable" }) {
                        try visibleHandPoint(target, in: app)
                            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.35)), withVelocity: 300, thenHoldForDuration: 0.4)
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
        XCTAssertEqual(manualPayments, 0, "The all-Plains deck should pay its mana automatically")
        XCTAssertTrue(sawLifeChange, "No life change was shown during a whole game")
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
            .press(forDuration: 0.1, thenDragTo: attacker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: 1500, thenHoldForDuration: 0)
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
        app.launchArguments.removeAll { $0 == "--rules-manual-connect" }
        app.launch()
        XCTAssertTrue(app.buttons["start-rules"].waitForExistence(timeout: 15))
        app.buttons["start-rules"].tap()
        XCTAssertTrue(app.buttons["phone-untap-local"].waitForExistence(timeout: 15), "Opening Rules Game should automatically resume the saved seat without a connection-button tap")
        XCTAssertEqual(app.buttons.matching(identifier: "phone-creature-card").count, 3)
        exitFixtureGame(app)
        app.buttons["start-rules"].tap()
        XCTAssertTrue(app.buttons["rules-start-ai"].waitForExistence(timeout: 15), "The saved server reconnects after Exit, but the exited game must not reopen")
        XCTAssertFalse(app.buttons["phone-untap-local"].exists)
        app.buttons["Disconnect"].tap()
        XCTAssertTrue(app.buttons["rules-connect"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons["rules-connect"].exists, "Explicit Disconnect must not start a reconnection loop")
        XCTAssertFalse(app.buttons["rules-start-ai"].exists)
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
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Order Triggers Manually"].waitForExistence(timeout: 5))
        app.buttons["Order Triggers Manually"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Order Triggers Automatically"].waitForExistence(timeout: 5))
        app.buttons["Order Triggers Automatically"].tap()
        exitFixtureGame(app)
    }

    @MainActor func testRulesTriggerOrderingSelectsAnAbilityCard() throws {
        guard let endpoint = ProcessInfo.processInfo.environment["RULES_BLOCK_FIXTURE_ADDRESS"] else { throw XCTSkip("Requires BlockPromptFixture") }
        let app = startFixtureGame(endpoint: endpoint + "/ordering")
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rules-prompt-card-'"))
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(choices.count, 2)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Trigger choices rendered as stack ability cards"
        attachment.lifetime = .keepAlways
        add(attachment)
        choices.element(boundBy: 0).tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'No'"), evaluatedWith: app.buttons["phone-untap-local"])
        waitForExpectations(timeout: 8)
        exitFixtureGame(app)
    }

    @MainActor private func startFixtureGame(endpoint: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--rules-ui-test", "--rules-manual-connect"]
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
        key.typeText(ProcessInfo.processInfo.environment["RULES_UI_TEST_KEY"] ?? "rules-local-verification-key")
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

    /// Two-player Rules game: this phone creates a waiting game, a second seat joins it (run
    /// `SecondSeatBot` against the same bridge first; set TEST_RUNNER_RULES_SECOND_SEAT=1), the creator
    /// starts it, and this phone plays several of its own cards through the interface. Checks the
    /// two-human lobby and turn flow from the phone's side with real XMage seats.
    @MainActor func testRulesTwoPlayerGameAgainstASecondSeat() throws {
        guard ProcessInfo.processInfo.environment["RULES_SECOND_SEAT"] == "1" else {
            throw XCTSkip("Start SecondSeatBot and set TEST_RUNNER_RULES_SECOND_SEAT=1 to run this check")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--rules-ui-test", "--rules-manual-connect"]
        // TEST_RUNNER_RULES_UI_TEST_PACKETS=JumpStart (or "Jump In"): draft two packets for this seat first.
        let packets = ProcessInfo.processInfo.environment["RULES_UI_TEST_PACKETS"]
        if let packets { app.launchArguments += ["-rules.deckSource", "\"\(packets)\""] }
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
        key.typeText(ProcessInfo.processInfo.environment["RULES_UI_TEST_KEY"] ?? "rules-local-verification-key")
        let fresh = app.buttons["rules-connect-new"]
        (fresh.exists ? fresh : app.buttons["rules-connect"]).tap()
        XCTAssertTrue(app.buttons["rules-create-human"].waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["rules-create-human"])
        waitForExpectations(timeout: 10)
        app.buttons["rules-create-human"].tap()
        if packets != nil {
            let choice = app.buttons.matching(identifier: "rules-packet-choice")
            XCTAssertTrue(choice.firstMatch.waitForExistence(timeout: 10), "Creating a packet game should offer packets")
            choice.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Choose Second Packet"].waitForExistence(timeout: 5))
            choice.firstMatch.tap()
        }
        let start = app.buttons["rules-start-human"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "Creating the waiting game failed")
        // The second seat polls for waiting games every second; start once it has had time to join.
        var startedAt: Date?
        for _ in 0..<15 where startedAt == nil {
            Thread.sleep(forTimeInterval: 2)
            guard start.exists, start.isEnabled else { break }
            start.tap()
            if app.descendants(matching: .any)["rules-prompt-message"].waitForExistence(timeout: 6) { startedAt = Date() }
        }
        XCTAssertNotNil(startedAt, "The two-player game never started (did SecondSeatBot join?)")

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
            if played >= 4 { break } // enough of our own turns against a real second seat
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
            if keepButton(app).exists { keepButton(app).tap(); continue }
            if text.localizedCaseInsensitiveContains("starting player"), app.buttons["Player 1"].exists { app.buttons["Player 1"].tap(); continue }
            // A target on the board (a removal spell, an aura): tap a highlighted card, else the opponent.
            if text.localizedCaseInsensitiveContains("select a") || text.localizedCaseInsensitiveContains("target") {
                let glow = app.descendants(matching: .any).matching(identifier: "phone-combat-glow").matching(NSPredicate(format: "value == 'Playable'")).firstMatch
                if glow.exists {
                    app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: glow.frame.midX, dy: glow.frame.midY)).tap()
                    Thread.sleep(forTimeInterval: 0.8); continue
                }
                if app.buttons["rules-target-opponent"].exists { app.buttons["rules-target-opponent"].tap(); Thread.sleep(forTimeInterval: 0.8); continue }
                if app.buttons["phone-browser-done"].exists && app.buttons["phone-browser-done"].isEnabled {
                    app.buttons["phone-browser-done"].tap(); Thread.sleep(forTimeInterval: 0.4); continue
                }
                let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rules-prompt-card-'")).firstMatch
                if card.exists && card.isHittable { card.tap(); Thread.sleep(forTimeInterval: 0.8); continue }
            }
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
        screenshot.name = "Rules mode — two-player game"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertGreaterThanOrEqual(played, 2, "This phone barely got to play against the second seat")
        // The other seat's hand stays hidden: no opponent card names in our hand list.
        XCTAssertLessThanOrEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'phone-hand-'")).count, 10)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.6)
        if app.buttons["Exit Game"].waitForExistence(timeout: 5) { app.buttons["Exit Game"].tap() }
    }

    private func text(blocked: Int, blocks: Int) -> String { "Block attempts \(blocked), blocks declared \(blocks)" }
    /// Plays several turns of an imported deck against the AI through the interface, answering
    /// whatever XMage asks the way a person would (modal choices, cards to pick, targets on the
    /// board, players). Set TEST_RUNNER_RULES_UI_TEST_DECK to a deck list ("24 Plains\n…"); it's
    /// pasted via the remembered deck setting. Fails on unsupported, stuck or alert states.
    @MainActor func testRulesImportedDeckGameAnswersEveryPrompt() throws {
        guard let deck = ProcessInfo.processInfo.environment["RULES_UI_TEST_DECK"], !deck.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_RULES_UI_TEST_DECK to a deck list to run this check")
        }
        let requiredPrompts = (ProcessInfo.processInfo.environment["RULES_UI_TEST_REQUIRED_PROMPTS"] ?? "")
            .split(separator: "|").map(String.init)
        let app = XCUIApplication()
        // Launch-argument defaults are parsed as property lists: quote the value so its "\n" escapes
        // become line breaks (unquoted, only the first line would arrive).
        app.launchArguments = ["--rules-ui-test", "--rules-manual-connect", "-rules.deckList", "\"" + deck.replacingOccurrences(of: "\"", with: "") + "\""]
        // TEST_RUNNER_RULES_UI_TEST_MANUAL_MANA=1 turns automatic payment off, to exercise the Auto button.
        let manualMana = ProcessInfo.processInfo.environment["RULES_UI_TEST_MANUAL_MANA"] == "1"
        if manualMana { app.launchArguments += ["-rules.autoPayMana", "NO"] }
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
        key.typeText(ProcessInfo.processInfo.environment["RULES_UI_TEST_KEY"] ?? "rules-local-verification-key")
        let fresh = app.buttons["rules-connect-new"]
        (fresh.exists ? fresh : app.buttons["rules-connect"]).tap()
        XCTAssertTrue(app.buttons["rules-start-ai"].waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["rules-start-ai"])
        waitForExpectations(timeout: 10)
        app.buttons["rules-start-ai"].tap()
        if !app.buttons["phone-untap-local"].waitForExistence(timeout: 30) {
            if app.keyboards.firstMatch.exists { app.keyboards.buttons["return"].firstMatch.tap() }
            app.swipeUp(); app.swipeUp()
            XCTFail("The game didn't start. Texts on screen: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
            return
        }

        // TEST_RUNNER_RULES_UI_TEST_MANUAL_TRIGGERS=1: switch to ordering triggers by hand from the
        // battlefield menu at our first main phase.
        var manualTriggersPending = ProcessInfo.processInfo.environment["RULES_UI_TEST_MANUAL_TRIGGERS"] == "1"
        let message = app.descendants(matching: .any)["rules-prompt-message"]
        let next = app.buttons["phone-untap-local"]
        let hand = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'phone-hand-'"))
        let fan = app.descendants(matching: .any).matching(identifier: "phone-local-hand").firstMatch
        var played = 0, stuck = 0, lastState = "", attackedTurn = "", activatedTurn = "", allAttacks = 0, activations = 0, autoButton = 0
        var seen: [String] = []
        let deadline = Date().addingTimeInterval(10 * 60)
        while Date() < deadline {
            if app.staticTexts["Victory"].exists || app.staticTexts["Defeat"].exists || app.staticTexts["Game Over"].exists { break }
            if played >= 10 { break }
            if app.alerts.firstMatch.exists {
                XCTFail("Unexpected alert: \(app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map(\.label))")
                app.alerts.firstMatch.buttons.firstMatch.tap(); continue
            }
            XCTAssertFalse(app.staticTexts["This choice is not supported yet."].exists, "Unsupported prompt: \(message.exists ? message.label : "")")
            let text = message.exists ? message.label : ""
            if !text.isEmpty, seen.last != text { seen.append(text) }
            let toast = app.staticTexts["rules-toast"]
            if toast.exists, seen.last != "toast: " + toast.label { seen.append("toast: " + toast.label) }
            XCTAssertFalse(toast.exists && toast.label.hasPrefix("Couldn't read"), "Unreadable update: \(toast.label)")
            if !requiredPrompts.isEmpty, played >= 4,
               requiredPrompts.allSatisfy({ required in seen.contains { $0.localizedCaseInsensitiveContains(required) } }),
               text.hasPrefix("Play ") { break }
            let state = text + "|" + (next.exists ? next.label : "")
            stuck = state == lastState ? stuck + 1 : 0
            lastState = state
            XCTAssertLessThan(stuck, 40, "Stuck at: \(state)")
            if stuck >= 40 { break }
            if manualTriggersPending, text.localizedCaseInsensitiveContains("Play spells") {
                manualTriggersPending = false
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.6)
                let manual = app.buttons["Order Triggers Manually"]
                XCTAssertTrue(manual.waitForExistence(timeout: 5), "The battlefield menu should offer manual trigger ordering")
                if manual.exists { manual.tap() }
                Thread.sleep(forTimeInterval: 1.0)
                continue
            }
            if keepButton(app).exists { keepButton(app).tap(); continue }
            if text.localizedCaseInsensitiveContains("starting player"), app.buttons["Magic Board"].exists { app.buttons["Magic Board"].tap(); continue }
            // Full-screen decisions: pick the first option or card, as a player might.
            let choice = app.buttons.matching(identifier: "rules-choice").firstMatch
            if choice.exists && choice.isHittable { choice.tap(); Thread.sleep(forTimeInterval: 0.8); continue }
            if app.buttons["phone-browser-done"].exists && app.buttons["phone-browser-done"].isEnabled {
                app.buttons["phone-browser-done"].tap(); Thread.sleep(forTimeInterval: 0.4); continue
            }
            let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rules-prompt-card-'")).firstMatch
            if card.exists && card.isHittable { card.tap(); Thread.sleep(forTimeInterval: 0.8); continue }
            for title in ["Confirm", "Yes", "Done"] where app.buttons[title].exists && app.buttons[title].isHittable {
                app.buttons[title].tap(); Thread.sleep(forTimeInterval: 0.8); break
            }
            // Targets on the board glow ("Playable"): tap one; otherwise target the opponent.
            if text.localizedCaseInsensitiveContains("target") || text.localizedCaseInsensitiveContains("select") && !text.localizedCaseInsensitiveContains("attackers") && !text.localizedCaseInsensitiveContains("blockers") {
                // A card to choose from our hand (an alternative cost, a discard…) is outlined in the hand.
                if let handChoice = hand.allElementsBoundByIndex.first(where: { ($0.value as? String) == "Playable" }) {
                    handChoice.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
                    Thread.sleep(forTimeInterval: 0.8); continue
                }
                let glow = app.descendants(matching: .any).matching(identifier: "phone-combat-glow").matching(NSPredicate(format: "value == 'Playable'")).firstMatch
                if glow.exists {
                    app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: glow.frame.midX, dy: glow.frame.midY)).tap()
                    Thread.sleep(forTimeInterval: 0.8); continue
                }
                if app.buttons["rules-target-opponent"].exists { app.buttons["rules-target-opponent"].tap(); Thread.sleep(forTimeInterval: 0.8); continue }
            }
            if text.hasPrefix("Pay"), app.buttons["rules-auto-pay"].exists {
                app.buttons["rules-auto-pay"].tap(); autoButton += 1
                // One tap pays the whole cost (Josh), not one mana: unless what's left needs a land
                // Auto can't use (then the button goes away), the payment prompt is gone shortly.
                let paid = Date().addingTimeInterval(4)
                while Date() < paid, message.exists, message.label.hasPrefix("Pay"), app.buttons["rules-auto-pay"].exists {
                    Thread.sleep(forTimeInterval: 0.2)
                }
                XCTAssertFalse(message.exists && message.label.hasPrefix("Pay") && app.buttons["rules-auto-pay"].exists,
                               "Auto paid only part of the cost: \(message.label)")
                continue
            }
            if text.hasPrefix("Pay") {
                Thread.sleep(forTimeInterval: 2.0)
                if !(message.exists && message.label == text) { continue }
                let land = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ', untapped'"))
                    .allElementsBoundByIndex.first { $0.frame.midY > app.frame.midY }
                if let land { land.tap(); Thread.sleep(forTimeInterval: 0.6); continue }
            }
            if next.exists, next.isEnabled {
                if text.localizedCaseInsensitiveContains("select attackers"), attackedTurn != state {
                    attackedTurn = state
                    // Arena's "All Attack" declares every creature that can attack.
                    if next.label.hasPrefix("All Attack") {
                        next.tap(); allAttacks += 1
                        Thread.sleep(forTimeInterval: 2.0)
                    } else {
                        for creature in app.buttons.matching(identifier: "phone-creature-card").allElementsBoundByIndex where creature.frame.midY > app.frame.midY {
                            creature.tap(); Thread.sleep(forTimeInterval: 0.4)
                        }
                    }
                } else if text.localizedCaseInsensitiveContains("Play spells"), activatedTurn != state,
                          !hand.allElementsBoundByIndex.contains(where: { ($0.value as? String) == "Playable" }),
                          app.descendants(matching: .any).matching(identifier: "phone-combat-glow").matching(NSPredicate(format: "value == 'Playable'")).firstMatch.exists {
                    // Nothing to play from hand: use a permanent's ability (equip, loyalty…) as a player would.
                    activatedTurn = state
                    let glow = app.descendants(matching: .any).matching(identifier: "phone-combat-glow").matching(NSPredicate(format: "value == 'Playable'")).firstMatch
                    app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: glow.frame.midX, dy: glow.frame.midY)).tap()
                    activations += 1
                    Thread.sleep(forTimeInterval: 1.0); continue
                } else if text.localizedCaseInsensitiveContains("Play spells"),
                          let playable = hand.allElementsBoundByIndex.first(where: { ($0.value as? String) == "Playable" }) {
                    if fan.value as? String != "Expanded" { playable.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap(); Thread.sleep(forTimeInterval: 0.6) }
                    if let target = hand.allElementsBoundByIndex.first(where: { ($0.value as? String) == "Playable" }) {
                        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                            .press(forDuration: 0.3, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.35)), withVelocity: 300, thenHoldForDuration: 0.4)
                        played += 1
                        Thread.sleep(forTimeInterval: 1.0)
                        continue
                    }
                }
                next.tap()
            }
            Thread.sleep(forTimeInterval: 0.6)
        }
        print("Imported-deck prompts seen: \(seen); All Attack used \(allAttacks)×, permanents activated \(activations)×, Auto pay tapped \(autoButton)×")
        if manualMana { XCTAssertGreaterThan(autoButton, 0, "With automatic payment off, the Auto button should have paid") }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Rules mode — imported deck game"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertGreaterThanOrEqual(played, 4, "Played only \(played) cards; prompts: \(seen)")
        for required in requiredPrompts {
            XCTAssertTrue(seen.contains { $0.localizedCaseInsensitiveContains(required) }, "Never reached \(required); prompts: \(seen)")
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.6)
        if app.buttons["Exit Game"].waitForExistence(timeout: 5) { app.buttons["Exit Game"].tap() }
    }
    /// JumpStart against the AI chosen on the Rules Game page: pick two packets when the game
    /// starts (the AI gets its own), then the engine deals from that deck. Set
    /// TEST_RUNNER_RULES_UI_TEST_PACKETS to "JumpStart" or "Jump In" (default JumpStart).
    @MainActor func testRulesJumpStartPacketsAgainstTheAI() throws {
        let source = ProcessInfo.processInfo.environment["RULES_UI_TEST_PACKETS"] ?? "JumpStart"
        let app = XCUIApplication()
        app.launchArguments = ["--rules-ui-test", "--rules-manual-connect", "-rules.deckSource", "\"\(source)\""]
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
        key.typeText(ProcessInfo.processInfo.environment["RULES_UI_TEST_KEY"] ?? "rules-local-verification-key")
        let fresh = app.buttons["rules-connect-new"]
        (fresh.exists ? fresh : app.buttons["rules-connect"]).tap()
        XCTAssertTrue(app.buttons["rules-start-ai"].waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["rules-start-ai"])
        waitForExpectations(timeout: 10)
        app.buttons["rules-start-ai"].tap()
        // Two packet choices, three offers each.
        let packets = app.buttons.matching(identifier: "rules-packet-choice")
        XCTAssertTrue(packets.firstMatch.waitForExistence(timeout: 10), "Starting a \(source) game should offer packets")
        XCTAssertTrue(app.navigationBars["Choose First Packet"].exists)
        packets.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Choose Second Packet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'First packet:'")).firstMatch.exists)
        packets.firstMatch.tap()
        // The engine game starts with that deck: the phone board and an opening-hand decision.
        XCTAssertTrue(app.buttons["phone-untap-local"].waitForExistence(timeout: 30),
                      "The \(source) game didn't start: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        let message = app.descendants(matching: .any)["rules-prompt-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 30))
        if message.label.localizedCaseInsensitiveContains("starting player"), app.buttons["Magic Board"].waitForExistence(timeout: 5) { app.buttons["Magic Board"].tap() }
        XCTAssertTrue(keepButton(app).waitForExistence(timeout: 20))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Rules mode — \(source) opening hand"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        keepButton(app).tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch.waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.6)
        if app.buttons["Exit Game"].waitForExistence(timeout: 5) { app.buttons["Exit Game"].tap() }
    }

    /// Arena's London mulligan in a Rules game: Mulligan once, drag the returned card to the Library
    /// zone ("Return 1 Card"), then Keep 6, as a person would.
    @MainActor func testRulesMulliganReturnsACardByDraggingItToTheLibrary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--rules-ui-test", "--rules-manual-connect"]
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
        key.typeText(ProcessInfo.processInfo.environment["RULES_UI_TEST_KEY"] ?? "rules-local-verification-key")
        let fresh = app.buttons["rules-connect-new"]
        (fresh.exists ? fresh : app.buttons["rules-connect"]).tap()
        XCTAssertTrue(app.buttons["rules-start-ai"].waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["rules-start-ai"])
        waitForExpectations(timeout: 10)
        app.buttons["rules-start-ai"].tap()
        let keep7 = app.buttons["Keep 7"]
        XCTAssertTrue(keep7.waitForExistence(timeout: 30), "Arena's Keep 7: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(app.staticTexts["You will return 1 card to the bottom of your library."].exists)
        app.buttons["Mulligan"].tap()
        // Arena: the new seven with Keep 6 / Mulligan; the card to return is chosen only on Keep.
        let keep6 = app.buttons["Keep 6"]
        XCTAssertTrue(keep6.waitForExistence(timeout: 20), "After a mulligan: a new seven, Keep 6 / Mulligan")
        XCTAssertTrue(app.staticTexts["You will return 2 cards to the bottom of your library."].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "phone-browser-card").count, 7, "The whole new seven is shown")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Rules mode — Keep 6 after a mulligan"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        keep6.tap()
        let title = app.staticTexts["Return 1 Card"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "Keeping six asks which card goes to the bottom")
        XCTAssertTrue(app.staticTexts["Drag 1 card to the bottom of your library."].exists)
        let zone = app.descendants(matching: .any)["phone-browser-zone-battlefield"]
        XCTAssertTrue(zone.exists, "The Library zone to drag to")
        let card = app.descendants(matching: .any).matching(identifier: "phone-browser-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.press(forDuration: 0.6, thenDragTo: zone, withVelocity: 300, thenHoldForDuration: 0.6)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch.waitForExistence(timeout: 20),
                      "After returning the card, the game starts with the kept six")
        let hand = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'phone-hand-'"))
        XCTAssertLessThanOrEqual(hand.count, 7, "Six kept, plus at most one draw")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.6)
        if app.buttons["Exit Game"].waitForExistence(timeout: 5) { app.buttons["Exit Game"].tap() }
    }

    /// A fan card's full AX frame may extend below the screen; its top may overlap the Rules
    /// fast-forward control. Use the exposed image near its left edge, clear of the Home gesture.
    private func visibleHandPoint(_ card: XCUIElement, in app: XCUIApplication) throws -> XCUICoordinate {
        let visible = card.frame.intersection(app.frame.insetBy(dx: 0, dy: 16))
        guard !visible.isNull, visible.width > 8, visible.height > 8 else {
            throw NSError(domain: "RulesHandGesture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The selected hand card has no visible image area"])
        }
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: visible.minX + min(22, visible.width * 0.25) - app.frame.minX,
            dy: visible.midY - app.frame.minY))
    }

    /// The opening hand's Keep button: Phone Play's opening-hand browser ("Keep").
    private func keepButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Keep'")).firstMatch
    }
}
