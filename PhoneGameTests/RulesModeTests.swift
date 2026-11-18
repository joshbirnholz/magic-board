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

    func testGestureTargetIsDroppedWhenTheEngineNeedsNoTarget() throws {
        let attacker = UUID()
        func prompt(_ method: String, targets: [String] = []) throws -> RulesPrompt {
            try JSONDecoder().decode(RulesPrompt.self, from: JSONSerialization.data(withJSONObject: [
                "id": "p", "method": method, "revision": 1, "supported": true, "choices": [], "targets": targets] as [String: Any]))
        }
        let id = attacker.uuidString.lowercased()
        // A lone attacker: XMage assigns the block itself and goes back to selecting blockers.
        let afterBlock = RulesPhoneAdapter.resolvePendingTarget(.card(attacker), prompt: try prompt("GAME_SELECT"), snapshot: nil)
        XCTAssertNil(afterBlock.answer); XCTAssertFalse(afterBlock.keep)
        // Several attackers: XMage asks which one, and the dragged-to attacker answers it.
        let asked = RulesPhoneAdapter.resolvePendingTarget(.card(attacker), prompt: try prompt("GAME_TARGET", targets: [id]), snapshot: nil)
        XCTAssertEqual(asked.answer, id); XCTAssertFalse(asked.keep)
        // An illegal target is dropped rather than sent.
        let illegal = RulesPhoneAdapter.resolvePendingTarget(.card(attacker), prompt: try prompt("GAME_TARGET", targets: [UUID().uuidString.lowercased()]), snapshot: nil)
        XCTAssertNil(illegal.answer); XCTAssertFalse(illegal.keep)
        // Paying mana before targets keeps it for the target prompt.
        XCTAssertTrue(RulesPhoneAdapter.resolvePendingTarget(.card(attacker), prompt: try prompt("GAME_PLAY_MANA"), snapshot: nil).keep)
        // The selection the gesture answered is still showing until the engine moves on.
        XCTAssertTrue(RulesPhoneAdapter.resolvePendingTarget(.card(attacker), prompt: try prompt("GAME_SELECT"), snapshot: nil, issuedDuring: "p").keep)
    }

    func testPriorityIsPassedAutomaticallyOnlyWhenNothingIsPlayable() throws {
        func snapshot(playable: [String]) throws -> RulesSnapshot {
            try JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: [
                "gameId": "g", "playerId": "p", "revision": 1, "turn": 2, "hand": [], "stack": [], "players": [],
                "playableIds": playable] as [String: Any]))
        }
        func prompt(_ method: String, _ message: String) throws -> RulesPrompt {
            try JSONDecoder().decode(RulesPrompt.self, from: JSONSerialization.data(withJSONObject: [
                "id": "x", "method": method, "revision": 1, "supported": true, "choices": [], "message": message] as [String: Any]))
        }
        let idle = try snapshot(playable: []), ready = try snapshot(playable: [UUID().uuidString])
        XCTAssertTrue(RulesPhoneAdapter.shouldAutoPass(try prompt("GAME_SELECT", "Play instants and activated abilities"), snapshot: idle))
        XCTAssertFalse(RulesPhoneAdapter.shouldAutoPass(try prompt("GAME_SELECT", "Play instants and activated abilities"), snapshot: ready), "something to respond with")
        XCTAssertFalse(RulesPhoneAdapter.shouldAutoPass(try prompt("GAME_SELECT", "Play spells and abilities"), snapshot: idle), "your main phase waits")
        XCTAssertFalse(RulesPhoneAdapter.shouldAutoPass(try prompt("GAME_SELECT", "Select attackers"), snapshot: idle))
        XCTAssertFalse(RulesPhoneAdapter.shouldAutoPass(try prompt("GAME_ASK", "Play instants?"), snapshot: idle))
    }

    func testLandsDontShowEngineZeroStats() async throws {
        let me = UUID().uuidString, land = UUID().uuidString, bear = UUID().uuidString
        func permanent(_ id: String, _ name: String, _ type: String, _ power: String, _ toughness: String) -> [String: Any] {
            ["id": id, "name": name, "faceDown": false, "transformed": false, "typeLine": type, "power": power, "toughness": toughness,
             "tapped": false, "summoningSick": false, "counters": []]
        }
        let json: [String: Any] = ["gameId": UUID().uuidString, "playerId": me, "revision": 1, "turn": 3, "phase": "PRECOMBAT_MAIN",
                                   "activePlayerId": me, "stack": [], "playableIds": [], "hand": [],
                                   "players": [["id": me, "name": "Me", "life": 20, "handCount": 0, "libraryCount": 0, "graveyard": [], "exile": [],
                                                "battlefield": [permanent(land, "Plains", "Basic Land — Plains", "0", "0"),
                                                                permanent(bear, "Grizzly Bears", "Creature — Bear", "2", "2")]]]]
        let adapter = RulesPhoneAdapter(engine: RulesGameSession())
        try await adapter.project(JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: json)))
        let field = adapter.presentation.state.battlefield.value
        XCTAssertEqual(field.first { $0.uuid.uuidString.lowercased() == land.lowercased() }?.isPowerToughnessVisible.value, false)
        XCTAssertEqual(field.first { $0.uuid.uuidString.lowercased() == bear.lowercased() }?.isPowerToughnessVisible.value, true)
    }

    func testManaIsPaidAutomaticallyWithAFittingBasicLand() throws {
        let me = UUID().uuidString, plains = UUID().uuidString, forest = UUID().uuidString, tapped = UUID().uuidString, dual = UUID().uuidString
        func land(_ id: String, _ type: String, tapped: Bool = false) -> [String: Any] {
            ["id": id, "name": type, "faceDown": false, "transformed": false, "typeLine": type, "tapped": tapped, "counters": []]
        }
        let snapshot = try JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: [
            "gameId": "g", "playerId": me, "revision": 1, "turn": 3, "hand": [], "stack": [], "playableIds": [],
            "players": [["id": me, "name": "Me", "life": 20, "handCount": 0, "libraryCount": 0, "graveyard": [], "exile": [],
                         "battlefield": [land(tapped, "Basic Land — Plains", tapped: true), land(plains, "Basic Land — Plains"),
                                         land(forest, "Basic Land — Forest"), land(dual, "Land — Plains Forest")]]]] as [String: Any]))
        func pay(_ message: String, method: String = "GAME_PLAY_MANA") throws -> String? {
            RulesPhoneAdapter.autoPayLand(try JSONDecoder().decode(RulesPrompt.self, from: JSONSerialization.data(withJSONObject: [
                "id": "p", "method": method, "revision": 1, "supported": true, "choices": [], "message": message] as [String: Any])), snapshot: snapshot)
        }
        XCTAssertEqual(try pay("Pay {1}{W}<div>Silvercoat Lion</div>"), plains, "a white symbol takes the untapped Plains")
        XCTAssertEqual(try pay("Pay {G}"), forest)
        XCTAssertNotNil(try pay("Pay {1}"), "generic is paid by some basic land")
        XCTAssertNil(try pay("Pay {U}"), "no Island: the player pays")
        XCTAssertNil(try pay("Pay {W/U}"), "hybrid stays manual")
        XCTAssertNil(try pay("Pay {X}{W}", method: "GAME_PLAY_XMANA"))
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

    func testEngineMainPhasesDoNotCreateCombat() {
        XCTAssertEqual(RulesPhoneAdapter.phonePhase("PRECOMBAT_MAIN"), .main)
        XCTAssertEqual(RulesPhoneAdapter.phonePhase("POSTCOMBAT_MAIN"), .ending)
        XCTAssertEqual(RulesPhoneAdapter.phonePhase("COMBAT"), .combat)
    }

    func testHoldingPrioritySuppressesAutomaticPass() throws {
        let prompt = try JSONDecoder().decode(RulesPrompt.self, from: Data(#"{"id":"priority","method":"GAME_SELECT","revision":1,"message":"Play instants and activated abilities","supported":true,"choices":[]}"#.utf8))
        let state = try JSONDecoder().decode(RulesSnapshot.self, from: Data(#"{"gameId":"game","playerId":"me","revision":1,"turn":1,"hand":[],"stack":[],"players":[],"playableIds":[]}"#.utf8))
        XCTAssertTrue(RulesPhoneAdapter.shouldAutoPass(prompt, snapshot: state))
        XCTAssertFalse(RulesPhoneAdapter.shouldAutoPass(prompt, snapshot: state, holdingPriority: true))
    }

    func testOpponentsCombatKeepsAttackersAndUntappedBlockers() async throws {
        let me = UUID().uuidString, opponent = UUID().uuidString
        let attacker = UUID(), blocker = UUID()
        func creature(_ id: UUID) -> [String: Any] {
            ["id": id.uuidString, "name": "Silvercoat Lion", "typeLine": "Creature — Cat", "power": "2", "toughness": "2",
             "faceDown": false, "transformed": false, "tapped": false, "counters": []]
        }
        func player(_ id: String, cards: [[String: Any]]) -> [String: Any] {
            ["id": id, "name": id, "life": 20, "handCount": 0, "libraryCount": 0, "battlefield": cards, "graveyard": [], "exile": []]
        }
        let json: [String: Any] = ["gameId": UUID().uuidString, "playerId": me, "revision": 4, "turn": 4,
                                   "phase": "COMBAT", "step": "DECLARE_BLOCKERS", "activePlayerId": opponent,
                                   "hand": [], "stack": [], "playableIds": [],
                                   "players": [player(me, cards: [creature(blocker)]), player(opponent, cards: [creature(attacker)])],
                                   "combat": [["defenderId": me, "attackers": [attacker.uuidString], "blockers": []]]]
        let adapter = RulesPhoneAdapter(engine: RulesGameSession())
        try await adapter.project(JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: json)), refreshArtwork: false)
        let game = adapter.presentation
        XCTAssertEqual(game.attackingPlayer, .b)
        XCTAssertEqual(game.combat?.attackers, [attacker])
        XCTAssertEqual(game.cards[blocker]?.controllerIdentifier.value, .a)
        XCTAssertEqual(game.cards[blocker]?.isTapped.value, false)
        XCTAssertEqual(game.cards[blocker]?.isPhoneCreature, true)
        XCTAssertNil(game.attachments[blocker])
    }

}
