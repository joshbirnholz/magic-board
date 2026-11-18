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
}

struct RulesSnapshot: Decodable {
    struct Priority: Decodable {
        let untilNextTurn: Bool
        let untilEndStep: Bool
        let untilNextMain: Bool
        let untilYourTurn: Bool
        let untilStackResolved: Bool
    }
    struct CombatGroup: Decodable {
        let defenderId: String
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
}

enum RulesPriorityAction: String, Encodable {
    case hold, release, cancelAutoPass, resolveStack, nextMain, endStep, yourTurn
}

struct RulesPrompt: Decodable, Identifiable {
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
    var subMessage: String? = nil
    var specialActionAvailable: Bool? = nil
    var specialActionLabel: String? = nil
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
        if components.port == nil { components.port = 17180 }
        guard let port = components.port, (1...65535).contains(port), let url = components.url else { throw Failure.invalidAddress }
        return url
    }
    enum Failure: LocalizedError {
        case invalidAddress
        var errorDescription: String? { "Enter a server address such as ws://my-pc.local:17180." }
    }
}
