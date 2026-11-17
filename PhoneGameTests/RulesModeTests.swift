import XCTest
import CardService
@testable import Magic_Board

@MainActor
final class RulesModeTests: XCTestCase {
    func testRulesModeRestoresUnauthorizedEditsAndLeavesSandboxSaveAlone() async throws {
        let original = try JSONEncoder().encode(GameState.current)
        let phone = PhoneGameSession()
        let engine = RulesGameSession()
        let adapter = RulesPhoneAdapter(engine: engine)
        phone.beginRules(adapter)
        defer {
            phone.leave()
            if let state = try? JSONDecoder().decode(GameState.self, from: original) { GameState.current.update(withValuesFrom: state) }
        }
        // Exercise the same projection path as incoming engine snapshots.
        try await adapter.project(snapshot())
        let savedSandbox = try? Data(contentsOf: PhoneGameSession.saveURL)
        GameState.current.player1.life.accept(99)
        try GameState.current.save()
        XCTAssertEqual(GameState.current.player1.life.value, 20, "Rules state must come from the engine")
        phone.send(.life(7))
        phone.send(.draw)
        phone.sendDirectly(.life(8))
        await Task.yield()
        XCTAssertEqual(GameState.current.player1.life.value, 20)
        XCTAssertEqual(try? Data(contentsOf: PhoneGameSession.saveURL), savedSandbox, "Rules mode must not overwrite the saved sandbox game")
    }

    private func snapshot() throws -> RulesSnapshot {
        let me = UUID().uuidString
        let opponent = UUID().uuidString
        let json: [String: Any] = ["gameId": UUID().uuidString, "playerId": me, "revision": 1,
                                  "turn": 1, "phase": "PRECOMBAT_MAIN", "step": "PRECOMBAT_MAIN",
                                  "activePlayer": "Me", "priorityPlayer": "Me", "hand": [], "stack": [], "playableIds": [],
                                  "players": [
                                    ["id": me, "name": "Me", "life": 20, "handCount": 0, "libraryCount": 0, "battlefield": [], "graveyard": [], "exile": []],
                                    ["id": opponent, "name": "Them", "life": 20, "handCount": 0, "libraryCount": 0, "battlefield": [], "graveyard": [], "exile": []]]]
        return try JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testSandboxReducerStillAllowsManualLifeChanges() throws {
        var sandbox = PhoneGame()
        sandbox.state.player1.life.accept(20)
        try sandbox.apply(.life(-3), player: .a)
        XCTAssertEqual(sandbox.state.player1.life.value, 17)
        try sandbox.apply(.life(5), player: .a)
        XCTAssertEqual(sandbox.state.player1.life.value, 22)
    }

    func testRulesAddressValidationAndDefaultPort() throws {
        XCTAssertEqual(try RulesEndpoint.parse("my-pc.local").absoluteString, "ws://my-pc.local:17180")
        XCTAssertEqual(try RulesEndpoint.parse("wss://example.test:443/rules").scheme, "wss")
        for address in ["", "https://example.test", "ws://user:password@example.test", "ws://example.test?token=secret", "ws://example.test:70000"] {
            XCTAssertThrowsError(try RulesEndpoint.parse(address), address)
        }
    }

    func testRulesAnswersPreserveWireTypes() throws {
        let answer = RulesCommand(type: "answer", requestId: "request", promptId: "prompt", revision: 3,
                                  kind: RulesAnswer.boolean(false).kind, value: .boolean(false))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(answer)) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "boolean")
        XCTAssertEqual(json["value"] as? Bool, false)
        XCTAssertEqual(json["revision"] as? Int, 3)
    }

    func testRulesSnapshotBeforeStartingPlayerHasNoPhaseOrPriority() throws {
        var initial: [String: Any] = ["type": "snapshot"]
        let known = try snapshot()
        initial["gameId"] = known.gameId; initial["playerId"] = known.playerId
        initial["revision"] = 1; initial["turn"] = 0
        initial["players"] = []; initial["hand"] = []; initial["stack"] = []; initial["playableIds"] = []
        let decoded = try JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: initial))
        XCTAssertNil(decoded.phase)
        XCTAssertNil(decoded.step)
        XCTAssertNil(decoded.priorityPlayer)
    }
}
