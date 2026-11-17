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
    @Published private(set) var tableId: String?
    @Published private(set) var ownsTable = false
    @Published private(set) var pendingRequest: String?
    @Published private(set) var notice = ""
    @Published var error: String?
    private var socket: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var generation = UUID()
    private var endpoint: URL?
    private var resumeToken: String?
    private let defaults: UserDefaults
    private let transport: URLSession
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, transport: URLSession = .shared) {
        self.defaults = defaults
        self.transport = transport
    }

    var canAnswer: Bool { status == .connected && prompt?.supported == true && pendingRequest == nil }
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
            tableId = nil; ownsTable = false; tables = []
        }
        endpoint = url
        disconnect()
        defaults.set(url.absoluteString, forKey: "rules.bridgeAddress")
        connectionKey = key
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
                    try await self.receive(data, socket: socket)
                }
            } catch {
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                self.fail("Connection lost. \(error.localizedDescription)")
            }
        }
    }

    func disconnect() {
        generation = UUID()
        connectionTask?.cancel(); connectionTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        status = .disconnected
        pendingRequest = nil
    }

    /// Leaving the screen detaches the phone; the bridge preserves its game for reconnection.
    func endSession() async {
        if let socket {
            try? await send(RulesCommand(type: "leave"), through: socket)
        }
        disconnect()
        resumeToken = nil; snapshot = nil; prompt = nil
        tableId = nil; ownsTable = false; tables = []
    }

    func startAiGame() async {
        await submit(RulesCommand(type: "createAiGame", requestId: UUID().uuidString))
    }

    func createHumanGame() async {
        await submit(RulesCommand(type: "createHumanGame", requestId: UUID().uuidString))
    }
    func refreshTables() async {
        await submit(RulesCommand(type: "listTables", requestId: UUID().uuidString))
    }
    func join(_ table: RulesTable) async {
        await submit(RulesCommand(type: "joinTable", requestId: UUID().uuidString, tableId: table.id))
    }
    func startMatch() async {
        await submit(RulesCommand(type: "startMatch", requestId: UUID().uuidString))
    }

    func answer(_ answer: RulesAnswer) async {
        guard canAnswer, let prompt, let snapshot else { return }
        await submit(RulesCommand(type: "answer", requestId: UUID().uuidString, promptId: prompt.id,
                                  revision: snapshot.revision, kind: answer.kind, value: answer))
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
            timeoutTask?.cancel()
            status = .connected
            notice = "Connected to XMage"
        case "snapshot":
            let next = try decoder.decode(RulesSnapshot.self, from: data)
            if let old = snapshot, old.gameId == next.gameId, old.revision > next.revision { return }
            snapshot = next
        case "tables":
            struct TableList: Decodable { let tables: [RulesTable] }
            tables = try decoder.decode(TableList.self, from: data).tables
        case "tableJoined":
            tableId = header.tableId
            ownsTable = header.owner ?? false
            tables = []
        case "prompt": prompt = try decoder.decode(RulesPrompt.self, from: data)
        case "promptCleared": prompt = nil
        case "ack":
            if header.requestId == pendingRequest { pendingRequest = nil; timeoutTask?.cancel() }
        case "error":
            error = header.message ?? "The rules server reported an error."
            if header.requestId == pendingRequest { pendingRequest = nil; timeoutTask?.cancel() }
        case "notice": notice = header.message ?? ""
        case "engineDisconnected": fail(header.message ?? "XMage disconnected.")
        case "gameOver": prompt = nil; notice = header.message ?? "Game finished"
        default: break
        }
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
        socket?.cancel(with: .goingAway, reason: nil)
    }
}

private enum RulesConnectionKey {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "MagicBoard.RulesBridge", kSecAttrAccount as String: "connectionKey"]
    }
    static func read() -> String {
        var request = query
        request[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func write(_ key: String) -> Bool {
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
