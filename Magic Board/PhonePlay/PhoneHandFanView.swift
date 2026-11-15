import SwiftUI
import CardService

/// Phone Play's local hand, Arena style: a fanned row of cards laid out explicitly (no stacks or
/// native drag sessions). A card can be picked up from the expanded hand; the board then draws it
/// under the finger and decides where it lands, while the fan opens a gap wherever the card would
/// be put back. Each mana cost belongs to its own card layer, so later cards cover earlier cards'
/// costs exactly as they cover the cards.
struct PhoneHandFanView: View {
    let hand: [CardInstance]
    let commandZone: [CardInstance]
    /// The fan's area (compact or expanded size).
    let size: CGSize
    @ObservedObject var presentation: PhoneHandPresentation
    let onTap: (CardInstance) -> Void
    /// The fan's frame in window coordinates, to map the finger to hand slots.
    @State private var fanFrame: CGRect = .zero
    /// The card this fan is currently dragging (at most one at a time).
    @State private var activeCard: CardInstance?
    /// Resets when the drag gesture ends *or* is cancelled by the system (fold, app switch),
    /// which SwiftUI reports without calling `onEnded`.
    @GestureState private var gestureActive = false

    struct Slot { var center: CGPoint; var angle: CGFloat }

    static func cardWidth(for size: CGSize) -> CGFloat { max(32, size.height * 63 / 88) }

    /// Center of the collapsed fan (container coordinates): centered on screen when it fits,
    /// otherwise slid just far enough to stay between the HUD controls — and never off-screen,
    /// even if `band` was measured from controls that have not caught up with a size change yet.
    static func compactCenter(width: CGFloat, compactWidth: CGFloat, band: ClosedRange<CGFloat>?) -> CGFloat {
        let preferred = band.map { min(max(width / 2, $0.lowerBound + compactWidth / 2), $0.upperBound - compactWidth / 2) } ?? width / 2
        return min(max(preferred, compactWidth / 2), max(compactWidth / 2, width - compactWidth / 2))
    }

    /// Centers and rotations (degrees) of `handCount` hand cards followed by `commandCount`
    /// commanders, which sit after a clear gap.
    static func slots(handCount: Int, commandCount: Int, size: CGSize) -> [Slot] {
        let n = handCount + commandCount
        guard n > 0 else { return [] }
        let w = cardWidth(for: size)
        let arc = fannedHandArcDegrees(totalCards: n, isVisible: true)
        let overhang = fannedHandRotationOverhang(cardWidth: w, totalCards: n, isVisible: true)
        let fanWidth = max(w, size.width - 2 * overhang)
        // Commanders sit apart: a clear 30% card gap after the last hand card, never overlapping it.
        let hasGap = handCount > 0 && commandCount > 0
        let gapDistance = w * 1.3
        let steps = max(1, n - 1 - (hasGap ? 1 : 0))
        let step = n > 1 ? min(w + 8, (fanWidth - w - (hasGap ? gapDistance : 0)) / CGFloat(steps)) : 0
        func offset(_ i: Int) -> CGFloat {
            guard hasGap, i >= handCount else { return CGFloat(i) * step }
            return CGFloat(handCount - 1) * step + gapDistance + CGFloat(i - handCount) * step
        }
        let total = w + offset(n - 1)
        let startX = (size.width - total) / 2 + w / 2
        let maxAngle = arc / 2 * .pi / 180
        let radius = maxAngle > 0 ? size.height * 0.12 / max(0.0001, 1 - cos(maxAngle)) : 0
        return (0..<n).map { i in
            let position = n > 1 ? CGFloat(i) / CGFloat(n - 1) - 0.5 : 0
            let angle = position * arc
            let x = startX + offset(i)
            let y = size.height / 2 + radius * (1 - cos(angle * .pi / 180))
            return Slot(center: CGPoint(x: x, y: y), angle: angle)
        }
    }

    private var cardWidth: CGFloat { Self.cardWidth(for: size) }

    /// What the fan shows, in order: the hand (the picked-up card removed, or moved into the gap
    /// while it is held over the hand), then the commanders.
    private var displayed: (hand: [CardInstance], command: [CardInstance]) {
        let dragged = presentation.draggingCardID
        var shownHand = hand.filter { $0.uuid != dragged }
        let shownCommand = commandZone.filter { $0.uuid != dragged }
        if let dragged, let held = presentation.heldIndex,
           let card = (hand + commandZone).first(where: { $0.uuid == dragged }) {
            shownHand.insert(card, at: min(max(0, held), shownHand.count))
        }
        return (shownHand, shownCommand)
    }

    /// Hand index a card held at window x would be put back at.
    private func insertionIndex(atWindowX x: CGFloat) -> Int {
        let dragged = presentation.draggingCardID
        let others = hand.filter { $0.uuid != dragged }.count
        let commanders = commandZone.filter { $0.uuid != dragged }.count
        let local = x - fanFrame.minX
        return Self.slots(handCount: others, commandCount: commanders, size: size)
            .prefix(others).filter { $0.center.x < local }.count
    }

    /// Window geometry of a card where the fan currently shows it.
    private func geometry(of id: UUID) -> PhoneHandCardGeometry? {
        let shown = displayed
        let all = shown.hand + shown.command
        guard let index = all.firstIndex(where: { $0.uuid == id }) else { return nil }
        let slot = Self.slots(handCount: shown.hand.count, commandCount: shown.command.count, size: size)[index]
        return PhoneHandCardGeometry(center: CGPoint(x: fanFrame.minX + slot.center.x, y: fanFrame.minY + slot.center.y),
                                     size: CGSize(width: cardWidth, height: size.height),
                                     angle: slot.angle * .pi / 180)
    }

    var body: some View {
        let shown = displayed
        let order = shown.hand + shown.command
        let slots = Self.slots(handCount: shown.hand.count, commandCount: shown.command.count, size: size)
        ZStack(alignment: .topLeading) {
            // Every card keeps its identity (and an in-progress drag gesture) even while it is
            // picked up and out of the fan.
            ForEach(Array((hand + commandZone).enumerated()), id: \.element.uuid) { index, card in
                let shownIndex = order.firstIndex { $0.uuid == card.uuid }
                let slot = shownIndex.flatMap { slots.indices.contains($0) ? slots[$0] : nil }
                    ?? Slot(center: CGPoint(x: size.width / 2, y: size.height / 2), angle: 0)
                cardView(card, index: index)
                    .frame(width: cardWidth, height: size.height)
                    .rotationEffect(.degrees(slot.angle))
                    .position(slot.center)
                    .opacity(presentation.draggingCardID == card.uuid ? 0 : 1)
                    .zIndex(Double(shownIndex ?? index))
                    .gesture(dragGesture(for: card))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(GeometryReader { geometry in
            // Read directly (a preference from here never reached this view inside the hosted hand).
            let frame = geometry.frame(in: .global)
            Color.clear
                .onAppear { fanFrame = frame }
                .onChange(of: frame) { fanFrame = $0 }
        })
        .animation(.easeInOut(duration: 0.2), value: cards.map(\.uuid))
        .onChange(of: gestureActive) { active in
            guard !active, let card = activeCard else { return }
            // A normal release has already run `onEnded` by the next turn of the run loop; if the
            // card is still marked active, the system cancelled the touch.
            DispatchQueue.main.async {
                guard activeCard?.uuid == card.uuid else { return }
                activeCard = nil
                _ = presentation.onCardDrag?(card, .cancelled, .zero)
                presentation.endDrag()
            }
        }
    }

    private var cards: [CardInstance] { hand + commandZone }

    private func cardView(_ card: CardInstance, index: Int) -> some View {
        PhoneHandCardFace(card: card, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture { onTap(card) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.representation.name ?? "Card")
            .accessibilityIdentifier(index < hand.count ? "phone-hand-\(index)" : "phone-command-\(index - hand.count)")
            .accessibilityAddTraits(.isButton)
    }

    private func dragGesture(for card: CardInstance) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($gestureActive) { _, state, _ in state = true }
            .onChanged { value in
                if activeCard == nil {
                    // Cards are only picked up from the expanded hand; the collapsed hand just expands.
                    guard presentation.isExpanded, presentation.draggingCardID == nil,
                          let start = geometry(of: card.uuid) else { return }
                    activeCard = card
                    presentation.draggingCardID = card.uuid
                    presentation.heldIndex = hand.firstIndex { $0.uuid == card.uuid }
                    _ = presentation.onCardDrag?(card, .began(start), value.startLocation)
                }
                guard activeCard?.uuid == card.uuid else { return }
                let overHand = presentation.onCardDrag?(card, .changed, value.location) ?? false
                let index = overHand ? insertionIndex(atWindowX: value.location.x) : nil
                if presentation.heldIndex != index {
                    withAnimation(.easeOut(duration: 0.16)) { presentation.heldIndex = index }
                }
            }
            .onEnded { value in
                guard activeCard?.uuid == card.uuid else { return }
                activeCard = nil
                let overHand = presentation.onCardDrag?(card, .changed, value.location) ?? false
                let index = overHand ? insertionIndex(atWindowX: value.location.x) : nil
                if presentation.heldIndex != index {
                    withAnimation(.easeOut(duration: 0.16)) { presentation.heldIndex = index }
                }
                let slot = index == nil ? nil : geometry(of: card.uuid)
                _ = presentation.onCardDrag?(card, .ended(index: index, slot: slot), value.location)
            }
    }
}

/// A hand card's face with its mana cost floating just above its top-right corner (Arena).
/// Shared by the fan and the card picked up out of it, so the cost travels with the card.
struct PhoneHandCardFace: View {
    let card: CardInstance
    /// The card's height; the cost scales with it.
    let height: CGFloat

    private static let commanderGlow = Color(#colorLiteral(red: 0.8982658702, green: 0.850980401, blue: 0.5490196347, alpha: 1))

    var body: some View {
        let width = height * 63 / 88
        let corner = width * 0.045
        let isCommander = card.pile?.location == .command
        HandCardView(isVisible: true, card: card.representation.card)
            .aspectRatio(63 / 88, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .background {
                if isCommander {
                    let glow = max(3, height * 0.03)
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .shadow(color: Self.commanderGlow, radius: glow)
                        .shadow(color: Self.commanderGlow, radius: glow)
                }
            }
            .overlay(alignment: .topTrailing) { costView(width: width) }
    }

    @ViewBuilder
    private func costView(width: CGFloat) -> some View {
        if let cost = displayedCost, !cost.isEmpty {
            let symbol = min(22, max(9, height * 0.075))
            addSymbols(string: cost, symbolLength: symbol)
                .font(.system(size: symbol))
                .fixedSize()
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.85), in: Capsule())
                .offset(x: -width * 0.03, y: -symbol * 0.95)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Mana cost, with commander tax added ("{tax}+cost") for commanders in the command zone.
    private var displayedCost: String? {
        let cost = card.representation.manaCost
        guard card.isCommander.value, card.pile?.location == .command else { return cost }
        let tax = card.commanderCasts.value * 2
        return tax > 0 ? "{\(tax)}+" + (cost ?? "") : cost
    }
}

