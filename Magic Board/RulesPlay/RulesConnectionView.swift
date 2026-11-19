import SwiftUI
import UniformTypeIdentifiers
import CardService

struct RulesConnectionView: View {
    let open: (RulesPhoneAdapter) -> Void
    @StateObject private var session = RulesGameSession()
    @AppStorage("rules.bridgeAddress") private var address = ""
    @State private var key = ""
    @State private var transferred = false
    @State private var attemptedAutomaticConnection = false
    @AppStorage("rules.deckList") private var deckList = ""
    @State private var format = "Limited"
    @State private var showDeckImport = false
    /// Built-in, a pasted list, or JumpStart / Jump In packets chosen when the game starts.
    @AppStorage("rules.deckSource") private var deckSourceRaw = ""
    @AppStorage("rules.packetSet") private var packetSet = ""
    @State private var pendingStart: PendingStart?

    private enum PendingStart: Identifiable {
        case ai, human, join(RulesTable)
        var id: String {
            switch self { case .ai: return "ai"; case .human: return "human"; case .join(let table): return "join-" + table.id }
        }
    }

    private var source: RulesDeckSource { RulesDeckSource(rawValue: deckSourceRaw) ?? (deckList.isEmpty ? .builtIn : .list) }
    private var packetSets: [(code: String, name: String)] { RulesPackets.sets(for: source) }
    private var chosenPacketSet: String { packetSets.contains { $0.code == packetSet } ? packetSet : (packetSets.first?.code ?? "") }

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
                Text("Connect to the Magic Board bridge on your PC using its local or private network address, or a secure wss:// address.")
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
                        Button("Play Against AI") { begin(.ai) }
                            .disabled(session.pendingRequest != nil || session.snapshot != nil)
                            .accessibilityIdentifier("rules-start-ai")
                        Button("Create Two-Player Game") { begin(.human) }
                            .disabled(session.pendingRequest != nil)
                            .accessibilityIdentifier("rules-create-human")
                    }
                    // Waiting-game polling is background maintenance, not reconnecting or
                    // starting a game. Don't insert/remove a progress row every three seconds.
                    if session.isPerformingGameAction { ProgressView("Working…") }
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
                    Picker("Deck", selection: Binding(get: { source }, set: { deckSourceRaw = $0.rawValue })) {
                        ForEach(RulesDeckSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityIdentifier("rules-deck-source")
                    switch source {
                    case .builtIn:
                        Text("A simple white creature deck; the AI plays a copy.").font(.caption).foregroundStyle(.secondary)
                    case .list:
                        TextEditor(text: $deckList)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 120)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("rules-deck-list")
                        Button("Import Text File") { showDeckImport = true }
                        Text("Paste a text deck list. The AI plays a copy of it.").font(.caption).foregroundStyle(.secondary)
                    case .jumpStart, .jumpIn:
                        Picker("Set", selection: Binding(get: { chosenPacketSet }, set: { packetSet = $0 })) {
                            ForEach(packetSets, id: \.code) { Text($0.name).tag($0.code) }
                        }
                        .accessibilityIdentifier("rules-packet-set")
                        Text("When the game starts, choose two packets from three offers each; they become your deck. Against the AI, it gets two random packets of its own.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !source.usesPackets {
                        Picker("Format", selection: $format) {
                            ForEach(session.formats, id: \.self) { format in
                                Text(format.replacingOccurrences(of: "Constructed - ", with: "")).tag(format)
                            }
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
                        Button { begin(.join(table)) } label: {
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
        .sheet(item: $pendingStart) { start in
            RulesPacketPicker(source: source, set: chosenPacketSet) { deckText in
                pendingStart = nil
                guard let deckText else { return }
                perform(start, packetDeck: deckText)
            }
        }
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
        .onAppear {
            key = session.connectionKey
            guard !attemptedAutomaticConnection else { return }
            attemptedAutomaticConnection = true
            guard session.status == .disconnected,
                  !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !key.isEmpty else { return }
            session.connect(address: address, key: key)
        }
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

    /// Starts, creates or joins a game; packet decks are chosen first.
    private func begin(_ start: PendingStart) {
        if source.usesPackets {
            if case .join(let table) = start, let format = table.format, format != "Limited" {
                session.error = "JumpStart and Jump In packets need a Limited game. Choose a deck list to join this \(format) game."
                return
            }
            guard !chosenPacketSet.isEmpty else { session.error = "No \(source.rawValue) packets are available in this build."; return }
            pendingStart = start
        } else {
            perform(start, packetDeck: nil)
        }
    }

    private func perform(_ start: PendingStart, packetDeck: String?) {
        do {
            let deck: RulesDeck?
            let gameFormat: String
            if let packetDeck {
                deck = try RulesDeckImporter.parse(packetDeck)
                gameFormat = "Limited"
            } else {
                let tableFormat: String
                if case .join(let table) = start { tableFormat = table.format ?? "Limited" } else { tableFormat = format }
                deck = try preparedDeck(for: tableFormat)
                gameFormat = tableFormat
            }
            switch start {
            case .ai:
                // The AI brings its own two random packets in a JumpStart / Jump In game.
                let aiDeck = packetDeck == nil ? nil : RulesPackets.randomDeckList(source, set: chosenPacketSet).flatMap { try? RulesDeckImporter.parse($0) }
                Task { await session.startAiGame(deck: deck, format: gameFormat, aiDeck: aiDeck) }
            case .human:
                Task { await session.createHumanGame(deck: deck, format: gameFormat) }
            case .join(let table):
                Task { await session.join(table, deck: deck) }
            }
        } catch { session.error = error.localizedDescription }
    }

    private func preparedDeck(for format: String) throws -> RulesDeck? {
        guard source == .list else {
            if format != "Limited" { throw RulesDeckImporter.Failure.message("Import a deck to play this format, or use Limited with the built-in deck.") }
            return nil
        }
        let deck = try RulesDeckImporter.parse(deckList)
        // XMage refuses an undersized deck with no reason given ("could not seat you"), so say why.
        if let deck {
            let cards = deck.main.reduce(0) { $0 + $1.count }
            let minimum = format == "Limited" ? 40 : 60
            if cards < minimum {
                throw RulesDeckImporter.Failure.message("This deck has \(cards) card\(cards == 1 ? "" : "s"). \(format) needs at least \(minimum).")
            }
        }
        if deck == nil && format != "Limited" {
            throw RulesDeckImporter.Failure.message("Import a deck to play this format, or use Limited with the built-in deck.")
        }
        return deck
    }
}

/// The existing Phone Play board remains visible and interactive beneath engine choices.
enum RulesText {
    static func plain(_ text: String) -> String {
        // XMage puts the card name in its own <div> ("Choose mode…<div>Blessed Alliance</div>"):
        // keep it on its own line instead of running it into the sentence.
        text.replacingOccurrences(of: #"<\s*(br|/?div|/?p)[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n\s*\n+"#, with: "\n", options: .regularExpression)
            // XMage tags object names with an id suffix ("Summon: Fenrir [3fa]").
            .replacingOccurrences(of: #" \[[0-9a-f]{3}\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&bull;", with: "•")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// The printed name of a token XMage calls "<Name> Token" (nil for other cards).
    static func tokenName(_ card: RulesCard) -> String? {
        guard let name = card.name, name.hasSuffix(" Token") || card.typeLine?.contains("Token") == true else { return nil }
        return name.hasSuffix(" Token") ? String(name.dropLast(" Token".count)) : name
    }

    /// A card's type line as printed: XMage writes "Artifact  - Treasure", and leaves "Token" off
    /// tokens (the board draws the token frame from it).
    static func typeLine(_ card: RulesCard) -> String? {
        guard var type = card.typeLine.map(plain) else { return tokenName(card) == nil ? nil : "Token" }
        type = type.replacingOccurrences(of: #"\s+-\s+"#, with: " — ", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if tokenName(card) != nil, !type.contains("Token") {
            // "Legendary Artifact — Food" becomes "Legendary Token Artifact — Food".
            let supertypes = ["Legendary", "Snow", "Basic", "World"]
            var words = type.components(separatedBy: " ")
            let index = words.firstIndex { !supertypes.contains($0) } ?? words.count
            words.insert("Token", at: index)
            type = words.joined(separator: " ")
        }
        return type
    }

    /// A card's rules as the engine states them, worded the way current cards refer to themselves
    /// (XMage writes "{this}"): "this creature" / "this land"…, an Aura's or Equipment's subtype,
    /// an instant's or sorcery's name, a legendary card's short name, "this token", and "this card"
    /// where the ability works from the graveyard or hand.
    static func cardRules(_ text: String, name: String?, typeLine: String? = nil) -> String {
        let plain = plain(text)
        guard plain.contains("{this}") else { return plain }
        let reference = selfReference(name: name, typeLine: typeLine)
        var result = ""
        var rest = Substring(plain)
        while let range = rest.range(of: "{this}") {
            let before = rest[..<range.lowerBound]
            let after = rest[range.upperBound...]
            result += before
            var phrase = reference
            // Off the battlefield the card is just "this card" (unless it's named, like an instant).
            let offBattlefield = after.range(of: #"^ from (your|a|its owner's) (graveyard|hand|library)"#, options: .regularExpression) != nil
                || result.range(of: #"(Discard|Reveal|discard|reveal) $"#, options: .regularExpression) != nil
            if offBattlefield, phrase.hasPrefix("this ") { phrase = "this card" }
            // Sentence starts take a capital ("This creature gets +1/+1").
            let trimmed = result.trimmingCharacters(in: .whitespaces)
            if phrase.hasPrefix("this "), trimmed.isEmpty || [".", "\n", "—", ":", "\"", "“", "("].contains(where: { trimmed.hasSuffix($0) }) {
                phrase = "T" + phrase.dropFirst()
            }
            result += phrase
            rest = after
        }
        return result + rest
    }

    /// How a card refers to itself in its rules text.
    static func selfReference(name: String?, typeLine: String?) -> String {
        let name = name ?? ""
        let type = typeLine ?? ""
        let (types, subtypes): (String, String) = {
            let parts = type.components(separatedBy: "—")
            return (parts[0], parts.count > 1 ? parts[1] : "")
        }()
        if name.hasSuffix(" Token") || types.contains("Token") { return "this token" }
        if types.contains("Instant") || types.contains("Sorcery") { return name.isEmpty ? "this spell" : name }
        if types.contains("Legendary"), !name.isEmpty {
            if let comma = name.range(of: ",") { return String(name[..<comma.lowerBound]) }
            if let epithet = name.range(of: " the ") { return String(name[..<epithet.lowerBound]) }
            return name
        }
        if !types.contains("Creature") {
            for subtype in ["Aura", "Equipment", "Saga", "Vehicle", "Class", "Spacecraft", "Room", "Case", "Attraction", "Siege"]
            where subtypes.split(separator: " ").contains(Substring(subtype)) {
                return "this \(subtype)"
            }
        }
        for (word, phrase) in [("Creature", "this creature"), ("Planeswalker", "this planeswalker"), ("Battle", "this battle"),
                               ("Land", "this land"), ("Artifact", "this artifact"), ("Enchantment", "this enchantment")]
        where types.contains(word) { return phrase }
        if type.isEmpty, !name.isEmpty { return name }
        return "this permanent"
    }
}
