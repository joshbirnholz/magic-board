import Foundation

struct PhoneCardGroup: Identifiable {
    let cards: [CardInstance]
    var id: UUID { cards[0].uuid }
    var top: CardInstance { cards[0] }
}

enum PhoneBattlefieldLayout {
    /// A small board starts large. Dense boards stop shrinking and use row pages.
    static func cardExtent(screenWidth: CGFloat, screenHeight: CGFloat, groups: Int) -> CGFloat {
        let comfortable = min(230, max(88, screenHeight * 0.32))
        let widthFit = max(200, screenWidth - comfortable) / (CGFloat(max(1, min(groups, 12))) + 0.35)
        return max(64, max(comfortable * 0.62, min(comfortable, widthFit)))
    }

    struct PackedRow {
        let centers: [CGFloat]
        let width: CGFloat
    }
    /// Each group's attachments reserve space once, just before that group, rather than
    /// multiplying the widest attachment fan across every permanent on both sides.
    static func packedRow(extras: [CGFloat], availableWidth: CGFloat, cellWidth: CGFloat, rotationSpill: CGFloat) -> PackedRow {
        guard !extras.isEmpty else { return PackedRow(centers: [], width: 0) }
        let extra = extras.reduce(0, +)
        let spacing = extras.count > 1 ? min(cellWidth, max(cellWidth * 0.45,
            (availableWidth - cellWidth - extra + 20) / CGFloat(extras.count - 1))) : cellWidth
        var center = rotationSpill + 250
        var centers: [CGFloat] = []
        for (index, fan) in extras.enumerated() {
            if index > 0 { center += spacing }
            center += fan
            centers.append(center)
        }
        return PackedRow(centers: centers, width: cellWidth + CGFloat(extras.count - 1) * spacing + extra - 20)
    }

    /// Identical non-land permanents with at least this many copies always stack.
    static let stackThreshold = 5

    /// Creatures in the middle, other permanents to their left, and planeswalkers, sagas and battles
    /// in their own lane on the right (as on Arena).
    enum Row { case creatures, support, side }

    static func row(for card: CardInstance) -> Row {
        let type = card.representation.typeLine ?? ""
        // A planeswalker, saga or battle that is also a creature fights in the creature row.
        if card.isPowerToughnessVisible.value || type.contains("Creature") { return .creatures }
        return ["Planeswalker", "Saga", "Battle"].contains(where: type.contains) ? .side : .support
    }

    static func groups(in game: PhoneGame, player: Player.Identifier, row: Row, ignoringTapped: Bool = false) -> [PhoneCardGroup] {
        let cards = game.state.battlefield.value.filter {
            guard $0.controllerIdentifier.value == player, game.attachments[$0.uuid] == nil else { return false }
            return Self.row(for: $0) == row
        }
        var groups: [PhoneCardGroup] = []
        for card in cards {
            if let index = groups.firstIndex(where: { canGroup(card, with: $0.top, game: game, ignoringTapped: ignoringTapped) }) {
                groups[index] = PhoneCardGroup(cards: groups[index].cards + [card])
            } else { groups.append(PhoneCardGroup(cards: [card])) }
        }
        return groups
    }

    /// Only visually equivalent lands/tokens collapse. Modified cards stay distinct.
    static func canGroup(_ card: CardInstance, with other: CardInstance, game: PhoneGame, ignoringTapped: Bool = false) -> Bool {
        guard card.representation.isLand || card.representation.isToken,
              !card.representation.isFaceDown, !other.representation.isFaceDown,
              card.representation.canonicalToken == other.representation.canonicalToken,
              card.controllerIdentifier.value == other.controllerIdentifier.value,
              (ignoringTapped || card.isTapped.value == other.isTapped.value),
              card.power.value == other.power.value, card.toughness.value == other.toughness.value,
              card.markedDamage.value == other.markedDamage.value,
              card.counters.value == other.counters.value,
              card.isSummoningSick.value == other.isSummoningSick.value,
              card.isFlying.value == other.isFlying.value,
              card.isCommander.value == other.isCommander.value,
              card.doesNotUntapAutomatically.value == other.doesNotUntapAutomatically.value,
              card.doesNotUntapNextTurn.value == other.doesNotUntapNextTurn.value,
              card.isPowerToughnessVisible.value == other.isPowerToughnessVisible.value,
              card.colors.value == other.colors.value,
              game.combat?.attackers.contains(card.uuid) == game.combat?.attackers.contains(other.uuid),
              game.combat?.blockers[card.uuid] == game.combat?.blockers[other.uuid],
              game.attachments[card.uuid] == nil, game.attachments[other.uuid] == nil,
              !game.attachments.values.contains(card.uuid), !game.attachments.values.contains(other.uuid)
        else { return false }
        return true
    }
}
