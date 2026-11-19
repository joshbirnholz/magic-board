import XCTest
import CardService
import MultipeerConnectivity
import UIKit
import RxCocoa
import RxSwift
@testable import Magic_Board

final class PhoneGameTests: XCTestCase {
    private func card(_ name: String, type: String, player: Player.Identifier = .a, token: Bool = false, layout: String? = nil, faces: [[String: Any]]? = nil, keywords: [String] = [], oracleText: String = "", oracleID: UUID = UUID()) throws -> CardInstance {
        var json: [String: Any] = [
            "scryfallID": UUID().uuidString, "oracleID": oracleID.uuidString,
            "name": name, "typeLine": type, "layout": layout ?? (token ? "token" : "normal"),
            "isFullArt": false, "collectorNumber": "1", "set": "tst", "rarity": "common",
            "frame": "2015", "isPromo": false, "isFoundInBoosters": true,
            "isFoilAvailable": false, "isNonFoilAvailable": true, "language": "en", "keywords": keywords, "oracleText": oracleText
        ]
        if let faces { json["cardFaces"] = faces }
        if type.contains("Creature") { json["power"] = "2"; json["toughness"] = "2" }
        let model = try JSONDecoder().decode(MTGCard.self, from: JSONSerialization.data(withJSONObject: json))
        return CardInstance(card: model, center: nil, ownerIdentifier: player)
    }

    func testAttachmentFootprintsOnlyPadTheirOwnGroup() {
        let plain = PhoneBattlefieldLayout.packedRow(extras: [0, 0, 0, 0], availableWidth: 5000, cellWidth: 600, rotationSpill: 40)
        XCTAssertEqual(plain.centers, [290, 890, 1490, 2090])
        let equipped = PhoneBattlefieldLayout.packedRow(extras: [0, 390, 0, 0], availableWidth: 5000, cellWidth: 600, rotationSpill: 40)
        XCTAssertEqual(equipped.centers, [290, 1280, 1880, 2480])
        XCTAssertEqual(equipped.centers[3] - equipped.centers[2], plain.centers[3] - plain.centers[2], "Plain cards must not inherit another creature's equipment fan")
        XCTAssertEqual(equipped.width - plain.width, 390, "Reserve one attachment fan, not one per creature")
        let dense = PhoneBattlefieldLayout.packedRow(extras: [0, 100, 0], availableWidth: 1500, cellWidth: 600, rotationSpill: 40)
        XCTAssertLessThanOrEqual(dense.width, 1500)
    }

    func testStackTargetsAreOwnedPublicUniqueAndSurviveSnapshots() throws {
        var game = PhoneGame()
        let spell = try card("Spell", type: "Instant")
        let creature = try card("Creature", type: "Creature", player: .b)
        let hidden = try card("Private hand", type: "Creature", player: .b)
        game.state.player1.hand.cards.accept([spell])
        game.state.player2.hand.cards.accept([hidden])
        game.state.battlefield.accept([creature])
        try game.apply(.play(spell.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        let item = game.stack[0].id
        let action = PhoneAction.setStackTargets(item, [.card(creature.uuid), .player(.b), .card(creature.uuid), .card(hidden.uuid), .card(spell.uuid), .card(UUID())])
        let wireAction = try JSONDecoder().decode(PhoneAction.self, from: JSONEncoder().encode(action))
        try game.apply(wireAction, player: .a)
        XCTAssertEqual(game.stack[0].targets, [.card(creature.uuid), .player(.b)])
        try game.apply(.setStackTargets(item, []), player: .b)
        XCTAssertEqual(game.stack[0].targets?.count, 2, "Only the spell's controller edits its targets")
        let data = try JSONEncoder().encode(game)
        let restored = try JSONDecoder().decode(PhoneGame.self, from: data)
        XCTAssertEqual(restored.stack[0].targets, game.stack[0].targets)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var stack = try XCTUnwrap(legacy["stack"] as? [[String: Any]])
        stack[0].removeValue(forKey: "targets"); legacy["stack"] = stack
        let oldSave = try JSONDecoder().decode(PhoneGame.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(oldSave.stack[0].targets)
    }

    func testStackTargetsClearOnZoneChangesAndPermanentResolution() throws {
        var game = PhoneGame()
        let spell = try card("Spell", type: "Instant")
        let permanent = try card("Permanent", type: "Creature", player: .b)
        let creature = try card("Creature", type: "Creature", player: .b)
        game.state.player1.hand.cards.accept([spell])
        game.state.player2.hand.cards.accept([permanent])
        game.state.battlefield.accept([creature])
        try game.apply(.play(spell.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        try game.apply(.moveToStack(permanent.uuid), player: .b)
        try game.apply(.setStackTargets(game.stack[0].id, [.card(permanent.uuid), .card(creature.uuid)]), player: .a)
        try game.apply(.resolve(game.stack[1].id), player: .b)
        XCTAssertTrue(game.state.battlefield.value.contains(permanent))
        XCTAssertEqual(game.stack[0].targets, [.card(creature.uuid)], "A resolved spell is a new object on the field")
        try game.apply(.move(creature.uuid, .graveyard, bottom: false), player: .b)
        XCTAssertEqual(game.stack[0].targets, [])
        XCTAssertEqual(game.stack.count, 1, "Players still resolve the spell manually")
    }

    func testTargetingSpellsAreInstantsSorceriesAndAuras() throws {
        XCTAssertTrue(try card("Bounce", type: "Instant", oracleText: "Return target creature to its owner's hand.").isPhoneTargetingSpell)
        XCTAssertTrue(try card("Draw", type: "Sorcery", oracleText: "Draw two cards.").isPhoneTargetingSpell)
        XCTAssertTrue(try card("Aura", type: "Enchantment — Aura", oracleText: "Enchant creature").isPhoneTargetingSpell)
        XCTAssertFalse(try card("Bear", type: "Creature — Bear", oracleText: "").isPhoneTargetingSpell)
        let aura = try card("Aura", type: "Enchantment — Aura", oracleText: "Enchant creature")
        aura.representation = .faceDown(aura.representation)
        XCTAssertFalse(aura.isPhoneTargetingSpell)
    }

    func testCastTargetingPutsSpellOnStackAndAuraAttachesWhenItResolves() throws {
        var game = PhoneGame()
        let aura = try card("Aura", type: "Enchantment — Aura", oracleText: "Enchant creature")
        let bounce = try card("Bounce", type: "Instant", oracleText: "Return target creature to its owner's hand.")
        let creature = try card("Bear", type: "Creature — Bear", oracleText: "")
        game.state.player1.hand.cards.accept([aura, bounce])
        game.state.battlefield.accept([creature])
        try game.apply(.castTargeting(aura.uuid, .card(creature.uuid)), player: .a)
        XCTAssertEqual(game.stack.last?.card, aura)
        XCTAssertEqual(game.stack.last?.targets, [.card(creature.uuid)])
        try game.apply(.castTargeting(bounce.uuid, nil), player: .a)
        XCTAssertEqual(game.stack.count, 2)
        XCTAssertEqual(game.stack.last?.targets ?? [], [], "Dragged out without a target")
        try game.apply(.counterStack(game.stack[1].id), player: .a)
        try game.apply(.resolve(game.stack[0].id), player: .a)
        XCTAssertTrue(game.state.battlefield.value.contains(aura))
        XCTAssertEqual(game.attachments[aura.uuid], creature.uuid, "A resolving Aura attaches to its target")
    }

    func testCommanderTaxGrowsWithCastsFromTheCommandZoneAndCanBeSet() throws {
        var game = PhoneGame()
        let general = try card("General", type: "Legendary Creature — Human", oracleText: "")
        general.isCommander.accept(true)
        game.state.player1.commandZone.cards.accept([general])
        try game.apply(.play(general.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        XCTAssertEqual(general.commanderCasts.value, 1, "Casting from the command zone adds tax")
        try game.apply(.moveToPlayer(general.uuid, .command, .a, bottom: false), player: .a)
        XCTAssertTrue(game.state.player1.commandZone.cards.value.contains(general))
        XCTAssertTrue(general.isCommander.value)
        try game.apply(.moveToStack(general.uuid), player: .a)
        XCTAssertEqual(general.commanderCasts.value, 2)
        try game.apply(.commanderTax(general.uuid, 0), player: .a)
        XCTAssertEqual(general.commanderCasts.value, 0)
        // Played from the hand it adds no tax.
        try game.apply(.moveToPlayer(general.uuid, .hand, .a, bottom: false), player: .a)
        try game.apply(.play(general.uuid, face: nil, faceDown: false, tapped: false, directly: true), player: .a)
        XCTAssertEqual(general.commanderCasts.value, 0)
    }

    func testTokenCopyOfDoubleFacedCardUsesItsFrontFace() throws {
        var game = PhoneGame()
        let dfc = try card("Front // Back", type: "Creature — Human // Creature — Werewolf", layout: "transform", faces: [
            ["name": "Front", "typeLine": "Creature — Human", "oracleText": ""],
            ["name": "Back", "typeLine": "Creature — Werewolf", "oracleText": ""]])
        game.state.player1.graveyard.cards.accept([dfc])
        try game.apply(.copy(dfc.uuid), player: .a)
        let token = try XCTUnwrap(game.state.battlefield.value.first)
        guard case .tokenCopy(.alternateFace(_, let face)) = token.representation else {
            return XCTFail("Expected a token copy of the front face, got \(token.representation)")
        }
        XCTAssertEqual(face.name, "Front")
        XCTAssertTrue(game.state.player1.graveyard.cards.value.contains(dfc), "The original stays in the graveyard")
    }

    func testPlaneswalkersSagasAndBattlesUseTheRightLaneUnlessCreatures() throws {
        XCTAssertEqual(PhoneBattlefieldLayout.row(for: try card("Jace", type: "Legendary Planeswalker — Jace")), .side)
        XCTAssertEqual(PhoneBattlefieldLayout.row(for: try card("Saga", type: "Enchantment — Saga")), .side)
        XCTAssertEqual(PhoneBattlefieldLayout.row(for: try card("Battle", type: "Battle — Siege")), .side)
        XCTAssertEqual(PhoneBattlefieldLayout.row(for: try card("Saga Creature", type: "Enchantment Creature — Saga Wolf")), .creatures)
        XCTAssertEqual(PhoneBattlefieldLayout.row(for: try card("Bear", type: "Creature — Bear")), .creatures)
        XCTAssertEqual(PhoneBattlefieldLayout.row(for: try card("Rings", type: "Artifact")), .support)
    }

    func testPrepareCardsCastAsCreatureAndCastTheirPreparedSpellAsACopy() throws {
        var game = PhoneGame()
        let card = try card("Scholar // Lesson", type: "Creature — Human Wizard // Sorcery", layout: "prepare", faces: [
            ["name": "Scholar", "typeLine": "Creature — Human Wizard", "oracleText": ""],
            ["name": "Lesson", "typeLine": "Sorcery", "oracleText": "Draw a card."]])
        // Played from the hand it's always the creature.
        XCTAssertEqual(Command.PlayCardParameters.options(for: card).map(\.title), ["Scholar"])
        game.state.player1.hand.cards.accept([card])
        try game.apply(.play(card.uuid, face: 0, faceDown: false, tapped: false, directly: true), player: .a)
        XCTAssertEqual(card.representation.name, "Scholar")
        // Not prepared: nothing to cast.
        try game.apply(.castPrepared(card.uuid), player: .a)
        XCTAssertTrue(game.stack.isEmpty)
        try game.apply(.counter(card.uuid, .prepared, 1), player: .a)
        try game.apply(.castPrepared(card.uuid), player: .a)
        XCTAssertEqual(game.stack.count, 1)
        XCTAssertEqual(game.stack.last?.text, "Lesson")
        XCTAssertTrue(game.stack.last?.card?.representation.isToken == true, "The prepared spell is cast as a copy")
        XCTAssertFalse(card.counters.value.contains(.prepared), "Casting it unprepares the card")
        XCTAssertTrue(game.state.battlefield.value.contains(card), "The creature stays on the battlefield")
        // The copy resolves away, leaving nothing in the graveyard.
        try game.apply(.resolve(game.stack[0].id), player: .a)
        XCTAssertTrue(game.stack.isEmpty)
        XCTAssertTrue(game.state.player1.graveyard.cards.value.isEmpty)
    }

    func testPrepareCardInHandShowsOnlyItsCreatureCost() throws {
        let card = try card("Scholar // Lesson", type: "Creature — Human Wizard // Sorcery", layout: "prepare", faces: [
            ["name": "Scholar", "typeLine": "Creature — Human Wizard", "oracleText": "", "manaCost": "{1}{U}"],
            ["name": "Lesson", "typeLine": "Sorcery", "oracleText": "Draw a card.", "manaCost": "{2}{U}"]])
        XCTAssertEqual(PhoneHandCardFace.handCost(for: card, inCommandZone: false), "{1}{U}")
    }

    func testCardsCastableFromGraveyardAndExileAreListed() throws {
        var game = PhoneGame()
        let flashback = try card("Think Twice", type: "Instant", keywords: ["Flashback"])
        let plain = try card("Shock", type: "Instant")
        let foretold = try card("Saw It Coming", type: "Instant", keywords: ["Foretell"])
        foretold.representation = .foretold(foretold.representation.card)
        let opponents = try card("Their Flashback", type: "Sorcery", player: .b, keywords: ["Flashback"])
        game.state.player1.graveyard.cards.accept([flashback, plain])
        game.state.player1.exile.cards.accept([foretold])
        game.state.player2.graveyard.cards.accept([opponents])
        XCTAssertEqual(game.castableCards(for: .a).map(\.uuid), [flashback.uuid, foretold.uuid])
        // Casting it from the graveyard works like casting from the hand (it goes onto the stack).
        try game.apply(.play(flashback.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        XCTAssertEqual(game.stack.last?.card, flashback)
        // A foretold card is cast face up.
        try game.apply(.play(foretold.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        guard case .card = foretold.representation else { return XCTFail("Foretold card should be revealed when cast") }
    }

    func testCardsMarkedCastableShowUntilCastAndFlashbackIsExiledAfter() throws {
        var game = PhoneGame()
        let plain = try card("Shock", type: "Instant")
        let theirs = try card("Their Sorcery", type: "Sorcery", player: .b)
        let flashback = try card("Think Twice", type: "Instant", keywords: ["Flashback"])
        game.state.player1.graveyard.cards.accept([plain, flashback])
        game.state.player2.exile.cards.accept([theirs])
        try game.apply(.markCastable(plain.uuid, true), player: .a)
        try game.apply(.markCastable(theirs.uuid, true), player: .a) // e.g. cast from an opponent's exile
        XCTAssertEqual(Set(game.castableCards(for: .a).map(\.uuid)), [plain.uuid, flashback.uuid, theirs.uuid])
        XCTAssertFalse(game.castableCards(for: .b).contains(theirs), "Only the player who marked it may cast it")
        // Casting resets the mark; a plain spell cast from the graveyard returns there.
        try game.apply(.play(plain.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        XCTAssertNil(game.markedCastable?[plain.uuid])
        try game.apply(.resolve(game.stack.last!.id), player: .a)
        XCTAssertTrue(game.state.player1.graveyard.cards.value.contains(plain))
        XCTAssertFalse(game.castableCards(for: .a).contains(plain))
        // Flashback: exiled when it resolves…
        try game.apply(.play(flashback.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        try game.apply(.resolve(game.stack.last!.id), player: .a)
        XCTAssertTrue(game.state.player1.exile.cards.value.contains(flashback))
        // …or when it's countered. Cast from the hand it goes to the graveyard as usual.
        let again = try card("Think Again", type: "Instant", keywords: ["Flashback"])
        game.state.player1.graveyard.cards.mutate { $0.append(again) }
        try game.apply(.play(again.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        try game.apply(.counterStack(game.stack.last!.id), player: .a)
        XCTAssertTrue(game.state.player1.exile.cards.value.contains(again))
        let fromHand = try card("Hand Flashback", type: "Instant", keywords: ["Flashback"])
        game.state.player1.hand.cards.accept([fromHand])
        try game.apply(.play(fromHand.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        try game.apply(.resolve(game.stack.last!.id), player: .a)
        XCTAssertTrue(game.state.player1.graveyard.cards.value.contains(fromHand))
    }

    func testStartGameDealsBothPlayersAndWaitsForBothToKeep() throws {
        var game = PhoneGame()
        game.state.player1.library.cards.accept(OrderedSet(try (0..<20).map { try card("A\($0)", type: "Instant") }))
        game.state.player2.library.cards.accept(OrderedSet(try (0..<20).map { try card("B\($0)", type: "Instant", player: .b) }))
        XCTAssertTrue(game.canStartGame)
        try game.apply(.startGame, player: .b)
        XCTAssertEqual(game.state.player1.hand.cards.value.count, 7)
        XCTAssertEqual(game.state.player2.hand.cards.value.count, 7)
        XCTAssertEqual(game.opening?.deciding, ["a", "b"])
        XCTAssertFalse(game.canStartGame)
        let firstHand = game.state.player1.hand.cards.value.map(\.uuid)
        try game.apply(.mulligan, player: .a)
        XCTAssertEqual(game.state.player1.hand.cards.value.count, 7)
        XCTAssertEqual(game.state.player1.library.cards.value.count + 7, 20)
        XCTAssertTrue(Set(firstHand).isSubset(of: Set(game.cards.keys)))
        try game.apply(.keepHand, player: .a)
        try game.apply(.mulligan, player: .a) // already kept: no new hand
        XCTAssertEqual(game.opening?.deciding, ["b"])
        try game.apply(.keepHand, player: .b)
        XCTAssertEqual(game.opening?.deciding, [])
        XCTAssertNotNil(game.opening?.firstPlayer)
        game.resetDecksAndLife()
        XCTAssertNil(game.opening)
    }

    func testCancelStartPutsHandsBackAndSmoothingFlags() throws {
        var game = PhoneGame()
        let lands = try (0..<17).map { try card("Land \($0)", type: "Basic Land — Island") }
        let spells = try (0..<23).map { try card("Spell \($0)", type: "Instant") }
        game.state.player1.library.cards.accept(OrderedSet(lands + spells))
        try game.apply(.markSmoothedDeck, player: .a)
        XCTAssertEqual(game.smoothedDecks, ["a"])
        try game.apply(.startGame, player: .a)
        XCTAssertEqual(game.state.player1.hand.cards.value.count, 7)
        try game.apply(.cancelStart, player: .b)
        XCTAssertNil(game.opening)
        XCTAssertTrue(game.state.player1.hand.cards.value.isEmpty)
        XCTAssertEqual(game.state.player1.library.cards.value.count, 40)
        XCTAssertTrue(game.canStartGame)
        try game.apply(.setHandSmoothing(false), player: .b)
        XCTAssertEqual(game.handSmoothing, false)
        game.smoothShuffle(.a)
        XCTAssertEqual(game.state.player1.library.cards.value.count, 40)
    }

    func testResetBringsBackStartGame() throws {
        var game = PhoneGame()
        for (player, prefix) in [(Player.Identifier.a, "A"), (.b, "B")] {
            let deck = try (0..<20).map { try card("\(prefix)\($0)", type: "Basic Land — Island", player: player) }
            game.state[player: player].library.cards.accept(OrderedSet(deck))
            var layout = game.deckLayout ?? [:]
            layout[player.rawValue] = [Pile.Location.library.rawValue: deck.map(\.uuid)]
            game.deckLayout = layout
        }
        XCTAssertEqual(game.phaseButton(for: .a), .startGame)
        try game.apply(.startGame, player: .a)
        try game.apply(.keepHand, player: .a); try game.apply(.keepHand, player: .b)
        let first = try XCTUnwrap(game.turn?.player)
        let land = try XCTUnwrap(game.state[player: first].hand.cards.value.first)
        try game.apply(.play(land.uuid, face: nil, faceDown: false, tapped: false, directly: true), player: first)
        let discard = try XCTUnwrap(game.state[player: first].hand.cards.value.first)
        try game.apply(.moveToPlayer(discard.uuid, .graveyard, first, bottom: false), player: first)
        XCTAssertNotEqual(game.phaseButton(for: first), .startGame)
        try game.apply(.resetDecks, player: .a)
        XCTAssertEqual(game.phaseButton(for: .a), .startGame)
        XCTAssertEqual(game.phaseButton(for: .b), .startGame)
        // An unfinished JumpStart pick (the other player hasn't chosen) doesn't block it.
        game.packetSelection = .init(kind: "JumpStart", setCode: "J22")
        XCTAssertTrue(game.canStartGame)
    }

    func testPhaseButtonWalksThroughTheTurnAndPassesIt() throws {
        var game = PhoneGame()
        game.state.player1.library.cards.accept(OrderedSet(try (0..<20).map { try card("A\($0)", type: "Instant") }))
        game.state.player2.library.cards.accept(OrderedSet(try (0..<20).map { try card("B\($0)", type: "Instant", player: .b) }))
        XCTAssertEqual(game.phaseButton(for: .a), .startGame)
        try game.apply(.startGame, player: .a)
        let first = try XCTUnwrap(game.opening?.firstPlayer)
        let second: Player.Identifier = first == .a ? .b : .a
        XCTAssertEqual(game.phaseButton(for: first), .untapAndDraw)
        XCTAssertEqual(game.phaseButton(for: second), .opponentsTurn)
        // The first player skips their first draw.
        try game.apply(.untapAndDraw(draw: true), player: first)
        XCTAssertEqual(game.state[player: first].hand.cards.value.count, 7)
        XCTAssertEqual(game.phaseButton(for: first), .moveToCombat)
        try game.apply(.beginCombat, player: first)
        XCTAssertEqual(game.attackingPlayer, first)
        XCTAssertEqual(game.phaseButton(for: first), .endCombat)
        XCTAssertEqual(game.phaseButton(for: second), .opponentsCombat)
        try game.apply(.endCombat, player: first)
        XCTAssertNil(game.combat)
        XCTAssertEqual(game.phaseButton(for: first), .endTurn)
        try game.apply(.endTurn, player: first)
        XCTAssertEqual(game.phaseButton(for: first), .opponentsTurn)
        XCTAssertEqual(game.phaseButton(for: second), .untapAndDraw)
        try game.apply(.untapAndDraw(draw: true), player: second)
        XCTAssertEqual(game.state[player: second].hand.cards.value.count, 8)
        try game.apply(.untapAndDraw(draw: false), player: second) // drawing can be turned off
        XCTAssertEqual(game.state[player: second].hand.cards.value.count, 8)
    }

    func testAttackingFromTheMenuMovesTheTurnToCombat() throws {
        var game = PhoneGame()
        let bear = try card("Grizzly Bears", type: "Creature — Bear")
        game.state.battlefield.accept([bear])
        try game.apply(.untapAndDraw(draw: false), player: .a)
        try game.apply(.attack(bear.uuid, tap: true), player: .a)
        XCTAssertEqual(game.turn?.phase, .combat)
        XCTAssertEqual(game.phaseButton(for: .a), .endCombat)
        try game.apply(.endCombat, player: .a)
        XCTAssertEqual(game.phaseButton(for: .a), .endTurn)
    }

    func testArrangeLibraryTopPutsCardsOnTopInOrder() throws {
        var game = PhoneGame()
        let cards = try (0..<5).map { try card("Card \($0)", type: "Instant") }
        game.state.player1.library.cards.accept(OrderedSet(cards)) // Card 4 is on top
        try game.apply(.arrangeLibraryTop([cards[1].uuid, cards[4].uuid]), player: .a)
        XCTAssertEqual(game.state.player1.library.cards.value.contents.reversed().map(\.representation.name),
                       ["Card 1", "Card 4", "Card 3", "Card 2", "Card 0"])
    }

    func testCastableCardsShowTheirAlternateCost() throws {
        let flashback = try card("Dreams", type: "Instant", keywords: ["Flashback"], oracleText: "Surveil 1, then draw a card.\nFlashback {3}{U} (You may cast this card from your graveyard for its flashback cost. Then exile it.)")
        XCTAssertEqual(PhoneGame.alternateCastCost(for: flashback), "{3}{U}")
        XCTAssertEqual(PhoneHandCardFace.handCost(for: flashback, inCommandZone: false, castableElsewhere: true), "{3}{U}")
        let escape = try card("Escapee", type: "Creature — Cat", keywords: ["Escape"], oracleText: "Escape—{3}{B}{B}, Exile four other cards from your graveyard.")
        XCTAssertEqual(PhoneGame.alternateCastCost(for: escape), "{3}{B}{B}")
        let retrace = try card("Retracer", type: "Sorcery", keywords: ["Retrace"], oracleText: "Retrace (You may cast this card from your graveyard by discarding a land card in addition to paying its other costs.)")
        XCTAssertNil(PhoneGame.alternateCastCost(for: retrace), "Retrace pays the normal cost")
    }

    func testCopiedStackSpellsVanishOrEnterAsTokens() throws {
        var game = PhoneGame()
        let bolt = try card("Bolt", type: "Instant")
        let bear = try card("Bear", type: "Creature — Bear")
        game.state.player1.hand.cards.accept([bolt, bear])
        try game.apply(.castTargeting(bear.uuid, nil), player: .a)
        try game.apply(.copyStackItem(game.stack[0].id), player: .a)
        XCTAssertEqual(game.stack.count, 2)
        try game.apply(.resolve(game.stack[1].id), player: .a)
        XCTAssertEqual(game.state.battlefield.value.count, 1)
        XCTAssertTrue(game.state.battlefield.value.first?.representation.isToken == true, "A copied permanent spell enters as a token")
        try game.apply(.resolve(game.stack[0].id), player: .a)
        try game.apply(.castTargeting(bolt.uuid, .player(.b)), player: .a)
        try game.apply(.copyStackItem(game.stack[0].id), player: .a)
        XCTAssertEqual(game.stack[1].targets, [.player(.b)], "A copy keeps the targets")
        try game.apply(.resolve(game.stack[1].id), player: .a)
        XCTAssertTrue(game.state.player1.graveyard.cards.value.isEmpty, "A copied instant ceases to exist")
        try game.apply(.resolve(game.stack[0].id), player: .a)
        XCTAssertEqual(game.state.player1.graveyard.cards.value.count, 1)
    }

    func testCompanionInSideboardIsListedBesideHand() throws {
        var game = PhoneGame()
        let companion = try card("Lurrus", type: "Legendary Creature — Cat Nightmare", keywords: ["Companion"])
        game.state.player1.sideboard.cards.accept([companion])
        XCTAssertFalse(game.castableCards(for: .a).contains(companion))
        try game.apply(.markCompanion(companion.uuid, true), player: .a)
        XCTAssertTrue(game.castableCards(for: .a).contains(companion))
        try game.apply(.play(companion.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        XCTAssertTrue(game.state.battlefield.value.contains(companion), "A companion can be played straight from the sideboard")
    }

    func testTopCardRevealedToChosenPlayers() throws {
        var game = PhoneGame()
        try game.apply(.revealTopCard(.a, [.b]), player: .a)
        XCTAssertEqual(game.revealedTops?["a"], ["b"])
        try game.apply(.revealTopCard(.a, []), player: .a)
        XCTAssertNil(game.revealedTops?["a"])
        try game.apply(.revealTopCard(.b, [.a, .b]), player: .a)
        try game.apply(.resetDecks, player: .a)
        XCTAssertNil(game.revealedTops, "Nothing stays revealed after a reset")
    }

    func testForetellAndPlotExileCardsCastableLater() throws {
        var game = PhoneGame()
        let foretold = try card("Doomskar", type: "Sorcery")
        let plotted = try card("Outlaw", type: "Creature — Human")
        game.state.player1.hand.cards.accept([foretold, plotted])
        try game.apply(.playCard(.init(cardInstanceID: foretold.uuid, mode: .foretell)), player: .a)
        try game.apply(.playCard(.init(cardInstanceID: plotted.uuid, mode: .plot)), player: .a)
        XCTAssertTrue(game.state.battlefield.value.isEmpty, "Neither goes to the battlefield")
        XCTAssertEqual(game.state.player1.exile.cards.value.count, 2)
        XCTAssertTrue(foretold.representation.isFaceDown, "Foretold cards are exiled face down")
        XCTAssertFalse(plotted.representation.isFaceDown, "Plotted cards are exiled face up")
        XCTAssertTrue(game.castableCards(for: .a).contains(foretold))
        XCTAssertTrue(game.castableCards(for: .a).contains(plotted))
    }

    func testResolvedAdventureGoesToExileCastable() throws {
        var game = PhoneGame()
        let knight = try card("Bonecrusher Giant", type: "Creature — Giant // Instant — Adventure", layout: "adventure",
                              faces: [["name": "Bonecrusher Giant", "typeLine": "Creature — Giant", "oracleText": "", "power": "4", "toughness": "3"],
                                      ["name": "Stomp", "typeLine": "Instant — Adventure", "oracleText": "Stomp deals 2 damage to any target."]])
        let adventure = try XCTUnwrap(knight.representation.card.cardFaces?[1])
        knight.representation = .alternateFace(knight.representation.card, adventure)
        game.stack.append(.init(card: knight, text: "Stomp", player: .a))
        try game.apply(.resolve(game.stack[0].id), player: .a)
        XCTAssertTrue(game.state.player1.exile.cards.value.contains(knight), "On an adventure in exile")
        XCTAssertFalse(game.state.player1.graveyard.cards.value.contains(knight))
        XCTAssertEqual(knight.representation.name, "Bonecrusher Giant", "Castable later as the creature")
        XCTAssertTrue(game.castableCards(for: .a).contains(knight))
    }

    func testTaplandsEnterTappedFromHand() throws {
        var game = PhoneGame()
        let taplandID = try XCTUnwrap(OfflineGameLibrary.shared.bundledOracleTags["tapland"]?.first, "Bundled tapland list")
        let gate = try card("Azorius Guildgate", type: "Land — Gate", oracleID: taplandID)
        let island = try card("Island", type: "Basic Land — Island")
        game.state.player1.hand.cards.accept([gate, island])
        try game.apply(.play(gate.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        try game.apply(.play(island.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        XCTAssertTrue(gate.isTapped.value, "A tapland enters tapped")
        XCTAssertFalse(island.isTapped.value)
    }

    func testCloakAndDisguiseShowAMysteriousCreature() throws {
        var game = PhoneGame()
        let cloaked = try card("Hidden", type: "Creature — Elf")
        game.state.player1.hand.cards.accept([cloaked])
        try game.apply(.playCard(.init(cardInstanceID: cloaked.uuid, mode: .cloak)), player: .a)
        XCTAssertTrue(game.state.battlefield.value.contains(cloaked))
        guard case .mysterious = cloaked.representation else { return XCTFail("Cloaked cards are A Mysterious Creature") }
        XCTAssertTrue(cloaked.representation.isFaceDown)
    }

    func testStackCardDraggedToAZoneLeavesTheStackWithoutResolving() throws {
        var game = PhoneGame()
        let spell = try card("Bounce", type: "Instant", oracleText: "")
        game.state.player1.hand.cards.accept([spell])
        try game.apply(.castTargeting(spell.uuid, nil), player: .a)
        try game.apply(.moveToPlayer(spell.uuid, .hand, .a, bottom: false), player: .a)
        XCTAssertTrue(game.stack.isEmpty)
        XCTAssertTrue(game.state.player1.hand.cards.value.contains(spell))
        try game.apply(.castTargeting(spell.uuid, nil), player: .a)
        try game.apply(.moveToPlayer(spell.uuid, .exile, .a, bottom: false), player: .a)
        XCTAssertTrue(game.stack.isEmpty)
        XCTAssertTrue(game.state.player1.exile.cards.value.contains(spell))
    }

    @MainActor func testPhonePilePreviewsIgnoreImagePixelSizeAndOverlayCounts() {
        var previewSizes: [CGSize] = []
        for (title, pixels) in [("Graveyard", CGSize(width: 146, height: 204)), ("Library", CGSize(width: 745, height: 1040)), ("Exile", CGSize(width: 488, height: 680))] {
            let pile = HUDCardPileView(frame: CGRect(x: 0, y: 0, width: 80, height: 64))
            pile.titleLabel.text = title
            pile.titleLabel.font = .systemFont(ofSize: 10)
            pile.numberLabel.text = "33"
            pile.numberLabel.font = .systemFont(ofSize: 14)
            pile.topCardImageView.image = UIGraphicsImageRenderer(size: pixels).image { UIColor.black.setFill(); $0.fill(CGRect(origin: .zero, size: pixels)) }
            pile.configurePhoneLayout(previewHeight: 32, scale: 1)
            pile.layoutIfNeeded()
            pile.contentView.layoutIfNeeded()
            previewSizes.append(pile.topCardImageView.bounds.size)
            XCTAssertTrue(pile.topCardImageView.frame.contains(pile.numberLabel.frame))
            XCTAssertGreaterThan(pile.topCardImageView.frame.minY, 0)
            XCTAssertLessThan(pile.titleLabel.frame.maxY, pile.bounds.height)
        }
        XCTAssertEqual(previewSizes[0], previewSizes[1])
        XCTAssertEqual(previewSizes[1], previewSizes[2])
    }

    @MainActor func testObservableBridgeDoesNotEchoModelChangesOrLoseRapidEdits() {
        let relay = BehaviorRelay(value: 20)
        let bridge = ObservableBridge(relay)
        var emitted: [Int] = []
        let subscription = relay.subscribe(onNext: { emitted.append($0) })
        defer { subscription.dispose() }
        relay.accept(21)
        XCTAssertEqual(emitted, [20, 21])
        XCTAssertEqual(bridge.value, 21)
        for _ in 0..<10 { bridge.value += 1 }
        XCTAssertEqual(relay.value, 31)
        XCTAssertEqual(emitted, Array(20...31))
    }

    func testPendingGuestLifeEditsSurviveEarlierHostSnapshot() throws {
        let host = PhoneGame()
        host.state.player2.life.accept(20)
        let client = try JSONDecoder().decode(PhoneGame.self, from: JSONEncoder().encode(host))
        client.state.player2.life.accept(22)
        let patch = try PhoneStatePatch(before: host, after: client.state)
        let request = PhoneGameSession.Request(gameID: host.id, action: .edit(patch))
        host.state.player2.life.accept(21)
        let packet = PhoneGameSession.Packet.snapshot(host, acknowledged: [UUID()])
        let decoded = try JSONDecoder().decode(PhoneGameSession.Packet.self, from: JSONEncoder().encode(packet))
        guard case .snapshot(let snapshot, let acknowledged) = decoded else { return XCTFail("Expected snapshot") }
        XCTAssertFalse(acknowledged.contains(request.id))
        let displayed = PhoneGameSession.displaySnapshot(snapshot, pending: [request])
        XCTAssertEqual(displayed.state.player2.life.value, 22)
        XCTAssertEqual(displayed.state.player1.life.value, host.state.player1.life.value)
    }

    func testSpellsUseLIFOStackAndResolveToCorrectZones() throws {
        var game = PhoneGame()
        let creature = try card("First spell", type: "Instant")
        let spell = try card("Response", type: "Instant", player: .b)
        game.state.player1.hand.cards.accept([creature])
        game.state.player2.hand.cards.accept([spell])
        try game.apply(.play(creature.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        try game.apply(.play(spell.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .b)
        XCTAssertEqual(game.stack.count, 2)
        let first = game.stack[0].id
        try game.apply(.resolve(first), player: .a)
        XCTAssertEqual(game.stack.count, 2, "Cannot resolve underneath the top item")
        try game.apply(.resolve(game.stack.last!.id), player: .b)
        XCTAssertTrue(game.state.player2.graveyard.cards.value.contains(spell))
        try game.apply(.resolve(first), player: .a)
        XCTAssertTrue(game.state.player1.graveyard.cards.value.contains(creature))
        XCTAssertTrue(game.stack.isEmpty)
    }

    func testLandBypassesStackAndOpponentCannotPlayPrivateHand() throws {
        var game = PhoneGame()
        let land = try card("Island", type: "Basic Land — Island")
        game.state.player1.hand.cards.accept([land])
        try game.apply(.play(land.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .b)
        XCTAssertTrue(game.state.player1.hand.cards.value.contains(land))
        try game.apply(.play(land.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        XCTAssertTrue(game.stack.isEmpty)
        XCTAssertTrue(game.state.battlefield.value.contains(land))
    }

    func testSharedLibraryAndGraveyardForDandan() throws {
        var game = PhoneGame()
        game.sharedDeck = true
        let fish = try card("Dandân", type: "Creature — Fish")
        game.state.player1.library.cards.accept([fish])
        try game.apply(.draw, player: .b)
        XCTAssertTrue(game.state.player2.hand.cards.value.contains(fish))
        XCTAssertEqual(fish.ownerIdentifier, .b)
        XCTAssertTrue(game.library(.a).cards.value.isEmpty)
        try game.apply(.move(fish.uuid, .graveyard, bottom: false), player: .b)
        XCTAssertTrue(game.graveyard(.a).cards.value.contains(fish))
        XCTAssertEqual(game.graveyard(.a), game.graveyard(.b))
    }

    func testAttachmentsRejectCyclesAndDetachOnZoneChange() throws {
        var game = PhoneGame()
        let bearer = try card("Bearer", type: "Creature")
        let equipment = try card("Equipment", type: "Artifact — Equipment")
        game.state.battlefield.accept([bearer, equipment])
        try game.apply(.attach(equipment.uuid, bearer.uuid), player: .a)
        try game.apply(.attach(bearer.uuid, equipment.uuid), player: .a)
        XCTAssertNil(game.attachments[bearer.uuid])
        try game.apply(.move(bearer.uuid, .graveyard, bottom: false), player: .a)
        XCTAssertNil(game.attachments[equipment.uuid])
        XCTAssertTrue(game.state.battlefield.value.contains(equipment))
    }

    func testGroupingSeparatesModifiedTappedAndAttachedCards() throws {
        var game = PhoneGame()
        let first = try card("Island", type: "Basic Land — Island")
        let second = CardInstance(card: first.representation, center: nil, ownerIdentifier: .a)
        game.state.battlefield.accept([first, second])
        XCTAssertEqual(PhoneBattlefieldLayout.groups(in: game, player: .a, row: .support).count, 1)
        second.isTapped.accept(true)
        XCTAssertEqual(PhoneBattlefieldLayout.groups(in: game, player: .a, row: .support).count, 2)
        XCTAssertEqual(PhoneBattlefieldLayout.groups(in: game, player: .a, row: .support, ignoringTapped: true).count, 1)
        second.isTapped.accept(false)
        first.counters.accept([.gray])
        XCTAssertEqual(PhoneBattlefieldLayout.groups(in: game, player: .a, row: .support).count, 2)
        first.counters.accept([])
        game.attachments[second.uuid] = first.uuid
        XCTAssertFalse(PhoneBattlefieldLayout.canGroup(first, with: second, game: game))
    }

    /// A HUD band measured before a size change (fold/unfold) must never put the collapsed hand off-screen.
    func testCollapsedHandStaysOnScreenWithStaleHUDBand() {
        // Band from a wider screen, entirely right of the current 500-pt container.
        let center = PhoneHandFanView.compactCenter(width: 500, compactWidth: 200, band: 700...1100)
        XCTAssertGreaterThanOrEqual(center - 100, 0)
        XCTAssertLessThanOrEqual(center + 100, 500)
        let left = PhoneHandFanView.compactCenter(width: 500, compactWidth: 200, band: -900 ... -300)
        XCTAssertGreaterThanOrEqual(left - 100, 0)
        // A band that fits keeps the hand centered.
        XCTAssertEqual(PhoneHandFanView.compactCenter(width: 500, compactWidth: 200, band: 40...460), 250)
    }

    func testAttackTapsUnlessVigilantAndOnlyOnePlayerAttacks() throws {
        var game = PhoneGame()
        let bear = try card("Grizzly Bears", type: "Creature — Bear")
        let knight = try card("Knight", type: "Creature — Knight", keywords: ["Vigilance"])
        let enemy = try card("Enemy", type: "Creature — Bear", player: .b)
        for c in [bear, knight] { c.controllerIdentifier.accept(.a) }
        enemy.controllerIdentifier.accept(.b)
        game.state.battlefield.accept([bear, knight, enemy])
        XCTAssertFalse(bear.hasVigilance)
        XCTAssertTrue(knight.hasVigilance)
        try game.apply(.attack(bear.uuid, tap: !bear.hasVigilance), player: .a)
        try game.apply(.attack(knight.uuid, tap: !knight.hasVigilance), player: .a)
        XCTAssertEqual(game.attackingPlayer, .a)
        XCTAssertTrue(bear.isTapped.value)
        XCTAssertFalse(knight.isTapped.value)
        // The defender can't start attacking mid-combat, but can block.
        try game.apply(.attack(enemy.uuid, tap: true), player: .b)
        XCTAssertFalse(game.combat!.attackers.contains(enemy.uuid))
        try game.apply(.block(enemy.uuid, bear.uuid), player: .b)
        XCTAssertEqual(game.combat?.blockers[enemy.uuid], bear.uuid)
        // Leaving the attack untaps it again and drops its blockers.
        try game.apply(.attack(bear.uuid, tap: true), player: .a)
        XCTAssertFalse(bear.isTapped.value)
        XCTAssertNil(game.combat?.blockers[enemy.uuid])
        try game.apply(.endCombat, player: .a)
        XCTAssertNil(game.combat)
        XCTAssertNil(game.attackingPlayer)
    }

    func testVigilanceCounterAndMoveToStack() throws {
        var game = PhoneGame()
        let bear = try card("Grizzly Bears", type: "Creature — Bear")
        bear.counters.accept([.vigilance])
        XCTAssertTrue(bear.hasVigilance)
        game.state[player: .a].hand.cards.accept([bear])
        try game.apply(.moveToStack(bear.uuid), player: .a)
        XCTAssertTrue(game.state[player: .a].hand.cards.value.isEmpty)
        XCTAssertEqual(game.stack.last?.card?.uuid, bear.uuid)
        try game.apply(.resolve(game.stack.last!.id), player: .a)
        XCTAssertTrue(game.state.battlefield.value.contains(bear))
        XCTAssertTrue(game.stack.isEmpty)
    }

    func testTokenCopiesOfTokensGroupWithTheToken() throws {
        var game = PhoneGame()
        let zombie = try card("Zombie", type: "Token Creature — Zombie", token: true)
        let copy = CardInstance(card: CardRepresentation.tokenCopy(zombie.representation), center: nil, ownerIdentifier: .a)
        let copyOfCopy = CardInstance(card: CardRepresentation.tokenCopy(.tokenCopy(zombie.representation)), center: nil, ownerIdentifier: .a)
        game.state.battlefield.accept([zombie, copy, copyOfCopy])
        XCTAssertTrue(PhoneBattlefieldLayout.canGroup(copy, with: zombie, game: game))
        XCTAssertTrue(PhoneBattlefieldLayout.canGroup(copyOfCopy, with: zombie, game: game))
        zombie.markedDamage.accept(1)
        XCTAssertFalse(PhoneBattlefieldLayout.canGroup(copy, with: zombie, game: game), "Marked damage changes the visible toughness and must separate tokens")
        copy.markedDamage.accept(1)
        XCTAssertTrue(PhoneBattlefieldLayout.canGroup(copy, with: zombie, game: game))
        zombie.markedDamage.accept(0)
        copy.markedDamage.accept(0)
        XCTAssertTrue(PhoneBattlefieldLayout.canGroup(copy, with: zombie, game: game), "Clearing damage restores visual equivalence")
        // A token copy of a nontoken card is still distinct from that card.
        let bears = try card("Grizzly Bears", type: "Creature — Bear")
        let bearsCopy = CardInstance(card: CardRepresentation.tokenCopy(bears.representation), center: nil, ownerIdentifier: .a)
        XCTAssertNotEqual(bearsCopy.representation.canonicalToken, bears.representation.canonicalToken)
    }

    func testDropAttachmentMovesFromHandAndPreventsCycles() throws {
        var game = PhoneGame()
        let bearer = try card("Bearer", type: "Creature")
        let aura = try card("Aura", type: "Enchantment — Aura")
        let equipment = try card("Equipment", type: "Artifact — Equipment")
        game.state.battlefield.accept([bearer, equipment])
        game.state.player1.hand.cards.accept([aura])
        try game.apply(.attachDroppedCard(aura.uuid, bearer.uuid), player: .a)
        XCTAssertTrue(game.state.player1.hand.cards.value.isEmpty)
        XCTAssertTrue(game.state.battlefield.value.contains(aura))
        XCTAssertEqual(game.attachments[aura.uuid], bearer.uuid)
        XCTAssertTrue(game.stack.isEmpty)
        try game.apply(.attachDroppedCard(equipment.uuid, aura.uuid), player: .a)
        XCTAssertEqual(game.attachedCards(to: bearer.uuid).map(\.uuid), [aura.uuid, equipment.uuid])
        try game.apply(.attachDroppedCard(bearer.uuid, equipment.uuid), player: .a)
        XCTAssertNil(game.attachments[bearer.uuid])
        XCTAssertEqual(game.attachments[equipment.uuid], aura.uuid)
        try game.apply(.attach(aura.uuid, nil), player: .a)
        XCTAssertNil(game.attachments[aura.uuid])
    }

    func testSnapshotRoundTripRetainsStackAttachmentsAndCardIdentity() throws {
        var game = PhoneGame()
        let card = try card("Bear", type: "Creature")
        game.stack = [.init(card: card, text: "Bear", player: .a)]
        let bearer = try self.card("Bearer", type: "Creature")
        let aura = try self.card("Aura", type: "Enchantment — Aura")
        game.state.battlefield.accept([bearer, aura])
        game.attachments[aura.uuid] = bearer.uuid
        game.combat = .init(attackers: [bearer.uuid], blockers: [:])
        game.sharedDeck = true
        let restored = try JSONDecoder().decode(PhoneGame.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(restored.id, game.id)
        XCTAssertEqual(restored.stack.first?.card?.uuid, card.uuid)
        XCTAssertNotNil(restored.cards[card.uuid])
        XCTAssertEqual(restored.attachments[aura.uuid], bearer.uuid)
        XCTAssertTrue(restored.combat?.attackers.contains(bearer.uuid) == true)
        XCTAssertTrue(restored.sharedDeck)
    }

    func testTokenDisappearsAndUntapRespectsStun() throws {
        var game = PhoneGame()
        let token = try card("Soldier", type: "Token Creature — Soldier", token: true)
        game.state.battlefield.accept([token])
        token.isTapped.accept(true); token.counters.accept([.stun])
        try game.apply(.untap, player: .a)
        XCTAssertTrue(token.isTapped.value)
        XCTAssertTrue(token.counters.value.isEmpty)
        try game.apply(.untap, player: .a)
        XCTAssertFalse(token.isTapped.value)
        try game.apply(.move(token.uuid, .hand, bottom: false), player: .a)
        XCTAssertNil(game.cards[token.uuid])
    }

    func testManualCombatTracksBlocksAndCleansUpRemovedAttackers() throws {
        var game = PhoneGame()
        let attacker = try card("Attacker", type: "Creature")
        let blocker = try card("Blocker", type: "Creature", player: .b)
        game.state.battlefield.accept([attacker, blocker])
        try game.apply(.attack(attacker.uuid, tap: true), player: .a)
        XCTAssertTrue(attacker.isTapped.value)
        XCTAssertTrue(game.combat?.attackers.contains(attacker.uuid) == true)
        try game.apply(.block(blocker.uuid, attacker.uuid), player: .b)
        XCTAssertEqual(game.combat?.blockers[blocker.uuid], attacker.uuid)
        try game.apply(.move(attacker.uuid, .graveyard, bottom: false), player: .a)
        XCTAssertTrue(game.combat?.attackers.isEmpty == true)
        XCTAssertNil(game.combat?.blockers[blocker.uuid])
        try game.apply(.endCombat, player: .b)
        XCTAssertNil(game.combat)
    }
    func testExistingViewObjectsSurviveRemoteSnapshot() throws {
        let previousSave = GameState.sessionSave
        GameState.sessionSave = { _ in }
        defer { GameState.sessionSave = previousSave }
        let state = GameState()
        let original = try card("Bear", type: "Creature")
        state.player1.hand.cards.accept([original])
        let remote = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
        remote.player1.hand.cards.value.first?.isTapped.accept(true)
        remote.player1.hand.cards.value.first?.counters.accept([.plusOnePlusOne])
        state.update(withValuesFrom: remote)
        XCTAssertTrue(state.player1.hand.cards.value.first === original)
        XCTAssertTrue(original.isTapped.value)
        XCTAssertEqual(original.counters.value, [.plusOnePlusOne])
    }

    func testGuestCreatedTokenReachesHostWithoutScreenCoordinates() throws {
        var host = PhoneGame()
        let client = try JSONDecoder().decode(PhoneGame.self, from: JSONEncoder().encode(host))
        let token = try card("Soldier", type: "Token Creature — Soldier", player: .b, token: true)
        XCTAssertNil(token.center.value)
        client.state.battlefield.mutate { $0.append(token) }
        let patch = try PhoneStatePatch(before: host, after: client.state)
        let decoded = try JSONDecoder().decode(PhoneStatePatch.self, from: JSONEncoder().encode(patch))
        host.state.player1.life.accept(18)
        try host.apply(.edit(decoded), player: .b)
        let created = try XCTUnwrap(host.state.battlefield.value.first { $0.uuid == token.uuid })
        XCTAssertTrue(created.representation.isToken)
        XCTAssertEqual(created.controllerIdentifier.value, .b)
        XCTAssertNil(created.center.value)
        XCTAssertEqual(host.state.player1.life.value, 18)
    }

    func testExistingControlPatchPreservesAnotherPlayersUnrelatedEdit() throws {
        var host = PhoneGame()
        let permanent = try card("Bear", type: "Creature")
        host.state.battlefield.accept([permanent])
        let baseline = try JSONDecoder().decode(PhoneGame.self, from: JSONEncoder().encode(host))
        let client = try JSONDecoder().decode(PhoneGame.self, from: JSONEncoder().encode(host))
        client.state.battlefield.value.first?.isTapped.accept(true)
        let patch = try PhoneStatePatch(before: baseline, after: client.state)
        permanent.power.accept("5")
        try host.apply(.edit(patch), player: .a)
        XCTAssertTrue(permanent.isTapped.value)
        XCTAssertEqual(permanent.power.value, "5")
    }

    func testExistingPileControlsMoveAndResetThroughPatch() throws {
        var host = PhoneGame()
        let permanent = try card("Bear", type: "Creature")
        host.state.battlefield.accept([permanent])
        permanent.counters.accept([.plusOnePlusOne])
        let before = try JSONDecoder().decode(PhoneGame.self, from: JSONEncoder().encode(host))
        var edited = try JSONDecoder().decode(PhoneGame.self, from: JSONEncoder().encode(host))
        try edited.apply(.move(permanent.uuid, .graveyard, bottom: false), player: .a)
        let patch = try PhoneStatePatch(before: before, after: edited.state)
        try host.apply(.edit(patch), player: .a)
        XCTAssertTrue(host.state.battlefield.value.isEmpty)
        XCTAssertTrue(host.state.player1.graveyard.cards.value.first === permanent)
        XCTAssertTrue(permanent.counters.value.isEmpty)
    }

    func testPhoneScaleStartsLargeAndStopsShrinkingOnCrowdedBoards() {
        let sparse = PhoneBattlefieldLayout.cardExtent(screenWidth: 651, screenHeight: 375, groups: 2)
        let crowded = PhoneBattlefieldLayout.cardExtent(screenWidth: 400, screenHeight: 375, groups: 20)
        XCTAssertGreaterThan(sparse, crowded)
        XCTAssertGreaterThanOrEqual(sparse, 72)
        XCTAssertGreaterThanOrEqual(crowded, 64)
    }

    @MainActor func testNearbyPickerUsesPublishedSnapshotAndHandlesRemovedRows() {
        let session = PhoneGameSession()
        let picker = NearbyGamePickerController(session: session)
        picker.loadViewIfNeeded()
        let peer = MCPeerID(displayName: "Nearby phone")
        let row = IndexPath(row: 0, section: 0)

        // Simulate willSet publication: the new peers are emitted while the
        // session's stored array is still empty.
        picker.display(peers: [peer], status: "Looking for nearby games…")
        XCTAssertTrue(session.nearby.isEmpty)
        XCTAssertEqual(picker.tableView(picker.tableView, numberOfRowsInSection: 0), 1)
        XCTAssertEqual(picker.tableView(picker.tableView, cellForRowAt: row).textLabel?.text, "Nearby phone")
        picker.tableView(picker.tableView, didSelectRowAt: row)
        XCTAssertEqual(session.status, "", "Do not invite a peer that has already disappeared")

        picker.display(peers: [], status: "Looking for nearby games…")
        XCTAssertEqual(picker.tableView(picker.tableView, numberOfRowsInSection: 0), 0)
        XCTAssertNil(picker.tableView(picker.tableView, cellForRowAt: row).textLabel?.text)
        picker.tableView(picker.tableView, didSelectRowAt: row)
    }

    func testSharedPlayChoicesPreserveMultiFaceAndSpecialModes() throws {
        let faces: [[String: Any]] = [
            ["name": "Front", "typeLine": "Creature — Wizard", "manaCost": "{U}", "oracleText": "", "power": "1", "toughness": "1"],
            ["name": "Back", "typeLine": "Land", "manaCost": "", "oracleText": "{T}: Add {U}."]
        ]
        let modal = try card("Front // Back", type: "Creature // Land", layout: "modal_dfc", faces: faces)
        let choices = Command.PlayCardParameters.options(for: modal, tapped: true)
        XCTAssertEqual(choices.map { $0.parameters.faceIndex }, [0, 1])
        XCTAssertTrue(choices.allSatisfy { $0.parameters.tapped })
        var game = PhoneGame()
        game.state.player1.hand.cards.accept([modal])
        try game.apply(.playCard(choices[1].parameters), player: .a)
        XCTAssertTrue(game.state.battlefield.value.contains(modal))
        XCTAssertTrue(modal.representation.isLand)
        XCTAssertTrue(modal.isTapped.value)
        XCTAssertEqual(modal.representation.name, "Back")
        let adventure = try card("Adventure", type: "Creature", layout: "adventure", faces: faces)
        XCTAssertEqual(Command.PlayCardParameters.options(for: adventure).map { $0.parameters.faceIndex }, [1, 0])
        let transform = try card("Transform", type: "Creature", layout: "transform", faces: faces)
        XCTAssertEqual(Command.PlayCardParameters.options(for: transform).map { $0.parameters.faceIndex }, [0])
        let fuse = try card("Fuse", type: "Instant", layout: "split", faces: faces, keywords: ["Fuse"])
        XCTAssertEqual(Command.PlayCardParameters.options(for: fuse).map { $0.parameters.faceIndex }, [0, 1, nil])
        let morph = try card("Morph", type: "Creature", keywords: ["Morph"])
        XCTAssertEqual(Command.PlayCardParameters.options(for: morph).last?.parameters.mode, .morph)
    }

    func testOnlyInstantsAndSorceriesUseStackForPlayCommands() throws {
        var game = PhoneGame()
        for type in ["Land", "Creature", "Artifact — Equipment", "Enchantment — Aura", "Planeswalker", "Battle — Siege", "Instant", "Sorcery"] {
            let instance = try card(type, type: type)
            game.state.player1.hand.cards.mutate { $0.append(instance) }
            let option = try XCTUnwrap(Command.PlayCardParameters.options(for: instance).first)
            try game.apply(.playCard(option.parameters), player: .a)
            let usesStack = type == "Instant" || type == "Sorcery"
            XCTAssertEqual(game.stack.contains { $0.card?.uuid == instance.uuid }, usesStack, type)
            XCTAssertEqual(game.state.battlefield.value.contains(instance), !usesStack, type)
        }
    }

    func testCreaturesEnterBattlefieldAndStackSpellsCannotTap() throws {
        var game = PhoneGame()
        let creature = try card("Bear", type: "Creature — Bear")
        let spell = try card("Spell", type: "Instant")
        game.state.player1.hand.cards.accept([creature, spell])
        try game.apply(.play(creature.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: .a)
        XCTAssertTrue(game.state.battlefield.value.contains(creature))
        XCTAssertTrue(game.stack.isEmpty)
        try game.apply(.play(spell.uuid, face: nil, faceDown: false, tapped: true, directly: false), player: .a)
        try game.apply(.tap(spell.uuid), player: .a)
        XCTAssertFalse(spell.isTapped.value)
        XCTAssertEqual(game.stack.count, 1)
    }
    @MainActor func testSharedLibraryDrawControlUsesLocalPlayer() {
        let oldRole = AppDelegate.shared.role
        let oldDraw = GameState.sessionDraw
        defer { AppDelegate.shared.role = oldRole; GameState.sessionDraw = oldDraw }
        AppDelegate.shared.role = .boardPlayer2
        var recipient: Player.Identifier?
        GameState.sessionDraw = { player, _, _ in recipient = player }
        PileViewController().draw(count: 1)
        XCTAssertEqual(recipient, .b)
    }
    func testBundledGamesHaveOfflineCardDataAndArtwork() throws {
        let library = OfflineGameLibrary.shared
        XCTAssertGreaterThan(library.games.count, 100)
        for game in library.games {
            XCTAssertFalse(game.entries.isEmpty, game.name)
            for entry in game.entries {
                let card = try XCTUnwrap(library.card(forKey: entry.key), entry.key)
                XCTAssertEqual(library.catalogArtworkCount(for: card), 2, card.name ?? entry.key)
            }
        }
        // Artwork is downloaded at runtime: one Scryfall source per file, matching its kind.
        let sources = library.artworkSources
        XCTAssertGreaterThan(sources.count, 10_000)
        XCTAssertEqual(Set(sources.map(\.file)).count, sources.count)
        for source in sources {
            XCTAssertEqual(source.url.host, "cards.scryfall.io", source.file)
            XCTAssertEqual(source.url.pathComponents.dropFirst().first, source.file.contains("-art_crop-") ? "art_crop" : "normal", source.file)
        }
        let dandan = try XCTUnwrap(library.games.first { $0.kind == "DanDân" })
        XCTAssertEqual(dandan.entries.reduce(0) { $0 + $1.count }, 80)
    }
    func testCardsGrowOnLargerScreensAndShrinkBeforePaging() {
        let phone = PhoneBattlefieldLayout.cardExtent(screenWidth: 720, screenHeight: 375, groups: 2)
        let tablet = PhoneBattlefieldLayout.cardExtent(screenWidth: 1100, screenHeight: 800, groups: 2)
        let dense = PhoneBattlefieldLayout.cardExtent(screenWidth: 1100, screenHeight: 800, groups: 10)
        XCTAssertGreaterThan(tablet, phone * 1.7)
        XCTAssertLessThan(dense, tablet)
        XCTAssertGreaterThan(dense, 100)
    }

    func testOfflineJumpInPairsBuildFortyCardDecks() throws {
        let library = OfflineGameLibrary.shared
        XCTAssertFalse(library.jumpInSets.isEmpty)
        for set in library.jumpInSets {
            let choices = library.jumpInPackets(set: set, first: nil)
            XCTAssertGreaterThanOrEqual(choices.count, 2)
            for first in choices {
                for second in library.jumpInPackets(set: set, first: first) {
                    let deck = try XCTUnwrap(library.jumpInDeck(set: set, first: first, second: second))
                    XCTAssertEqual(DeckParser.parse(deckList: deck, autofix: true).flatMap(\.cardCounts).reduce(0) { $0 + $1.count }, 40)
                }
            }
        }
    }

    func testJumpInBasicArtsUsePacketSetsAndBalancedPrintings() throws {
        let library = OfflineGameLibrary.shared
        let names = ["Plains", "Island", "Swamp", "Mountain", "Forest"]
        func verify(_ list: String, sets: Set<String>) throws {
            var counts: [String: [String: Int]] = [:]
            for entry in DeckParser.parse(deckList: list, autofix: true).flatMap(\.cardCounts) {
                let card = try XCTUnwrap(library.card(for: entry.identifier))
                guard let name = card.name, names.contains(name) else { continue }
                XCTAssertTrue(sets.contains(card.set.uppercased()))
                let arts = library.jumpInBasicPrintings(set: card.set, name: name)
                XCTAssertTrue(arts.contains { $0.scryfallID == card.scryfallID }, "Wrong printing for \(card.set) \(name)")
                counts[card.set.uppercased() + ":" + name, default: [:]][card.collectorNumber, default: 0] += entry.count
            }
            for (group, quantities) in counts {
                let parts = group.components(separatedBy: ":")
                let numbers = library.jumpInBasicPrintings(set: parts[0], name: parts[1]).map { quantities[$0.collectorNumber, default: 0] }
                XCTAssertLessThanOrEqual((numbers.max() ?? 0) - (numbers.min() ?? 0), 1, group)
            }
        }
        for code in library.jumpInSets {
            for name in names { XCTAssertFalse(library.jumpInBasicPrintings(set: code, name: name).isEmpty) }
            let packets = library.jumpInPacketPool.filter { $0.setCode == code }
            let deck = try XCTUnwrap(library.jumpInDeck(set: code, first: packets[0].name, second: packets[1].name))
            try verify(deck, sets: [code])
        }
        XCTAssertTrue(library.jumpInBasicPrintings(set: "BLB", name: "Island").allSatisfy { !$0.isFullArt })
        XCTAssertTrue(library.jumpInBasicPrintings(set: "FIN", name: "Island").allSatisfy(\.isFullArt))
        let mixed = try XCTUnwrap(library.jumpInDeck(set: "ALL", first: "ECL · BLIGHTED", second: "FIN · ARTIFACTS"))
        try verify(mixed, sets: ["ECL", "FIN"])
    }

    func testJumpInDualsUseTheSetsCommonLandsBeforeDMU() throws {
        let library = OfflineGameLibrary.shared
        func packet(_ set: String, _ colors: Set<String>) throws -> OfflineGameLibrary.JumpInPacket {
            try XCTUnwrap(library.jumpInPacketPool.first { $0.setCode == set && Set($0.colors) == colors }, "\(set) \(colors)")
        }
        // Final Fantasy: its towns.
        let fin = [try packet("FIN", ["W"]), try packet("FIN", ["U"])]
        XCTAssertEqual(library.jumpInDual(for: ["W", "U"], sets: fin)?.name, "Sharlayan, Nation of Scholars")
        // Bloomburrow has no common duals of its own: Dominaria United's.
        let blb = [try packet("BLB", ["W"]), try packet("BLB", ["U"])]
        XCTAssertEqual(library.jumpInDual(for: ["W", "U"], sets: blb)?.name, "Idyllic Beachfront")
        // A partial cycle uses the set's land where it has one, DMU's elsewhere.
        let sos = [try packet("SOS", ["U"]), try packet("SOS", ["G"])]
        XCTAssertEqual(library.jumpInDual(for: ["U", "G"], sets: sos)?.name, "Paradox Gardens")
        XCTAssertEqual(library.jumpInDual(for: ["W", "U"], sets: sos)?.name, "Idyllic Beachfront")
        // Cross-set: the packet sharing the pair's colors decides.
        XCTAssertEqual(library.jumpInDual(for: ["U", "G"], sets: [try packet("FIN", ["W"]), try packet("TDM", ["G"])])?.name, "Thornwood Falls")

        // A whole two-color Final Fantasy deck contains its town and no DMU dual.
        let deck = try XCTUnwrap(library.jumpInDeck(set: "FIN", first: fin[0].name, second: fin[1].name))
        let cards = try DeckParser.parse(deckList: deck, autofix: true).flatMap(\.cardCounts).map { try XCTUnwrap(library.card(for: $0.identifier)) }
        XCTAssertTrue(cards.contains { $0.name == "Sharlayan, Nation of Scholars" && $0.set.uppercased() == "FIN" })
        XCTAssertFalse(cards.contains { $0.set.uppercased() == "DMU" })
    }

    func testPreloadedDandanDealsToBothPlayersWithoutDatabaseLookup() throws {
        var game = PhoneGame()
        try game.apply(.dandan, player: .a)
        XCTAssertEqual(game.library(.a).cards.value.count, 80)
        try game.apply(.draw, player: .a)
        try game.apply(.draw, player: .b)
        XCTAssertEqual(game.state.player1.hand.cards.value.count, 1)
        XCTAssertEqual(game.state.player2.hand.cards.value.count, 1)
        XCTAssertEqual(game.state.player2.hand.cards.value.first?.ownerIdentifier, .b)
        XCTAssertEqual(game.library(.b).cards.value.count, 78)
    }

    func testResetDecksReturnsLoadedDeckResetsLifeAndDeletesTokens() throws {
        var game = PhoneGame()
        try game.apply(.dandan, player: .a)
        try game.apply(.drawCards(7, opening: true), player: .a)
        try game.apply(.draw, player: .b)
        let played = try XCTUnwrap(game.state.player1.hand.cards.value.first)
        try game.apply(.moveToPlayer(played.uuid, .graveyard, .a, bottom: false), player: .a)
        let token = CardInstance(card: played.representation, center: nil, ownerIdentifier: .a)
        token.representation = .tokenCopy(played.representation)
        game.state.battlefield.mutate { $0.append(token) }
        game.state.player1.life.accept(7)
        game.state.player2.life.accept(3)

        try game.apply(.resetDecks, player: .a)

        XCTAssertEqual(game.library(.a).cards.value.count, 80)
        XCTAssertTrue(game.state.player1.hand.cards.value.isEmpty)
        XCTAssertTrue(game.state.player2.hand.cards.value.isEmpty)
        XCTAssertTrue(game.graveyard(.a).cards.value.isEmpty)
        XCTAssertFalse(game.cards.keys.contains(token.uuid))
        XCTAssertEqual(game.state.player1.life.value, 20)
        XCTAssertEqual(game.state.player2.life.value, 20)
    }

    func testJumpStartBasicLandPrintingsFollowSetPolicy() throws {
        let library = OfflineGameLibrary.shared
        let basics: Set<String> = ["Plains", "Island", "Swamp", "Mountain", "Forest"]
        let specific = ["J22": "j22", "MSH": "msh", "TLA": "tla", "SJM": "thb"]
        for packet in library.games where packet.kind == "JumpStart" {
            for entry in packet.entries {
                let card = try XCTUnwrap(library.card(forKey: entry.key))
                guard let name = card.name, basics.contains(name) else { continue }
                XCTAssertEqual(card.set.lowercased(), specific[packet.setCode ?? ""] ?? "fdn", packet.name + ": " + entry.key)
            }
        }
    }

    func testDandanMatchesSecretLairDeckAndPrintings() throws {
        let library = OfflineGameLibrary.shared
        let deck = try XCTUnwrap(library.games.first { $0.kind == "DanDân" })
        var quantities: [String: Int] = [:]
        for entry in deck.entries {
            let card = try XCTUnwrap(library.card(forKey: entry.key))
            XCTAssertEqual(card.set.lowercased(), "sld")
            quantities[card.collectorNumber, default: 0] += entry.count
        }
        var expected = Dictionary(uniqueKeysWithValues: (2138...2164).map { (String($0), 2) })
        for number in [2138, 2139, 2144, 2145, 2146, 2147] { expected[String(number)] = 5 }
        expected["2140"] = 4
        expected["2142"] = 8
        XCTAssertEqual(quantities, expected)
        XCTAssertEqual(quantities.values.reduce(0, +), 80)
        let parsed = DeckParser.parse(deckList: try CardService.shared.getDandanDecklist(), autofix: true)
        XCTAssertEqual(parsed.flatMap(\.cardCounts).reduce(0) { $0 + $1.count }, 80)
    }

    func testEveryBundledJumpStartPacketHasTwentyCards() {
        for game in OfflineGameLibrary.shared.games where game.kind == "JumpStart" {
            XCTAssertEqual(game.entries.reduce(0) { $0 + $1.count }, 20, game.name)
        }
    }

    func testMarvelJumpStartIncludesEveryOfficialPacket() {
        let packets = OfflineGameLibrary.shared.games.filter { $0.kind == "JumpStart" && $0.setCode == "MSH" }
        XCTAssertEqual(packets.count, 51)
        for packet in packets {
            XCTAssertEqual(packet.entries.reduce(0) { $0 + $1.count }, 20, packet.name)
        }
    }

    func testAllJumpStartSetsAndDynamicOffers() {
        let library = OfflineGameLibrary.shared
        for (set, count) in [("JMP",121),("J22",121),("J25",121),("TLA",66),("MSH",51),("SJM",75)] {
            XCTAssertEqual(library.games.filter { $0.kind == "JumpStart" && $0.setCode == set }.count, count)
            var seen = Set<String>()
            for _ in 0..<20 {
                let offers = library.jumpStartOffers(set: set)
                XCTAssertEqual(Set(offers).count, 3)
                seen.formUnion(offers)
            }
            XCTAssertGreaterThan(seen.count, 3)
        }
        XCTAssertEqual(library.jumpInPacketPool.count,133)
        for set in library.jumpInSets {
            let seen = Set((0..<20).flatMap { _ in library.jumpInPackets(set: set, first: nil) })
            XCTAssertGreaterThan(seen.count,3,set)
        }
    }

    func testAllSetsJumpInOffersAndCrossSetDecks() throws {
        let library = OfflineGameLibrary.shared
        XCTAssertEqual(library.jumpInSetOptions.first, "ALL")
        var seenSets = Set<String>()
        for _ in 0..<50 {
            let offers = library.jumpInPackets(set: "ALL", first: nil)
            XCTAssertEqual(Set(offers).count, 3)
            for first in offers {
                let packet = try XCTUnwrap(library.jumpInPacket(set: "ALL", choice: first))
                seenSets.insert(packet.setCode)
                let seconds = library.jumpInPackets(set: "ALL", first: first)
                XCTAssertEqual(Set(seconds).count, 3)
                XCTAssertFalse(seconds.contains(first))
            }
        }
        XCTAssertGreaterThan(seenSets.count, 1)
        // These names occur in multiple sets: each printing must resolve separately.
        for set in ["DFT", "FIN", "EOE"] {
            XCTAssertEqual(library.jumpInPacket(set: "ALL", choice: set + " · ARTIFACTS")?.setCode, set)
        }
        XCTAssertNotNil(library.jumpInDeck(set: "ALL", first: "DFT · ARTIFACTS", second: "FIN · ARTIFACTS"))
        let first = try XCTUnwrap(library.jumpInPacketPool.first)
        let second = try XCTUnwrap(library.jumpInPacketPool.first { $0.setCode != first.setCode })
        let list = try XCTUnwrap(library.jumpInDeck(set: "ALL", first: first.setCode + " · " + first.name, second: second.setCode + " · " + second.name))
        var game = PhoneGame()
        try game.apply(.load(list, name: "Mixed Jump In"), player: .a)
        XCTAssertEqual(game.library(.a).cards.value.count, 40)
        try game.apply(.startPackets(kind: "Jump In", set: "ALL"), player: .b)
        let selection = try XCTUnwrap(game.packetSelection)
        for player in [Player.Identifier.a, .b] {
            let first = try XCTUnwrap(game.packetSelection?.offers[player.rawValue]?.first)
            try game.apply(.choosePacket(selection.id, first), player: player)
            let second = try XCTUnwrap(game.packetSelection?.offers[player.rawValue]?.first)
            try game.apply(.choosePacket(selection.id, second), player: player)
            XCTAssertEqual(game.library(player).cards.value.count, 40)
        }
        XCTAssertNil(game.packetSelection)
    }

    func testPacketSelectionStartsForBothPlayersAndPreservesOffersAcrossSnapshots() throws {
        var game = PhoneGame()
        try game.apply(.startPackets(kind: "JumpStart",set: "J22"),player: .b)
        let initial = try XCTUnwrap(game.packetSelection)
        XCTAssertEqual(initial.offers["a"]?.count,3)
        XCTAssertEqual(initial.offers["b"]?.count,3)
        for player in [Player.Identifier.a,.b] {
            let first = try XCTUnwrap(game.packetSelection?.offers[player.rawValue]?.first)
            try game.apply(.choosePacket(initial.id,first),player: player)
            let snapshot = try JSONDecoder().decode(PhoneGame.self,from: JSONEncoder().encode(game))
            XCTAssertEqual(snapshot.packetSelection?.offers,game.packetSelection?.offers)
            let second = try XCTUnwrap(game.packetSelection?.offers[player.rawValue]?.first)
            try game.apply(.choosePacket(initial.id,second),player: player)
            XCTAssertEqual(game.library(player).cards.value.count,40)
        }
        XCTAssertNil(game.packetSelection)
    }

    func testResetClearsCompletedPacketSelectionAndAllowsAnotherDeck() throws {
        var game = PhoneGame()
        let id = game.id
        try game.apply(.startPackets(kind: "JumpStart", set: "J22"), player: .a)
        let selection = try XCTUnwrap(game.packetSelection)
        for _ in 0..<2 {
            let choice = try XCTUnwrap(game.packetSelection?.offers["a"]?.first)
            try game.apply(.choosePacket(selection.id, choice), player: .a)
        }
        XCTAssertTrue(game.packetSelection?.completed.contains("a") == true)
        try game.apply(.reset, player: .a)
        XCTAssertNil(game.packetSelection)
        XCTAssertTrue(game.cards.isEmpty)
        XCTAssertTrue(game.deckNames.isEmpty)
        XCTAssertNotEqual(game.id, id)
        try game.apply(.startPackets(kind: "JumpStart", set: "J25"), player: .a)
        XCTAssertNotEqual(game.packetSelection?.id, selection.id)
        XCTAssertFalse(game.packetSelection?.offers["a"]?.isEmpty ?? true)
    }

    func testNewJumpInSetsHaveCompleteOfflinePacketsAndBuildDecks() throws {
        let library = OfflineGameLibrary.shared
        for set in ["EOE", "ECL", "SOS"] {
            XCTAssertTrue(library.jumpInSets.contains(set))
            let packets = library.jumpInPacketPool.filter { $0.setCode == set }
            XCTAssertEqual(packets.count,10,set)
            for packet in packets {
                let second = try XCTUnwrap(library.jumpInPackets(set:set,first:packet.name).first)
                let list = try XCTUnwrap(library.jumpInDeck(set:set,first:packet.name,second:second),packet.name)
                var game = PhoneGame()
                try game.apply(.load(list,name:packet.name),player:.a)
                XCTAssertEqual(game.library(.a).cards.value.count,40,packet.name)
                for slot in packet.randomSlots {
                    XCTAssertEqual(slot.reduce(0) { $0 + $1.probability },100,accuracy:0.05)
                }
            }
        }
    }

}
