import XCTest
import Foundation

/// Avoid enumerating the large hand's accessibility children: verify real coordinate taps
/// against the fixture's independently observed engine-answer stream.
final class RulesDiscardUITests: XCTestCase {
    private struct Status: Decodable, Sendable { let remaining: Int; let answers: Int; let complete: Bool }

    @MainActor func testNineCardHandDiscardsThroughNormalPhoneGestures() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_DISCARD_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_DISCARD_FIXTURE_ADDRESS to the local discard fixture")
        }
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
        guard start.isEnabled else { XCTFail("The fixture's game button never enabled"); return }
        start.tap()
        XCTAssertTrue(app.buttons["phone-untap-local"].waitForExistence(timeout: 20))

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
        XCTAssertTrue(status.complete, "Hand taps delivered \(status.answers) answers; \(status.remaining) cards remain")
        XCTAssertEqual(status.remaining, 7)
        XCTAssertEqual(status.answers, 2)
        if app.buttons["Exit Game"].waitForExistence(timeout: 3) { app.buttons["Exit Game"].tap() }
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
