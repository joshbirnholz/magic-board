import SwiftUI

struct RulesConnectionView: View {
    let open: (RulesPhoneAdapter) -> Void
    @StateObject private var session = RulesGameSession()
    @AppStorage("rules.bridgeAddress") private var address = ""
    @State private var key = ""
    @State private var transferred = false

    var body: some View {
        Form {
            Section {
                TextField("ws://my-pc.local:17180", text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityIdentifier("rules-server-address")
                SecureField("Connection key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("rules-connection-key")
            } header: { Text("Rules server") } footer: {
                Text("Connect to the Magic Board bridge on your PC. Use its local address at home or its private network address away from home.")
            }
            Section {
                if session.status == .connecting {
                    HStack { ProgressView(); Text("Connecting…") }
                    Button("Cancel") { session.disconnect() }
                } else if session.status == .connected {
                    Label("Connected to XMage", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    if let table = session.tableId {
                        Text("Game \(table.prefix(8))").font(.headline).monospacedDigit()
                        if session.ownsTable {
                            Text("Have the other player connect to this server and join your waiting game.").font(.callout)
                            Button("Start Game") { Task { await session.startMatch() } }
                                .disabled(session.pendingRequest != nil)
                                .accessibilityIdentifier("rules-start-human")
                        } else {
                            Text("Waiting for the other player to start the game…").font(.callout)
                        }
                    } else {
                        Button("Play Against AI") { Task { await session.startAiGame() } }
                            .disabled(session.pendingRequest != nil || session.snapshot != nil)
                            .accessibilityIdentifier("rules-start-ai")
                        Button("Create Two-Player Game") { Task { await session.createHumanGame() } }
                            .disabled(session.pendingRequest != nil)
                            .accessibilityIdentifier("rules-create-human")
                    }
                    if session.pendingRequest != nil { ProgressView("Working…") }
                    Button("Disconnect") { session.disconnect() }
                } else {
                    Button("Connect") { session.connect(address: address, key: key) }
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || key.isEmpty)
                        .accessibilityIdentifier("rules-connect")
                    if session.snapshot != nil || session.tableId != nil {
                        Button("Connect as New Session") { session.connect(address: address, key: key, resume: false) }
                    }
                }
            }
            if session.status == .connected, session.tableId == nil {
                Section("Waiting Games") {
                    Button("Refresh Games") { Task { await session.refreshTables() } }
                        .disabled(session.pendingRequest != nil)
                        .accessibilityIdentifier("rules-refresh-games")
                    ForEach(session.tables) { table in
                        Button {
                            Task { await session.join(table) }
                        } label: {
                            HStack {
                                Text("Game \(table.id.prefix(8))")
                                Spacer()
                                Text("\(table.players)/\(table.capacity)").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .disabled(session.pendingRequest != nil)
                        .accessibilityIdentifier("rules-join-\(table.id)")
                    }
                }
            }
            if let error = session.error {
                Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("rules-connection-error") }
            }
        }
        .navigationTitle("Rules Game")
        .onAppear { key = session.connectionKey }
        .task(id: session.status == .connected && session.tableId == nil) {
            guard session.status == .connected, session.tableId == nil else { return }
            while !Task.isCancelled {
                await session.refreshTables()
                do { try await Task.sleep(nanoseconds: 3_000_000_000) }
                catch { return }
            }
        }
        .onReceive(session.$snapshot.compactMap { $0 }) { _ in
            guard !transferred else { return }
            transferred = true
            open(RulesPhoneAdapter(engine: session))
        }
        .onDisappear { if !transferred { Task { await session.endSession() } } }
    }
}

/// The existing Phone Play board remains visible and interactive beneath engine choices.
struct RulesPromptBar: View {
    @ObservedObject var session: RulesGameSession
    @State private var number = 0
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rules Game").font(.caption.bold())
                Spacer()
                if let state = session.snapshot {
                    Text("Turn \(state.turn) · \(RulesText.plain((state.step ?? "Starting Game").replacingOccurrences(of: "_", with: " ")))")
                        .font(.caption).monospacedDigit()
                }
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                    .accessibilityLabel(expanded ? "Collapse game prompt" : "Expand game prompt")
            }
            if session.status == .disconnected {
                Text(session.notice).font(.callout)
                Button("Reconnect") {
                    let address = UserDefaults.standard.string(forKey: "rules.bridgeAddress") ?? ""
                    session.connect(address: address, key: session.connectionKey)
                }
            } else if expanded, let prompt = session.prompt {
                Text(RulesText.plain(prompt.message ?? "Choose an action"))
                    .font(.callout)
                    .accessibilityIdentifier("rules-prompt-message")
                if !prompt.supported {
                    Text("This choice is not supported yet.").foregroundStyle(.secondary)
                } else {
                    buttons(prompt)
                }
            } else if expanded {
                Text(session.notice.isEmpty ? "Waiting for the other player…" : RulesText.plain(session.notice)).font(.callout)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: 400)
        .disabled(session.pendingRequest != nil)
        .onChange(of: session.prompt?.id) { _ in number = session.prompt?.min ?? 0; expanded = true }
    }

    @ViewBuilder private func buttons(_ prompt: RulesPrompt) -> some View {
        switch prompt.method {
        case "GAME_ASK":
            let mulligan = prompt.message?.localizedCaseInsensitiveContains("mulligan") == true
            HStack {
                answer(mulligan ? "Mulligan" : "Yes", .boolean(true))
                answer(mulligan ? "Keep Hand" : "No", .boolean(false))
            }
        case "GAME_GET_AMOUNT":
            Stepper("\(number)", value: $number, in: (prompt.min ?? 0)...max(prompt.min ?? 0, prompt.max ?? 0)).monospacedDigit()
            answer("Confirm", .number(number))
        case "GAME_CHOOSE_CHOICE", "GAME_CHOOSE_ABILITY":
            ScrollView(.horizontal) {
                HStack { ForEach(prompt.choices) { choice in answer(RulesText.plain(choice.label), .choice(choice.id)) } }
            }
        case "GAME_CHOOSE_PILE":
            Text("Pile selection will be available in a later build.").font(.caption)
        case "GAME_SELECT":
            Text("Play a card from your hand or tap a permanent to use it.").font(.caption).foregroundStyle(.secondary)
            answer("Next", .boolean(true))
        case "GAME_PLAY_MANA", "GAME_PLAY_XMANA":
            Text("Tap your mana sources on the battlefield.").font(.caption).foregroundStyle(.secondary)
            HStack {
                if prompt.method == "GAME_PLAY_XMANA" { answer("Done", .boolean(true)) }
                answer("Cancel", .boolean(false))
            }
        case "GAME_TARGET":
            Text("Choose a card or player.").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(prompt.cards ?? []) { card in answer(RulesText.plain(card.name ?? "Card"), .object(card.id)) }
                    ForEach(targetPlayers(prompt)) { player in answer(player.name, .object(player.id)) }
                }
            }
            if prompt.required != true { answer("Done", .boolean(false)) }
        default:
            Text("This choice is not supported yet.").font(.caption)
        }
    }

    private func targetPlayers(_ prompt: RulesPrompt) -> [RulesPlayer] {
        session.snapshot?.players.filter { prompt.targets?.contains($0.id) == true } ?? []
    }
    private func answer(_ title: String, _ value: RulesAnswer) -> some View {
        Button(title) { Task { await session.answer(value) } }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!session.canAnswer)
    }
}

enum RulesText {
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
