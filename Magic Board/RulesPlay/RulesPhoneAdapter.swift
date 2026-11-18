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
    /// Arena's London mulligan on top of XMage's order: XMage asks for bottom cards right after a
    /// mulligan, before the next keep question. The app holds that question, shows Keep / Mulligan,
    /// and only asks for the cards once the player keeps.
    private enum MulliganChoice { case undecided, keeping, mulliganing }
    private var mulliganChoice = MulliganChoice.undecided
    /// The prompt that was showing when the gesture chose its target (still showing until the engine moves on).
    private var pendingTargetPromptID: String?
    private var hiddenIDs: [String: UUID] = [:]
    private(set) var presentation = PhoneGame()
    /// Whether an engine snapshot has reached the board (before that, life totals are Phone Play's defaults).
    private(set) var hasProjected = false
    /// The cards of the current card-choice prompt, for the board's browser (see PhoneGame.rulesChoice).
    private(set) var choiceCards: [CardInstance] = []
    /// Rules-only source links; never enter Phone Play's editable/saved game state.
    private(set) var abilitySources: [UUID: UUID] = [:]
    /// The payment prompt a land was last chosen for (see updateStatus).
    private var paymentTapped: (promptID: String, message: String?, pool: String?)?

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
        // Arena shows the opening hand in a browser (Keep / Mulligan); Phone Play's opening-hand
        // browser is driven by `opening`, one per mulligan question.
        presentation.opening = openingHand(for: pending == nil ? prompt : nil)
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
        // A land tapped for a payment that left the cost unchanged couldn't pay it (XMage just asks
        // again): say so, instead of the tap seeming to do nothing.
        if let prompt, pending == nil, prompt.method == "GAME_PLAY_MANA", let paid = paymentTapped,
           prompt.id != paid.promptID, prompt.message == paid.message {
            paymentTapped = nil
            // Producing floating mana is progress even if it cannot pay the spell directly (e.g.
            // colorless mana to pay Capital City's colored-mana ability). Don't call that a failed tap.
            if floatingMana == paid.pool {
                phone?.error = "That can't pay this cost. Tap another land, or Cancel."
            }
        }
        // A card choice arrives (or ends) without a new board state: project again so the board's
        // browser opens with the cards (or closes).
        let choiceID = prompt?.style == .browser && pending == nil ? prompt?.id : nil
        if choiceID != presentation.rulesChoice?.id, let snapshot = engine.snapshot {
            Task { [weak self] in try? await self?.project(snapshot, refreshArtwork: true) }
        }
        // The London mulligan's deferred answers (see MulliganChoice).
        if let prompt, pending == nil, prompt.id != autoPassedPromptID, status == .connected {
            if prompt.isLondonBottom, mulliganChoice == .mulliganing, let card = prompt.targets?.first {
                autoPassedPromptID = prompt.id
                Task { [weak self] in await self?.engine.answer(.object(card)) }
            } else if prompt.isMulligan, mulliganChoice != .undecided {
                let again = mulliganChoice == .mulliganing
                autoPassedPromptID = prompt.id
                mulliganChoice = .undecided
                Task { [weak self] in await self?.engine.answer(.boolean(again)) }
            }
        }
        // Who plays first is decided at random (Josh), not asked.
        if let prompt, pending == nil, prompt.id != autoPassedPromptID, status == .connected, prompt.isStartingPlayer,
           let choice = prompt.targets?.randomElement() {
            autoPassedPromptID = prompt.id
            Task { [weak self] in await self?.engine.answer(.object(choice)) }
        }
        if let target = pendingTarget, pending == nil {
            let (answer, keep) = Self.resolvePendingTarget(target, prompt: prompt, snapshot: engine.snapshot, issuedDuring: pendingTargetPromptID)
            if !keep { pendingTarget = nil }
            if let answer { Task { [weak self] in await self?.engine.answer(.object(answer)) } }
        }
    }

    /// The main phase button's label (Arena's wording) and whether it answers the current prompt.
    /// Our creatures that could attack now but haven't been declared, and how many are declared.
    static func attackers(_ snapshot: RulesSnapshot?) -> (available: [String], declared: [String]) {
        guard let snapshot, let mine = snapshot.players.first(where: { $0.id == snapshot.playerId }) else { return ([], []) }
        let declared = (snapshot.combat ?? []).flatMap(\.attackers).filter { id in mine.battlefield.contains { $0.id == id } }
        let available = mine.battlefield.filter {
            ($0.typeLine ?? "").contains("Creature") && $0.tapped != true && $0.summoningSick != true && !declared.contains($0.id)
        }.map(\.id)
        return (available, declared)
    }

    /// Our creatures declared as blockers.
    static func blockers(_ snapshot: RulesSnapshot?) -> [String] {
        guard let snapshot, let mine = snapshot.players.first(where: { $0.id == snapshot.playerId }) else { return [] }
        return (snapshot.combat ?? []).flatMap(\.blockers).filter { id in mine.battlefield.contains { $0.id == id } }
    }

    /// The main button's label (Arena's wording; a second line is the small caption under it, as in
    /// Arena's "Next / To Combat") and whether it answers the current prompt.
    static func primaryButton(prompt: RulesPrompt?, snapshot: RulesSnapshot?, pending: Bool) -> (String, Bool) {
        if pending { return ("Sending…", false) }
        guard let prompt else {
            if let snapshot, let active = snapshot.activePlayerId, active != snapshot.playerId { return ("Opponent's Turn", false) }
            return ("Waiting", false)
        }
        // Arena: an optional choice on the board ("Choose up to…", "you may…") is finished with the
        // main button, not a button floating over the cards.
        if prompt.method == "GAME_TARGET", prompt.required != true, !prompt.isLondonBottom { return ("Done", true) }
        guard prompt.method == "GAME_SELECT" else { return ("Choose", false) }
        let message = RulesText.plain(prompt.message ?? "").lowercased()
        let combat = snapshot?.combat ?? []
        if message.contains("select attackers") {
            // Arena: "All Attack" until attackers are chosen, then "N Attackers" confirms them.
            let (available, declared) = attackers(snapshot)
            if !declared.isEmpty { return ("\(declared.count) Attacker\(declared.count == 1 ? "" : "s")", true) }
            return (available.isEmpty ? "No Attacks" : "All Attack", true)
        }
        if message.contains("select blockers") {
            let declared = blockers(snapshot)
            return (declared.isEmpty ? "No Blocks" : "\(declared.count) Blocker\(declared.count == 1 ? "" : "s")", true)
        }
        guard let snapshot else { return ("Next", true) }
        if !snapshot.stack.isEmpty { return ("Resolve", true) }
        let mine = snapshot.players.first { $0.id == snapshot.playerId }
        let creatures = mine?.battlefield.filter { ($0.typeLine ?? "").contains("Creature") && $0.tapped != true } ?? []
        if snapshot.activePlayerId == snapshot.playerId {
            switch snapshot.step ?? "" {
            case "PRECOMBAT_MAIN": return (creatures.contains { $0.summoningSick != true } ? "Next\nTo Combat" : "Next\nTo Main 2", true)
            case "POSTCOMBAT_MAIN", "END_TURN", "CLEANUP": return ("End Turn", true)
            default: return ("Next", true)
            }
        }
        // The opponent's turn: once they've attacked, passing takes you to declaring blockers.
        if combat.contains(where: { !$0.attackers.isEmpty }), !creatures.isEmpty, (snapshot.step ?? "").contains("ATTACKERS") {
            return ("Next\nTo Blockers", true)
        }
        return ("Pass", true)
    }

    /// Arena's second button above the main one, if any, during attacker selection.
    static func secondaryButton(prompt: RulesPrompt?, snapshot: RulesSnapshot?) -> String? {
        guard let prompt, prompt.method == "GAME_SELECT",
              RulesText.plain(prompt.message ?? "").lowercased().contains("select attackers") else { return nil }
        let (available, declared) = attackers(snapshot)
        if !declared.isEmpty { return "Cancel Attacks" }
        return available.isEmpty ? nil : "No Attacks"
    }

    /// The main button: "All Attack" declares every available attacker (then shows "N Attackers"
    /// to confirm); otherwise it answers the selection (pass, confirm attackers or blockers).
    func pressMain() async {
        if let prompt = engine.prompt, prompt.method == "GAME_TARGET", prompt.required != true, !prompt.isLondonBottom {
            await engine.answer(.boolean(false)) // Done: no (more) choices
            return
        }
        guard engine.prompt?.method == "GAME_SELECT" else { phone?.error = "Complete the current rules choice first."; return }
        let (label, _) = Self.primaryButton(prompt: engine.prompt, snapshot: engine.snapshot, pending: engine.pendingRequest != nil)
        if label == "All Attack" { await selectInTurn(Self.attackers(engine.snapshot).available); return }
        await engine.answer(.boolean(true))
    }

    /// The second button: "No Attacks" confirms with none; "Cancel Attacks" deselects them all.
    func pressSecondary() async {
        switch Self.secondaryButton(prompt: engine.prompt, snapshot: engine.snapshot) {
        case "No Attacks": await engine.answer(.boolean(true))
        case "Cancel Attacks": await cancelAllAttacks() // selecting a declared attacker again removes it
        default: break
        }
    }

    /// Selects each creature in turn; XMage asks again after each one.
    private func selectInTurn(_ ids: [String]) async {
        for id in ids {
            guard await selectAndWait(id) else { break }
        }
    }

    /// Arena's Cancel Attacks: deselects every declared attacker, reading the declared set afresh
    /// after each one (XMage re-asks after every change).
    private func cancelAllAttacks() async {
        for _ in 0..<20 {
            guard let id = Self.attackers(engine.snapshot).declared.first, await selectAndWait(id) else { break }
        }
    }

    /// Answers the selection with one creature, then waits for XMage's next selection prompt and the
    /// updated board. (The prompt is briefly absent in between: answering then was silently dropped,
    /// so Cancel Attacks only removed the first attacker.)
    private func selectAndWait(_ id: String) async -> Bool {
        let before = engine.prompt?.id
        let revision = engine.snapshot?.revision
        await engine.answer(.object(id))
        for _ in 0..<100 {
            let settled = engine.pendingRequest == nil && engine.prompt != nil && engine.prompt?.id != before
                && engine.snapshot?.revision != revision
            if settled { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return engine.prompt?.method == "GAME_SELECT" && engine.pendingRequest == nil
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
            guard card.tapped != true, let type = card.typeLine,
                  type.contains("Basic"), type.contains("Land"), !type.contains("Creature") else { return nil }
            // Wastes has no land subtype. Nonbasic and creature lands need manual activation:
            // their abilities can have restrictions or costs that this simple payer cannot assess.
            if card.name == "Wastes" { return (card.id, "C") }
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

    /// While XMage asks "Mulligan?", Phone Play's opening-hand browser shows the hand (Keep / Mulligan).
    private func openingHand(for prompt: RulesPrompt?) -> PhoneGame.Opening? {
        guard let prompt, prompt.isMulligan || prompt.isLondonBottom else { return nil }
        // The browser's title says who goes first ("You Go First"): the engine's starting player.
        let snapshot = engine.snapshot
        let first: Player.Identifier = snapshot?.activePlayerId.map { $0 == snapshot?.playerId ? .a : .b } ?? .a
        // Returning cards after Keep is a new opening (the browser closed when Keep was tapped).
        let key = mulliganChoice == .keeping ? prompt.id + "-return" : prompt.id
        var opening = PhoneGame.Opening(id: UUID(uuidString: key) ?? Self.stableID(key), firstPlayer: first,
                                        deciding: [phone?.player.rawValue ?? Player.Identifier.a.rawValue])
        let text = RulesText.plain(prompt.message ?? "")
        if prompt.isMulligan, let after = Self.firstNumber(in: text, after: "down to") {
            // "Mulligan down to 6 cards?": you'd keep 7 now, and a mulligan returns 1.
            opening.keepCount = after + 1
            opening.mulliganReturns = 7 - after
        } else if prompt.isLondonBottom {
            // "Select a card (2 more) to put on the bottom of your library". XMage asks this right
            // after a mulligan; like Arena, the new seven is shown with Keep / Mulligan first, and
            // the cards are only chosen once the player keeps.
            let remaining = Self.firstNumber(in: text, after: "(") ?? 1
            if mulliganChoice == .keeping {
                opening.returning = remaining
            } else {
                let handSize = engine.snapshot?.hand.count ?? 7
                opening.keepCount = handSize - remaining
                opening.mulliganReturns = remaining + 1
            }
        }
        return opening
    }

    /// Re-applies the current prompt after a Keep / Mulligan choice that XMage hasn't asked about yet.
    private func refreshMulligan() {
        updateStatus(engine.status, prompt: engine.prompt, pending: engine.pendingRequest, holdingPriority: engine.holdingPriority)
    }

    static func firstNumber(in text: String, after marker: String) -> Int? {
        guard let range = text.range(of: marker) else { return nil }
        let digits = text[range.upperBound...].drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }

    /// A UUID derived from a prompt ID that isn't one itself, so the same prompt keeps the same opening.
    static func stableID(_ text: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in text.utf8.enumerated() { bytes[index % 16] = bytes[index % 16] &* 31 &+ byte }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
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

    private var floatingMana: String? {
        guard let snapshot = engine.snapshot else { return nil }
        return snapshot.players.first { $0.id == snapshot.playerId }?.floatingMana
    }

    /// Whether choosing this card (the card menu's "Choose / Activate") can do anything now, so the
    /// menu doesn't offer an action the engine would refuse.
    func canChoose(_ id: UUID) -> Bool {
        guard engine.canAnswer, let prompt = engine.prompt, let snapshot = engine.snapshot else { return false }
        let key = id.uuidString.lowercased()
        let mine = snapshot.players.first { $0.id == snapshot.playerId }
        let step = snapshot.step ?? ""
        switch prompt.method {
        case "GAME_SELECT":
            if snapshot.playableIds.contains(key) { return true }
            if step.contains("ATTACK") { return snapshot.activePlayerId == snapshot.playerId && mine?.battlefield.contains { $0.id == key } == true }
            if step.contains("BLOCK") { return snapshot.players.contains { $0.battlefield.contains { $0.id == key } } }
            return false
        case "GAME_TARGET":
            return prompt.targets?.contains(key) == true
        case "GAME_PLAY_MANA", "GAME_PLAY_XMANA":
            return mine?.battlefield.contains { $0.id == key && $0.tapped != true } == true
        default:
            return false
        }
    }

    /// A card tapped in the board's card-choice browser.
    func chooseInBrowser(_ id: UUID) async {
        guard let prompt = engine.prompt, prompt.style == .browser, engine.canAnswer else { return }
        await engine.answer(.object(id.uuidString.lowercased()))
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
        case .moveToPlayer(let id, .library, _, bottom: true) where engine.prompt?.isLondonBottom == true:
            // Dragging a card to the library during the mulligan: XMage's "put on the bottom".
            await engine.answer(.object(id.uuidString.lowercased()))
        case .attachDroppedCard(let id, let target):
            // Dropped onto a permanent: play it, with that permanent as its target if it needs one
            // (an Aura). A land dropped on another land just plays.
            pendingTarget = .card(target)
            await choose(id)
        case .block(let id, let target):
            pendingTarget = target.map(PhoneGame.Target.card)
            await choose(id)
        case .resolve, .untap, .untapAndDraw, .beginCombat, .endCombat, .endTurn:
            await pressMain()
        case .keepHand:
            if engine.prompt?.isLondonBottom == true {
                // Keep this hand: now choose which cards go to the bottom ("Return N Cards").
                mulliganChoice = .keeping
                refreshMulligan()
            } else {
                mulliganChoice = .undecided
                await engine.answer(.boolean(false))
            }
        case .mulligan:
            if engine.prompt?.isLondonBottom == true {
                // Mulligan again: which cards go to the bottom doesn't matter (the hand is shuffled
                // away), so they're returned automatically and the mulligan is taken.
                mulliganChoice = .mulliganing
                refreshMulligan()
            } else {
                mulliganChoice = .undecided
                await engine.answer(.boolean(true))
            }
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
        if let prompt = engine.prompt, prompt.method == "GAME_PLAY_MANA" { paymentTapped = (prompt.id, prompt.message, floatingMana) }
        else { paymentTapped = nil }
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
        // A card choice's cards (a library search) aren't on the board: load their printings too.
        let choiceSource = engine.prompt?.style == .browser ? engine.prompt?.cards ?? [] : []
        allCards += choiceSource.filter { card in !allCards.contains { $0.id == card.id } }
        var models: [String: MTGCard] = [:]
        for card in allCards {
            try Task.checkCancellation()
            if let model = await catalog.localCard(card) { models[card.id] = model }
        }
        try Task.checkCancellation()
        let centers = phone?.game.cards.mapValues { $0.center.value } ?? [:]
        func instance(_ card: RulesCard, owner: Player.Identifier, battlefield: Bool = false) throws -> CardInstance {
            let printed = try models[card.id] ?? Self.placeholder(name: RulesText.tokenName(card) ?? card.name ?? "Unknown card", typeLine: RulesText.typeLine(card) ?? "", rules: card.rules, manaCost: card.manaCost)
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
            // XMage reports "0"/"0" for every object, lands included. Only creatures show power and
            // toughness; otherwise Phone Play treats the card as a creature and moves it to the
            // creature row. A Vehicle is one only while crewed (XMage's type line then says Creature),
            // so an uncrewed one sits with the artifacts and enchantments.
            let type = (card.typeLine ?? printed.typeLine ?? "")
            let hasStats = type.contains("Creature")
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
        game.opening = openingHand(for: engine.pendingRequest == nil ? engine.prompt : nil)
        // A card choice (library search, revealed cards…) goes to Phone Play's fanned browser.
        if engine.pendingRequest == nil, let prompt = engine.prompt, prompt.style == .browser, let cards = prompt.cards {
            choiceCards = try cards.map { try instance($0, owner: .a) }
            let ids = cards.compactMap { UUID(uuidString: $0.id) }
            let message = prompt.plainMessage.lowercased()
            let kind: PhoneGame.RulesChoice.Kind = message.contains("(scry)") ? .scry : message.contains("(surveil)") ? .surveil : .choose
            let title: String = switch kind {
            case .scry: "Scry \(cards.count)"
            case .surveil: "Surveil \(cards.count)"
            case .choose: prompt.plainMessage
            }
            let hint: String? = switch kind {
            case .scry: "Drag cards to the bottom of your library (or tap them). The rest stay on top."
            case .surveil: "Drag cards to your graveyard (or tap them). The rest stay on top."
            case .choose: nil
            }
            game.rulesChoice = .init(id: prompt.id, title: title,
                                     subtitle: hint ?? prompt.subMessage.map(RulesText.plain).flatMap { $0.isEmpty ? nil : $0 },
                                     cardIDs: ids,
                                     selectable: Set(ids.filter { prompt.isCardSelectable($0.uuidString.lowercased()) }),
                                     selected: Set((prompt.selectedIds ?? []).compactMap(UUID.init(uuidString:))),
                                     kind: kind)
        } else {
            choiceCards = []
        }
        game.stack = try snapshot.stack.reversed().map { card in
            let targets: [PhoneGame.Target] = (card.targets ?? []).compactMap { target in
                if snapshot.players.contains(where: { $0.id == target }) { return .player(seat(target)) }
                if visibleIDs.contains(target), let id = UUID(uuidString: target) { return .card(id) }
                return nil
            }
            let text = card.ability == true ? RulesText.cardRules(card.rules ?? card.name ?? "Ability", name: card.name, typeLine: card.typeLine) : card.name ?? "Spell"
            let controller = card.controllerId.map(seat) ?? snapshot.activePlayerId.map(seat) ?? .a
            // An ability shows its source card's art (Arena), with the ability's text over it.
            let ability = card.ability == true
            // An ability takes its source's printing and colors when the source is visible, so its
            // frame and art match the source's mini card.
            let source = ability ? card.sourceId.flatMap { id in allCards.first { $0.id == id } } : nil
            if let source, models[card.id] == nil { models[card.id] = models[source.id] }
            let shown = ability && (card.name ?? "").isEmpty ? nil : try instance(card, owner: controller)
            if let source, let colors = source.colors { shown?.colors.accept(colors.compactMap(MTGColor.init(rawValue:))) }
            var item = PhoneGame.StackItem(id: UUID(uuidString: card.id) ?? UUID(), card: shown, text: text, player: controller, targets: targets)
            if ability { item.isAbility = true }
            return item
        }
        abilitySources = Dictionary(uniqueKeysWithValues: snapshot.stack.compactMap { card in
            guard card.ability == true, let ability = UUID(uuidString: card.id),
                  let source = card.sourceId, visibleIDs.contains(source), let id = UUID(uuidString: source) else { return nil }
            return (ability, id)
        })
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
        hasProjected = true
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
        if let rules { json["oracleText"] = RulesText.cardRules(rules, name: name, typeLine: typeLine) }
        if let manaCost { json["manaCost"] = manaCost }
        return try JSONDecoder().decode(MTGCard.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

/// Preserve Scryfall image identity while supplying current engine text/types to battlefield properties.
enum RulesCardCharacteristics {
    static func applying(_ engine: RulesCard, to printed: MTGCard) throws -> MTGCard {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(printed)) as! [String: Any]
        func apply(to values: inout [String: Any]) {
            if let type = RulesText.typeLine(engine) { values["typeLine"] = type }
            if let rules = engine.rules { values["oracleText"] = RulesText.cardRules(rules, name: engine.name, typeLine: RulesText.typeLine(engine)); values["keywords"] = [] }
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
        // The lookups are blocking network calls: run them off the actor, so projecting snapshots
        // (which reads this cache) never waits on Scryfall. A slow lookup used to freeze the board
        // while the game went on underneath.
        let token = RulesText.tokenName(card)
        let set = card.set, number = card.collectorNumber, name = card.name
        let model: MTGCard? = await Task.detached(priority: .utility) { () -> MTGCard? in
            // XMage names tokens "Treasure Token"; Scryfall's token is "Treasure", in the set's token set.
            if let token { return try? CardService.shared.getToken(name: token, set: set) }
            if let set, let number, let found = try? CardService.shared.getCard(code: set.lowercased(), number: number) { return found }
            if let name { return try? CardService.shared.getCard(name: name) }
            return nil
        }.value
        if let model { cache[key] = model }
        else { failedKeys.insert(key) }
        return model
    }
}
