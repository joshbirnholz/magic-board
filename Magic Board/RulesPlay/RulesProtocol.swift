import Foundation

struct RulesDeck: Codable {
    struct Card: Codable {
        let name: String
        let set: String?
        let collectorNumber: String?
        let count: Int
    }
    let name: String
    let main: [Card]
    let sideboard: [Card]
}

struct RulesTable: Decodable, Identifiable {
    let id: String
    let name: String
    let players: Int
    let capacity: Int
    let format: String?
}

/// Rules-only presentation values. These never enter PhoneGame or its editable state patches.
struct RulesCard: Decodable, Identifiable, Equatable {
    struct Counter: Decodable, Equatable { let name: String; let count: Int }
    let id: String
    let name: String?
    let set: String?
    let collectorNumber: String?
    let faceDown: Bool
    let transformed: Bool
    let power: String?
    let toughness: String?
    let rules: String?
    let tapped: Bool?
    let damage: Int?
    let summoningSick: Bool?
    let attachedTo: String?
    let ability: Bool?
    let typeLine: String?
    let manaCost: String?
    let colors: [String]?
    let targets: [String]?
    /// Stack objects only: the bridge's best inference of who controls it.
    var controllerId: String? = nil
    /// Physical source of a stack ability; distinct from the ability's own id and targets.
    var sourceId: String? = nil
    /// Chosen X reported by XMage's variable-cost metadata; zero is meaningful, nil is unknown.
    var chosenX: Int? = nil
    /// Current keyword abilities from engine permanent icons, including gained abilities.
    var keywords: [String]? = nil
    let counters: [Counter]
}

struct RulesPlayer: Decodable, Identifiable {
    let id: String
    let name: String
    let life: Int
    let handCount: Int
    let libraryCount: Int
    let battlefield: [RulesCard]
    let graveyard: [RulesCard]
    let exile: [RulesCard]
    let counters: [RulesCard.Counter]?
    /// Unspent mana by symbol (W, U, B, R, G, C); nil from older bridges.
    var manaPool: [String: Int]? = nil

    /// The floating mana as symbols in WUBRG order, e.g. "{B}{C}{C}".
    var floatingMana: String {
        ["W", "U", "B", "R", "G", "C"].map { symbol in String(repeating: "{\(symbol)}", count: max(0, manaPool?[symbol] ?? 0)) }.joined()
    }
}

struct RulesSnapshot: Decodable {
    struct CardGroup: Decodable, Identifiable {
        let name: String
        let cards: [RulesCard]
        var id: String { name + ":" + cards.map(\.id).joined(separator: ",") }
    }
    struct Priority: Decodable {
        let untilNextTurn: Bool
        let untilEndStep: Bool
        let untilNextMain: Bool
        let untilYourTurn: Bool
        let untilStackResolved: Bool
    }
    struct CombatGroup: Decodable {
        // XMage can retain attackers briefly after their defending permanent leaves play.
        let defenderId: String?
        let attackers: [String]
        let blockers: [String]
    }
    let gameId: String
    let playerId: String
    let revision: Int
    let turn: Int
    let phase: String?
    let step: String?
    let activePlayer: String?
    let activePlayerId: String?
    let priorityPlayer: String?
    let hand: [RulesCard]
    let stack: [RulesCard]
    let players: [RulesPlayer]
    let playableIds: [String]
    let combat: [CombatGroup]?
    var priority: Priority? = nil
    /// Information XMage permits this seat to inspect, separate from answerable prompts.
    var revealed: [CardGroup]? = nil
    var lookedAt: [CardGroup]? = nil
}

enum RulesPriorityAction: String, Encodable {
    case hold, release, cancelAutoPass, resolveStack, nextMain, endStep, yourTurn
}

struct RulesPrompt: Decodable, Identifiable {
    struct Source: Decodable, Identifiable {
        let id: String
        let name: String
    }

    struct Choice: Decodable, Identifiable { let id: String; let label: String }
    struct Amount: Decodable {
        let label: String
        let min: Int
        let max: Int
        let defaultValue: Int
    }
    let id: String
    let method: String
    let revision: Int
    let message: String?
    let min: Int?
    let max: Int?
    let required: Bool?
    let supported: Bool
    let choices: [Choice]
    let cards: [RulesCard]?
    let targets: [String]?
    let secondPile: [RulesCard]?
    let amounts: [Amount]?
    let canCancel: Bool?
    var queryType: String? = nil
    var targetZone: String? = nil
    var subMessage: String? = nil
    var source: Source? = nil
    var specialActionAvailable: Bool? = nil
    var specialActionLabel: String? = nil
    var selectionIds: [String]? = nil
    var selectedIds: [String]? = nil

    func isCardSelectable(_ id: String) -> Bool {
        guard let selectionIds else { return true } // older bridges do not provide this metadata
        return selectionIds.contains(id) || selectedIds?.contains(id) == true
    }
}

enum RulesAnswer: Encodable {
    case boolean(Bool), object(String), number(Int), choice(String), amounts([Int])
    case specialAction, cancel
    var kind: String {
        switch self {
        case .boolean: return "boolean"
        case .object: return "uuid"
        case .number: return "integer"
        case .choice: return "string"
        case .amounts: return "amounts"
        case .specialAction: return "special"
        case .cancel: return "cancel"
        }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .boolean(let value): try container.encode(value)
        case .object(let value), .choice(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .amounts(let values): try container.encode(values)
        case .specialAction, .cancel: try container.encode(true)
        }
    }
}

struct RulesCommand: Encodable {
    var type: String
    var protocolVersion: Int? = nil
    var resumeToken: String? = nil
    var requestId: String? = nil
    var tableId: String? = nil
    var promptId: String? = nil
    var revision: Int? = nil
    var kind: String? = nil
    var value: RulesAnswer? = nil
    var deck: RulesDeck? = nil
    /// createAiGame only: the AI's own deck (JumpStart / Jump In packets). Without it the AI plays a copy of `deck`.
    var aiDeck: RulesDeck? = nil
    var format: String? = nil
    var priorityAction: RulesPriorityAction? = nil
    var autoOrderTriggers: Bool? = nil
}

enum RulesEndpoint {
    static func parse(_ input: String) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.invalidAddress }
        let candidate = text.contains("://") ? text : "ws://" + text
        guard var components = URLComponents(string: candidate),
              ["ws", "wss"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { throw Failure.invalidAddress }
        // Secure endpoints normally terminate at an HTTPS proxy (port 443). Keep its
        // implicit port intact; only direct, unencrypted bridge connections default to 17180.
        if components.port == nil, components.scheme == "ws" { components.port = 17180 }
        guard (1...65535).contains(components.port ?? 443), let url = components.url else { throw Failure.invalidAddress }
        return url
    }
    enum Failure: LocalizedError {
        case invalidAddress
        var errorDescription: String? { "Enter a server address such as ws://my-pc.local:17180." }
    }
}

/// Display timing for actual engine transitions. Details (targets, art, mana taps) may enrich the
/// current action immediately; a later action cannot erase it before it has been readable.
struct RulesPresentationClock {
    private(set) var previous: RulesSnapshot?
    private(set) var deadline: TimeInterval = 0
    private var currentHold: TimeInterval = 0
    private var acknowledgedRevision: Int?

    mutating func reset() { previous = nil; deadline = 0; currentHold = 0; acknowledgedRevision = nil }

    mutating func visible(revision: Int, now: TimeInterval) {
        guard previous?.revision == revision, acknowledgedRevision != revision else { return }
        acknowledgedRevision = revision
        deadline = max(deadline, now + currentHold)
    }

    func delay(before next: RulesSnapshot, now: TimeInterval) -> TimeInterval {
        guard let previous, previous.gameId == next.gameId, next.revision > previous.revision,
              !Self.isDetailUpdate(previous, next) else { return 0 }
        return max(0, deadline - now)
    }

    mutating func presented(_ next: RulesSnapshot, now: TimeInterval) {
        defer { previous = next }
        guard let previous, previous.gameId == next.gameId else { deadline = 0; currentHold = 0; acknowledgedRevision = nil; return }
        guard next.revision > previous.revision else { return }
        let oldStack = Set(previous.stack.map(\.id)), newStack = Set(next.stack.map(\.id))
        let duration: TimeInterval
        if !newStack.subtracting(oldStack).isEmpty {
            duration = 0.9
        } else if !oldStack.subtracting(newStack).isEmpty {
            duration = 0.55
        } else if Self.targets(previous) != Self.targets(next), !next.stack.isEmpty {
            duration = 0.85
        } else if Self.battlefield(previous) != Self.battlefield(next) || Self.life(previous) != Self.life(next) {
            duration = 0.5
        } else if previous.turn != next.turn || previous.activePlayerId != next.activePlayerId {
            duration = 0.4
        } else if previous.hand.count != next.hand.count || previous.players.map(\.handCount) != next.players.map(\.handCount) {
            duration = 0.3
        } else {
            duration = 0
        }
        currentHold = duration > 0 ? duration : max(0, deadline - now)
        deadline = max(deadline, now + duration)
    }

    private static func targets(_ state: RulesSnapshot) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: state.stack.map { ($0.id, $0.targets ?? []) })
    }
    private static func life(_ state: RulesSnapshot) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: state.players.map { ($0.id, $0.life) })
    }
    private static func battlefield(_ state: RulesSnapshot) -> [String: String] {
        Dictionary(uniqueKeysWithValues: state.players.flatMap(\.battlefield).map {
            ($0.id, "\($0.power ?? "")/\($0.toughness ?? ""):\($0.damage ?? 0)")
        })
    }
    private static func isDetailUpdate(_ old: RulesSnapshot, _ next: RulesSnapshot) -> Bool {
        old.turn == next.turn && old.activePlayerId == next.activePlayerId && old.step == next.step
            && Set(old.stack.map(\.id)) == Set(next.stack.map(\.id))
            && battlefield(old) == battlefield(next) && life(old) == life(next)
            && old.hand.count == next.hand.count && old.players.map(\.handCount) == next.players.map(\.handCount)
            && old.players.map(\.libraryCount) == next.players.map(\.libraryCount)
    }
}
