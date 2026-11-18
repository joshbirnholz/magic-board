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
    private var pendingTarget: PhoneGame.Target? { didSet { pendingTargetPromptID = pendingTarget == nil ? nil : engine.prompt?.id } }
    private var autoPassedPromptID: String?
    /// The prompt that was showing when the gesture chose its target (still showing until the engine moves on).
    private var pendingTargetPromptID: String?
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
        Publishers.CombineLatest4(engine.$status, engine.$prompt, engine.$pendingRequest, engine.$holdingPriority)
            .sink { [weak self] status, prompt, pending, holding in
                guard let self else { return }
                self.updateStatus(status, prompt: prompt, pending: pending, holdingPriority: holding)
            }.store(in: &subscriptions)
        engine.$error.compactMap { $0 }.sink { [weak phone] in phone?.error = $0 }.store(in: &subscriptions)
    }

    private func updateStatus(_ status: RulesGameSession.Status, prompt: RulesPrompt?, pending: String?, holdingPriority: Bool) {
        let (label, enabled) = Self.primaryButton(prompt: prompt, snapshot: engine.snapshot, pending: pending != nil)
        // Arena: while choosing targets, the legal targets glow instead of the playable cards.
        presentation.rulesPlayable = Self.highlighted(snapshot: engine.snapshot, prompt: pending == nil ? prompt : nil)
        phone?.displayRules(presentation, connected: status == .connected,
                            status: status == .connected ? "Connected to XMage" : "Rules server disconnected",
                            primaryLabel: label, primaryEnabled: enabled)
        if let prompt, pending == nil, prompt.id != autoPassedPromptID,
           Self.shouldAutoPass(prompt, snapshot: engine.snapshot, holdingPriority: holdingPriority), status == .connected, prompt.supported {
            autoPassedPromptID = prompt.id
            Task { [weak self] in await self?.engine.answer(.boolean(true)) }
        }
        // Arena pays mana for you: tap a fitting basic land for each payment prompt. Anything it
        // can't decide plainly (hybrid, X, non-basic lands) is left to the player to tap.
        // (Not engine.canAnswer: @Published sinks run before the property changes, so it would still
        // see the previous pending request here.)
        if Self.autoPaysMana, let prompt, pending == nil, prompt.id != autoPassedPromptID, status == .connected, prompt.supported,
           let land = Self.autoPayLand(prompt, snapshot: engine.snapshot) {
            autoPassedPromptID = prompt.id
            Task { [weak self] in await self?.engine.answer(.object(land)) }
        }
        if let target = pendingTarget, pending == nil {
            let (answer, keep) = Self.resolvePendingTarget(target, prompt: prompt, snapshot: engine.snapshot, issuedDuring: pendingTargetPromptID)
            if !keep { pendingTarget = nil }
            if let answer { Task { [weak self] in await self?.engine.answer(.object(answer)) } }
        }
    }

    /// The main phase button's label (Arena's wording) and whether it answers the current prompt.
    static func primaryButton(prompt: RulesPrompt?, snapshot: RulesSnapshot?, pending: Bool) -> (String, Bool) {
        if pending { return ("Sending…", false) }
        guard let prompt else {
            if let snapshot, let active = snapshot.activePlayerId, active != snapshot.playerId { return ("Opponent's\nTurn", false) }
            return ("Waiting", false)
        }
        guard prompt.method == "GAME_SELECT" else { return ("Choose", false) }
        let message = RulesText.plain(prompt.message ?? "").lowercased()
        let combat = snapshot?.combat ?? []
        if message.contains("select attackers") {
            return (combat.contains { !$0.attackers.isEmpty } ? "Attack" : "No\nAttacks", true)
        }
        if message.contains("select blockers") {
            return (combat.contains { !$0.blockers.isEmpty } ? "Block" : "No\nBlocks", true)
        }
        guard let snapshot else { return ("Next", true) }
        if !snapshot.stack.isEmpty { return ("Resolve", true) }
        let mine = snapshot.players.first { $0.id == snapshot.playerId }
        let creatures = mine?.battlefield.filter { ($0.typeLine ?? "").contains("Creature") && $0.tapped != true } ?? []
        if snapshot.activePlayerId == snapshot.playerId {
            switch snapshot.step ?? "" {
            case "PRECOMBAT_MAIN": return (creatures.contains { $0.summoningSick != true } ? "To\nAttackers" : "Next", true)
            case "POSTCOMBAT_MAIN", "END_TURN", "CLEANUP": return ("End\nTurn", true)
            default: return ("Next", true)
            }
        }
        // The opponent's turn: once they've attacked, passing takes you to declaring blockers.
        if combat.contains(where: { !$0.attackers.isEmpty }), !creatures.isEmpty, (snapshot.step ?? "").contains("ATTACKERS") {
            return ("To\nBlockers", true)
        }
        return ("Pass", true)
    }

    /// Whether basic lands are tapped for you when paying (Arena's default). Turned off from the
    /// battlefield menu ("Pay Mana Manually"), for when the automatic choice would be wrong.
    static var autoPaysMana: Bool {
        get { UserDefaults.standard.object(forKey: "rules.autoPayMana") == nil ? true : UserDefaults.standard.bool(forKey: "rules.autoPayMana") }
        set { UserDefaults.standard.set(newValue, forKey: "rules.autoPayMana") }
    }

    /// The untapped basic land to tap for a "Pay {…}" prompt, or nil when the choice isn't plain.
    static func autoPayLand(_ prompt: RulesPrompt, snapshot: RulesSnapshot?) -> String? {
        guard prompt.method == "GAME_PLAY_MANA", let snapshot,
              let mine = snapshot.players.first(where: { $0.id == snapshot.playerId }) else { return nil }
        let text = RulesText.plain(prompt.message ?? "")
        let symbols = (try? NSRegularExpression(pattern: #"\{([^}]+)\}"#))?
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } } ?? []
        guard !symbols.isEmpty else { return nil }
        let colors: Set<String> = ["W", "U", "B", "R", "G"]
        // Only plain costs: single colours, colourless and generic numbers.
        guard symbols.allSatisfy({ colors.contains($0) || $0 == "C" || Int($0) != nil }) else { return nil }
        let basic: [String: String] = ["Plains": "W", "Island": "U", "Swamp": "B", "Mountain": "R", "Forest": "G", "Wastes": "C"]
        let lands: [(id: String, color: String)] = mine.battlefield.compactMap { card in
            guard card.tapped != true, let type = card.typeLine, type.contains("Land") else { return nil }
            let produced = basic.compactMap { type.contains($0.key) ? $0.value : nil }
            return produced.count == 1 ? (card.id, produced[0]) : nil
        }
        if let needed = symbols.first(where: { colors.contains($0) || $0 == "C" }) {
            return lands.first { $0.color == needed }?.id
        }
        // Generic only: tap the most plentiful colour, keeping scarce colours open.
        let counts = Dictionary(grouping: lands, by: \.color).mapValues(\.count)
        return lands.max { (counts[$0.color] ?? 0) < (counts[$1.color] ?? 0) }?.id
    }

    /// Arena passes priority for you when you have nothing you could do. XMage stops at every
    /// "Play instants and activated abilities" (each step of the opponent's turn, responses to their
    /// spells…), so pass those automatically when the engine reports nothing playable. Your own main
    /// phases ("Play spells…") and attack/block declarations always wait for you.
    static func shouldAutoPass(_ prompt: RulesPrompt, snapshot: RulesSnapshot?, holdingPriority: Bool = false) -> Bool {
        guard !holdingPriority, prompt.method == "GAME_SELECT", prompt.specialActionAvailable != true,
              let snapshot, snapshot.playableIds.isEmpty else { return false }
        let message = RulesText.plain(prompt.message ?? "").lowercased()
        return message.contains("instants") && !message.contains("select")
    }

    /// What to do with a target chosen by gesture (a spell dragged onto a target, a blocker dragged
    /// onto an attacker) once the engine's next prompt arrives. A target prompt consumes it, answering
    /// only if it's legal there. Back at a plain selection, the engine needed no target (for example a
    /// block against a lone attacker is assigned automatically), so it's dropped: otherwise it could
    /// answer some later, unrelated target prompt.
    static func resolvePendingTarget(_ target: PhoneGame.Target, prompt: RulesPrompt?, snapshot: RulesSnapshot?,
                                     issuedDuring promptID: String? = nil) -> (answer: String?, keep: Bool) {
        // Still the prompt the gesture answered (its acknowledgement can arrive before the next prompt).
        if let promptID, prompt?.id == promptID { return (nil, true) }
        switch prompt?.method {
        case "GAME_TARGET":
            let id: String?
            switch target {
            case .card(let card): id = card.uuidString.lowercased()
            case .player(let player): id = snapshot?.players.first(where: { ($0.id == snapshot?.playerId) == (player == .a) })?.id
            }
            guard let id, prompt?.targets?.contains(id) == true else { return (nil, false) }
            return (id, false)
        case "GAME_SELECT": return (nil, false)
        default: return (nil, true) // mana payment, choices… keep it for the target prompt that follows
        }
    }

    /// Whether this card is one of the current target prompt's choices (so tapping it answers).
    func isTargetPromptChoice(_ id: UUID) -> Bool {
        guard let prompt = engine.prompt, prompt.method == "GAME_TARGET" else { return false }
        return prompt.targets?.contains(id.uuidString.lowercased()) == true
    }

    /// Cards to outline: a target prompt's legal card targets, otherwise what the engine says is playable now.
    static func highlighted(snapshot: RulesSnapshot?, prompt: RulesPrompt?) -> Set<UUID> {
        if prompt?.method == "GAME_TARGET" { return Set((prompt?.targets ?? []).compactMap(UUID.init(uuidString:))) }
        return Set((snapshot?.playableIds ?? []).compactMap(UUID.init(uuidString:)))
    }

    func send(_ action: PhoneAction) async {
        switch action {
        case .playCard(let parameters): await choose(parameters.cardInstanceID)
        case .play(let id, _, _, _, _), .moveToStack(let id), .tap(let id), .attack(let id, _): await choose(id)
        case .castTargeting(let id, let target):
            pendingTarget = target
            await choose(id)
        case .attachDroppedCard(let id, let target):
            // Dropped onto a permanent: play it, with that permanent as its target if it needs one
            // (an Aura). A land dropped on another land just plays.
            pendingTarget = .card(target)
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
        let (label, enabled) = Self.primaryButton(prompt: engine.prompt, snapshot: engine.snapshot, pending: engine.pendingRequest != nil)
        phone?.displayRules(presentation, connected: engine.status == .connected,
                            status: engine.notice, primaryLabel: label, primaryEnabled: enabled)
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
            // XMage reports "0"/"0" for every object, lands included. Only creatures (and vehicles,
            // which print theirs) show power and toughness; otherwise Phone Play treats the card as a
            // creature and lands leave the land row.
            let type = (card.typeLine ?? printed.typeLine ?? "")
            let hasStats = type.contains("Creature") || type.contains("Vehicle")
            if hasStats, let power = card.power { result.power.accept(power) }
            if hasStats, let toughness = card.toughness { result.toughness.accept(toughness) }
            result.isPowerToughnessVisible.accept(hasStats && (card.power != nil || card.toughness != nil))
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
        game.rulesPlayable = Self.highlighted(snapshot: snapshot, prompt: engine.pendingRequest == nil ? engine.prompt : nil)
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
        let phase = Self.phonePhase(enginePhase)
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

    static func phonePhase(_ enginePhase: String) -> PhoneGame.Turn.Phase {
        switch enginePhase {
        case "COMBAT": return .combat
        case "POSTCOMBAT_MAIN", "ENDING": return .ending
        default: return .main
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
