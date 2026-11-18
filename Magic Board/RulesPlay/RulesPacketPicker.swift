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

    static func offers(_ source: RulesDeckSource, set: String, first: String?) -> [String] {
        switch source {
        case .jumpStart: return library.jumpStartOffers(set: set, excluding: first)
        case .jumpIn: return Array(library.jumpInPackets(set: set, first: first).prefix(3))
        default: return []
        }
    }

    static func deckList(_ source: RulesDeckSource, set: String, first: String, second: String) -> String? {
        switch source {
        case .jumpStart: return library.jumpStartDeck(first: first, second: second)
        case .jumpIn: return library.jumpInDeck(set: set, first: first, second: second)
        default: return nil
        }
    }

    /// Two random packets, as the AI's own deck.
    static func randomDeckList(_ source: RulesDeckSource, set: String) -> String? {
        for _ in 0..<5 {
            guard let first = offers(source, set: set, first: nil).randomElement(),
                  let second = offers(source, set: set, first: first).filter({ $0 != first }).randomElement(),
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
        .onAppear { if offers.isEmpty { offers = RulesPackets.offers(source, set: set, first: nil) } }
        .interactiveDismissDisabled()
    }

    private func choose(_ name: String) {
        guard let first else {
            first = name
            offers = RulesPackets.offers(source, set: set, first: name).filter { $0 != name }
            return
        }
        if let deck = RulesPackets.deckList(source, set: set, first: first, second: name) { done(deck) }
        else { failure = "Those two packets couldn't be combined. Choose another." }
    }
}
