import XCTest
import CardService
@testable import Magic_Board

@MainActor
final class RulesModeTests: XCTestCase {
    func testLondonMulliganDoesNotCaptureScryOrOtherLibraryDecisions() throws {
        func prompt(_ text: String, method: String = "GAME_TARGET") throws -> RulesPrompt {
            let json: [String: Any] = ["id": "p", "method": method, "revision": 1, "message": text,
                                      "supported": true, "choices": [], "cards": [["id": "card", "name": "Plains",
                                          "faceDown": false, "transformed": false, "counters": []]]]
            return try JSONDecoder().decode(RulesPrompt.self, from: JSONSerialization.data(withJSONObject: json))
        }
        for count in [1, 2, 6] {
            let london = try prompt("Select a card (\(count) more) to put on the bottom of your library")
            XCTAssertTrue(london.isLondonBottom)
            XCTAssertEqual(london.style, .compact)
            XCTAssertNil(london.boardBannerText, "The opening-hand browser owns this decision")
        }
        for text in ["Select cards to PUT on the BOTTOM of your library (Scry) (selected 0 of 2)",
                     "Select cards to put into your graveyard (Surveil)",
                     "Choose a card to put on the bottom of your library",
                     "Select a card (0 more) to put on the bottom of your library"] {
            let libraryChoice = try prompt(text)
            XCTAssertFalse(libraryChoice.isLondonBottom, text)
            XCTAssertEqual(libraryChoice.style, .browser, "Library choices use the card-choice browser, not the opening hand")
        }
        XCTAssertFalse(try prompt("Select a card (1 more) to put on the bottom of your library", method: "GAME_ASK").isLondonBottom)
    }

    func testScryOrderQuestionsAnswerFromTheBrowserArrangement() throws {
        let ids = (0..<3).map { _ in UUID() }
        func prompt(_ text: String, _ cards: [UUID]) throws -> RulesPrompt {
            let json: [String: Any] = ["id": "p", "method": "GAME_TARGET", "revision": 1, "message": text, "supported": true, "choices": [],
                                      "cards": cards.map { ["id": $0.uuidString.lowercased(), "name": "Island", "faceDown": false,
                                                            "transformed": false, "counters": []] }]
            return try JSONDecoder().decode(RulesPrompt.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let top = "Select card ORDER to put on the TOP of your library (last one chosen will be topmost)"
        let bottom = "Select card ORDER to put on the BOTTOM of your library (last one chosen will be bottommost)"
        // Arranged top first: ids[0] ends on top, so the deepest (ids[2]) is chosen first.
        XCTAssertEqual(RulesPhoneAdapter.libraryOrderAnswer(try prompt(top, ids), arranged: ids), ids[2].uuidString.lowercased())
        XCTAssertEqual(RulesPhoneAdapter.libraryOrderAnswer(try prompt(top, [ids[0], ids[1]]), arranged: ids), ids[1].uuidString.lowercased())
        // Bottom: the last chosen is bottommost, so the highest is chosen first.
        XCTAssertEqual(RulesPhoneAdapter.libraryOrderAnswer(try prompt(bottom, [ids[2], ids[1]]), arranged: ids), ids[1].uuidString.lowercased())
        // Cards the browser didn't arrange, or another question, are left to the player.
        XCTAssertNil(RulesPhoneAdapter.libraryOrderAnswer(try prompt(top, [ids[0], UUID()]), arranged: ids))
        XCTAssertNil(RulesPhoneAdapter.libraryOrderAnswer(try prompt("Select cards to PUT on the BOTTOM of your library (Scry)", ids), arranged: ids))
    }

    func testCardChoiceUsesEngineEligibilityAndKeepsSelectedCardsDeselectable() throws {
        func prompt(_ fields: [String: Any]) throws -> RulesPrompt {
            var json: [String: Any] = ["id": "p", "method": "GAME_TARGET", "revision": 1,
                                      "supported": true, "choices": []]
            json.merge(fields) { _, value in value }
            return try JSONDecoder().decode(RulesPrompt.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let eligible = try prompt(["selectionIds": ["instant"], "selectedIds": ["selected"]])
        XCTAssertTrue(eligible.isCardSelectable("instant"))
        XCTAssertFalse(eligible.isCardSelectable("land"), "Duress must not offer a displayed land as a legal choice")
        XCTAssertTrue(eligible.isCardSelectable("selected"), "An already selected card may be removed again")
        XCTAssertFalse(try prompt(["selectionIds": []]).isCardSelectable("land"))
        XCTAssertTrue(try prompt([:]).isCardSelectable("legacy"), "Older bridges remain compatible")
    }

    func testRejectedConnectionKeyShowsTheServerReason() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_RECOVERY_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_RECOVERY_FIXTURE_ADDRESS to the local fixture")
        }
        let engine = RulesGameSession()
        let previousKey = engine.connectionKey
        defer { engine.disconnect(); engine.connectionKey = previousKey }
        engine.connect(address: address, key: "deliberately-invalid-test-key", resume: false)
        let deadline = Date().addingTimeInterval(8)
        while engine.status != .disconnected && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(engine.status, .disconnected)
        XCTAssertTrue(engine.error?.localizedCaseInsensitiveContains("key") == true, engine.error ?? "No rejection message")
        XCTAssertFalse(engine.hasRetainedSession)
    }

    func testTransientCardInformationRemainsVisibleAndDismissedReplaysStayClosed() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_RECOVERY_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_RECOVERY_FIXTURE_ADDRESS to the local fixture")
        }
        let engine = RulesGameSession()
        let previousKey = engine.connectionKey
        defer { engine.disconnect(); engine.connectionKey = previousKey }
        engine.connect(address: address + "/information", key: "rules-local-verification-key", resume: false)
        let deadline = Date().addingTimeInterval(8)
        while engine.status != .connected && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        guard engine.status == .connected else { XCTFail("Fixture did not connect: \(engine.error ?? "")"); return }
        await engine.startAiGame()
        while engine.notice != "Information replay 1" && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(engine.snapshot?.lookedAt?.count, 0, "The very next snapshot no longer contains the cards")
        let group = try XCTUnwrap(engine.cardInformation.first)
        XCTAssertEqual(group.cards.first?.id, "visible", "The transient information must survive until the player can read it")
        engine.dismissCardInformation(group.id)
        await engine.refreshTables()
        while engine.notice != "Information replay 2" && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(engine.notice, "Information replay 2")
        XCTAssertTrue(engine.cardInformation.isEmpty, "Identical replayed information must stay dismissed")
        XCTAssertNil(engine.pendingRequest)
        await engine.refreshTables()
        while engine.notice != "Information replay 3" && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(engine.cardInformation.first?.id, group.id, "A later reveal of the same hand must be readable again")
        await engine.endSession()
        XCTAssertTrue(engine.cardInformation.isEmpty)
    }

    func testUnreadableReplaysStopRetryingWithoutDisconnecting() async throws {
        guard let address = ProcessInfo.processInfo.environment["RULES_RECOVERY_FIXTURE_ADDRESS"] else {
            throw XCTSkip("Set TEST_RUNNER_RULES_RECOVERY_FIXTURE_ADDRESS to the malformed-update fixture")
        }
        let engine = RulesGameSession()
        let previousKey = engine.connectionKey
        defer { engine.disconnect(); engine.connectionKey = previousKey }
        engine.connect(address: address, key: "rules-local-verification-key", resume: false)
        let deadline = Date().addingTimeInterval(8)
        while engine.status != .connected && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(engine.status, .connected)
        await engine.startAiGame()
        while engine.notice != "Replay count 2" && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(engine.notice, "Replay count 2")
        XCTAssertTrue(engine.error?.contains("Reconnect or update") == true)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(engine.status, .connected, "A fourth malformed update would make the fixture close an unbounded replay loop")
        XCTAssertNil(engine.pendingRequest)
        await engine.endSession()
    }
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

    func testFloatingManaReadsAsSymbols() throws {
        let player = try JSONDecoder().decode(RulesPlayer.self, from: Data(#"{"id":"p","name":"Me","life":20,"handCount":0,"libraryCount":0,"battlefield":[],"graveyard":[],"exile":[],"manaPool":{"W":0,"U":0,"B":1,"R":0,"G":0,"C":2}}"#.utf8))
        XCTAssertEqual(player.floatingMana, "{B}{C}{C}")
        let old = try JSONDecoder().decode(RulesPlayer.self, from: Data(#"{"id":"p","name":"Me","life":20,"handCount":0,"libraryCount":0,"battlefield":[],"graveyard":[],"exile":[]}"#.utf8))
        XCTAssertEqual(old.floatingMana, "")
    }

    func testTokensUseTheirPrintedName() throws {
        let token = try JSONDecoder().decode(RulesCard.self, from: Data(#"{"id":"t","name":"Treasure Token","set":"FIN","faceDown":false,"transformed":false,"typeLine":"Token Artifact — Treasure","counters":[]}"#.utf8))
        XCTAssertEqual(RulesText.tokenName(token), "Treasure")
        let xmageToken = try JSONDecoder().decode(RulesCard.self, from: Data(#"{"id":"t","name":"Food Token","set":"M20","faceDown":false,"transformed":false,"typeLine":"Legendary Artifact  - Food","counters":[]}"#.utf8))
        XCTAssertEqual(RulesText.typeLine(xmageToken), "Legendary Token Artifact — Food")
        let card = try JSONDecoder().decode(RulesCard.self, from: Data(#"{"id":"c","name":"Ahriman","faceDown":false,"transformed":false,"typeLine":"Creature — Eye Horror","counters":[]}"#.utf8))
        XCTAssertNil(RulesText.tokenName(card))
    }

    func testOptionalBoardChoiceIsFinishedWithTheMainButton() throws {
        func prompt(required: Bool, message: String = "Choose a creature you control") throws -> RulesPrompt {
            try JSONDecoder().decode(RulesPrompt.self, from: JSONSerialization.data(withJSONObject: [
                "id": "p", "method": "GAME_TARGET", "revision": 1, "supported": true, "choices": [], "required": required,
                "message": message, "targets": [UUID().uuidString.lowercased()]] as [String: Any]))
        }
        XCTAssertEqual(RulesPhoneAdapter.primaryButton(prompt: try prompt(required: false), snapshot: nil, pending: false).0, "Done")
        XCTAssertEqual(RulesPhoneAdapter.primaryButton(prompt: try prompt(required: false), snapshot: nil, pending: false).1, true)
        XCTAssertEqual(RulesPhoneAdapter.primaryButton(prompt: try prompt(required: true), snapshot: nil, pending: false).0, "Choose")
    }

    func testAbilitySourceLinksStayInTheRulesAdapterAndClearWithTheStack() async throws {
        let me = UUID().uuidString, source = UUID().uuidString.lowercased(), ability = UUID().uuidString.lowercased()
        let card: [String: Any] = ["id": source, "name": "Ahriman", "faceDown": false, "transformed": false,
                                  "typeLine": "Creature — Eye Horror", "power": "2", "toughness": "2", "counters": []]
        var item = card; item["id"] = ability; item["ability"] = true; item["sourceId"] = source
        var json: [String: Any] = ["gameId": UUID().uuidString, "playerId": me, "revision": 1, "turn": 3,
                                  "hand": [], "stack": [item], "playableIds": [],
                                  "players": [["id": me, "name": "Me", "life": 20, "handCount": 0, "libraryCount": 30,
                                               "battlefield": [card], "graveyard": [], "exile": []]]]
        let adapter = RulesPhoneAdapter(engine: RulesGameSession())
        func state() throws -> RulesSnapshot { try JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: json)) }
        try await adapter.project(state(), refreshArtwork: false)
        XCTAssertEqual(adapter.abilitySources, [try XCTUnwrap(UUID(uuidString: ability)): try XCTUnwrap(UUID(uuidString: source))])
        item["sourceId"] = UUID().uuidString.lowercased(); json["stack"] = [item]
        try await adapter.project(state(), refreshArtwork: false)
        XCTAssertTrue(adapter.abilitySources.isEmpty, "Unseen origins must not gain a visible endpoint")
        item["sourceId"] = source; item["ability"] = false; json["stack"] = [item]
        try await adapter.project(state(), refreshArtwork: false)
        XCTAssertTrue(adapter.abilitySources.isEmpty, "Ordinary spells do not gain ability-source links")
        json["stack"] = []
        try await adapter.project(state(), refreshArtwork: false)
        XCTAssertTrue(adapter.abilitySources.isEmpty)
    }

    func testStructuredPromptSourceAndOlderBridgeFallback() throws {
        func prompt(_ extra: [String: Any]) throws -> RulesPrompt {
            var json: [String: Any] = ["id": "s", "method": "GAME_TARGET", "revision": 1, "supported": true,
                                      "message": "Select another creature or artifact (to sacrifice)", "choices": []]
            json.merge(extra) { _, new in new }
            return try JSONDecoder().decode(RulesPrompt.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let sourced = try prompt(["source": ["id": "source-id", "name": "Ahriman"]])
        XCTAssertEqual(sourced.source?.id, "source-id")
        XCTAssertEqual(sourced.boardBannerText, "Ahriman: Choose another creature or artifact (to sacrifice)")
        XCTAssertNil(try prompt([:]).source)
        XCTAssertEqual(try prompt([:]).boardBannerText, "Choose another creature or artifact (to sacrifice)")
    }

    func testBattlefieldInstructionNamesTheAskingCard() throws {
        let prompt = try JSONDecoder().decode(RulesPrompt.self, from: JSONSerialization.data(withJSONObject: [
            "id": "sacrifice", "method": "GAME_TARGET", "revision": 1, "supported": true, "choices": [],
            "message": "Select another creature or artifact (to sacrifice)",
            "subMessage": "<font color='#696969' object_id='b95222bf-68a0-4769-8c28-4807c05cd345'>Ahriman</font> [b95]"] as [String: Any]))
        XCTAssertEqual(prompt.boardBannerText, "Ahriman: Choose another creature or artifact (to sacrifice)")
    }

    func testCombatShortcutDoesNotDuplicateRealSpecialActions() throws {
        func prompt(_ message: String, label: String) throws -> RulesPrompt {
            try JSONDecoder().decode(RulesPrompt.self, from: JSONSerialization.data(withJSONObject: [
                "id": "p", "method": "GAME_SELECT", "revision": 1, "supported": true, "choices": [],
                "message": message, "specialActionAvailable": true, "specialActionLabel": label] as [String: Any]))
        }
        XCTAssertFalse(try prompt("Select attackers", label: "All attack").showsSpecialAction)
        XCTAssertTrue(try prompt("Play spells and abilities", label: "Special action").showsSpecialAction)
    }

    func testRevealedCardsSayWhyFromTheGameLog() throws {
        let group = try JSONDecoder().decode(RulesSnapshot.CardGroup.self, from: Data(#"{"name":"Revealed cards","cards":[{"id":"f","name":"Forest","faceDown":false,"transformed":false,"counters":[]}]}"#.utf8))
        let log = ["Computer casts Summon: Fenrir", "Computer reveals Forest (Summon: Fenrir)", "Computer draws a card"]
        XCTAssertEqual(RulesCardInformationView.reason(for: group, log: log), "Computer reveals Forest (Summon: Fenrir)")
        XCTAssertNil(RulesCardInformationView.reason(for: group, log: ["Computer draws a card"]))
        XCTAssertEqual(RulesText.plain("Summon: Fenrir [3fa]"), "Summon: Fenrir")
    }

    func testRulesTextItalicsMatchSpellbook() {
        func italic(_ line: String) -> [String] { RulesOracleText.italicRanges(line).map { String(line[$0]) } }
        XCTAssertEqual(italic("Rat Tail — When this creature dies, create a Treasure token. (It's an artifact.)"),
                       ["Rat Tail — ", "(It's an artifact.)"])
        XCTAssertEqual(italic("Cycling — {2}"), [])
        XCTAssertEqual(italic("{T}: Add {C}."), [])
    }

    func testCardRulesReadLikePrintedText() {
        func rules(_ text: String, _ name: String, _ type: String) -> String { RulesText.cardRules(text, name: name, typeLine: type) }
        XCTAssertEqual(rules("Rat Tail &mdash; When {this} dies, create a Treasure token.", "Undercity Dire Rat", "Creature — Rat"),
                       "Rat Tail — When this creature dies, create a Treasure token.")
        XCTAssertEqual(rules("{this} enters tapped.<br>{T}: Add {W}.", "Insomnia, Crown City", "Land — Town"), "This land enters tapped.\n{T}: Add {W}.")
        XCTAssertEqual(rules("{this} deals 3 damage to any target.", "Lightning Bolt", "Instant"), "Lightning Bolt deals 3 damage to any target.")
        XCTAssertEqual(rules("Return {this} from your graveyard to the battlefield.", "Bloodghast", "Creature — Vampire Spirit"),
                       "Return this card from your graveyard to the battlefield.")
        XCTAssertEqual(rules("Cycling {2} ({2}, Discard {this}: Draw a card.)", "Capital City", "Land — Town"),
                       "Cycling {2} ({2}, Discard this card: Draw a card.)")
        XCTAssertEqual(rules("Whenever {this} attacks, draw a card.", "Syr Konrad, the Grim", "Legendary Creature — Human Knight"),
                       "Whenever Syr Konrad attacks, draw a card.")
        XCTAssertEqual(rules("{this} gets +1/+1.", "Acererak the Archlich", "Legendary Creature — Zombie Wizard"), "Acererak gets +1/+1.")
        XCTAssertEqual(rules("Enchanted creature gets +2/+2. When {this} is put into a graveyard, draw.", "Rancor", "Enchantment — Aura"),
                       "Enchanted creature gets +2/+2. When this Aura is put into a graveyard, draw.")
        XCTAssertEqual(rules("{T}, Sacrifice {this}: Add one mana of any color.", "Treasure Token", "Token Artifact — Treasure"),
                       "{T}, Sacrifice this token: Add one mana of any color.")
        XCTAssertEqual(RulesText.plain("Tom &amp; Jerry&#39;s &quot;deal&quot;"), "Tom & Jerry's \"deal\"")
    }

    func testOpponentSpellTargetsReachTheStackArcs() async throws {
        let me = UUID().uuidString, opponent = UUID().uuidString
        let bear = UUID().uuidString, shock = UUID().uuidString, bolt = UUID().uuidString, missing = UUID().uuidString
        let bearCard: [String: Any] = ["id": bear, "name": "Grizzly Bears", "faceDown": false, "transformed": false, "typeLine": "Creature — Bear",
                                       "power": "2", "toughness": "2", "tapped": false, "summoningSick": false, "counters": []]
        func spell(_ id: String, _ name: String, targets: [String]) -> [String: Any] {
            ["id": id, "name": name, "faceDown": false, "transformed": false, "typeLine": "Instant", "controllerId": opponent,
             "counters": [], "targets": targets]
        }
        let json: [String: Any] = ["gameId": UUID().uuidString, "playerId": me, "revision": 1, "turn": 3, "phase": "PRECOMBAT_MAIN",
                                   "activePlayerId": opponent, "playableIds": [], "hand": [],
                                   "stack": [spell(shock, "Shock", targets: [bear]), spell(bolt, "Lightning Bolt", targets: [me, missing])],
                                   "players": [["id": me, "name": "Me", "life": 20, "handCount": 0, "libraryCount": 0, "graveyard": [], "exile": [],
                                                "battlefield": [bearCard]],
                                               ["id": opponent, "name": "Them", "life": 20, "handCount": 0, "libraryCount": 0, "graveyard": [], "exile": [],
                                                "battlefield": []]]]
        let adapter = RulesPhoneAdapter(engine: RulesGameSession())
        try await adapter.project(JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: json)))
        let stack = Dictionary(uniqueKeysWithValues: adapter.presentation.stack.map { ($0.id.uuidString.lowercased(), $0) })
        XCTAssertEqual(stack[shock.lowercased()]?.player, .b, "the opponent's spell is drawn from their side")
        XCTAssertEqual(stack[shock.lowercased()]?.targets, [.card(UUID(uuidString: bear)!)], "a creature target gets an arc")
        XCTAssertEqual(stack[bolt.lowercased()]?.targets, [.player(.a)], "a player target points at me; unseen objects are dropped")
    }

    func testUncrewedVehiclesSitWithArtifactsUntilCrewed() async throws {
        let me = UUID().uuidString, parked = UUID().uuidString, crewed = UUID().uuidString
        func vehicle(_ id: String, _ type: String) -> [String: Any] {
            ["id": id, "name": "Cargo Ship", "faceDown": false, "transformed": false, "typeLine": type, "power": "2", "toughness": "3",
             "tapped": false, "summoningSick": false, "counters": []]
        }
        let json: [String: Any] = ["gameId": UUID().uuidString, "playerId": me, "revision": 1, "turn": 3, "phase": "PRECOMBAT_MAIN",
                                   "activePlayerId": me, "stack": [], "playableIds": [], "hand": [],
                                   "players": [["id": me, "name": "Me", "life": 20, "handCount": 0, "libraryCount": 0, "graveyard": [], "exile": [],
                                                "battlefield": [vehicle(parked, "Artifact  - Vehicle"), vehicle(crewed, "Artifact Creature  - Vehicle")]]]]
        let adapter = RulesPhoneAdapter(engine: RulesGameSession())
        try await adapter.project(JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: json)))
        let field = adapter.presentation.state.battlefield.value
        XCTAssertEqual(field.first { $0.uuid.uuidString.lowercased() == parked.lowercased() }?.isPhoneCreature, false, "Uncrewed: with the artifacts")
        XCTAssertEqual(field.first { $0.uuid.uuidString.lowercased() == crewed.lowercased() }?.isPhoneCreature, true, "Crewed: a creature")
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

    func testJumpStartAndJumpInPacketsMakeImportableFortyCardDecks() throws {
        for source in [RulesDeckSource.jumpStart, .jumpIn] {
            let set = try XCTUnwrap(RulesPackets.sets(for: source).first?.code, "\(source.rawValue) has bundled sets")
            let offers = RulesPackets.offers(source, set: set, first: nil)
            XCTAssertFalse(offers.isEmpty, "\(source.rawValue) offers packets")
            let first = try XCTUnwrap(offers.first)
            let second = try XCTUnwrap(RulesPackets.offers(source, set: set, first: first).first { $0 != first })
            let text = try XCTUnwrap(RulesPackets.deckList(source, set: set, first: first, second: second))
            let deck = try XCTUnwrap(RulesDeckImporter.parse(text))
            XCTAssertGreaterThanOrEqual(deck.main.reduce(0) { $0 + $1.count }, 40, "\(source.rawValue): \(first) + \(second)")
            let ai = try XCTUnwrap(RulesPackets.randomDeckList(source, set: set).flatMap { try RulesDeckImporter.parse($0) })
            XCTAssertGreaterThanOrEqual(ai.main.reduce(0) { $0 + $1.count }, 40)
        }
    }

    func testAIPicksASecondPacketThatKeepsItToTwoColorsWhenPossible() {
        let offers: [(name: String, colors: Set<String>)] = [("Dragons", ["R"]), ("Angels", ["W"]), ("Sea", ["U", "G"])]
        for _ in 0..<20 {
            // After a white packet, red or white keeps two colours; blue-green would make three.
            XCTAssertNotEqual(RulesPackets.aiSecondPick(firstColors: ["W"], offers: offers), "Sea")
        }
        // Nothing keeps it to two: take the fewest colours.
        let wide: [(name: String, colors: Set<String>)] = [("Grixis", ["U", "B", "R"]), ("Orzhov", ["W", "B"])]
        XCTAssertEqual(RulesPackets.aiSecondPick(firstColors: ["W", "U"], offers: wide), "Orzhov")
        XCTAssertNil(RulesPackets.aiSecondPick(firstColors: ["W"], offers: []))
    }

    func testSandboxReducerStillAllowsManualLifeChanges() throws {
        var sandbox = PhoneGame()
        sandbox.state.player1.life.accept(20)
        try sandbox.apply(.life(-3), player: .a)
        XCTAssertEqual(sandbox.state.player1.life.value, 17)
        try sandbox.apply(.life(5), player: .a)
        XCTAssertEqual(sandbox.state.player1.life.value, 22)
    }

    func testAutomaticManaLeavesRestrictedLandsManualAndRecognizesWastes() throws {
        func pay(name: String, type: String, cost: String, sick: Bool = false) throws -> String? {
            let snapshot = try JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: [
                "gameId": "g", "playerId": "me", "revision": 1, "turn": 3, "hand": [], "stack": [], "playableIds": [],
                "players": [["id": "me", "name": "Me", "life": 20, "handCount": 0, "libraryCount": 0,
                             "graveyard": [], "exile": [], "battlefield": [[
                                "id": "land", "name": name, "faceDown": false, "transformed": false,
                                "typeLine": type, "tapped": false, "summoningSick": sick, "counters": []]]]]] as [String: Any]))
            let prompt = try JSONDecoder().decode(RulesPrompt.self, from: JSONSerialization.data(withJSONObject: [
                "id": "p", "method": "GAME_PLAY_MANA", "revision": 1, "supported": true,
                "choices": [], "message": "Pay " + cost] as [String: Any]))
            return RulesPhoneAdapter.autoPayLand(prompt, snapshot: snapshot)
        }
        XCTAssertNil(try pay(name: "Murmuring Bosk", type: "Land — Forest", cost: "{G}"))
        XCTAssertNil(try pay(name: "Dryad Arbor", type: "Land Creature — Forest Dryad", cost: "{G}", sick: true))
        XCTAssertNil(try pay(name: "Forest", type: "Basic Land Creature — Forest", cost: "{G}", sick: true))
        XCTAssertEqual(try pay(name: "Snow-Covered Forest", type: "Basic Snow Land — Forest", cost: "{G}"), "land")
        XCTAssertEqual(try pay(name: "Wastes", type: "Basic Land", cost: "{C}"), "land")
        XCTAssertEqual(try pay(name: "Wastes", type: "Basic Land", cost: "{1}"), "land")
        XCTAssertNil(try pay(name: "Wastes", type: "Basic Land", cost: "{W}"))
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

    func testCombatSnapshotSurvivesADefenderLeavingPlay() throws {
        let json: [String: Any] = ["gameId": "g", "playerId": "me", "revision": 4, "turn": 8,
                                  "phase": "COMBAT", "step": "COMBAT_DAMAGE", "hand": [], "stack": [],
                                  "players": [], "playableIds": [],
                                  "combat": [["attackers": ["attacker"], "blockers": []]]]
        let state = try JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        let group = try XCTUnwrap(state.combat?.first)
        XCTAssertNil(group.defenderId)
        XCTAssertEqual(group.attackers, ["attacker"])
    }

    func testLookedAtCardsCanResolveAnImageFromPrintingWithoutAName() throws {
        let json: [String: Any] = ["gameId": "g", "playerId": "me", "revision": 2, "turn": 1,
                                  "hand": [], "stack": [], "players": [], "playableIds": [],
                                  "lookedAt": [["name": "Opponent's hand", "cards": [[
                                    "id": "visible", "set": "M10", "collectorNumber": "230",
                                    "faceDown": false, "transformed": false, "counters": []]]]],
                                  "revealed": []]
        let state = try JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        let card = try XCTUnwrap(state.lookedAt?.first?.cards.first)
        XCTAssertNil(card.name)
        XCTAssertEqual(card.set, "M10")
        XCTAssertEqual(card.collectorNumber, "230")
        XCTAssertEqual(state.lookedAt?.first?.name, "Opponent's hand")
        XCTAssertEqual(state.revealed?.count, 0)
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

    func testPlainNameOnlyDeckListImports() throws {
        let deck = try XCTUnwrap(RulesDeckImporter.parse("22 Plains\n10 Silvercoat Lion\n8 Blessed Alliance\n8 Pacifism\n6 Reverent Mantra\n6 Soul Warden"))
        XCTAssertEqual(deck.main.reduce(0) { $0 + $1.count }, 60)
        XCTAssertEqual(Set(deck.main.map(\.name)), ["Plains", "Silvercoat Lion", "Blessed Alliance", "Pacifism", "Reverent Mantra", "Soul Warden"])
        print("RULES-DECK-JSON " + String(decoding: try JSONEncoder().encode(deck), as: UTF8.self))
    }

    func testEngineMarkupKeepsTheCardNameOnItsOwnLine() {
        let text = RulesText.plain("Choose mode (selected 0 of 3, min 1)<div style='font-size:11pt'><font color='#F0E68C'>Blessed Alliance</font></div>")
        XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "Choose mode (selected 0 of 3, min 1)\nBlessed Alliance")
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

    func testPassCaptionNamesTheNextStep() throws {
        let me = UUID().uuidString, opponent = UUID().uuidString
        let prompt = try JSONDecoder().decode(RulesPrompt.self, from: JSONSerialization.data(withJSONObject: [
            "id": "p", "method": "GAME_SELECT", "revision": 1, "supported": true, "choices": [],
            "message": "Play spells and abilities"] as [String: Any]))
        func label(_ step: String, stack: [[String: Any]] = []) throws -> String {
            let player: (String) -> [String: Any] = { ["id": $0, "name": $0, "life": 20, "handCount": 0, "libraryCount": 0, "battlefield": [], "graveyard": [], "exile": []] }
            let json: [String: Any] = ["gameId": UUID().uuidString, "playerId": me, "revision": 1, "turn": 2,
                                       "phase": "X", "step": step, "activePlayerId": opponent, "hand": [], "stack": stack,
                                       "playableIds": [], "players": [player(me), player(opponent)], "combat": []]
            let snapshot = try JSONDecoder().decode(RulesSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
            return RulesPhoneAdapter.primaryButton(prompt: prompt, snapshot: snapshot, pending: false).0
        }
        XCTAssertEqual(try label("BEGIN_COMBAT"), "Pass\nTo Attackers")
        XCTAssertEqual(try label("DECLARE_ATTACKERS"), "Pass\nTo End of Combat")
        XCTAssertEqual(try label("POSTCOMBAT_MAIN"), "Pass\nTo End Step")
        XCTAssertEqual(try label("END_TURN"), "Pass\nTo Your Turn")
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
