import SwiftUI
import CardService
import CardView

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
    /// The touch currently down on a card, before it is picked up: a quick release is a tap.
    @State private var press: (card: UUID, token: UUID, start: CGPoint, location: CGPoint)?
    /// Where a held card was lifted: nothing reorders until the finger moves away from it, so a
    /// card can be held up to read and put back down unchanged.
    @State private var liftPoint: CGPoint?

    /// How long a touch rests before the card lifts out of the fan (a shorter touch is a tap).
    static let holdDelay: TimeInterval = 0.16

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
    /// commanders / castable cards, which sit after a clear gap. Laid out like the card browser:
    /// cards overlap (squeezing only when they don't fit), tilt by their distance from the middle
    /// and dip slightly toward the edges — so two or three cards sit together, not spread apart.
    static func slots(handCount: Int, commandCount: Int, size: CGSize) -> [Slot] {
        let n = handCount + commandCount
        guard n > 0 else { return [] }
        let w = cardWidth(for: size)
        let hasGap = handCount > 0 && commandCount > 0
        let extraGap = hasGap ? w * 0.45 : 0
        let usable = size.width * 0.97
        let step = n > 1 ? min(w * 0.62, max(4, (usable - w - extraGap) / CGFloat(n - 1))) : 0
        func offset(_ i: Int) -> CGFloat { CGFloat(i) * step + (hasGap && i >= handCount ? extraGap : 0) }
        let total = w + offset(n - 1)
        let startX = (size.width - total) / 2 + w / 2
        let half = max(1, size.width / 2)
        return (0..<n).map { i in
            let x = startX + offset(i)
            let position = max(-1.2, min(1.2, (x - size.width / 2) / half))
            let angle = position * 7
            let y = size.height / 2 + position * position * size.height * 0.07
            return Slot(center: CGPoint(x: x, y: y), angle: angle)
        }
    }

    private var cardWidth: CGFloat { Self.cardWidth(for: size) }

    /// What the fan shows, in order: the hand (the picked-up card removed, or moved into the gap
    /// while it is held over the hand), then the commanders.
    private var displayed: (hand: [CardInstance], command: [CardInstance]) {
        let dragged = presentation.draggingCardID
        var shownHand = hand.filter { $0.uuid != dragged }
        let shownCommand = extras.filter { $0.uuid != dragged }
        if let dragged, let held = presentation.heldIndex,
           let card = cards.first(where: { $0.uuid == dragged }) {
            shownHand.insert(card, at: min(max(0, held), shownHand.count))
        }
        return (shownHand, shownCommand)
    }

    /// Hand index a card held at window x would be put back at.
    private func insertionIndex(atWindowX x: CGFloat) -> Int {
        let dragged = presentation.draggingCardID
        let others = hand.filter { $0.uuid != dragged }.count
        let commanders = extras.filter { $0.uuid != dragged }.count
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
            ForEach(Array(cards.enumerated()), id: \.element.uuid) { index, card in
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

    private var cards: [CardInstance] { hand + extras }
    /// Commanders, then cards castable from another zone (flashback in the graveyard, foretold in
    /// exile…), all to the right of the hand after a gap, as on Arena.
    private var extras: [CardInstance] {
        let shown = Set((hand + commandZone).map(\.uuid))
        return commandZone + presentation.castable.filter { !shown.contains($0.uuid) }
    }

    private func cardView(_ card: CardInstance, index: Int) -> some View {
        // Taps are recognized by the drag gesture (a quick release), so a held card can lift at once.
        let isCommand = index >= hand.count && index < hand.count + commandZone.count
        let isCastable = index >= hand.count + commandZone.count
        return PhoneHandCardFace(card: card, height: size.height, inCommandZone: isCommand,
                                 castableFrom: isCastable ? (presentation.castableInExile.contains(card.uuid) ? .exile
                                    : presentation.castableCompanions.contains(card.uuid) ? .sideboard : .graveyard) : nil)
            .background(PhoneHandMenuSource(card: card, presentation: presentation)
                .frame(width: cardWidth, height: size.height))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityAction { onTap(card) }
            .accessibilityLabel(card.representation.name ?? "Card")
            .accessibilityIdentifier(index < hand.count ? "phone-hand-\(index)"
                                     : isCastable ? "phone-castable-\(index - hand.count - commandZone.count)"
                                     : "phone-command-\(index - hand.count)")
            .accessibilityAddTraits(.isButton)
    }

    private func dragGesture(for card: CardInstance) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($gestureActive) { _, state, _ in state = true }
            .onChanged { value in
                if activeCard == nil {
                    if press?.card != card.uuid {
                        // Touch down: lift after a short hold, or right away once the finger moves.
                        let token = UUID()
                        press = (card.uuid, token, value.startLocation, value.location)
                        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay) {
                            guard let current = press, current.token == token, activeCard == nil else { return }
                            pickUp(card, start: current.start, location: current.location)
                        }
                    } else {
                        press?.location = value.location
                    }
                    let moved = hypot(value.translation.width, value.translation.height)
                    guard moved >= 6 else { return }
                    pickUp(card, start: value.startLocation, location: value.location)
                    return
                }
                guard activeCard?.uuid == card.uuid else { return }
                follow(card, to: value.location)
            }
            .onEnded { value in
                let pressed = press
                press = nil
                guard activeCard?.uuid == card.uuid else {
                    // Released before lifting: a quick single tap opens the card (or the hand).
                    let moved = hypot(value.translation.width, value.translation.height)
                    if pressed?.card == card.uuid, moved < 6, activeCard == nil, presentation.draggingCardID == nil { onTap(card) }
                    return
                }
                activeCard = nil
                let overHand = presentation.onCardDrag?(card, .changed, value.location) ?? false
                // Lifted and put back without moving: it stays exactly where it was.
                let unmoved = liftPoint.map { hypot(value.location.x - $0.x, value.location.y - $0.y) < 8 } ?? false
                liftPoint = nil
                if unmoved, !hand.contains(where: { $0.uuid == card.uuid }) {
                    // A commander or castable card held up and put back: nothing happens.
                    _ = presentation.onCardDrag?(card, .cancelled, value.location)
                    return
                }
                let index = unmoved ? hand.firstIndex(where: { $0.uuid == card.uuid })
                    : overHand ? insertionIndex(atWindowX: value.location.x) : nil
                if presentation.heldIndex != index {
                    withAnimation(.easeOut(duration: 0.16)) { presentation.heldIndex = index }
                }
                let slot = index == nil ? nil : geometry(of: card.uuid)
                _ = presentation.onCardDrag?(card, .ended(index: index, slot: slot), value.location)
            }
    }

    /// Lifts the card out of the expanded fan. The collapsed hand only expands (on a tap).
    private func pickUp(_ card: CardInstance, start: CGPoint, location: CGPoint) {
        guard activeCard == nil, presentation.isExpanded, presentation.draggingCardID == nil,
              let geometry = geometry(of: card.uuid) else { return }
        press = nil
        activeCard = card
        liftPoint = location
        presentation.draggingCardID = card.uuid
        presentation.heldIndex = hand.firstIndex { $0.uuid == card.uuid }
        _ = presentation.onCardDrag?(card, .began(geometry), start)
        follow(card, to: location)
    }

    private func follow(_ card: CardInstance, to location: CGPoint) {
        let overHand = presentation.onCardDrag?(card, .changed, location) ?? false
        if let lift = liftPoint {
            guard hypot(location.x - lift.x, location.y - lift.y) >= 8 else { return }
            liftPoint = nil
        }
        let index = overHand ? insertionIndex(atWindowX: location.x) : nil
        if presentation.heldIndex != index {
            // A tick as the gap moves to another place in the hand.
            if index != nil, presentation.heldIndex != nil { PhoneHaptics.hover() }
            withAnimation(.easeOut(duration: 0.16)) { presentation.heldIndex = index }
        }
    }
}

/// Phone Play's opponent hand: the same fan as the local hand (`PhoneHandFanView.slots`), drawn
/// as card backs, with their commanders face up after the gap. The bar rotates the hand's
/// container 180°, so it hangs from the top of the screen, facing the opponent.
///
/// Hidden cards are identified by their place in the fan, not by card: when the opponent
/// reorders their hand (or plays a card from the middle of it) the backs never move to show
/// which card went where, so a sorted hand gives nothing away (lands vs. spells).
struct PhoneOpponentHandFanView: View {
    let hand: [CardInstance]
    let commandZone: [CardInstance]
    let size: CGSize
    let onTap: (CardInstance) -> Void

    var body: some View {
        let slots = PhoneHandFanView.slots(handCount: hand.count, commandCount: commandZone.count, size: size)
        let width = PhoneHandFanView.cardWidth(for: size)
        ZStack(alignment: .topLeading) {
            ForEach(0..<hand.count, id: \.self) { index in
                HandCardView(isVisible: false, card: hand[index].representation.card)
                    .aspectRatio(63 / 88, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: width * 0.045, style: .continuous))
                    .frame(width: width, height: size.height)
                    .rotationEffect(.degrees(slots[index].angle))
                    .position(slots[index].center)
                    .zIndex(Double(index))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Face-down card")
            }
            ForEach(Array(commandZone.enumerated()), id: \.element.uuid) { offset, card in
                let slot = slots[hand.count + offset]
                PhoneHandCardFace(card: card, height: size.height, inCommandZone: true)
                    .frame(width: width, height: size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(card) }
                    .rotationEffect(.degrees(slot.angle))
                    .position(slot.center)
                    .zIndex(Double(hand.count + offset))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(card.representation.name ?? "Card")
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        // Only the hand's size (and the commanders) animate, never the order of hidden cards.
        .animation(.easeInOut(duration: 0.2), value: hand.count)
        .animation(.easeInOut(duration: 0.2), value: commandZone.map(\.uuid))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Opponent's hand, \(hand.count) card\(hand.count == 1 ? "" : "s")")
    }
}

/// An image-backed UIKit source lets the native menu zoom start at this exact fan card.
private struct PhoneHandMenuSource: UIViewRepresentable {
    let card: CardInstance
    let presentation: PhoneHandPresentation
    final class Coordinator {
        let id: UUID
        weak var presentation: PhoneHandPresentation?
        init(id: UUID, presentation: PhoneHandPresentation) { self.id = id; self.presentation = presentation }
    }
    func makeCoordinator() -> Coordinator { Coordinator(id: card.uuid, presentation: presentation) }
    /// Keeps Arena's card corners at any size; this sits behind the face, so square or
    /// mis-sized corners would show around the face's rounded ones.
    final class SourceView: UIImageView {
        override func layoutSubviews() {
            super.layoutSubviews()
            layer.cornerCurve = .continuous
            layer.cornerRadius = bounds.width * 0.045
        }
    }
    func makeUIView(context: Context) -> SourceView {
        let view = SourceView()
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.clipsToBounds = true
        presentation.menuSources[card.uuid] = .init(view)
        return view
    }
    func updateUIView(_ view: SourceView, context: Context) {
        view.image = card.representation.imageIfLoaded(type: .normal)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SourceView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
    static func dismantleUIView(_ view: SourceView, coordinator: Coordinator) {
        if coordinator.presentation?.menuSources[coordinator.id]?.view === view {
            coordinator.presentation?.menuSources[coordinator.id] = nil
        }
    }
}

/// A hand card's face with its mana cost floating just above its top-right corner (Arena).
/// Shared by the fan and the card picked up out of it, so the cost travels with the card.
struct PhoneHandCardFace: View {
    let card: CardInstance
    /// The card's height; the cost scales with it.
    let height: CGFloat
    /// Command-zone cards (shown after the hand) glow yellow and include commander tax in their
    /// cost. Passed in: Phone Play's zones aren't in `GameState.current`, so `card.pile` is nil.
    var inCommandZone: Bool = false
    /// A hidden card (the top of a library) shows its back, with no mana cost.
    var faceDown: Bool = false
    /// Castable from the graveyard (purple glow) or exile (orange glow), shown beside the hand.
    var castableFrom: Pile.Location? = nil
    /// The blue "release to play" outline while the card is dragged (drawn under the ability tiles).
    var playGlow: PhoneHandPlayGlow? = nil
    private static let exileGlow = Color(red: 1.0, green: 0.55, blue: 0.16)
    private static let graveyardGlow = Color(red: 0.66, green: 0.36, blue: 1.0)
    private static let companionGlow = Color(red: 0.2, green: 0.82, blue: 0.76)

    private static let commanderGlow = Color(#colorLiteral(red: 0.8982658702, green: 0.850980401, blue: 0.5490196347, alpha: 1))

    var body: some View {
        let width = height * 63 / 88
        let corner = width * 0.045
        let isCommander = inCommandZone
        HandCardView(isVisible: !faceDown, card: card.representation.card)
            .aspectRatio(63 / 88, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .background {
                if isCommander || castableFrom != nil {
                    let glow = max(3, height * 0.03)
                    let color = castableFrom == .exile ? Self.exileGlow : castableFrom == .graveyard ? Self.graveyardGlow
                        : castableFrom == .sideboard ? Self.companionGlow : Self.commanderGlow
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(color)
                        .shadow(color: color, radius: glow)
                        .shadow(color: color, radius: glow)
                }
            }
            .overlay { if let playGlow { PhoneHandPlayGlowOutline(glow: playGlow, width: width) } }
            .overlay(alignment: .topTrailing) { costView(width: width) }
            .overlay(alignment: .topLeading) { abilityTiles(width: width) }
    }

    /// Arena's hand-only ability tiles (Cycling, Flash, Kicker, Ninjutsu…) on the card's left edge.
    private func abilityTiles(width: CGFloat) -> some View {
        PhoneHandAbilityTileStack(card: card, height: height, faceDown: faceDown)
    }

    @ViewBuilder
    private func costView(width: CGFloat) -> some View {
        if !faceDown, let cost = displayedCost, !cost.isEmpty {
            let symbol = min(22, max(9, height * 0.075))
            // Arena: the symbols float on their own, each ringed by a soft dark shadow (no plate).
            addSymbols(string: cost, symbolLength: symbol)
                .font(.system(size: symbol))
                .fixedSize()
                .shadow(color: .black.opacity(0.9), radius: max(1.5, symbol * 0.12))
                .shadow(color: .black.opacity(0.6), radius: max(2.5, symbol * 0.22), y: symbol * 0.06)
                .offset(x: -width * 0.03, y: -symbol * 0.95)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Mana cost, with commander tax added ("{tax}+cost") for commanders in the command zone.
    private var displayedCost: String? { Self.handCost(for: card, inCommandZone: inCommandZone, castableElsewhere: castableFrom != nil) }

    /// The cost floated over a hand card: a prepare card shows only its creature's cost (it's cast
    /// as the creature; its spell is cast later while prepared), and commanders add their tax.
    static func handCost(for card: CardInstance, inCommandZone: Bool, castableElsewhere: Bool = false) -> String? {
        // Cast from the graveyard or exile, it costs what its flashback (escape, foretell…) says.
        if castableElsewhere, !card.representation.keywords.contains("Companion"), let alternate = PhoneGame.alternateCastCost(for: card) { return alternate }
        // Split cards, double-faced cards and the like show their faces' costs with one slash.
        var cost = card.representation.manaCost?.replacingOccurrences(of: " // ", with: " / ")
        if card.representation.card.layout == "prepare", case .card(let mtgCard) = card.representation,
           let creature = mtgCard.cardFaces?.first {
            cost = creature.manaCost
        }
        // Scryfall gives a double-faced card no top-level cost, only its faces': a transforming
        // card is cast as its front face, and a modal one as either face.
        if cost?.isEmpty ?? true, case .card(let mtgCard) = card.representation,
           let faces = mtgCard.cardFaces, faces.count > 1 {
            let costs = faces.compactMap(\.manaCost).filter { !$0.isEmpty }
            cost = mtgCard.layout == "modal_dfc" ? costs.joined(separator: " / ") : faces[0].manaCost
        }
        guard inCommandZone else { return cost }
        let tax = card.commanderCasts.value * 2
        return tax > 0 ? "{\(tax)}+" + (cost ?? "") : cost
    }
}



/// Whether a dragged hand card shows Arena's blue "release to play" outline.
final class PhoneHandPlayGlow: ObservableObject {
    @Published var isVisible = false
}

/// Arena's blue glow: a bright rim just outside the card with a soft cyan-blue halo (never over
/// the card). It sits above the card but below its cost and ability tiles.
private struct PhoneHandPlayGlowOutline: View {
    @ObservedObject var glow: PhoneHandPlayGlow
    let width: CGFloat

    var body: some View {
        let halo = Color(red: 0.2, green: 0.62, blue: 1)
        RoundedRectangle(cornerRadius: width * 0.05, style: .continuous)
            .strokeBorder(Color(red: 0.62, green: 0.88, blue: 1), lineWidth: max(2, width * 0.02))
            .shadow(color: halo, radius: width * 0.06)
            .shadow(color: halo, radius: width * 0.06)
            .scaleEffect(x: 1.03, y: 1.022)
            .opacity(glow.isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: glow.isVisible)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Arena's hand-only ability tiles (Cycling, Flash, Kicker, Ninjutsu…) on a card's left edge, for a
/// card `height` tall: in the hand, and on the opening hand in the browser.
struct PhoneHandAbilityTileStack: View {
    let card: CardInstance
    let height: CGFloat
    var faceDown = false

    var body: some View {
        let icons = faceDown ? [] : PhoneHandAbilityTiles.icons(for: card)
        if !icons.isEmpty {
            let size = height * 63 / 88 * 0.2
            VStack(spacing: size * 0.08) {
                ForEach(Array(icons.enumerated()), id: \.offset) { _, icon in
                    // Arena's hand tile: a dark rounded square shading from charcoal to black, a thin
                    // rim lit from above, and the ability's symbol in a pale-to-deep gold gradient.
                    let shape = RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    ZStack {
                        shape.fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.1), Color(white: 0.04)],
                                                  startPoint: .top, endPoint: .bottom))
                        shape.strokeBorder(LinearGradient(colors: [PhoneHandAbilityTiles.goldLight.opacity(0.7), Color(white: 0.12)],
                                                          startPoint: .top, endPoint: .bottom),
                                           lineWidth: max(0.75, size * 0.05))
                        if let glyph = icon.image {
                            LinearGradient(colors: PhoneHandAbilityTiles.goldGradient, startPoint: .top, endPoint: .bottom)
                                .mask(Image(uiImage: glyph).renderingMode(.template).resizable().scaledToFit())
                                .padding(size * 0.12)
                                .shadow(color: .black.opacity(0.8), radius: max(0.5, size * 0.03), y: max(0.5, size * 0.02))
                        }
                    }
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
                }
            }
            .offset(x: -size * 0.4, y: height * 0.16)
            .accessibilityHidden(true)
        }
    }
}

/// The hand-only ability icons for a card in hand (abilities that do nothing once it's on the
/// battlefield), worked out once per card face.
enum PhoneHandAbilityTiles {
    private static var cache: [String: [MTGCardView.Icon]] = [:]
    /// Arena's gold for hand-only ability symbols, from pale at the top to deep at the bottom.
    static let goldLight = Color(red: 1.0, green: 0.9, blue: 0.58)
    static let goldGradient = [goldLight, Color(red: 0.93, green: 0.73, blue: 0.28), Color(red: 0.7, green: 0.47, blue: 0.13)]

    static func icons(for card: CardInstance) -> [MTGCardView.Icon] {
        let representation = card.representation
        let key = "\(representation.card.scryfallID)|\(representation.name ?? "")"
        if let cached = cache[key] { return cached }
        let properties = MTGCardView.properties(
            includedIcons: .all, name: representation.name, manaCost: representation.manaCost,
            typeLine: representation.typeLine, oracleText: representation.oracleText, colorInitials: nil,
            fullArt: representation.fullArt, borderColor: representation.borderColor.rawValue,
            frame: representation.card.frame, frameEffects: representation.frameEffects,
            power: representation.power, toughness: representation.toughness, loyalty: representation.loyalty,
            layout: representation.layout, flavorName: representation.flavorName, isAltFace: false,
            keywords: representation.keywords, securityStamp: representation.card.securityStamp, isCommander: false)
        var seen: Set<String> = []
        let icons = properties.icons.filter { icon in
            guard !icon.isPermanentEffect, !icon.isInherent, icon.image != nil else { return false }
            return seen.insert(icon.name ?? "\(icon)").inserted
        }
        let result = Array(icons.prefix(3))
        cache[key] = result
        return result
    }
}
