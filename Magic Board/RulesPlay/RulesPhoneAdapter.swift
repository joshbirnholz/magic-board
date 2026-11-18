import Foundation
import Combine
import CardService

/// Maps engine snapshots into the Phone Play presentation and routes its gestures to engine answers.
/// PhoneGame is a display projection here; its sandbox reducer is never used.
@MainActor
final class RulesPhoneAdapter {
    let engine: RulesGameSession
    private weak var phone: PhoneGameSession?
    private var subscriptions: Set<AnyCancellable> = []
    private var projectionTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private let catalog = RulesCardCatalog.shared
    private var pendingTarget: PhoneGame.Target?
    private var hiddenIDs: [String: UUID] = [:]
    private(set) var presentation = PhoneGame()

    init(engine: RulesGameSession) { self.engine = engine }

    func attach(to phone: PhoneGameSession) {
        self.phone = phone
        engine.$snapshot.sink { [weak self] snapshot in
            guard let self, let snapshot else { return }
            self.projectionTask?.cancel()
            self.projectionTask = Task { [weak self] in
                guard let self else { return }
                do { try await self.project(snapshot) }
                catch is CancellationError { }
                catch { self.phone?.error = "Unable to display the rules game: \(error.localizedDescription)" }
            }
        }.store(in: &subscriptions)
        Publishers.CombineLatest3(engine.$status, engine.$prompt, engine.$pendingRequest)
            .sink { [weak self] status, prompt, pending in
                guard let self else { return }
                self.updateStatus(status, prompt: prompt, pending: pending)
            }.store(in: &subscriptions)
        engine.$error.compactMap { $0 }.sink { [weak phone] in phone?.error = $0 }.store(in: &subscriptions)
    }

    private func updateStatus(_ status: RulesGameSession.Status, prompt: RulesPrompt?, pending: String?) {
        let label: String
        if pending != nil { label = "Sending…" }
        else if prompt?.method == "GAME_SELECT" { label = "Next" }
        else if prompt != nil { label = "Choose" }
        else { label = "Waiting" }
        phone?.displayRules(presentation, connected: status == .connected,
                            status: status == .connected ? "Connected to XMage" : "Rules server disconnected",
                            primaryLabel: label)
        if let target = pendingTarget, prompt?.method == "GAME_TARGET", pending == nil {
            let id: String?
            switch target {
            case .card(let card): id = card.uuidString.lowercased()
            case .player(let player): id = engine.snapshot?.players.first(where: { ($0.id == engine.snapshot?.playerId) == (player == .a) })?.id
            }
            pendingTarget = nil
            if let id, prompt?.targets?.contains(id) == true {
                Task { [weak self] in await self?.engine.answer(.object(id)) }
            }
        }
    }

    func send(_ action: PhoneAction) async {
        switch action {
        case .playCard(let parameters): await choose(parameters.cardInstanceID)
        case .play(let id, _, _, _, _), .moveToStack(let id), .tap(let id), .attack(let id, _): await choose(id)
        case .castTargeting(let id, let target):
            pendingTarget = target
            await choose(id)
        case .block(let id, let target):
            pendingTarget = target.map(PhoneGame.Target.card)
            await choose(id)
        case .resolve, .untap, .untapAndDraw, .beginCombat, .endCombat, .endTurn:
            if engine.prompt?.method == "GAME_SELECT" { await engine.answer(.boolean(true)) }
            else { phone?.error = "Complete the current rules choice first." }
        case .keepHand: await engine.answer(.boolean(false))
        case .mulligan: await engine.answer(.boolean(true))
        case .reorderHand(let ids):
            let hand = presentation.state.player1.hand.cards.value.contents
            presentation.state.player1.hand.cards.accept(OrderedSet(ids.compactMap { id in hand.first { $0.uuid == id } } + hand.filter { !ids.contains($0.uuid) }))
            refresh()
        case .inspect: break
        default:
            phone?.error = "XMage controls this action in Rules mode. Use the current game prompt."
            refresh()
        }
    }

    func send(_ command: Command) async {
        switch command {
        case .moveCardsToBattlefield(let cards):
            if let card = cards.first { await send(.playCard(card)) }
        case .reorderHand(let order): await send(.reorderHand(order.cardInstanceIDs))
        case .rebroadcast: refresh()
        default: phone?.error = "XMage controls card zones in Rules mode."
        }
    }

    private func choose(_ id: UUID) async {
        guard engine.canAnswer else { return }
        if engine.prompt?.method == "GAME_SELECT", let snapshot = engine.snapshot,
           !snapshot.playableIds.contains(id.uuidString.lowercased()),
           !(snapshot.step ?? "").contains("ATTACK") && !(snapshot.step ?? "").contains("BLOCK") {
            phone?.error = "That card has no legal action right now."
            return
        }
        await engine.answer(.object(id.uuidString.lowercased()))
    }

    func leave() async {
        projectionTask?.cancel()
        artworkTask?.cancel()
        subscriptions.removeAll()
        await engine.endSession()
    }

    private func refresh() {
        phone?.displayRules(presentation, connected: engine.status == .connected,
                            status: engine.notice, primaryLabel: engine.prompt?.method == "GAME_SELECT" ? "Next" : "Choose")
    }

    func project(_ snapshot: RulesSnapshot, refreshArtwork: Bool = true) async throws {
        var game = PhoneGame()
        game.id = UUID(uuidString: snapshot.gameId) ?? presentation.id
        game.revision = snapshot.revision
        func seat(_ id: String) -> Player.Identifier { id == snapshot.playerId ? .a : .b }
        var allCards = snapshot.hand + snapshot.stack
        for player in snapshot.players { allCards += player.battlefield + player.graveyard + player.exile }
        var models: [String: MTGCard] = [:]
        for card in allCards {
            try Task.checkCancellation()
            if let model = await catalog.localCard(card) { models[card.id] = model }
        }
        try Task.checkCancellation()
        let centers = phone?.game.cards.mapValues { $0.center.value } ?? [:]
        func instance(_ card: RulesCard, owner: Player.Identifier, battlefield: Bool = false) throws -> CardInstance {
            let printed = try models[card.id] ?? Self.placeholder(name: card.name ?? "Unknown card", typeLine: card.typeLine ?? "", rules: card.rules, manaCost: card.manaCost)
            let model = try battlefield ? RulesCardCharacteristics.applying(card, to: printed) : printed
            var representation = CardRepresentation.card(model).choosingFrontFace
            if card.transformed, let back = model.cardFaces?.last { representation = .alternateFace(model, back) }
            if card.faceDown { representation = .faceDown(representation) }
            let template = CardInstance(card: representation, center: nil, ownerIdentifier: owner)
            // Preserve engine object identity without changing the shared CardInstance initializer.
            var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as! [String: Any]
            encoded["uuid"] = card.id
            let result = try JSONDecoder().decode(CardInstance.self, from: JSONSerialization.data(withJSONObject: encoded))
            result.center.accept(centers[result.uuid] ?? nil)
            result.isTapped.accept(card.tapped ?? false)
            result.isSummoningSick.accept(card.summoningSick ?? false)
            if let colors = card.colors { result.colors.accept(colors.compactMap(MTGColor.init(rawValue:))) }
            if let power = card.power { result.power.accept(power) }
            if let toughness = card.toughness { result.toughness.accept(toughness) }
            result.isPowerToughnessVisible.accept(card.power != nil || card.toughness != nil)
            let counterTypes: [String: Counter] = ["+1/+1": .plusOnePlusOne, "-1/-1": .minusOneMinusOne,
                                                 "loyalty": .loyalty, "lore": .lore, "stun": .stun,
                                                 "shield": .shield, "flying": .flying, "finality": .finality]
            result.counters.accept(card.counters.flatMap { counter in
                counterTypes[counter.name.lowercased()].map { Array(repeating: $0, count: max(0, min(999, counter.count))) } ?? []
            })
            return result
        }
        for player in snapshot.players {
            let owner = seat(player.id)
            let projected = game.state[player: owner]
            projected.name.accept(owner == .a ? "You" : player.name)
            projected.life.accept(player.life)
            projected.isHidden = false
            projected.graveyard.cards.accept(OrderedSet(try player.graveyard.map { try instance($0, owner: owner) }))
            projected.exile.cards.accept(OrderedSet(try player.exile.map { try instance($0, owner: owner) }))
            let battlefield = try player.battlefield.map { try instance($0, owner: owner, battlefield: true) }
            game.state.battlefield.mutate { $0.formUnion(battlefield) }
            for card in player.battlefield {
                if let id = UUID(uuidString: card.id), let parent = card.attachedTo.flatMap(UUID.init(uuidString:)) { game.attachments[id] = parent }
            }
            projected.library.cards.accept(OrderedSet(try hiddenCards(player.libraryCount, key: player.id + ":library", owner: owner)))
            if owner == .b { projected.hand.cards.accept(OrderedSet(try hiddenCards(player.handCount, key: player.id + ":hand", owner: owner))) }
        }
        let hand = try snapshot.hand.map { try instance($0, owner: .a) }
        let oldOrder = presentation.state.player1.hand.cards.value.map(\.uuid)
        game.state.player1.hand.cards.accept(OrderedSet(oldOrder.compactMap { id in hand.first { $0.uuid == id } } + hand.filter { !oldOrder.contains($0.uuid) }))
        let visibleIDs = Set(allCards.map(\.id))
        game.stack = try snapshot.stack.reversed().map { card in
            let targets: [PhoneGame.Target] = (card.targets ?? []).compactMap { target in
                if snapshot.players.contains(where: { $0.id == target }) { return .player(seat(target)) }
                if visibleIDs.contains(target), let id = UUID(uuidString: target) { return .card(id) }
                return nil
            }
            let text = card.ability == true ? RulesText.plain(card.rules ?? card.name ?? "Ability") : card.name ?? "Spell"
            let controller = card.controllerId.map(seat) ?? snapshot.activePlayerId.map(seat) ?? .a
            return PhoneGame.StackItem(id: UUID(uuidString: card.id) ?? UUID(), card: card.ability == true ? nil : try instance(card, owner: controller), text: text, player: controller, targets: targets)
        }
        let active = snapshot.activePlayerId.map(seat) ?? snapshot.players.first { $0.name == snapshot.activePlayer }.map { seat($0.id) } ?? .a
        let enginePhase = snapshot.phase ?? ""
        let phase: PhoneGame.Turn.Phase = enginePhase.contains("COMBAT") ? .combat : enginePhase.contains("POST") ? .ending : .main
        game.turn = .init(player: active, phase: phase, number: snapshot.turn)
        if phase == .combat {
            var combat = PhoneGame.Combat(player: active)
            for group in snapshot.combat ?? [] {
                combat.attackers.formUnion(group.attackers.compactMap(UUID.init(uuidString:)))
                // Existing Phone Play supports one attacked creature per blocker.
                if group.attackers.count == 1, let attacker = group.attackers.first.flatMap(UUID.init(uuidString:)) {
                    for blocker in group.blockers.compactMap(UUID.init(uuidString:)) { combat.blockers[blocker] = attacker }
                }
            }
            game.combat = combat
        }
        try Task.checkCancellation()
        presentation = game
        refresh()
        if refreshArtwork {
            artworkTask?.cancel()
            let missing = allCards.filter { !$0.faceDown && models[$0.id] == nil }
            if !missing.isEmpty {
                artworkTask = Task { [weak self] in
                    guard let self else { return }
                    var loaded = false
                    for card in missing {
                        guard !Task.isCancelled else { return }
                        if await self.catalog.card(card) != nil { loaded = true }
                    }
                    guard loaded, !Task.isCancelled,
                          self.presentation.id == game.id, self.presentation.revision == snapshot.revision else { return }
                    try? await self.project(snapshot, refreshArtwork: false)
                }
            }
        }
    }

    private func hiddenCards(_ count: Int, key: String, owner: Player.Identifier) throws -> [CardInstance] {
        let model = try Self.placeholder(name: "Hidden card")
        return try (0..<max(0, min(2000, count))).map { index in
            let key = "\(key):\(index)"
            let id = hiddenIDs[key] ?? UUID()
            hiddenIDs[key] = id
            let card = CardInstance(card: .faceDown(.card(model)), center: nil, ownerIdentifier: owner)
            var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as! [String: Any]
            data["uuid"] = id.uuidString
            return try JSONDecoder().decode(CardInstance.self, from: JSONSerialization.data(withJSONObject: data))
        }
    }

    static func placeholder(name: String, typeLine: String = "", rules: String? = nil, manaCost: String? = nil) throws -> MTGCard {
        var json: [String: Any] = ["scryfallID": "00000000-0000-0000-0000-000000000001", "name": name,
                                  "layout": "normal", "typeLine": RulesText.plain(typeLine), "isFullArt": false,
                                  "collectorNumber": "0", "set": "tst", "rarity": "common", "frame": "2015",
                                  "isPromo": false, "isFoundInBoosters": false, "isFoilAvailable": false,
                                  "isNonFoilAvailable": true, "language": "en", "keywords": []]
        if let rules { json["oracleText"] = RulesText.plain(rules) }
        if let manaCost { json["manaCost"] = manaCost }
        return try JSONDecoder().decode(MTGCard.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

/// Preserve Scryfall image identity while supplying current engine text/types to battlefield properties.
enum RulesCardCharacteristics {
    static func applying(_ engine: RulesCard, to printed: MTGCard) throws -> MTGCard {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(printed)) as! [String: Any]
        func apply(to values: inout [String: Any]) {
            if let type = engine.typeLine { values["typeLine"] = RulesText.plain(type) }
            if let rules = engine.rules { values["oracleText"] = RulesText.plain(rules); values["keywords"] = [] }
            if let mana = engine.manaCost { values["manaCost"] = mana }
            if let colors = engine.colors { values["colors"] = colors }
        }
        apply(to: &json)
        if var faces = json["cardFaces"] as? [[String: Any]], !faces.isEmpty {
            let face = engine.transformed ? faces.count - 1 : 0
            apply(to: &faces[face])
            json["cardFaces"] = faces
        }
        return try JSONDecoder().decode(MTGCard.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

/// Keeps the existing synchronous card lookup off the UI actor, cached and serialized.
actor RulesCardCatalog {
    static let shared = RulesCardCatalog()
    private var cache: [String: MTGCard] = [:]
    private var failedKeys: Set<String> = []
    private var nextLookup = Date.distantPast
    private func key(_ card: RulesCard) -> String { "\(card.set ?? ""):\(card.collectorNumber ?? ""):\(card.name ?? "")" }
    func localCard(_ card: RulesCard) -> MTGCard? {
        guard !card.faceDown else { return nil }
        let key = key(card)
        if let model = cache[key] { return model }
        if let set = card.set, let number = card.collectorNumber,
           let local = CardService.shared.localCard(for: .collectorNumberSet(collectorNumber: number, set: set.lowercased(), name: card.name)) {
            cache[key] = local
            return local
        }
        return nil
    }
    func card(_ card: RulesCard) async -> MTGCard? {
        guard !card.faceDown else { return nil }
        if let local = localCard(card) { return local }
        let key = key(card)
        guard !failedKeys.contains(key) else { return nil }
        // Projection asks sequentially. Keep remote lookups below Scryfall's request limit.
        let delay = max(0, nextLookup.timeIntervalSinceNow)
        nextLookup = Date().addingTimeInterval(delay + 0.12)
        do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return nil }
        if let cached = cache[key] { return cached }
        guard !failedKeys.contains(key) else { return nil }
        var model: MTGCard?
        if let set = card.set, let number = card.collectorNumber { model = try? CardService.shared.getCard(code: set.lowercased(), number: number) }
        if model == nil, let name = card.name { model = try? CardService.shared.getCard(name: name) }
        if let model { cache[key] = model }
        else { failedKeys.insert(key) }
        return model
    }
}
