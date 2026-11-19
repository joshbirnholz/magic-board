import Foundation
import Combine
import Security

/// A rules session owns its socket and displayed engine state independently of normal Phone Play.
@MainActor
final class RulesGameSession: ObservableObject {
    enum Status: Equatable { case disconnected, connecting, connected }
    @Published private(set) var status: Status = .disconnected
    @Published private(set) var snapshot: RulesSnapshot?
    @Published private(set) var prompt: RulesPrompt?
    @Published private(set) var tables: [RulesTable] = []
    @Published private(set) var room: RulesRoom?
    @Published private(set) var features: [String] = []
    var supportsRooms: Bool { features.contains("rooms") }
    @Published private(set) var tableId: String?
    @Published private(set) var ownsTable = false
    @Published private(set) var formats: [String] = ["Limited"]
    @Published private(set) var result: String?
    @Published private(set) var pendingRequest: String?
    /// A newer engine action is waiting for the currently visible action's reading time.
    @Published private(set) var isPresentingActions = false
    private var presentationClock = RulesPresentationClock()
    @Published private(set) var notice = ""
    @Published private(set) var holdingPriority = false
    @Published private(set) var autoOrderTriggers = true
    @Published private(set) var cardInformation: [RulesSnapshot.CardGroup] = []
    /// Recent game log lines (newest last), to explain what a reveal or other event was for.
    @Published private(set) var gameLog: [String] = []
    @Published var error: String?
    /// Set by the payment prompt's Auto button (automatic payment off): keep paying the rest of
    /// this cost with basic lands, not just one mana (Josh). Ends when the cost is paid or no basic
    /// land can pay what's left (see RulesPhoneAdapter.updateStatus).
    var payingCostAutomatically = false
    /// Discovery has its own receipt/timeout and never occupies the gameplay action slot.
    private var tableRefreshRequest: String?
    private var tableRefreshTimeoutTask: Task<Void, Never>?
    var isPerformingGameAction: Bool { pendingRequest != nil }
    private var socket: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var generation = UUID()
    private var endpoint: URL?
    private var resumeToken: String?
    private let defaults: UserDefaults
    private let transport: URLSession
    private let decoder = JSONDecoder()
    private var dismissedCardInformation: Set<String> = []
    private var activeCardInformation: Set<String> = []
    private struct RetainedSeat: Codable {
        let endpoint: URL
        let token: String
    }

    init(defaults: UserDefaults = .standard, transport: URLSession = .shared) {
        self.defaults = defaults
        self.transport = transport
        let saved = RulesConnectionKey.read(account: "retainedSeat")
        if let seat = try? JSONDecoder().decode(RetainedSeat.self, from: Data(saved.utf8)),
           (try? RulesEndpoint.parse(seat.endpoint.absoluteString)) != nil, !seat.token.isEmpty {
            endpoint = seat.endpoint
            resumeToken = seat.token
        }
    }

    var canAnswer: Bool { status == .connected && prompt?.supported == true && pendingRequest == nil && !isPresentingActions }
    var hasRetainedSession: Bool { resumeToken != nil }
    var connectionKey: String {
        get { RulesConnectionKey.read() }
        set {
            if !RulesConnectionKey.write(newValue) { error = "The connection key could not be saved securely." }
        }
    }

    func connect(address: String, key: String, resume: Bool = true) {
        let url: URL
        do { url = try RulesEndpoint.parse(address) }
        catch { self.error = error.localizedDescription; return }
        guard !key.isEmpty else { error = "Enter the connection key configured on your PC."; return }
        if endpoint != url || !resume {
            resumeToken = nil; snapshot = nil; prompt = nil
            RulesConnectionKey.delete(account: "retainedSeat")
            tableId = nil; ownsTable = false; tables = []; room = nil; features = []
            result = nil
            holdingPriority = false
            autoOrderTriggers = true
            clearCardInformation()
        }
        endpoint = url
        disconnect()
        defaults.set(url.absoluteString, forKey: "rules.bridgeAddress")
        connectionKey = key
        unreadableReports = 0
        presentationClock.reset()
        isPresentingActions = false
        status = .connecting
        notice = "Connecting to your rules server…"
        error = nil
        var request = URLRequest(url: url)
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let socket = transport.webSocketTask(with: request)
        socket.maximumMessageSize = 8 * 1024 * 1024
        self.socket = socket
        let generation = self.generation
        socket.resume()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self, self.generation == generation, self.status == .connecting else { return }
            self.fail("The rules server did not finish connecting. Check its address and connection key.")
        }
        connectionTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let self, self.generation == generation else { return }
                    let data: Data
                    switch message {
                    case .string(let string): data = Data(string.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: continue
                    }
                    do {
                        try await self.receive(data, socket: socket)
                    } catch let error as DecodingError {
                        // One unreadable update shouldn't end the game: report which field, then ask
                        // the bridge for the current state again.
                        self.reportUnreadable(error, data: data)
                    }
                }
            } catch {
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                let reason = socket.closeReason.flatMap { String(data: $0, encoding: .utf8) }?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let reason, !reason.isEmpty {
                    if socket.closeCode == .policyViolation && reason.localizedCaseInsensitiveContains("key") {
                        self.fail("The rules server rejected the connection key. Check that it matches the key on your PC.")
                    } else {
                        self.fail("The rules server closed the connection: \(reason)")
                    }
                } else {
                    self.fail("Connection lost. \(error.localizedDescription)")
                }
            }
        }
    }

    func disconnect() {
        generation = UUID()
        presentationClock.reset()
        isPresentingActions = false
        connectionTask?.cancel(); connectionTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        tableRefreshTimeoutTask?.cancel(); tableRefreshTimeoutTask = nil
        tableRefreshRequest = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        status = .disconnected
        pendingRequest = nil
    }

    /// Explicitly leave the game; transient disconnects preserve the seat for reconnection.
    func endSession() async {
        let generation = self.generation
        if let socket {
            try? await send(RulesCommand(type: "leave"), through: socket)
        }
        guard self.generation == generation else { return }
        disconnect()
        resumeToken = nil; snapshot = nil; prompt = nil
        RulesConnectionKey.delete(account: "retainedSeat")
        tableId = nil; ownsTable = false; tables = []; room = nil
        result = nil
        holdingPriority = false
        autoOrderTriggers = true
        clearCardInformation()
    }

    /// These windows are informational: closing one must never answer an engine prompt.
    func dismissCardInformation(_ id: String) {
        dismissedCardInformation.insert(id)
        cardInformation.removeAll { $0.id == id }
    }

    private func clearCardInformation() {
        cardInformation = []
        gameLog = []
        dismissedCardInformation = []
        activeCardInformation = []
    }

    private var unreadableReports = 0

    private func reportUnreadable(_ error: DecodingError, data: Data) {
        let type = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String ?? "message"
        let detail: String
        switch error {
        case .keyNotFound(let key, let context): detail = "missing \((context.codingPath + [key]).map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(_, let context), .typeMismatch(_, let context), .dataCorrupted(let context):
            detail = "bad value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default: detail = "unknown"
        }
        print("Rules: couldn't read a \(type) (\(detail))")
        // A replay can contain the same incompatible payload. Bound retries for this connection
        // so it cannot become a tight request/replay loop, and don't let a delayed task resync a
        // different connection after the player reconnects.
        guard unreadableReports < 3 else { return }
        unreadableReports += 1
        let generation = self.generation
        self.error = "Couldn't read a game update (\(type): \(detail)). \(unreadableReports < 3 ? "Refreshing." : "Reconnect or update the rules bridge.")"
        if unreadableReports < 3 {
            Task { [weak self] in
                guard let self, self.generation == generation else { return }
                await self.submit(RulesCommand(type: "resync", requestId: UUID().uuidString))
            }
        }
    }

    func startAiGame(deck: RulesDeck? = nil, format: String = "Limited", aiDeck: RulesDeck? = nil) async {
        await submit(RulesCommand(type: "createAiGame", requestId: UUID().uuidString, deck: deck, aiDeck: aiDeck, format: format))
    }

    func createHumanGame(deck: RulesDeck? = nil, format: String = "Limited") async {
        await submit(RulesCommand(type: "createHumanGame", requestId: UUID().uuidString, deck: deck, format: format))
    }
    func openRoom(source: RulesDeckSource, set: String, format: String) async {
        await submit(RulesCommand(type: "openRoom", requestId: UUID().uuidString, format: format,
                                  deckSource: source.rawValue, packetSet: set))
    }
    func submitRoomDeck(_ deck: RulesDeck?) async {
        guard let room, room.needsDeck else { return }
        await submit(RulesCommand(type: "submitRoomDeck", requestId: UUID().uuidString, tableId: room.id, deck: deck))
    }
    func leaveRoom() async { await submit(RulesCommand(type: "leaveRoom", requestId: UUID().uuidString)) }
    func refreshTables() async {
        guard status == .connected, let socket, pendingRequest == nil, tableRefreshRequest == nil else { return }
        let request = UUID().uuidString, generation = self.generation
        tableRefreshRequest = request
        do {
            try await send(RulesCommand(type: supportsRooms ? "listRooms" : "listTables", requestId: request), through: socket)
            guard self.generation == generation, tableRefreshRequest == request else { return }
            tableRefreshTimeoutTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                guard let self, self.generation == generation, self.tableRefreshRequest == request else { return }
                self.tableRefreshRequest = nil
                self.error = "Couldn't refresh waiting games. Try Refresh Games again."
            }
        } catch {
            guard self.generation == generation else { return }
            tableRefreshRequest = nil
            fail(error.localizedDescription)
        }
    }
    func join(_ table: RulesTable, deck: RulesDeck? = nil) async {
        await submit(RulesCommand(type: table.room == true ? "joinRoom" : "joinTable", requestId: UUID().uuidString, tableId: table.id, deck: deck))
    }
    func startMatch() async {
        await submit(RulesCommand(type: "startMatch", requestId: UUID().uuidString))
    }

    func answer(_ answer: RulesAnswer) async {
        guard canAnswer, let prompt, let snapshot else { return }
        await submit(RulesCommand(type: "answer", requestId: UUID().uuidString, promptId: prompt.id,
                                  revision: snapshot.revision, kind: answer.kind, value: answer))
    }

    func controlPriority(_ action: RulesPriorityAction) async {
        await submit(RulesCommand(type: "priorityControl", requestId: UUID().uuidString,
                                  promptId: prompt?.id, revision: snapshot?.revision, priorityAction: action))
    }

    func setAutoOrderTriggers(_ enabled: Bool) async {
        await submit(RulesCommand(type: "settings", requestId: UUID().uuidString, autoOrderTriggers: enabled))
    }

    func concede() async {
        guard snapshot != nil, result == nil else { return }
        await submit(RulesCommand(type: "concede", requestId: UUID().uuidString))
    }

    private func submit(_ command: RulesCommand) async {
        guard status == .connected, let socket, pendingRequest == nil else { return }
        pendingRequest = command.requestId
        let generation = self.generation
        do {
            try await send(command, through: socket)
            guard self.generation == generation else { return }
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled, let self, self.generation == generation,
                      self.pendingRequest == command.requestId else { return }
                self.fail("The rules server did not acknowledge your action. Reconnect to retrieve the current game.")
            }
        } catch {
            guard self.generation == generation else { return }
            fail(error.localizedDescription)
        }
    }

    private struct Header: Decodable {
        let type: String
        let protocolVersion: Int?
        let resumeToken: String?
        let requestId: String?
        let message: String?
        let tableId: String?
        let owner: Bool?
        let formats: [String]?
        let features: [String]?
        let code: String?
    }

    private func receive(_ data: Data, socket: URLSessionWebSocketTask) async throws {
        let header = try decoder.decode(Header.self, from: data)
        switch header.type {
        case "hello":
            guard header.protocolVersion == 1 else { fail("This bridge version is incompatible with the app."); return }
            try await send(RulesCommand(type: "connect", protocolVersion: 1, resumeToken: resumeToken), through: socket)
        case "ready":
            guard header.protocolVersion == 1, let token = header.resumeToken else { fail("The bridge sent an invalid connection response."); return }
            resumeToken = token
            if let endpoint, let data = try? JSONEncoder().encode(RetainedSeat(endpoint: endpoint, token: token)) {
                if !RulesConnectionKey.write(String(decoding: data, as: UTF8.self), account: "retainedSeat") {
                    error = "Connected, but this device could not save the game for recovery after an app restart."
                }
            }
            if let formats = header.formats { self.formats = formats }
            features = header.features ?? []
            timeoutTask?.cancel()
            status = .connected
            notice = "Connected to XMage"
        case "snapshot":
            let next = try decoder.decode(RulesSnapshot.self, from: data)
            if let old = snapshot, old.gameId == next.gameId, old.revision > next.revision { return }
            if let old = snapshot, old.gameId != next.gameId { clearCardInformation() }
            let pause = presentationClock.delay(before: next, now: ProcessInfo.processInfo.systemUptime)
            if pause > 0 { try await pausePresentation(pause, socket: socket) }
            guard self.socket === socket, status == .connected else { return }
            // XMage may clear these transient views on the very next priority update. Retain
            // each permitted view until dismissed so a fast replay can't hide it before rendering.
            let groups = ((next.revealed ?? []) + (next.lookedAt ?? [])).filter { !$0.cards.isEmpty }
            let active = Set(groups.map(\.id))
            // A later reveal of the same unchanged hand is a new opportunity to inspect it.
            // Replays while that view is still active must respect the player's dismissal.
            dismissedCardInformation.subtract(active.subtracting(activeCardInformation))
            activeCardInformation = active
            for group in groups {
                guard !dismissedCardInformation.contains(group.id) else { continue }
                if let index = cardInformation.firstIndex(where: { $0.name == group.name }) {
                    cardInformation[index] = group
                } else { cardInformation.append(group) }
            }
            presentationClock.presented(next, now: ProcessInfo.processInfo.systemUptime)
            snapshot = next
        case "roomState":
            let next = try decoder.decode(RulesRoom.self, from: data)
            if snapshot == nil {
                room = next
                if next.stage == "waiting" || next.stage == "choosing" { tableId = nil; ownsTable = false }
            }
        case "roomClosed":
            room = nil
            if snapshot == nil { tableId = nil; ownsTable = false }
            if let message = header.message { notice = message }
        case "tables":
            struct TableList: Decodable { let tables: [RulesTable] }
            tables = try decoder.decode(TableList.self, from: data).tables
        case "tableJoined":
            tableId = header.tableId
            ownsTable = header.owner ?? false
            tables = []
        case "prompt": prompt = try decoder.decode(RulesPrompt.self, from: data)
        case "promptCleared": prompt = nil
        case "prioritySettings":
            struct Settings: Decodable { let holdingPriority: Bool; let autoOrderTriggers: Bool? }
            let settings = try decoder.decode(Settings.self, from: data)
            holdingPriority = settings.holdingPriority
            if let automatic = settings.autoOrderTriggers { autoOrderTriggers = automatic }
        case "ack":
            if let request = header.requestId, request == tableRefreshRequest {
                tableRefreshRequest = nil
                tableRefreshTimeoutTask?.cancel(); tableRefreshTimeoutTask = nil
            }
            if header.requestId == pendingRequest { pendingRequest = nil; timeoutTask?.cancel() }
        case "error":
            let message = header.message ?? "The rules server reported an error."
            if header.code == "sessionExpired" {
                resumeToken = nil
                RulesConnectionKey.delete(account: "retainedSeat")
                snapshot = nil; prompt = nil; tableId = nil; ownsTable = false; room = nil; holdingPriority = false; autoOrderTriggers = true
                result = nil; tables = []
                clearCardInformation()
            }
            if status == .connecting { fail(message); return }
            error = message
            if let request = header.requestId, request == tableRefreshRequest {
                tableRefreshRequest = nil
                tableRefreshTimeoutTask?.cancel(); tableRefreshTimeoutTask = nil
            }
            if let requestId = header.requestId, requestId == pendingRequest { pendingRequest = nil; timeoutTask?.cancel() }
        case "log":
            // XMage's game log ("Computer reveals Forest"): kept to explain reveals and the like.
            if let line = header.message.map(RulesText.plain), !line.isEmpty {
                gameLog.append(line)
                if gameLog.count > 40 { gameLog.removeFirst(gameLog.count - 40) }
            }
        case "notice": notice = header.message ?? ""
        case "engineDisconnected": fail(header.message ?? "XMage disconnected.")
        case "gameOver":
            let pause = max(0, presentationClock.deadline - ProcessInfo.processInfo.systemUptime)
            if pause > 0 { try await pausePresentation(pause, socket: socket) }
            guard self.socket === socket, status == .connected else { return }
            prompt = nil; result = header.message ?? "Game finished"; notice = result ?? "Game finished"
        default: break
        }
    }

    private func pausePresentation(_ duration: TimeInterval, socket: URLSessionWebSocketTask) async throws {
        let generation = self.generation
        isPresentingActions = true
        defer { if self.generation == generation { isPresentingActions = false } }
        var remaining = duration
        repeat {
            try await Task.sleep(nanoseconds: UInt64(min(1, remaining) * 1_000_000_000))
            try Task.checkCancellation()
            guard self.generation == generation, self.socket === socket else { throw CancellationError() }
            // Projection/artwork may finish after the wire update. Its first visible frame gets
            // the same reading time; repeated artwork refreshes cannot prolong the action.
            remaining = max(0, presentationClock.deadline - ProcessInfo.processInfo.systemUptime)
        } while remaining > 0
    }

    func didPresentSnapshot(_ snapshot: RulesSnapshot) {
        guard self.snapshot?.gameId == snapshot.gameId, self.snapshot?.revision == snapshot.revision else { return }
        presentationClock.visible(revision: snapshot.revision, now: ProcessInfo.processInfo.systemUptime)
    }

    private func send(_ command: RulesCommand, through socket: URLSessionWebSocketTask) async throws {
        let data = try JSONEncoder().encode(command)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func fail(_ message: String) {
        disconnect()
        error = message
        notice = "Disconnected · reconnect to continue"
    }

    deinit {
        connectionTask?.cancel()
        timeoutTask?.cancel()
        tableRefreshTimeoutTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
    }
}

private enum RulesConnectionKey {
    private static func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "MagicBoard.RulesBridge", kSecAttrAccount as String: account]
    }
    static func read(account: String = "connectionKey") -> String {
        var request = query(account: account)
        request[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func write(_ key: String, account: String = "connectionKey") -> Bool {
        let query = query(account: account)
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
    static func delete(account: String) {
        SecItemDelete(query(account: account) as CFDictionary)
    }
}
