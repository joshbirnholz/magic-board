import Foundation
import CardService

/// Screen coordinates are intentionally absent: each device arranges its own view.
struct PhoneGame: Codable {
    struct StackItem: Codable, Identifiable {
        var id = UUID()
        var card: CardInstance?
        var text: String
        var player: Player.Identifier
    }

    var id = UUID()
    var revision = 0
    var state = GameState()
    var stack: [StackItem] = []
    var attachments: [UUID: UUID] = [:]
    struct Combat: Codable {
        var attackers: Set<UUID> = []
        /// Blocker → the attacker it blocks.
        var blockers: [UUID: UUID] = [:]
        /// The attacking player (whose untap button reads End Combat). Optional for older saves.
        var player: Player.Identifier?
    }

    /// The player attacking in the current combat, if any.
    var attackingPlayer: Player.Identifier? {
        guard let combat else { return nil }
        return combat.player ?? combat.attackers.lazy.compactMap { cards[$0]?.controllerIdentifier.value }.first
    }
    var combat: Combat?
    struct PacketSelection: Codable {
        var id = UUID()
        let kind: String
        let setCode: String
        var offers: [String: [String]] = [:]
        var firstChoices: [String: String] = [:]
        var completed: Set<String> = []
    }
    var packetSelection: PacketSelection?
    var sharedDeck = false
    var deckNames: [String: String] = [:]
    /// Each player's last loaded deck: location raw value → card IDs. Optional so older saves still decode.
    var deckLayout: [String: [String: [UUID]]]?

    var cards: [UUID: CardInstance] {
        var cards = state.cardsInZones
        for item in stack {
            if let card = item.card { cards[card.uuid] = card }
        }
        return cards
    }

    func library(_ player: Player.Identifier) -> Pile {
        state[player: sharedDeck ? .a : player].library
    }

    func graveyard(_ player: Player.Identifier) -> Pile {
        state[player: sharedDeck ? .a : player].graveyard
    }

    func pile(_ location: Pile.Location, player: Player.Identifier) -> Pile {
        if location == .library { return library(player) }
        if location == .graveyard { return graveyard(player) }
        return state[player: player][location]
    }

    mutating func remove(_ card: CardInstance) {
        state.battlefield.mutate { $0.remove(card) }
        for player in state.allPlayers {
            for pile in player.allPiles { pile.cards.mutate { $0.remove(card) } }
        }
        stack.removeAll { $0.card?.uuid == card.uuid }
        attachments[card.uuid] = nil
        attachments = attachments.filter { $0.value != card.uuid }
        combat?.attackers.remove(card.uuid)
        combat?.blockers[card.uuid] = nil
        let remainingBlocks = combat?.blockers.filter { $0.value != card.uuid } ?? [:]
        combat?.blockers = remainingBlocks
    }

    mutating func move(_ card: CardInstance, to location: Pile.Location, player: Player.Identifier, bottom: Bool = false) {
        remove(card)
        guard !card.representation.isToken else { return }
        card.reset(removingCounters: true)
        if sharedDeck && location == .hand {
            card.ownerIdentifier = player
            card.controllerIdentifier.accept(player)
        }
        let destination = pile(location, player: player)
        destination.cards.mutate {
            if bottom { $0.insert(card, at: 0) } else { $0.append(card) }
        }
    }

    mutating func apply(_ action: PhoneAction, player: Player.Identifier) throws {
        switch action {
        case .reset:
            // A new game ID discards queued edits and choices from the previous board.
            // The nearby connection itself remains active.
            self = PhoneGame()
        case .edit(let patch):
            patch.apply(to: &self)
        case .drawCards(let count, let opening):
            guard (1...20).contains(count) else { return }
            if opening {
                let hand = state[player: player].hand.cards.value.contents
                for card in hand { move(card, to: .library, player: player) }
                library(player).cards.mutate { $0 = OrderedSet($0.contents.shuffled()) }
            }
            for _ in 0..<count { try apply(.draw, player: player) }
        case .playCard(let configuration):
            guard let card = cards[configuration.cardInstanceID], canUse(card, player: player) else { return }
            switch configuration.mode {
            case .morph: card.representation = .morph(card.representation.card)
            case .manifest: card.representation = .manifest(card.representation.card)
            case .foretell: card.representation = .foretold(card.representation.card)
            case .prototype: card.representation = .prototyped(card.representation.card)
            case .default: break
            }
            if configuration.increaseTax { card.commanderCasts.mutate { $0 += 1 } }
            try apply(.play(card.uuid, face: configuration.faceIndex.flatMap { $0 >= 0 ? $0 : nil }, faceDown: (configuration.faceIndex ?? 0) < 0, tapped: configuration.tapped, directly: false), player: player)
        case .moveToPlayer(let id, let location, let destinationPlayer, let bottom):
            guard let card = cards[id], canUse(card, player: player) else { return }
            move(card, to: location, player: destinationPlayer, bottom: bottom)
        case .reorderHand(let ids):
            let hand = state[player: player].hand
            let ordered = ids.compactMap { id in hand.cards.value.first { $0.uuid == id } }
            hand.cards.accept(OrderedSet(ordered + hand.cards.value.filter { !ids.contains($0.uuid) }))
        case .reveal(let ids, let target, let reveal):
            for id in ids {
                guard let card = cards[id], canUse(card, player: player) else { continue }
                card.revealedPlayers.mutate { if reveal { $0.insert(target) } else { $0.remove(target) } }
            }
        case .draw:
            guard let card = library(player).cards.value.last else { return }
            remove(card)
            if sharedDeck { card.ownerIdentifier = player }
            card.controllerIdentifier.accept(player)
            state[player: player].hand.cards.mutate { $0.append(card) }
        case .life(let change):
            state[player: player].life.mutate { $0 += change }
        case .untap:
            for card in state.battlefield.value where card.controllerIdentifier.value == player {
                card.isSummoningSick.accept(false)
                if card.doesNotUntapNextTurn.value { card.doesNotUntapNextTurn.accept(false); continue }
                if card.doesNotUntapAutomatically.value { continue }
                if let index = card.counters.value.firstIndex(of: .stun) {
                    card.counters.mutate { $0.remove(at: index) }
                } else { card.isTapped.accept(false) }
            }
        case .shuffle:
            library(player).cards.mutate { $0 = OrderedSet($0.contents.shuffled()) }
        case .attack(let id, let tap):
            guard let card = state.battlefield.value.first(where: { $0.uuid == id }),
                  card.controllerIdentifier.value == player else { return }
            // Only one player attacks at a time; the defender can't declare attackers mid-combat.
            if let attacking = attackingPlayer, attacking != player { return }
            if combat == nil { combat = Combat() }
            combat?.player = player
            if combat?.attackers.contains(id) == true {
                combat?.attackers.remove(id)
                let remainingBlocks = combat?.blockers.filter { $0.value != id } ?? [:]
                combat?.blockers = remainingBlocks
                // `tap` means attacking taps it (no vigilance), so leaving the attack untaps it again.
                if tap { card.isTapped.accept(false) }
            } else {
                combat?.attackers.insert(id)
                combat?.blockers[id] = nil
                if tap { card.isTapped.accept(true) }
            }
        case .block(let id, let target):
            guard let card = state.battlefield.value.first(where: { $0.uuid == id }),
                  card.controllerIdentifier.value == player else { return }
            if let target {
                guard combat?.attackers.contains(target) == true, combat?.attackers.contains(id) != true,
                      cards[target]?.controllerIdentifier.value != player else { return }
            }
            combat?.blockers[id] = target
        case .endCombat:
            combat = nil
        case .play(let id, let face, let faceDown, let tapped, let directly):
            guard let card = cards[id], canUse(card, player: player) else { return }
            remove(card)
            if let face, let faces = card.representation.card.cardFaces, faces.indices.contains(face) {
                card.representation = .alternateFace(card.representation.card, faces[face])
            }
            if faceDown { card.representation = .faceDown(card.representation) }
            card.controllerIdentifier.accept(player)
            card.isTapped.accept(tapped)
            let type = card.representation.typeLine ?? ""
            let usesStack = type.contains("Instant") || type.contains("Sorcery")
            if directly || !usesStack || faceDown {
                state.battlefield.mutate { $0.append(card) }
            } else {
                card.isTapped.accept(false)
                stack.append(StackItem(card: card, text: card.representation.name ?? "Spell", player: player))
            }
        case .moveToStack(let id):
            // Cast a permanent spell (or anything else) onto the stack; it resolves onto the battlefield.
            guard let card = cards[id], canUse(card, player: player),
                  !stack.contains(where: { $0.card?.uuid == id }) else { return }
            remove(card)
            card.controllerIdentifier.accept(player)
            card.isTapped.accept(false)
            stack.append(StackItem(card: card, text: card.representation.name ?? "Spell", player: player))
        case .resolve(let id):
            guard let top = stack.last, top.id == id else { return }
            stack.removeLast()
            if let card = top.card {
                let type = card.representation.typeLine ?? ""
                if type.contains("Instant") || type.contains("Sorcery") {
                    move(card, to: .graveyard, player: card.ownerIdentifier)
                } else {
                    state.battlefield.mutate { $0.append(card) }
                }
            }
        case .counterStack(let id):
            guard let item = stack.first(where: { $0.id == id }) else { return }
            if let card = item.card { move(card, to: .graveyard, player: card.ownerIdentifier) }
            stack.removeAll { $0.id == id }
        case .tap(let id):
            guard let card = cards[id], state.battlefield.value.contains(card), card.controllerIdentifier.value == player else { return }
            card.isTapped.mutate { $0.toggle() }
        case .move(let id, let location, let bottom):
            guard let card = cards[id], canUse(card, player: player) else { return }
            let destinationPlayer = location == .hand ? player : card.ownerIdentifier
            move(card, to: location, player: destinationPlayer, bottom: bottom)
        case .counter(let id, let kind, let delta):
            guard let card = publicCard(id) else { return }
            if delta > 0 { card.counters.mutate { $0.append(kind) } }
            else if let index = card.counters.value.firstIndex(of: kind) { card.counters.mutate { $0.remove(at: index) } }
        case .stats(let id, let power, let toughness):
            guard let card = publicCard(id) else { return }
            card.power.accept(String(power.prefix(12)))
            card.toughness.accept(String(toughness.prefix(12)))
            card.isPowerToughnessVisible.accept(true)
        case .control(let id):
            guard let card = publicCard(id) else { return }
            card.controllerIdentifier.accept(card.controllerIdentifier.value == .a ? .b : .a)
        case .attachDroppedCard(let source, let target):
            guard let card = cards[source], canUse(card, player: player), source != target,
                  state.battlefield.value.contains(where: { $0.uuid == target }) else { return }
            var ancestor: UUID? = target
            while let node = ancestor {
                guard node != source else { return }
                ancestor = attachments[node]
            }
            if !state.battlefield.value.contains(card) {
                try apply(.play(source, face: nil, faceDown: false, tapped: false, directly: true), player: player)
            }
            try apply(.attach(source, target), player: player)
        case .attach(let source, let target):
            guard let sourceCard = state.battlefield.value.first(where: { $0.uuid == source }) else { return }
            if let target {
                guard source != target, state.battlefield.value.contains(where: { $0.uuid == target }) else { return }
                var ancestor: UUID? = target
                while let node = ancestor {
                    guard node != source else { return }
                    ancestor = attachments[node]
                }
                attachments[sourceCard.uuid] = target
            } else { attachments[source] = nil }
        case .flip(let id):
            guard let card = publicCard(id) else { return }
            switch card.representation {
            case .faceDown(let original): card.representation = original
            case .morph(let original), .manifest(let original), .foretold(let original): card.representation = .card(original)
            case .alternateFace(let original, _): card.representation = .card(original)
            default:
                if let back = card.representation.card.cardFaces?.dropFirst().first {
                    card.representation = .alternateFace(card.representation.card, back)
                } else { card.representation = .faceDown(card.representation) }
            }
        case .copy(let id):
            guard let card = publicCard(id) else { return }
            let token = CardInstance(card: CardRepresentation.tokenCopy(card.representation).canonicalToken, center: nil, ownerIdentifier: player)
            token.controllerIdentifier.accept(player)
            state.battlefield.mutate { $0.append(token) }
        case .token(let id):
            guard let card = CardService.shared.localCard(for: .id(id)) else {
                throw PhoneGameError.message("This token is missing from the offline database.")
            }
            let token = CardInstance(card: card, center: nil, ownerIdentifier: player)
            state.battlefield.mutate { $0.append(token) }
        case .startPackets(let kind, let set):
            guard packetSelection == nil else { return }
            let library = OfflineGameLibrary.shared
            var selection = PacketSelection(kind: kind, setCode: set)
            for player in [Player.Identifier.a, .b] {
                let offers = kind == "Jump In" ? library.jumpInPackets(set: set, first: nil) : library.jumpStartOffers(set: set)
                guard !offers.isEmpty else { throw PhoneGameError.message("No offline packets are available for this set.") }
                selection.offers[player.rawValue] = offers
            }
            if sharedDeck { self = PhoneGame() }
            packetSelection = selection
        case .choosePacket(let selectionID, let choice):
            guard var selection = packetSelection, selection.id == selectionID,
                  !selection.completed.contains(player.rawValue),
                  selection.offers[player.rawValue]?.contains(choice) == true else { return }
            let library = OfflineGameLibrary.shared
            if let first = selection.firstChoices[player.rawValue] {
                let deck = selection.kind == "Jump In" ? library.jumpInDeck(set: selection.setCode, first: first, second: choice) : library.jumpStartDeck(first: first, second: choice)
                guard let deck else { throw PhoneGameError.message("The selected packets could not be built from the offline catalog.") }
                try apply(.load(deck, name: first + " + " + choice), player: player)
                selection.completed.insert(player.rawValue)
                selection.offers[player.rawValue] = []
            } else {
                selection.firstChoices[player.rawValue] = choice
                selection.offers[player.rawValue] = selection.kind == "Jump In" ? library.jumpInPackets(set: selection.setCode, first: choice) : library.jumpStartOffers(set: selection.setCode, excluding: choice)
            }
            packetSelection = selection.completed.count == 2 ? nil : selection
        case .load(let list, let name):
            guard !sharedDeck else { throw PhoneGameError.message("Start a new game before replacing the shared DanDân deck.") }
            let loaded = try Self.load(list: list, owner: player)
            guard !loaded.isEmpty else { throw PhoneGameError.message("The deck list contains no cards.") }
            for card in Array(cards.values) where card.ownerIdentifier == player { remove(card) }
            for (location, instances) in loaded { state[player: player][location].cards.accept(OrderedSet(instances)) }
            library(player).cards.mutate { $0 = OrderedSet($0.contents.shuffled()) }
            state[player: player].life.accept(20)
            deckNames[player.rawValue] = name
            var layout = deckLayout ?? [:]
            layout[player.rawValue] = Dictionary(uniqueKeysWithValues: loaded.map { ($0.key.rawValue, $0.value.map(\.uuid)) })
            deckLayout = layout
        case .dandan:
            let list = try CardService.shared.getDandanDecklist()
            let loaded = try Self.load(list: list, owner: .a)
            self = PhoneGame()
            sharedDeck = true
            state.player1.library.cards.accept(OrderedSet((loaded[.library] ?? []).shuffled()))
            state.player1.life.accept(20); state.player2.life.accept(20)
            deckNames = ["a": "DanDân · shared deck", "b": "DanDân · shared deck"]
            deckLayout = ["a": [Pile.Location.library.rawValue: (loaded[.library] ?? []).map(\.uuid)]]
        case .resetDecks:
            resetDecksAndLife()
        }
    }

    /// Returns each player's last loaded deck to where it was loaded (library shuffled), resets every
    /// card's properties and both life totals, and deletes all tokens. Other cards stay where they are.
    mutating func resetDecksAndLife() {
        let all = cards
        stack.removeAll()
        combat = nil
        attachments = [:]
        packetSelection = nil
        for card in all.values where card.representation.isToken { remove(card) }
        for (playerRaw, layout) in deckLayout ?? [:] {
            guard let player = Player.Identifier(rawValue: playerRaw) else { continue }
            for (locationRaw, ids) in layout {
                guard let location = Pile.Location(rawValue: locationRaw) else { continue }
                for id in ids {
                    guard let card = all[id], !card.representation.isToken else { continue }
                    remove(card)
                    if card.ownerIdentifier != player { card.ownerIdentifier = player }
                    pile(location, player: player).cards.mutate { $0.append(card) }
                }
            }
        }
        for card in all.values where !card.representation.isToken {
            card.reset(removingCounters: true)
            card.commanderCasts.accept(0)
            card.revealedPlayers.accept([])
        }
        for player in [Player.Identifier.a, .b] {
            library(player).cards.mutate { $0 = OrderedSet($0.contents.shuffled()) }
            library(player).isTopCardRevealed.accept(false)
            state[player: player].life.accept(20)
        }
    }

    func attachedCards(to base: UUID) -> [CardInstance] {
        var result: [CardInstance] = []
        var visited: Set<UUID> = [base]
        func appendChildren(of parent: UUID) {
            for card in state.battlefield.value where attachments[card.uuid] == parent {
                guard visited.insert(card.uuid).inserted else { continue }
                result.append(card)
                appendChildren(of: card.uuid)
            }
        }
        appendChildren(of: base)
        return result
    }

    func canUse(_ card: CardInstance, player: Player.Identifier) -> Bool {
        publicCard(card.uuid) != nil || state[player: player].hand.cards.value.contains(card) ||
        state[player: player].commandZone.cards.value.contains(card) ||
        state[player: player].sideboard.cards.value.contains(card) || library(player).cards.value.contains(card)
    }

    func publicCard(_ id: UUID) -> CardInstance? {
        if let card = state.battlefield.value.first(where: { $0.uuid == id }) { return card }
        if let card = stack.compactMap(\.card).first(where: { $0.uuid == id }) { return card }
        for player in state.allPlayers {
            for pile in [player.graveyard, player.exile, player.commandZone] {
                if let card = pile.cards.value.first(where: { $0.uuid == id }) { return card }
            }
        }
        return nil
    }

    private static func load(list: String, owner: Player.Identifier) throws -> [Pile.Location: [CardInstance]] {
        var result: [Pile.Location: [CardInstance]] = [:]
        for group in DeckParser.parse(deckList: list, autofix: true) {
            let location: Pile.Location
            switch group.name {
            case "Sideboard": location = .sideboard
            case "Commander", "Companion": location = .command
            default: location = .library
            }
            for entry in group.cardCounts {
                guard (1...500).contains(entry.count) else { throw PhoneGameError.message("Invalid card quantity.") }
                guard let card = CardService.shared.localCard(for: entry.identifier) else {
                    throw PhoneGameError.message("A card is missing from the offline database: \(entry.identifier). Download the card database before going offline.")
                }
                for _ in 0..<entry.count {
                    result[location, default: []].append(CardInstance(card: card, center: nil, ownerIdentifier: owner))
                }
            }
        }
        return result
    }
}

extension CardInstance {
    /// Vigilance printed on the card or granted by a vigilance counter: attacking doesn't tap it.
    var hasVigilance: Bool {
        (representation.card.keywords ?? []).contains { $0.caseInsensitiveCompare("Vigilance") == .orderedSame }
            || counters.value.contains(.vigilance)
    }

    /// Whether it fights as a creature on the battlefield (shows power/toughness or is typed Creature).
    var isPhoneCreature: Bool {
        isPowerToughnessVisible.value || (representation.typeLine ?? "").contains("Creature")
    }
}

enum PhoneGameError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum PhoneAction: Codable {
    case draw, untap, shuffle, dandan, reset, resetDecks
    case startPackets(kind: String, set: String)
    case choosePacket(UUID, String)
    case edit(PhoneStatePatch)
    case drawCards(Int, opening: Bool)
    case playCard(Command.PlayCardParameters)
    case moveToPlayer(UUID, Pile.Location, Player.Identifier, bottom: Bool)
    case reorderHand([UUID])
    case reveal([UUID], Player.Identifier, Bool)
    case life(Int)
    case play(UUID, face: Int?, faceDown: Bool, tapped: Bool, directly: Bool)
    case resolve(UUID), counterStack(UUID), moveToStack(UUID)
    case tap(UUID), flip(UUID), control(UUID), copy(UUID), token(UUID)
    case move(UUID, Pile.Location, bottom: Bool)
    case counter(UUID, Counter, Int)
    case stats(UUID, String, String)
    case attach(UUID, UUID?)
    case attachDroppedCard(UUID, UUID)
    case load(String, name: String)
    case attack(UUID, tap: Bool), block(UUID, UUID?), endCombat
}

#if DEBUG
extension PhoneGame {
    static func boardFixture(crowded: Bool = false, bigHand: Bool = false, support: Bool = false, commander: Bool = false) throws -> PhoneGame {
        let fixtureImages: [String: [String: String]] = [
            "Island": ["small": "https://cards.scryfall.io/small/front/1/3/1335d293-3dd2-4f13-bd2c-22181f4528ee.jpg?1791578424", "normal": "https://cards.scryfall.io/normal/front/1/3/1335d293-3dd2-4f13-bd2c-22181f4528ee.jpg?1791578424", "art_crop": "https://cards.scryfall.io/art_crop/front/1/3/1335d293-3dd2-4f13-bd2c-22181f4528ee.jpg?1791578424"],
            "Grizzly Bears": ["small": "https://cards.scryfall.io/small/front/4/0/409f9b88-f03e-40b6-9883-68c14c37c0de.jpg?1783943001", "normal": "https://cards.scryfall.io/normal/front/4/0/409f9b88-f03e-40b6-9883-68c14c37c0de.jpg?1783943001", "art_crop": "https://cards.scryfall.io/art_crop/front/4/0/409f9b88-f03e-40b6-9883-68c14c37c0de.jpg?1783943001"],
            "Memory Lapse": ["small": "https://cards.scryfall.io/small/front/3/0/30202613-d05f-4f47-af97-d0b75ccac293.jpg?1783937610", "normal": "https://cards.scryfall.io/normal/front/3/0/30202613-d05f-4f47-af97-d0b75ccac293.jpg?1783937610", "art_crop": "https://cards.scryfall.io/art_crop/front/3/0/30202613-d05f-4f47-af97-d0b75ccac293.jpg?1783937610"],
            "Brainstorm": ["small": "https://cards.scryfall.io/small/front/1/e/1ede3080-8c47-48a0-b757-92c3fa91fac0.jpg?1793281332", "normal": "https://cards.scryfall.io/normal/front/1/e/1ede3080-8c47-48a0-b757-92c3fa91fac0.jpg?1793281332", "art_crop": "https://cards.scryfall.io/art_crop/front/1/e/1ede3080-8c47-48a0-b757-92c3fa91fac0.jpg?1793281332"],
            "Predict": ["small": "https://cards.scryfall.io/small/front/3/4/349ac7e6-af38-4dc3-abfe-369564c75630.jpg?1783934305", "normal": "https://cards.scryfall.io/normal/front/3/4/349ac7e6-af38-4dc3-abfe-369564c75630.jpg?1783934305", "art_crop": "https://cards.scryfall.io/art_crop/front/3/4/349ac7e6-af38-4dc3-abfe-369564c75630.jpg?1783934305"],
            "Dandân": ["small": "https://cards.scryfall.io/small/front/a/c/ac2e32d0-f172-4934-9d73-1bc2ab86586e.jpg?1783943282", "normal": "https://cards.scryfall.io/normal/front/a/c/ac2e32d0-f172-4934-9d73-1bc2ab86586e.jpg?1783943282", "art_crop": "https://cards.scryfall.io/art_crop/front/a/c/ac2e32d0-f172-4934-9d73-1bc2ab86586e.jpg?1783943282"],
            "Vision Charm": ["small": "https://cards.scryfall.io/small/front/7/8/78b384d3-3adf-493a-8b89-bfe68fd1c3e2.jpg?1783946996", "normal": "https://cards.scryfall.io/normal/front/7/8/78b384d3-3adf-493a-8b89-bfe68fd1c3e2.jpg?1783946996", "art_crop": "https://cards.scryfall.io/art_crop/front/7/8/78b384d3-3adf-493a-8b89-bfe68fd1c3e2.jpg?1783946996"],
            "Accumulated Knowledge": ["small": "https://cards.scryfall.io/small/front/a/d/ad88e5ee-0eee-47af-a7b4-9bac044e1c8c.jpg?1783935186", "normal": "https://cards.scryfall.io/normal/front/a/d/ad88e5ee-0eee-47af-a7b4-9bac044e1c8c.jpg?1783935186", "art_crop": "https://cards.scryfall.io/art_crop/front/a/d/ad88e5ee-0eee-47af-a7b4-9bac044e1c8c.jpg?1783935186"]
        ]
        func make(_ name: String, _ type: String, _ player: Player.Identifier, token: Bool = false) throws -> CardInstance {
            var json: [String: Any] = ["scryfallID": UUID().uuidString, "name": name, "typeLine": type,
                "layout": token ? "token" : "normal", "isFullArt": false, "collectorNumber": "1", "set": "tst",
                "rarity": "common", "frame": "2015", "isPromo": false, "isFoundInBoosters": true,
                "isFoilAvailable": false, "isNonFoilAvailable": true, "language": "en", "keywords": [],
                "borderColor": "black", "colors": ["U"], "manaCost": "{1}{U}", "oracleText": "Fixture card for verifying the original board renderer."]
            if var images = fixtureImages[name] {
                images["large"] = images["normal"]
                json["imageUris"] = images
            }
            let costs = ["Memory Lapse":"{1}{U}", "Brainstorm":"{U}", "Predict":"{1}{U}", "Dandân":"{U}{U}", "Vision Charm":"{U}", "Accumulated Knowledge":"{1}{U}"]
            if let cost = costs[name] { json["manaCost"] = cost }
            if type.contains("Creature") { json["power"] = "2"; json["toughness"] = "2" }
            let model = try JSONDecoder().decode(MTGCard.self, from: JSONSerialization.data(withJSONObject: json))
            return CardInstance(card: model, center: nil, ownerIdentifier: player)
        }
        var game = PhoneGame()
        game.state.player1.life.accept(20); game.state.player2.life.accept(20)
        for player in [Player.Identifier.a, .b] {
            let island = try make("Island", "Basic Land — Island", player)
            let bear = try make("Grizzly Bears", "Creature — Bear", player)
            let soldier = try make("Soldier", "Token Creature — Soldier", player, token: true)
            var field = [island, bear, soldier]
            if support { field.append(try make("Control Magic", "Enchantment — Aura", player)) }
            if crowded {
                for index in 1...10 { field.append(try make("Creature \(index)", "Creature", player)) }
            }
            for _ in 0..<4 { field.append(CardInstance(card: island.representation, center: nil, ownerIdentifier: player)) }
            for _ in 0..<3 { field.append(CardInstance(card: soldier.representation, center: nil, ownerIdentifier: player)) }
            let aura = try make("Feral Invocation", "Enchantment — Aura", player)
            field.append(aura); game.attachments[aura.uuid] = bear.uuid
            game.state.battlefield.mutate { $0.formUnion(field) }
            let names = ["Memory Lapse", "Brainstorm", "Island", "Predict", "Dandân", "Vision Charm", "Accumulated Knowledge"]
            let hand = try (bigHand ? names + names + ["Island"] : names).map {
                try make($0, $0 == "Island" ? "Basic Land — Island" : "Instant", player)
            }
            game.state[player: player].hand.cards.accept(OrderedSet(hand))
            if commander {
                let general = try make("Dandân", "Legendary Creature — Fish", player)
                general.isCommander.accept(true)
                general.commanderCasts.accept(1)
                game.state[player: player].commandZone.cards.accept(OrderedSet([general]))
            }
            game.state[player: player].library.cards.accept(OrderedSet(try (0..<15).map { _ in try make("Island", "Basic Land — Island", player) }))
        }
        let spell = try make("Memory Lapse", "Instant", .b)
        game.stack = [.init(card: spell, text: "Memory Lapse", player: .b)]
        return game
    }
}
#endif
