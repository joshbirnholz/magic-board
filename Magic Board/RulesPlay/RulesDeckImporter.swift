import Foundation
import CardService

enum RulesDeckImporter {
    static func parse(_ text: String) throws -> RulesDeck? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let groups = DeckParser.parse(deckList: text, autofix: true)
        var main: [RulesDeck.Card] = []
        var sideboard: [RulesDeck.Card] = []
        for group in groups {
            if group.name == DeckParser.CardGroup.GroupName.command.rawValue {
                throw Failure.message("Commander deck setup is not available in this build yet.")
            }
            if group.name == DeckParser.CardGroup.GroupName.maybeboard.rawValue { continue }
            let side = group.name == DeckParser.CardGroup.GroupName.sideboard.rawValue || group.name == DeckParser.CardGroup.GroupName.companion.rawValue
            for entry in group.cardCounts {
                let name: String
                let set: String?
                let number: String?
                switch entry.identifier {
                case .name(let value), .idName(_, let value): name = value; set = nil; number = nil
                case .nameSet(let value, let code): name = value; set = code; number = nil
                case .collectorNumberSet(let collector, let code, let value):
                    guard let value else { throw Failure.message("A card in this deck is missing its name.") }
                    name = value; set = code; number = collector
                default: throw Failure.message("Use a text deck list containing card names.")
                }
                guard (1...99).contains(entry.count) else { throw Failure.message("Card quantities must be between 1 and 99.") }
                let card = RulesDeck.Card(name: name, set: set, collectorNumber: number, count: entry.count)
                if side { sideboard.append(card) } else { main.append(card) }
            }
        }
        guard !main.isEmpty else { throw Failure.message("No main-deck cards were found in this list.") }
        guard main.reduce(0, { $0 + $1.count }) <= 500, sideboard.reduce(0, { $0 + $1.count }) <= 100 else {
            throw Failure.message("This deck is too large for this build.")
        }
        return RulesDeck(name: "Imported Deck", main: main, sideboard: sideboard)
    }
    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
    }
}
