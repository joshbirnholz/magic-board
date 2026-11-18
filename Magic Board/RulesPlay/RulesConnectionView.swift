import SwiftUI
import UniformTypeIdentifiers
import CardService

struct RulesConnectionView: View {
    let open: (RulesPhoneAdapter) -> Void
    @StateObject private var session = RulesGameSession()
    @AppStorage("rules.bridgeAddress") private var address = ""
    @State private var key = ""
    @State private var transferred = false
    @AppStorage("rules.deckList") private var deckList = ""
    @State private var format = "Limited"
    @State private var showDeckImport = false

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
                        Button("Play Against AI") {
                            do {
                                let deck = try preparedDeck(for: format)
                                Task { await session.startAiGame(deck: deck, format: format) }
                            } catch { session.error = error.localizedDescription }
                        }
                            .disabled(session.pendingRequest != nil || session.snapshot != nil)
                            .accessibilityIdentifier("rules-start-ai")
                        Button("Create Two-Player Game") {
                            do {
                                let deck = try preparedDeck(for: format)
                                Task { await session.createHumanGame(deck: deck, format: format) }
                            } catch { session.error = error.localizedDescription }
                        }
                            .disabled(session.pendingRequest != nil)
                            .accessibilityIdentifier("rules-create-human")
                    }
                    if session.pendingRequest != nil { ProgressView("Working…") }
                    Button("Disconnect") { session.disconnect() }
                } else {
                    Button(session.hasRetainedSession ? "Reconnect" : "Connect") { session.connect(address: address, key: key) }
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || key.isEmpty)
                        .accessibilityIdentifier("rules-connect")
                    if session.hasRetainedSession {
                        Button("Connect as New Session") { session.connect(address: address, key: key, resume: false) }
                            .accessibilityIdentifier("rules-connect-new")
                    }
                }
            }
            if session.tableId == nil {
                Section {
                    DisclosureGroup("Deck") {
                        TextEditor(text: $deckList)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 120)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("rules-deck-list")
                        Button("Import Text File") { showDeckImport = true }
                        if !deckList.isEmpty { Button("Use Built-in Deck") { deckList = ""; format = "Limited" } }
                        Text("Paste a text deck list, or leave it empty to use the built-in white creature deck. The AI uses a copy of your deck.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Format", selection: $format) {
                        ForEach(session.formats, id: \.self) { format in
                            Text(format.replacingOccurrences(of: "Constructed - ", with: "")).tag(format)
                        }
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
                            do {
                                let deck = try preparedDeck(for: table.format ?? "Limited")
                                Task { await session.join(table, deck: deck) }
                            } catch { session.error = error.localizedDescription }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Game \(table.id.prefix(8))")
                                    if let format = table.format {
                                        Text(format.replacingOccurrences(of: "Constructed - ", with: "")).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
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
        .fileImporter(isPresented: $showDeckImport, allowedContentTypes: [.plainText], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 256_000 else { throw RulesDeckImporter.Failure.message("Choose a text deck list smaller than 256 KB.") }
                let text = try String(contentsOf: url, encoding: .utf8)
                _ = try RulesDeckImporter.parse(text)
                deckList = text
            } catch { session.error = error.localizedDescription }
        }
        .onAppear { key = session.connectionKey }
        .onChange(of: session.formats) { formats in
            if !formats.contains(format) { format = formats.contains("Limited") ? "Limited" : (formats.first ?? "Limited") }
        }
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

    private func preparedDeck(for format: String) throws -> RulesDeck? {
        let deck = try RulesDeckImporter.parse(deckList)
        if deck == nil && format != "Limited" {
            throw RulesDeckImporter.Failure.message("Import a deck to play this format, or use Limited with the built-in deck.")
        }
        return deck
    }
}

/// The existing Phone Play board remains visible and interactive beneath engine choices.
enum RulesText {
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
