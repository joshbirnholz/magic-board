import Foundation
import UIKit
import Combine
import MultipeerConnectivity
import CardService

/// Owns transport and game ordering; the original storyboard owns presentation.
final class PhoneGameSession: ObservableObject {
    enum Mode { case menu, host, join, rules }
    struct Request: Codable {
        var id = UUID()
        var gameID: UUID
        var action: PhoneAction
    }
    enum Packet: Codable {
        case snapshot(PhoneGame, acknowledged: [UUID])
        case action(Request)
        case failure(String)
    }
    @Published private(set) var game = PhoneGame()
    @Published private(set) var mode: Mode = .menu
    @Published private(set) var connected = false
    @Published private(set) var hasSnapshot = false
    @Published private(set) var status = ""
    @Published private(set) var nearby: [MCPeerID] = []
    @Published var error: String?
    var onUpdate: (() -> Void)?
    // Rules uses this class only as the existing Phone Play presentation facade.
    // Its engine state and transport live in RulesGameSession, never in PhoneGame.apply.
    private(set) var rulesAdapter: RulesPhoneAdapter?
    var rulesAction: ((PhoneAction) -> Void)?
    var rulesCommand: ((Command) -> Void)?
    var rulesLeave: (() -> Void)?
    var rulesPrimaryLabel = "Next"
    private let connection = NearbyGameConnection()
    private var appliedRequests: Set<UUID> = []
    private var pendingEdits: [Request] = []
    private var remotePeer: MCPeerID?
    private var baseline: Data?
    private var originalState: Data?
    private var applyingSnapshot = false
    private var fixture = false
    #if DEBUG
    private var verificationInvited = false
    private var verificationSent = false
    #endif
    static var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("phoneGame.json")
    }
    var player: Player.Identifier { mode == .host || mode == .rules ? .a : .b }
    var opponent: Player.Identifier { player == .a ? .b : .a }
    var canAct: Bool { mode == .host || connected && hasSnapshot }
    var hasSavedGame: Bool { FileManager.default.fileExists(atPath: Self.saveURL.path) }

    init() {
        connection.onPeers = { [weak self] peers in
            guard let self else { return }
            self.nearby = peers
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--phone-network-join"), !self.verificationInvited, let peer = peers.first {
                self.verificationInvited = true
                self.join(peer)
            }
            #endif
        }
        connection.onError = { [weak self] in self?.error = $0 }
        connection.onConnection = { [weak self] peer, state in
            guard let self else { return }
            let wasConnected = self.connected
            self.connected = state == .connected
            switch state {
            case .connected:
                self.remotePeer = peer
                self.status = "Connected to \(peer.displayName)"
                if self.mode == .host { self.publish() }
            case .connecting: self.status = "Connecting to \(peer.displayName)…"
            case .notConnected:
                self.pendingEdits.removeAll()
                self.status = "Disconnected · rejoin to continue"
                // Tell the player when an established game connection drops (not on failed attempts).
                if wasConnected, self.mode != .menu {
                    self.error = self.mode == .host
                        ? "\(peer.displayName) disconnected. The game is saved on this phone; they can rejoin with Join Game to continue."
                        : "You were disconnected from \(peer.displayName). Rejoin their game with Join Game to continue; nothing on the host is lost."
                }
            @unknown default: break
            }
            self.onUpdate?()
        }
        connection.onData = { [weak self] data, peer in self?.receive(data, from: peer) }
    }

    private func activate() {
        if originalState == nil { originalState = try? JSONEncoder().encode(GameState.current) }
        AppDelegate.shared.transceiver.stop()
        GameState.sessionSave = { [weak self] state in self?.captureLocalEdits(state) }
        GameState.sessionCards = { [weak self] in self?.game.stack.compactMap(\.card) ?? [] }
        GameState.sessionPile = { [weak self] player, location in
            self?.game.pile(location, player: player) ?? GameState.current[player: player][location]
        }
        GameState.sessionDraw = { [weak self] player, count, opening in
            guard let self, player == self.player else { return }
            self.send(.drawCards(count, opening: opening))
        }
    }

    func host(resume: Bool = false) {
        mode = .host
        activate()
        var hosted: PhoneGame
        if resume {
            guard let data = try? Data(contentsOf: Self.saveURL), let saved = try? JSONDecoder().decode(PhoneGame.self, from: data) else {
                error = "The saved phone game could not be opened."
                return
            }
            hosted = saved
            // An unfinished packet draft from the saved game shouldn't pop the picker on resume.
            hosted.packetSelection = nil
        } else { hosted = PhoneGame(state: GameState.current) }
        appliedRequests.removeAll(); hasSnapshot = true; connected = false
        AppDelegate.shared.role = .boardPlayer1
        applyingSnapshot = true
        hosted.state.player1.isHidden = false
        hosted.state.player2.isHidden = false
        applyingSnapshot = false
        adopt(hosted)
        status = "Waiting for a nearby player"
        connection.host()
        persist()
        onUpdate?()
    }

    func browse() {
        mode = .join
        activate()
        AppDelegate.shared.role = .boardPlayer2
        connected = false; hasSnapshot = false; remotePeer = nil
        status = "Looking for nearby games…"
        connection.browse()
        onUpdate?()
    }
    func join(_ peer: MCPeerID) {
        status = "Connecting to \(peer.displayName)…"
        connection.join(peer)
    }
    func reconnect() { if let remotePeer { join(remotePeer) } }

    func leave() {
        rulesLeave?()
        rulesAdapter = nil; rulesAction = nil; rulesCommand = nil; rulesLeave = nil
        if mode == .host { persist() }
        applyingSnapshot = true
        connection.stop()
        GameState.sessionSave = nil; GameState.sessionCards = nil
        GameState.sessionPile = nil; GameState.sessionDraw = nil
        if let originalState, let state = try? JSONDecoder().decode(GameState.self, from: originalState) {
            GameState.current.update(withValuesFrom: state)
        }
        AppDelegate.shared.role = .board
        AppDelegate.shared.transceiver.resume()
        mode = .menu; connected = false; hasSnapshot = false; remotePeer = nil
        applyingSnapshot = false
        onUpdate?()
    }

    /// Bridge the existing hand, deck picker, and pile commands unchanged.
    func send(_ command: Command) {
        if let rulesCommand { rulesCommand(command); return }
        switch command {
        case .rebroadcast: if mode == .host { publish() }
        case .moveCardsToBattlefield(let cards): cards.forEach { send(.playCard($0)) }
        case .moveCards(let move):
            move.cardInstanceIDs.forEach { send(.moveToPlayer($0, move.destination.location, move.destination.playerIdentifier, bottom: (move.insertionIndex ?? 1) <= 0)) }
        case .loadDeck(let deck):
            guard deck.source == .decklist else { error = "Import a deck list or choose bundled JumpStart packets to play offline."; return }
            send(.load(deck.deckList, name: "Deck"))
        case .reorderHand(let order): send(.reorderHand(order.cardInstanceIDs))
        case .revealCardsToPlayer(let parameters): send(.reveal(parameters.cardInstanceIDs, parameters.playerIdentifier, true))
        case .unrevealCardsToPlayer(let parameters): send(.reveal(parameters.cardInstanceIDs, parameters.playerIdentifier, false))
        case .removeAllRevealedCards(let player): send(.reveal(Array(game.cards.keys), player, false))
        }
    }

    /// How a card can be played: like `PlayCardParameters.options`, except a disturb card in the
    /// graveyard is cast as its back face.
    func castOptions(for card: CardInstance, tapped: Bool = false) -> [Command.PlayCardParameters.Option] {
        if game.state[player: player].graveyard.cards.value.contains(card), let face = PhoneGame.castFace(for: card),
           let name = card.representation.card.cardFaces?[face].name {
            return [.init(title: name, parameters: .init(cardInstanceID: card.uuid, faceIndex: face, tapped: tapped))]
        }
        return Command.PlayCardParameters.options(for: card, tapped: tapped)
    }

    private var localInspection: PhoneGame.Inspection?

    /// Tells the other phone what's open (a battlefield card's menu, a pile sheet) until the
    /// controller is dismissed, so it can be outlined there.
    func trackInspection(_ inspection: PhoneGame.Inspection, while controller: UIViewController) {
        trackInspection(inspection) { [weak controller] in
            guard let controller else { return false }
            return controller.presentingViewController != nil || controller.isBeingPresented
        }
    }

    /// The same, for as long as `isActive` holds (a pile's browser, which isn't presented).
    func trackInspection(_ inspection: PhoneGame.Inspection, while isActive: @escaping () -> Bool) {
        localInspection = inspection
        if canAct { send(.inspect(inspection)) }
        watchInspection(inspection, isActive: isActive)
    }

    private func watchInspection(_ inspection: PhoneGame.Inspection, isActive: @escaping () -> Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.localInspection == inspection else { return }
            if isActive() {
                self.watchInspection(inspection, isActive: isActive)
            } else {
                self.localInspection = nil
                if self.canAct { self.send(.inspect(nil)) }
            }
        }
    }

    /// Asked before a commander moves to a zone other than the command zone, as on the iPad board:
    /// call the completion with true to put it into the command zone instead.
    var chooseCommanderZone: ((CardInstance, Pile.Location, @escaping (Bool) -> Void) -> Void)?

    func send(_ action: PhoneAction) {
        if let rulesAction { rulesAction(action); return }
        if let choose = chooseCommanderZone, let (id, location, owner) = Self.commanderMove(action, game: game),
           let card = game.cards[id] {
            choose(card, location) { [weak self] toCommandZone in
                self?.sendDirectly(toCommandZone ? .moveToPlayer(id, .command, owner, bottom: false) : action)
            }
            return
        }
        sendDirectly(action)
    }

    /// A move of a commander card into the hand, graveyard, exile or library.
    private static func commanderMove(_ action: PhoneAction, game: PhoneGame) -> (UUID, Pile.Location, Player.Identifier)? {
        let id: UUID, location: Pile.Location
        switch action {
        case .moveToPlayer(let card, let destination, _, _): id = card; location = destination
        case .move(let card, let destination, _): id = card; location = destination
        default: return nil
        }
        guard location != .command, let card = game.cards[id], card.isCommander.value,
              !card.representation.isToken,
              !game.state[player: card.ownerIdentifier].commandZone.cards.value.contains(card) else { return nil }
        return (id, location, card.ownerIdentifier)
    }

    /// Sends without the commander-zone question (the caller already asked, e.g. Top / Bottom / Command Zone).
    func sendDirectly(_ action: PhoneAction) {
        guard canAct else { error = "Reconnect to the host before making changes."; onUpdate?(); return }
        if mode == .host { apply(action, player: .a) }
        else {
            let request = Request(gameID: game.id, action: action)
            if case .edit = action { pendingEdits.append(request) }
            do { try connection.send(JSONEncoder().encode(Packet.action(request))) }
            catch {
                pendingEdits.removeAll { $0.id == request.id }
                self.error = error.localizedDescription; onUpdate?()
            }
        }
    }

    private func receive(_ data: Data, from peer: MCPeerID) {
        do {
            switch try JSONDecoder().decode(Packet.self, from: data) {
            case .snapshot(let snapshot, let acknowledged):
                guard mode != .host, peer == remotePeer,
                      !hasSnapshot || game.id != snapshot.id || snapshot.revision >= game.revision else { return }
                if game.id != snapshot.id { pendingEdits.removeAll() }
                let acknowledgedIDs = Set(acknowledged)
                pendingEdits.removeAll { acknowledgedIDs.contains($0.id) }
                hasSnapshot = true
                adopt(Self.displaySnapshot(snapshot, pending: pendingEdits))
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--phone-network-join"), !verificationSent {
                    verificationSent = true
                    if ProcessInfo.processInfo.arguments.contains("--phone-packet-network-check") {
                        send(.startPackets(kind: "JumpStart", set: "J22"))
                    } else {
                        // Exercise the same relay/save path as the existing life control.
                        GameState.current.player2.life.mutate { $0 -= 1 }
                        send(.shuffle)
                    }
                }
                #endif
            case .action(let request):
                guard mode == .host, peer == remotePeer, request.gameID == game.id,
                      !appliedRequests.contains(request.id) else { return }
                appliedRequests.insert(request.id)
                apply(request.action, player: .b)
            case .failure(let message):
                guard peer == remotePeer else { return }
                error = message; onUpdate?()
            }
        } catch { self.error = "Unable to read this game update. Both phones need the same app version."; onUpdate?() }
    }

    private func captureLocalEdits(_ state: GameState) {
        guard !applyingSnapshot else { return }
        if mode == .rules {
            // Card placement is local presentation. All rule-bearing edits are restored
            // from the last engine snapshot; no sandbox patch is ever submitted.
            if let baseline, let authoritative = try? JSONDecoder().decode(PhoneGame.self, from: baseline) {
                let centers = Dictionary(uniqueKeysWithValues: state.battlefield.value.map { ($0.uuid, $0.center.value) })
                adopt(authoritative)
                applyingSnapshot = true
                for card in game.state.battlefield.value {
                    if let center = centers[card.uuid] { card.center.accept(center) }
                }
                baseline = try? JSONEncoder().encode(game)
                applyingSnapshot = false
            }
            return
        }
        do {
            guard canAct else {
                if let baseline { adopt(try JSONDecoder().decode(PhoneGame.self, from: baseline)) }
                error = "Reconnect before editing the battlefield."; onUpdate?(); return
            }
            if mode == .host {
                game.state = state
                state.battlefield.accept(state.battlefield.value)
                let placedIDs = Set(state.cardsInZones.keys)
                game.stack.removeAll { item in item.card.map { placedIDs.contains($0.uuid) } ?? false }
                game.revision += 1
                baseline = try JSONEncoder().encode(game)
                persist(); publish(); onUpdate?(); NotificationCenter.default.post(name: .phoneGameDidChange, object: nil)
            } else if let baseline {
                let before = try JSONDecoder().decode(PhoneGame.self, from: baseline)
                let patch = try PhoneStatePatch(before: before, after: state)
                guard !patch.isEmpty else { return }
                game.state = state
                self.baseline = try JSONEncoder().encode(game)
                send(.edit(patch))
                onUpdate?()
            }
        } catch { self.error = error.localizedDescription; onUpdate?() }
    }

    private func apply(_ action: PhoneAction, player: Player.Identifier) {
        applyingSnapshot = true
        do {
            try game.apply(action, player: player)
            game.revision += 1
            let snapshot = game
            adopt(snapshot)
            persist(); publish()
        } catch {
            self.error = error.localizedDescription
            if player == .b { try? connection.send(JSONEncoder().encode(Packet.failure(error.localizedDescription))) }
            publish()
            onUpdate?()
        }
        applyingSnapshot = false
    }

    /// Preserve newer optimistic edits while older host acknowledgements arrive.
    static func displaySnapshot(_ snapshot: PhoneGame, pending: [Request]) -> PhoneGame {
        var displayed = snapshot
        for request in pending where request.gameID == snapshot.id {
            if case .edit = request.action { try? displayed.apply(request.action, player: .b) }
        }
        return displayed
    }

    private func adopt(_ snapshot: PhoneGame) {
        applyingSnapshot = true
        let canonical = GameState.current.update(withValuesFrom: snapshot.state, additionalCards: snapshot.stack.compactMap(\.card))
        var next = snapshot
        next.state = GameState.current
        next.stack = snapshot.stack.map { item in
            var item = item
            if let card = item.card { item.card = canonical[card.uuid] ?? card }
            return item
        }
        game = next
        baseline = try? JSONEncoder().encode(game)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--phone-network-") }) {
            print("PHONE_SYNC player=\(player.rawValue) revision=\(game.revision) lifeB=\(game.state.player2.life.value) stack=\(game.stack.count) packetSelection=\(game.packetSelection?.id.uuidString ?? "none") offersA=\(game.packetSelection?.offers["a"]?.count ?? 0) offersB=\(game.packetSelection?.offers["b"]?.count ?? 0)")
            fflush(stdout)
        }
        #endif
        applyingSnapshot = false
        onUpdate?()
        NotificationCenter.default.post(name: .phoneGameDidChange, object: nil)
    }
    private func publish() {
        guard connected else { return }
        do { try connection.send(JSONEncoder().encode(Packet.snapshot(game, acknowledged: Array(appliedRequests)))) }
        catch { self.error = error.localizedDescription; onUpdate?() }
    }
    private func persist() {
        guard !fixture else { return }
        do { try JSONEncoder().encode(game).write(to: Self.saveURL, options: .atomic) }
        catch { self.error = "Could not save the phone game: \(error.localizedDescription)"; onUpdate?() }
    }

    @MainActor
    func beginRules(_ adapter: RulesPhoneAdapter) {
        mode = .rules
        rulesAdapter = adapter
        activate()
        AppDelegate.shared.role = .boardPlayer1
        rulesAction = { [weak adapter] action in Task { @MainActor in await adapter?.send(action) } }
        rulesCommand = { [weak adapter] command in Task { @MainActor in await adapter?.send(command) } }
        rulesLeave = { [weak adapter] in Task { @MainActor in adapter?.disconnect() } }
        adapter.attach(to: self)
    }

    func displayRules(_ projection: PhoneGame, connected: Bool, status: String, primaryLabel: String) {
        guard mode == .rules else { return }
        self.connected = connected
        self.status = status
        rulesPrimaryLabel = primaryLabel
        hasSnapshot = true
        adopt(projection)
    }
}

#if DEBUG
extension PhoneGameSession {
    func joinFixture() {
        fixture = true
        browse()
    }
    func hostFixture() {
        do {
            let asGuest = ProcessInfo.processInfo.arguments.contains("--phone-board-as-guest")
            mode = asGuest ? .join : .host
            connected = asGuest
            fixture = true
            activate()
            AppDelegate.shared.role = asGuest ? .boardPlayer2 : .boardPlayer1
            hasSnapshot = true
            status = "Fixture · original board"
            adopt(try PhoneGame.boardFixture(crowded: ProcessInfo.processInfo.arguments.contains("--phone-board-crowded"),
                                             bigHand: ProcessInfo.processInfo.arguments.contains("--phone-board-big-hand"),
                                             support: ProcessInfo.processInfo.arguments.contains("--phone-board-support"),
                                             commander: ProcessInfo.processInfo.arguments.contains("--phone-board-commander"),
                                             targeting: ProcessInfo.processInfo.arguments.contains("--phone-board-targets"),
                                             permanentHand: ProcessInfo.processInfo.arguments.contains("--phone-board-permanent-hand")))
            if ProcessInfo.processInfo.arguments.contains("--phone-board-stack") {
                for (owner, name) in [(Player.Identifier.a, "Brainstorm"), (.b, "Predict"), (.a, "Vision Charm")] {
                    if let card = game.state[player: owner].hand.cards.value.first(where: { $0.representation.name == name }) {
                        try game.apply(.play(card.uuid, face: nil, faceDown: false, tapped: false, directly: false), player: owner)
                    }
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--phone-board-resolution"),
               let creature = game.state.battlefield.value.first(where: { $0.controllerIdentifier.value == player && $0.representation.name == "Grizzly Bears" }) {
                try game.apply(.moveToStack(creature.uuid), player: player)
            }
            if ProcessInfo.processInfo.arguments.contains("--phone-board-attacking"),
               let attacker = game.state.battlefield.value.first(where: { $0.controllerIdentifier.value == player && $0.representation.name == "Grizzly Bears" }) {
                send(.attack(attacker.uuid, tap: false))
            }
            if ProcessInfo.processInfo.arguments.contains("--phone-board-opponent-attacking"),
               let attacker = game.state.battlefield.value.first(where: { $0.controllerIdentifier.value != player && $0.representation.name == "Grizzly Bears" }) {
                // As if the opponent's phone had declared it (applied directly: the opponent acts there).
                try? game.apply(.attack(attacker.uuid, tap: false), player: attacker.controllerIdentifier.value)
                onUpdate?()
            }
            if ProcessInfo.processInfo.arguments.contains("--phone-board-empty-hand") {
                game.state[player: player].hand.cards.accept([])
            }
            if ProcessInfo.processInfo.arguments.contains("--phone-network-host") { connection.host() }
        } catch { self.error = error.localizedDescription }
    }
}
#endif
