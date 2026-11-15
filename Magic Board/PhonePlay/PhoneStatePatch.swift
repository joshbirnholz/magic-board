import Foundation

/// Existing controls write observable fields directly. Send only those edits,
/// rather than replacing another player's unrelated changes with an old snapshot.
struct PhoneStatePatch: Codable {
    struct CardEdit: Codable {
        var card: CardInstance
        var fields: Set<String>
    }
    struct ZoneEdit: Codable {
        var player: Player.Identifier?
        var location: Pile.Location?
        var added: [UUID]
        var removed: [UUID]
        var order: [UUID]
    }
    struct PlayerEdit: Codable {
        var player: Player.Identifier
        var life: Int?
        var name: String?
    }
    struct RevealEdit: Codable {
        var player: Player.Identifier
        var location: Pile.Location
        var revealed: Bool
    }
    var cards: [CardEdit] = []
    var zones: [ZoneEdit] = []
    var players: [PlayerEdit] = []
    var reveals: [RevealEdit] = []

    var isEmpty: Bool { cards.isEmpty && zones.isEmpty && players.isEmpty && reveals.isEmpty }

    init(before: PhoneGame, after: GameState) throws {
        let oldCards = before.cards
        for card in after.allCards.values {
            let old = oldCards[card.uuid]
            let oldFields = try old.map { try Self.jsonFields($0) } ?? [:]
            let newFields = try Self.jsonFields(card)
            let fields = Set(newFields.keys.filter {
                $0 != "center" && $0 != "previouslyViewedFocusIndex" &&
                !Self.equal(oldFields[$0], newFields[$0])
            })
            if !fields.isEmpty { cards.append(CardEdit(card: card, fields: fields)) }
        }
        func zone(_ old: OrderedSet<CardInstance>, _ new: OrderedSet<CardInstance>, player: Player.Identifier?, location: Pile.Location?) -> ZoneEdit? {
            let from = old.map(\.uuid), to = new.map(\.uuid)
            guard from != to else { return nil }
            return ZoneEdit(player: player, location: location, added: to.filter { !from.contains($0) }, removed: from.filter { !to.contains($0) }, order: to)
        }
        if let edit = zone(before.state.battlefield.value, after.battlefield.value, player: nil, location: nil) { zones.append(edit) }
        for (old, new) in zip(before.state.allPlayers, after.allPlayers) {
            let life = old.life.value == new.life.value ? nil : new.life.value
            let name = old.name.value == new.name.value ? nil : new.name.value
            if life != nil || name != nil { players.append(.init(player: new.identifier, life: life, name: name)) }
            for (oldPile, newPile) in zip(old.allPiles, new.allPiles) {
                if let edit = zone(oldPile.cards.value, newPile.cards.value, player: new.identifier, location: newPile.location) { zones.append(edit) }
                if oldPile.isTopCardRevealed.value != newPile.isTopCardRevealed.value {
                    reveals.append(.init(player: new.identifier, location: newPile.location, revealed: newPile.isTopCardRevealed.value))
                }
            }
        }
    }

    func apply(to game: inout PhoneGame) {
        var known = game.cards
        for edit in cards where known[edit.card.uuid] == nil { known[edit.card.uuid] = edit.card }
        // Move membership first; property changes follow so zone-reset effects
        // cannot overwrite a player's explicit tap/counter/representation edits.
        for edit in zones {
            let relay = edit.player.flatMap { player in edit.location.map { game.state[player: player][$0].cards } } ?? game.state.battlefield
            for id in edit.removed { if let card = known[id] { relay.mutate { $0.remove(card) } } }
        }
        for edit in zones {
            let relay = edit.player.flatMap { player in edit.location.map { game.state[player: player][$0].cards } } ?? game.state.battlefield
            for id in edit.added {
                guard let card = known[id] else { continue }
                game.remove(card)
                relay.mutate { $0.append(card) }
            }
            let current = relay.value.contents
            let ordered = edit.order.compactMap { id in current.first { $0.uuid == id } }
            let extra = current.filter { !edit.order.contains($0.uuid) }
            relay.accept(OrderedSet(ordered + extra))
        }
        // A permanent removed without entering another zone also loses attachments.
        let fieldIDs = Set(game.state.battlefield.value.map(\.uuid))
        game.attachments = game.attachments.filter { fieldIDs.contains($0.key) && fieldIDs.contains($0.value) }
        for edit in cards {
            known[edit.card.uuid]?.applyValues(from: edit.card, fields: edit.fields)
        }
        for edit in players {
            if let life = edit.life { game.state[player: edit.player].life.accept(life) }
            if let name = edit.name { game.state[player: edit.player].name.accept(name) }
        }
        for edit in reveals { game.state[player: edit.player][edit.location].isTopCardRevealed.accept(edit.revealed) }
    }

    private static func jsonFields(_ card: CardInstance) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any] ?? [:]
    }
    private static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (let lhs as NSObject, let rhs as NSObject): return lhs.isEqual(rhs)
        default: return false
        }
    }
}
