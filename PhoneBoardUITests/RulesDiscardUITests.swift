import XCTest
import Foundation

/// Avoid enumerating the large hand's accessibility children: verify real coordinate taps
/// against the fixture's independently observed engine-answer stream.
final class RulesDiscardUITests: XCTestCase {
    private struct Status: Decodable, Sendable { let remaining: Int?; let answers: Int; let complete: Bool }

    @MainActor func testQuestionDisplaysItsVisibleCardAndDoesNotReopenInformationAfterAnswering() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_QUESTION_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_QUESTION_FIXTURE_ADDRESS to the question fixture")
        }
        let app = try await openFixture(address + "/question", question: true)
        defer { app.terminate() }
        let contextID = "rules-context-card-00000000-0000-0000-0000-000000000031"
        // A read-only card image may be represented as Other by UIKit's accessibility bridge.
        let face = app.descendants(matching: .any)[contextID]
        XCTAssertTrue(face.waitForExistence(timeout: 5))
        XCTAssertEqual(face.label, "Revitalize")
        XCTAssertEqual(face.frame.midX, app.frame.midX, accuracy: 20, "A short card row should be centred")
        XCTAssertFalse(app.buttons[contextID].exists, "Question context is not a card-selection action")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Visible card context for a rules question"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Yes"].tap()
        XCTAssertTrue(app.buttons["phone-untap-local"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["rules-information-title"].exists, "Already inspected question context must not reopen")
        let observer = try informationObserver(address)
        defer { observer.cancel(with: .goingAway, reason: nil) }
        let status = try await readStatus(observer)
        XCTAssertTrue(status.complete)
        XCTAssertEqual(status.answers, 1)
    }

    @MainActor func testTwoMulligansReturnOnlyTheKeptHandsCardsToTheLibrary() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_MULLIGAN_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_MULLIGAN_FIXTURE_ADDRESS to MulliganPromptFixture")
        }
        let app = try await openFixture(address, opening: true)
        defer { app.terminate() }
        XCTAssertFalse(app.buttons["Choose"].exists, "The opening-hand browser owns this decision")
        app.buttons["Mulligan"].tap()
        XCTAssertTrue(app.buttons["Keep 6"].waitForExistence(timeout: 5))
        app.buttons["Mulligan"].tap()
        let keep = app.buttons["Keep 5"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "phone-browser-card").count, 7)
        keep.tap()
        for remaining in [2, 1] {
            let title = remaining == 1 ? "Return 1 Card" : "Return 2 Cards"
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
            let zone = app.descendants(matching: .any)["phone-browser-zone-battlefield"]
            let card = app.descendants(matching: .any).matching(identifier: "phone-browser-card").firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.press(forDuration: 0.6, thenDragTo: zone, withVelocity: 300, thenHoldForDuration: 0.6)
        }
        XCTAssertTrue(app.buttons["phone-untap-local"].waitForExistence(timeout: 5))
        var request = URLRequest(url: try XCTUnwrap(URL(string: address + "/observer")))
        request.setValue("Bearer rules-local-verification-key", forHTTPHeaderField: "Authorization")
        let observer = URLSession.shared.webSocketTask(with: request)
        observer.resume()
        defer { observer.cancel(with: .goingAway, reason: nil) }
        struct OpeningStatus: Decodable { let mulligans: Int; let returns: Int; let handCount: Int; let complete: Bool }
        let data: Data
        switch try await observer.receive() {
        case .string(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        @unknown default: throw NSError(domain: "MulliganFixture", code: 1)
        }
        let status = try JSONDecoder().decode(OpeningStatus.self, from: data)
        XCTAssertTrue(status.complete)
        XCTAssertEqual(status.mulligans, 2)
        XCTAssertEqual(status.returns, 3, "One automatic return before the redraw, then two chosen cards from the kept hand")
        XCTAssertEqual(status.handCount, 5)
    }

    @MainActor func testStackAbilityHasAWhiteConnectionFromItsSource() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_BLOCK_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_BLOCK_FIXTURE_ADDRESS to BlockPromptFixture")
        }
        let app = try await openFixture(address + "/ability")
        defer { app.terminate() }
        let stack = app.buttons["phone-stack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 5))
        let linked = expectation(for: NSPredicate(format: "value CONTAINS '1 ability source connections'"), evaluatedWith: stack)
        await fulfillment(of: [linked], timeout: 5)
        XCTAssertTrue((stack.value as? String)?.contains("0 target connections") == true, "Source arrows are not target arrows")
        let origin = stack.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let creature = app.buttons.matching(identifier: "phone-creature-card").firstMatch
        XCTAssertTrue(creature.exists)
        origin.press(forDuration: 0.1, thenDragTo: creature.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertTrue((stack.value as? String)?.contains("0 target connections") == true,
                      "Dragging a Rules stack object must not create an editable targeting line")
        XCTAssertTrue((stack.value as? String)?.contains("1 ability source connections") == true)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "White arrow from Ahriman to its stack ability"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testSummoningSicknessMarkerFollowsEngineState() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_BLOCK_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_BLOCK_FIXTURE_ADDRESS to BlockPromptFixture")
        }
        let app = try await openFixture(address + "/sickness")
        defer { app.terminate() }
        let cards = app.buttons.matching(identifier: "phone-creature-card")
        let sick = cards.matching(NSPredicate(format: "value CONTAINS 'Summoning sick'")).firstMatch
        XCTAssertTrue(sick.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Engine summoning-sickness spiral on creature art"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["phone-untap-local"].tap()
        let cleared = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sick)
        await fulfillment(of: [cleared], timeout: 5)
        XCTAssertEqual(cards.count, 3, "Losing sickness must not remove or move the creature")
    }

    @MainActor func testPromptAppearanceDoesNotMoveOrResizePermanents() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_BLOCK_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_BLOCK_FIXTURE_ADDRESS to BlockPromptFixture")
        }
        let app = try await openFixture(address + "/stable")
        defer { app.terminate() }
        let cards = app.buttons.matching(identifier: "phone-creature-card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["rules-board-banner"].exists)
        let before = cards.allElementsBoundByIndex.map(\.frame)
        XCTAssertEqual(before.count, 3)
        app.buttons["phone-untap-local"].tap()
        XCTAssertTrue(app.staticTexts["rules-board-banner"].waitForExistence(timeout: 5))
        let after = cards.allElementsBoundByIndex.map(\.frame)
        XCTAssertEqual(before.count, after.count)
        for (old, new) in zip(before, after) {
            XCTAssertEqual(old.minX, new.minX, accuracy: 1)
            XCTAssertEqual(old.minY, new.minY, accuracy: 1)
            XCTAssertEqual(old.width, new.width, accuracy: 1)
            XCTAssertEqual(old.height, new.height, accuracy: 1)
        }
    }

    @MainActor func testLongCrewInstructionStaysBetweenTheCardRows() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_BLOCK_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_BLOCK_FIXTURE_ADDRESS to BlockPromptFixture")
        }
        let app = try await openFixture(address + "/crew")
        defer { app.terminate() }
        let banner = app.staticTexts["rules-board-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.label.contains("Sky Skiff"))
        XCTAssertTrue(banner.label.contains("selected power 0 of 1"), "The engine's crew requirement must remain available")
        let cards = app.buttons.matching(identifier: "phone-creature-card").allElementsBoundByIndex
        let opponentBottom = try XCTUnwrap(cards.filter { ($0.value as? String) == "Attacking" }.map(\.frame.maxY).max())
        let localTop = try XCTUnwrap(cards.filter { ($0.value as? String) == "Untapped" }.map(\.frame.minY).min())
        XCTAssertGreaterThanOrEqual(banner.frame.minY, opponentBottom - 1)
        XCTAssertLessThanOrEqual(banner.frame.maxY, localTop + 1)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Crew instruction between permanent rows"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testFloatingManaDoesNotReportAFailedPaymentTap() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_BLOCK_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_BLOCK_FIXTURE_ADDRESS to BlockPromptFixture")
        }
        let app = try await openFixture(address + "/mana")
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["rules-prompt-message"].label.contains("{B}"), "VoiceOver must retain mana costs drawn as inline images")
        let source = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Capital City, 1, untapped'")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        XCTAssertTrue(app.descendants(matching: .any)["rules-mana-pool"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Capital City, 1, tapped'")).firstMatch.waitForExistence(timeout: 5))
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["rules-toast"].exists, "Floating mana is useful progress toward a filtering ability, even with black still unpaid")
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }

    @MainActor func testBattlefieldSacrificeInstructionNamesItsSource() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_BLOCK_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_BLOCK_FIXTURE_ADDRESS to BlockPromptFixture")
        }
        let app = try await openFixture(address + "/source")
        defer { app.terminate() }
        let banner = app.staticTexts["rules-board-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertEqual(banner.label, "Ahriman: Choose another creature or artifact (to sacrifice)")
        let cards = app.buttons.matching(identifier: "phone-creature-card").allElementsBoundByIndex
        let opponentBottom = try XCTUnwrap(cards.filter { ($0.value as? String) == "Attacking" }.map(\.frame.maxY).max())
        let localTop = try XCTUnwrap(cards.filter { ($0.value as? String) == "Untapped" }.map(\.frame.minY).min())
        XCTAssertGreaterThanOrEqual(banner.frame.minY, opponentBottom - 1)
        XCTAssertLessThanOrEqual(banner.frame.maxY, localTop + 1)
    }

    @MainActor func testAttackerSelectionHasOnlyTheMainAllAttackButton() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_BLOCK_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_BLOCK_FIXTURE_ADDRESS to BlockPromptFixture")
        }
        let app = try await openFixture(address + "/attack")
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["rules-board-banner"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["rules-board-banner"].label, "Choose attackers.")
        XCTAssertEqual(app.buttons["phone-untap-local"].label, "All Attack")
        XCTAssertTrue(app.buttons["phone-untap-local"].isEnabled)
        XCTAssertTrue(app.buttons["rules-secondary-action"].exists)
        XCTAssertFalse(app.buttons["rules-special-action"].exists, "XMage's All attack shortcut must not duplicate the main combat button")
    }

    @MainActor func testBattlefieldBannerUpdatesWithoutBlockingCombatCardTaps() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_BLOCK_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_BLOCK_FIXTURE_ADDRESS to BlockPromptFixture")
        }
        let app = try await openFixture(address)
        defer { app.terminate() }
        let banner = app.staticTexts["rules-board-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertEqual(banner.label, "Choose blockers.")
        let cards = app.buttons.matching(identifier: "phone-creature-card").allElementsBoundByIndex
        let opponentBottom = try XCTUnwrap(cards.filter { ($0.value as? String) == "Attacking" }.map(\.frame.maxY).max())
        let localTop = try XCTUnwrap(cards.filter { ($0.value as? String) == "Untapped" }.map(\.frame.minY).min())
        XCTAssertGreaterThan(localTop, opponentBottom, "The fixture leaves an open combat gap")
        XCTAssertGreaterThanOrEqual(banner.frame.minY, opponentBottom - 1, "The instruction must not cover attackers' power/toughness")
        XCTAssertLessThanOrEqual(banner.frame.maxY, localTop + 1, "The instruction must stay above our permanents")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Arena-style battlefield instruction band"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let blocker = try XCTUnwrap(cards.first { ($0.value as? String) == "Untapped" && $0.isHittable })
        blocker.tap()
        let targetBanner = expectation(for: NSPredicate(format: "label == 'Choose attacker to block'"), evaluatedWith: banner)
        await fulfillment(of: [targetBanner], timeout: 5)
        XCTAssertFalse(app.buttons["rules-fast-forward"].isEnabled, "Skip actions require priority, not an outstanding target")
        let attackers = app.buttons.matching(identifier: "phone-creature-card").allElementsBoundByIndex
        let attacker = try XCTUnwrap(attackers.first { ($0.value as? String) == "Attacking" && $0.isHittable })
        attacker.tap()
        let next = app.buttons["phone-untap-local"]
        let assigned = expectation(for: NSPredicate(format: "value == '1 blocking assignments'"), evaluatedWith: next)
        await fulfillment(of: [assigned], timeout: 5)
    }

    @MainActor func testRevealedCardsCloseLocallyAndCanShowTheBattlefield() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_INFORMATION_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_INFORMATION_FIXTURE_ADDRESS to the local information fixture")
        }
        let app = try await openFixture(address + "/information", information: true)
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["rules-information-title"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Rules revealed-card inspector"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["rules-information-battlefield"].tap()
        XCTAssertTrue(app.buttons["Revealed Cards"].waitForExistence(timeout: 3))
        app.buttons["Revealed Cards"].tap()
        let done = app.buttons["rules-information-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        XCTAssertFalse(done.exists)
        let observer = try informationObserver(address)
        defer { observer.cancel(with: .goingAway, reason: nil) }
        let status = try await readStatus(observer)
        XCTAssertEqual(status.answers, 0, "Closing information must not answer or advance the engine")
    }

    @MainActor func testCardPickerDisablesAnIneligibleDisplayedLand() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_INFORMATION_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_INFORMATION_FIXTURE_ADDRESS to the local information fixture")
        }
        let app = try await openFixture(address + "/choice")
        defer { app.terminate() }
        let land = app.buttons["rules-prompt-card-00000000-0000-0000-0000-000000000030"]
        let instant = app.buttons["rules-prompt-card-00000000-0000-0000-0000-000000000031"]
        XCTAssertTrue(land.waitForExistence(timeout: 5))
        XCTAssertFalse(land.isEnabled, "A visible land is not a legal Duress choice")
        XCTAssertTrue(instant.isEnabled)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Engine-provided card eligibility"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let confirm = app.buttons["phone-browser-done"]
        XCTAssertTrue(confirm.exists)
        XCTAssertEqual(confirm.label, "Confirm")
        XCTAssertFalse(confirm.isEnabled)
        let observer = try informationObserver(address)
        defer { observer.cancel(with: .goingAway, reason: nil) }
        instant.tap()
        XCTAssertTrue(instant.isSelected)
        XCTAssertTrue(confirm.isEnabled)
        var status = try await readStatus(observer)
        XCTAssertEqual(status.answers, 0, "Tapping must not answer the engine")
        instant.tap()
        XCTAssertFalse(instant.isSelected)
        XCTAssertFalse(confirm.isEnabled, "Selection can be toggled off before committing")
        observer.send(.string("status")) { _ in }
        status = try await readStatus(observer)
        XCTAssertEqual(status.answers, 0)
        instant.tap()
        confirm.tap()
        observer.send(.string("status")) { _ in }
        status = try await readStatus(observer)
        XCTAssertTrue(status.complete)
        XCTAssertEqual(status.answers, 1)
    }

    private func informationObserver(_ address: String) throws -> URLSessionWebSocketTask {
        var request = URLRequest(url: try XCTUnwrap(URL(string: address + "/observer")))
        request.setValue("Bearer rules-local-verification-key", forHTTPHeaderField: "Authorization")
        let observer = URLSession.shared.webSocketTask(with: request)
        observer.resume()
        return observer
    }

    @MainActor func testNineCardHandDiscardsThroughNormalPhoneGestures() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_DISCARD_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_DISCARD_FIXTURE_ADDRESS to the local discard fixture")
        }
        let app = try await openFixture(address)

        var request = URLRequest(url: try XCTUnwrap(URL(string: address + "/observer")))
        request.setValue("Bearer rules-local-verification-key", forHTTPHeaderField: "Authorization")
        let observer = URLSession.shared.webSocketTask(with: request)
        observer.resume()
        defer { observer.cancel(with: .goingAway, reason: nil) }
        var status = try await readStatus(observer)
        XCTAssertEqual(status.remaining, 9)
        for _ in 0..<8 where !status.complete {
            try await Task.sleep(nanoseconds: 600_000_000)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
            try await Task.sleep(nanoseconds: 600_000_000)
            try await observer.send(.string("status"))
            status = try await readStatus(observer)
        }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Nine-card cleanup via coordinate taps"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(status.complete, "Hand taps delivered \(status.answers) answers; \(status.remaining ?? -1) cards remain")
        XCTAssertEqual(status.remaining, 7)
        XCTAssertEqual(status.answers, 2)
        if app.buttons["Exit Game"].waitForExistence(timeout: 3) { app.buttons["Exit Game"].tap() }
    }

    @MainActor private func openFixture(_ address: String, information: Bool = false, opening: Bool = false, question: Bool = false) async throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--rules-ui-test"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["start-rules"].waitForExistence(timeout: 15))
        app.buttons["start-rules"].tap()
        let server = app.textFields["rules-server-address"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        if let value = server.value as? String { server.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        server.typeText(address)
        let key = app.secureTextFields["rules-connection-key"]
        key.tap()
        if let value = key.value as? String { key.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        key.typeText("rules-local-verification-key")
        // Finish editing before tapping form actions; simulator keyboard geometry can lag rotation.
        key.typeText("\n")
        let fresh = app.buttons["rules-connect-new"]
        (fresh.exists ? fresh : app.buttons["rules-connect"]).tap()
        let start = app.buttons["rules-start-ai"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        for _ in 0..<50 where !start.isEnabled { try await Task.sleep(nanoseconds: 200_000_000) }
        guard start.isEnabled else {
            throw NSError(domain: "RulesFixture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The fixture's game button never enabled"])
        }
        start.tap()
        let ready = information ? app.staticTexts["rules-information-title"] : app.buttons[question ? "Yes" : opening ? "Keep 7" : "phone-untap-local"]
        guard ready.waitForExistence(timeout: 20) else {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Fixture did not reach the game"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            throw NSError(domain: "RulesFixture", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "The fixture stayed on setup instead of showing the game"])
        }
        return app
    }

    private func readStatus(_ observer: URLSessionWebSocketTask) async throws -> Status {
        let message = try await observer.receive()
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        @unknown default: throw NSError(domain: "DiscardFixture", code: 1)
        }
        return try JSONDecoder().decode(Status.self, from: data)
    }
}
