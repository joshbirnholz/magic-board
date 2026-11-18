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
                    Button("Connect") { session.connect(address: address, key: key) }
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || key.isEmpty)
                        .accessibilityIdentifier("rules-connect")
                    if session.hasRetainedSession {
                        Button("Connect as New Session") { session.connect(address: address, key: key, resume: false) }
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
struct RulesPromptBar: View {
    @ObservedObject var session: RulesGameSession
    var exit: (() -> Void)? = nil
    @State private var number = 0
    @State private var expanded = true
    @State private var amounts: [Int] = []
    @State private var choiceSearch = ""
    @State private var pile = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rules Game").font(.caption.bold())
                Spacer()
                if let state = session.snapshot {
                    Text("\(turnOwner(state)) · Turn \(state.turn) · \(RulesText.plain((state.step ?? "Starting Game").replacingOccurrences(of: "_", with: " ").capitalized))")
                        .font(.caption).monospacedDigit()
                }
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                    .accessibilityLabel(expanded ? "Collapse game prompt" : "Expand game prompt")
            }
            ForEach(session.snapshot?.players ?? []) { player in
                if let counters = player.counters, !counters.isEmpty {
                    Text("\(player.id == session.snapshot?.playerId ? "You" : player.name): \(counters.map { "\($0.name) \($0.count)" }.joined(separator: " · "))")
                        .font(.caption).monospacedDigit()
                }
            }
            if session.status == .disconnected {
                Text(session.notice).font(.callout)
                Button("Reconnect") {
                    let address = UserDefaults.standard.string(forKey: "rules.bridgeAddress") ?? ""
                    session.connect(address: address, key: session.connectionKey)
                }
            } else if let result = session.result {
                Text(RulesText.plain(result)).font(.headline)
                if let exit { Button("Exit Game", action: exit).buttonStyle(.borderedProminent) }
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
                Text(waitingMessage).font(.callout)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: 400)
        .disabled(session.pendingRequest != nil)
        .onAppear(perform: resetInputs)
        .onChange(of: session.prompt?.id) { _ in resetInputs() }
    }

    private func turnOwner(_ state: RulesSnapshot) -> String {
        guard let active = state.activePlayerId else { return "Preparing" }
        return active == state.playerId ? "Your turn" : "\(state.activePlayer ?? "Opponent")'s turn"
    }

    private var waitingMessage: String {
        guard let state = session.snapshot else { return "Waiting for the game…" }
        let mine = state.players.first { $0.id == state.playerId }?.name
        if let priority = state.priorityPlayer, !priority.isEmpty, priority != mine { return "Waiting for \(priority)…" }
        return "Resolving game actions…"
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
            if prompt.choices.count > 12 {
                TextField("Search choices", text: $choiceSearch)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }
            ScrollView(.horizontal) {
                LazyHStack {
                    ForEach(prompt.choices.filter { choiceSearch.isEmpty || $0.label.localizedCaseInsensitiveContains(choiceSearch) }) { choice in
                        answer(RulesText.plain(choice.label), .choice(choice.id))
                    }
                }
            }
        case "GAME_CHOOSE_PILE":
            Picker("Pile", selection: $pile) {
                Text("Pile 1 (\(prompt.cards?.count ?? 0))").tag(0)
                Text("Pile 2 (\(prompt.secondPile?.count ?? 0))").tag(1)
            }.pickerStyle(.segmented)
            cardRow(pile == 0 ? prompt.cards ?? [] : prompt.secondPile ?? [], selectable: false)
            answer("Choose Pile \(pile + 1)", .boolean(pile == 0))
        case "GAME_GET_MULTI_AMOUNT": distribution(prompt)
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
            if let cards = prompt.cards, !cards.isEmpty { cardRow(cards, selectable: true) }
            HStack { ForEach(targetPlayers(prompt)) { player in answer(player.name, .object(player.id)) } }
            if prompt.required != true { answer("Done", .boolean(false)) }
        default:
            Text("This choice is not supported yet.").font(.caption)
        }
    }

    private func resetInputs() {
        number = session.prompt?.min ?? 0
        amounts = session.prompt?.amounts?.map(\.defaultValue) ?? []
        choiceSearch = ""
        pile = 0
        expanded = true
    }

    private func cardRow(_ cards: [RulesCard], selectable: Bool) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(cards) { card in
                    if selectable {
                        Button { Task { await session.answer(.object(card.id)) } } label: {
                            RulesChoiceCardFace(card: card)
                        }.buttonStyle(.plain).disabled(!session.canAnswer)
                    } else { RulesChoiceCardFace(card: card) }
                }
            }
        }.frame(height: cards.isEmpty ? 24 : 170)
    }

    @ViewBuilder private func distribution(_ prompt: RulesPrompt) -> some View {
        let rows = prompt.amounts ?? []
        let values = amounts.count == rows.count ? amounts : rows.map(\.defaultValue)
        let total = values.reduce(0, +)
        let minimum = prompt.min ?? 0
        let maximum = prompt.max ?? 0
        ScrollView {
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    Stepper(value: Binding(get: {
                        amounts.indices.contains(index) ? amounts[index] : row.defaultValue
                    }, set: { value in
                        if amounts.count != rows.count { amounts = rows.map(\.defaultValue) }
                        amounts[index] = value
                    }), in: row.min...max(row.min, row.max)) {
                        Text("\(RulesText.plain(row.label)): \(values[index])").font(.callout).monospacedDigit()
                    }
                }
            }
        }.frame(maxHeight: 160)
        Text("Total: \(total) · allowed \(minimum)–\(maximum)").font(.caption).monospacedDigit()
        HStack {
            answer("Confirm", .amounts(values)).disabled(total < minimum || total > maximum)
            if prompt.canCancel == true { answer("Cancel", .boolean(false)) }
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

/// Shares Phone Play's Scryfall-backed card face for engine card and pile choices.
private struct RulesChoiceCardFace: View {
    let card: RulesCard
    @State private var instance: CardInstance?

    var body: some View {
        VStack(spacing: 4) {
            if let instance {
                PhoneHandCardFace(card: instance, height: 128, faceDown: card.faceDown)
            } else {
                RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.2)).frame(width: 92, height: 128)
            }
            Text(RulesText.plain(card.name ?? "Card")).font(.caption).lineLimit(2)
        }
        .frame(width: 96)
        .accessibilityLabel(card.faceDown ? "Face-down card" : RulesText.plain(card.name ?? "Card"))
        .task(id: card.id) {
            let catalog = RulesCardCatalog.shared
            let cached = await catalog.localCard(card)
            if let model = cached ?? (try? RulesPhoneAdapter.placeholder(name: card.name ?? "Card", typeLine: card.typeLine ?? "", rules: card.rules, manaCost: card.manaCost)) {
                instance = CardInstance(card: model, center: nil, ownerIdentifier: .a)
            }
            if cached == nil, let loaded = await catalog.card(card), !Task.isCancelled {
                instance = CardInstance(card: loaded, center: nil, ownerIdentifier: .a)
            }
        }
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
