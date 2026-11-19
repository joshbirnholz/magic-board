import SwiftUI
import CardService

/// Where a Rules game's deck comes from, chosen on the Rules Game page.
enum RulesDeckSource: String, CaseIterable, Identifiable {
    case builtIn = "Built-in"
    case list = "Deck List"
    case jumpStart = "JumpStart"
    case jumpIn = "Jump In"
    var id: String { rawValue }
    var usesPackets: Bool { self == .jumpStart || self == .jumpIn }
}

/// JumpStart and Jump In for Rules games: offers, the two-packet deck, and a random one for the AI.
/// Uses the same bundled packets and deck builders as Phone Play's packet games.
enum RulesPackets {
    static var library: OfflineGameLibrary { .shared }

    static func sets(for source: RulesDeckSource) -> [(code: String, name: String)] {
        switch source {
        case .jumpStart: return library.jumpStartSets
        case .jumpIn: return library.jumpInSetOptions.map { ($0, $0 == "ALL" ? "All Jump In Sets" : $0) }
        default: return []
        }
    }

    /// Three offers whose display names are all different and differ from every name already shown
    /// (the first round's offers), so variants such as "Vampires 1" and "Vampires 4" never both appear.
    static func offers(_ source: RulesDeckSource, set: String, first: String?, shown: [String] = []) -> [String] {
        let shownNames = Set((shown + [first].compactMap { $0 }).map(OfflineGameLibrary.packetDisplayName))
        switch source {
        case .jumpStart:
            let pool = library.games.filter { $0.kind == "JumpStart" && ($0.setCode ?? "JMP") == set }.map(\.name)
            return uniqueOffers(pool.shuffled(), excluding: shownNames)
        case .jumpIn:
            // Jump In's offers follow colour rules, so redraw until one has no repeated names.
            var best: [String] = []
            for _ in 0..<40 {
                let draw = uniqueOffers(library.jumpInPackets(set: set, first: first), excluding: shownNames)
                if draw.count > best.count { best = draw }
                if best.count >= 3 { break }
            }
            return best
        default: return []
        }
    }

    /// The first three candidates with distinct display names not in `excluding`.
    static func uniqueOffers(_ candidates: [String], excluding: Set<String>, count: Int = 3) -> [String] {
        var seen = excluding
        var result: [String] = []
        for name in candidates where result.count < count {
            if seen.insert(OfflineGameLibrary.packetDisplayName(name)).inserted { result.append(name) }
        }
        return result
    }

    static func deckList(_ source: RulesDeckSource, set: String, first: String, second: String) -> String? {
        switch source {
        case .jumpStart: return library.jumpStartDeck(first: first, second: second)
        case .jumpIn: return library.jumpInDeck(set: set, first: first, second: second)
        default: return nil
        }
    }

    /// A packet's colours ("W", "U"…), from its mana symbols; colourless packets have none.
    static func colors(_ source: RulesDeckSource, set: String, name: String) -> Set<String> {
        let symbols = library.packetColorSymbols(kind: kind(source), set: set, name: name)
        return Set(["W", "U", "B", "R", "G"].filter { symbols.contains("{\($0)}") })
    }

    /// The AI drafts like a player: a packet from its first three offers, then one from three more,
    /// keeping to two colours when it can (Josh: "limit itself to a two color deck when possible").
    static func aiSecondPick(firstColors: Set<String>, offers: [(name: String, colors: Set<String>)]) -> String? {
        guard !offers.isEmpty else { return nil }
        let fewest = offers.map { firstColors.union($0.colors).count }.min() ?? 0
        // Any offer that keeps the deck to two colours is fine; otherwise the fewest colours possible.
        let limit = max(2, fewest)
        return offers.filter { firstColors.union($0.colors).count <= limit }.randomElement()?.name
    }

    /// The AI's own two packets, drafted from its own offers.
    static func randomDeckList(_ source: RulesDeckSource, set: String) -> String? {
        for _ in 0..<5 {
            // First pick: prefer a one- or two-colour packet, so a two-colour deck stays possible.
            let firstOffers = offers(source, set: set, first: nil)
            guard let first = (firstOffers.filter { colors(source, set: set, name: $0).count <= 2 }.randomElement() ?? firstOffers.randomElement()) else { continue }
            let secondOffers = offers(source, set: set, first: first, shown: firstOffers).filter { $0 != first }
                .map { (name: $0, colors: colors(source, set: set, name: $0)) }
            guard let second = aiSecondPick(firstColors: colors(source, set: set, name: first), offers: secondOffers),
                  let deck = deckList(source, set: set, first: first, second: second) else { continue }
            return deck
        }
        return nil
    }

    static func kind(_ source: RulesDeckSource) -> String { source == .jumpIn ? "Jump In" : "JumpStart" }
}

/// Choose two packets, three offers at a time, like Phone Play's packet draft (and Arena's
/// JumpStart event). Calls `done` with the combined deck list, or nil when cancelled.
struct RulesPacketPicker: View {
    let source: RulesDeckSource
    let set: String
    let done: (String?) -> Void
    @State private var first: String?
    @State private var offers: [String] = []
    @State private var firstOffers: [String] = []
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 10) {
                    if let first {
                        Text("First packet: \(OfflineGameLibrary.packetDisplayName(first))").font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(offers, id: \.self) { name in
                            Button { choose(name) } label: {
                                PacketChoiceCard(frontCardURL: RulesPackets.library.packetFrontCardURL(kind: RulesPackets.kind(source), set: set, name: name),
                                                 title: OfflineGameLibrary.packetDisplayName(name),
                                                 manaSymbols: RulesPackets.library.packetColorSymbols(kind: RulesPackets.kind(source), set: set, name: name))
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: (proxy.size.width - 64) / 3)
                            .accessibilityIdentifier("rules-packet-choice")
                        }
                    }
                    .frame(maxHeight: max(120, proxy.size.height - 24))
                    if let failure { Text(failure).foregroundStyle(.red).font(.callout) }
                }
                .padding(.horizontal, 16)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .navigationTitle(first == nil ? "Choose First Packet" : "Choose Second Packet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done(nil) } } }
        }
        .onAppear { if offers.isEmpty { offers = RulesPackets.offers(source, set: set, first: nil); firstOffers = offers } }
        .interactiveDismissDisabled()
    }

    private func choose(_ name: String) {
        guard let first else {
            first = name
            offers = RulesPackets.offers(source, set: set, first: name, shown: firstOffers).filter { $0 != name }
            return
        }
        if let deck = RulesPackets.deckList(source, set: set, first: first, second: name) { done(deck) }
        else { failure = "Those two packets couldn't be combined. Choose another." }
    }
}
