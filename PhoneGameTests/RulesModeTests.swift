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

    func testStackItemsBelongToTheirController() async throws {
        let me = UUID().uuidString, opponent = UUID().uuidString
        let ability = UUID().uuidString, spell = UUID().uuidString
        func object(_ id: String, _ name: String, ability: Bool, controller: String?) -> [String: Any] {
            var card: [String: Any] = ["id": id, "name": name, "faceDown": false, "transformed": false, "ability": ability,
                                       "rules": "Draw a card.", "counters": []]
            if let controller { card["controllerId"] = controller }
            return card
        }
        func player(_ id: String, _ name: String) -> [String: Any] {
            ["id": id, "name": name, "life": 20, "handCount": 0, "libraryCount": 0, "battlefield": [], "graveyard": [], "exile": []]
        }
        let json: [String: Any] = ["gameId": UUID().uuidString, "playerId": me, "revision": 1, "turn": 2,
                                   "phase": "PRECOMBAT_MAIN", "activePlayerId": me, "hand": [], "playableIds": [],
                                   "stack": [object(ability, "Trigger", ability: true, controller: opponent),
                                             object(spell, "Divination", ability: false, controller: nil)],
                                   "players": [player(me, "Me"), player(opponent, "Them")]]
        let adapter = RulesPhoneAdapter(engine: RulesGameSession())
        try await adapter.project(JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: json)))
        let stack = Dictionary(uniqueKeysWithValues: adapter.presentation.stack.map { ($0.id.uuidString.lowercased(), $0) })
        XCTAssertEqual(stack[ability.lowercased()]?.player, .b, "the opponent's trigger is theirs")
        XCTAssertEqual(stack[spell.lowercased()]?.player, .a, "without a controller, the active player")
        XCTAssertEqual(stack[spell.lowercased()]?.card?.ownerIdentifier, .a)
    }

    func testEnginePlayableCardsReachThePresentationOnlyInRulesMode() async throws {
        let me = UUID().uuidString, land = UUID().uuidString
        let json: [String: Any] = ["gameId": UUID().uuidString, "playerId": me, "revision": 1, "turn": 1,
                                   "phase": "PRECOMBAT_MAIN", "activePlayerId": me, "stack": [], "playableIds": [land.lowercased()],
                                   "hand": [["id": land, "name": "Plains", "faceDown": false, "transformed": false, "typeLine": "Basic Land — Plains", "counters": []]],
                                   "players": [["id": me, "name": "Me", "life": 20, "handCount": 1, "libraryCount": 0, "battlefield": [], "graveyard": [], "exile": []]]]
        let adapter = RulesPhoneAdapter(engine: RulesGameSession())
        try await adapter.project(JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: json)))
        XCTAssertEqual(adapter.presentation.rulesPlayable, [UUID(uuidString: land)!])
        XCTAssertNil(PhoneGame().rulesPlayable, "sandbox games never carry engine playability")
    }

    func testTargetPromptHighlightsLegalTargetsInsteadOfPlayableCards() throws {
        let playable = UUID(), target = UUID()
        let snapshot = try JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: [
            "gameId": UUID().uuidString, "playerId": UUID().uuidString, "revision": 1, "turn": 1,
            "hand": [], "stack": [], "players": [], "playableIds": [playable.uuidString.lowercased()]] as [String: Any]))
        func prompt(_ method: String) throws -> RulesPrompt {
            try JSONDecoder().decode(RulesPrompt.self, from: JSONSerialization.data(withJSONObject: [
                "id": "p", "method": method, "revision": 1, "supported": true, "choices": [],
                "targets": [target.uuidString.lowercased(), UUID().uuidString.lowercased() + "-not-a-card"]] as [String: Any]))
        }
        XCTAssertEqual(RulesPhoneAdapter.highlighted(snapshot: snapshot, prompt: try prompt("GAME_SELECT")), [playable])
        XCTAssertEqual(RulesPhoneAdapter.highlighted(snapshot: snapshot, prompt: try prompt("GAME_TARGET")), [target])
        XCTAssertEqual(RulesPhoneAdapter.highlighted(snapshot: snapshot, prompt: nil), [playable])
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
        let distribution = RulesCommand(type: "answer", requestId: "distribution", promptId: "prompt", revision: 3,
                                        kind: RulesAnswer.amounts([10, 2]).kind, value: .amounts([10, 2]))
        let amounts = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(distribution)) as? [String: Any])
        XCTAssertEqual(amounts["kind"] as? String, "amounts")
        XCTAssertEqual(amounts["value"] as? [Int], [10, 2])
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

    func testRulesDeckImportReusesExistingParserAndPreservesSideboard() throws {
        let deck = try XCTUnwrap(RulesDeckImporter.parse("Deck\n24 Plains (M10) 230\n18 Silvercoat Lion (M10) 31\n18 Siege Mastodon (M10) 30\n\nSideboard\n2 Pacifism (M10) 22"))
        XCTAssertEqual(deck.main.reduce(0) { $0 + $1.count }, 60)
        XCTAssertEqual(deck.main.first?.name, "Plains")
        XCTAssertEqual(deck.main.first?.collectorNumber, "230")
        XCTAssertEqual(deck.sideboard.first?.name, "Pacifism")
        XCTAssertEqual(deck.sideboard.first?.count, 2)
        XCTAssertNil(try RulesDeckImporter.parse("   "))
        XCTAssertThrowsError(try RulesDeckImporter.parse("Commander\n1 Atraxa, Praetors' Voice\nDeck\n99 Plains"))
    }

    func testBattlefieldCharacteristicsPreservePrintedImageAndLeavePrintedModelUnchanged() throws {
        let template = try RulesPhoneAdapter.placeholder(name: "Test card", typeLine: "Artifact", rules: "Printed text", manaCost: "{2}")
        var printedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? [String: Any])
        printedJSON["imageUris"] = ["normal": "https://example.test/printed-card.jpg"]
        let printed = try JSONDecoder().decode(MTGCard.self, from: JSONSerialization.data(withJSONObject: printedJSON))
        let raw: [String: Any] = ["id": UUID().uuidString, "name": "Test card", "faceDown": false, "transformed": false,
                                  "typeLine": "Artifact Creature — Construct", "rules": "Flying\nGranted ability", "colors": ["U"],
                                  "counters": [["name": "+1/+1", "count": 1]], "power": "5", "toughness": "6"]
        let engine = try JSONDecoder().decode(RulesCard.self, from: JSONSerialization.data(withJSONObject: raw))
        let displayed = try RulesCardCharacteristics.applying(engine, to: printed)
        XCTAssertEqual(displayed.scryfallID, printed.scryfallID)
        XCTAssertEqual(displayed.imageURL(type: .normal), URL(string: "https://example.test/printed-card.jpg"))
        XCTAssertEqual(displayed.typeLine, "Artifact Creature — Construct")
        XCTAssertEqual(displayed.oracleText, "Flying\nGranted ability")
        XCTAssertEqual(displayed.colors, [.blue])
        XCTAssertEqual(printed.typeLine, "Artifact")
        XCTAssertEqual(printed.oracleText, "Printed text")
    }
}
