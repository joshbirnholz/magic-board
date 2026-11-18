import XCTest
import Foundation

/// Avoid enumerating the large hand's accessibility children: verify real coordinate taps
/// against the fixture's independently observed engine-answer stream.
final class RulesDiscardUITests: XCTestCase {
    private struct Status: Decodable, Sendable { let remaining: Int?; let answers: Int; let complete: Bool }

    @MainActor func testBattlefieldBannerUpdatesWithoutBlockingCombatCardTaps() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_BLOCK_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_BLOCK_FIXTURE_ADDRESS to BlockPromptFixture")
        }
        let app = try await openFixture(address)
        defer { app.terminate() }
        let banner = app.staticTexts["rules-board-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertEqual(banner.label, "Choose blockers.")
        XCTAssertEqual(banner.frame.midY, app.frame.midY, accuracy: 24)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Arena-style battlefield instruction band"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let cards = app.buttons.matching(identifier: "phone-creature-card").allElementsBoundByIndex
        let blocker = try XCTUnwrap(cards.first { ($0.value as? String) == "Untapped" && $0.isHittable })
        blocker.tap()
        let targetBanner = expectation(for: NSPredicate(format: "label == 'Choose attacker to block'"), evaluatedWith: banner)
        await fulfillment(of: [targetBanner], timeout: 5)
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
        instant.tap()
        let observer = try informationObserver(address)
        defer { observer.cancel(with: .goingAway, reason: nil) }
        let status = try await readStatus(observer)
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

    @MainActor private func openFixture(_ address: String, information: Bool = false) async throws -> XCUIApplication {
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
        if information {
            XCTAssertTrue(app.staticTexts["rules-information-title"].waitForExistence(timeout: 20))
        } else {
            XCTAssertTrue(app.buttons["phone-untap-local"].waitForExistence(timeout: 20))
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
