import UIKit
import CardView
import Combine
import MultipeerConnectivity

/// Uses the same native table/navigation presentation as the existing pile views.
final class NearbyGamePickerController: UITableViewController {
    private let session: PhoneGameSession
    private var subscriptions = Set<AnyCancellable>()
    private var displayedPeers: [MCPeerID] = []
    private var displayedStatus = ""
    var onJoined: (() -> Void)?
    var onCancel: (() -> Void)?
    init(session: PhoneGameSession) { self.session = session; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Nearby Phone Games"
        navigationItem.leftBarButtonItem = .init(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        Publishers.CombineLatest(session.$nearby, session.$status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers, status in self?.display(peers: peers, status: status) }
            .store(in: &subscriptions)
        session.$hasSnapshot.removeDuplicates().filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onJoined?() }.store(in: &subscriptions)
    }
    @objc private func cancel() { onCancel?() }
    // @Published emits before the session's stored values change. UIKit must
    // use the emitted snapshot for both row counts and row contents.
    func display(peers: [MCPeerID], status: String) {
        displayedPeers = peers
        displayedStatus = status
        tableView.reloadData()
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { displayedPeers.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { displayedStatus }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Choose Host Phone Game on the other phone. Keep Wi-Fi and Bluetooth enabled; no router or internet connection is needed."
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        guard displayedPeers.indices.contains(indexPath.row) else { return cell }
        cell.textLabel?.text = displayedPeers[indexPath.row].displayName
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard displayedPeers.indices.contains(indexPath.row) else { return }
        let peer = displayedPeers[indexPath.row]
        guard session.nearby.contains(peer) else { return }
        session.join(peer)
    }
}

// The original board menu's actions, organized into a scrollable native sheet.
final class BoardMenuAction {
    let title: String?
    let style: UIAlertAction.Style
    let handler: ((BoardMenuAction) -> Void)?
    /// Shown by navigating forward within the menu's own sheet, instead of closing the menu.
    let destination: (() -> UIViewController?)?
    init(title: String?, style: UIAlertAction.Style, handler: ((BoardMenuAction) -> Void)? = nil) {
        self.title = title; self.style = style; self.handler = handler; self.destination = nil
    }
    init(title: String, push destination: @escaping () -> UIViewController?) {
        self.title = title; self.style = .default; self.handler = nil; self.destination = destination
    }
}

/// The long-press board menu: every action at a glance as compact icon tiles, grouped (Game,
/// Cards, Board, More) on one page — the most used ones (load, reset, exit) first. Actions with a
/// destination navigate forward within this sheet.
final class BoardMenuSheetController: UIViewController {
    private var actions: [BoardMenuAction] = []
    var textFields: [UITextField]? = []
    /// Kept for callers; the reset options are tiles now.
    var onReset: (() -> Void)?

    init(title: String?, message: String?, preferredStyle: UIAlertController.Style) {
        super.init(nibName: nil, bundle: nil); self.title = title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func addAction(_ action: BoardMenuAction) { if action.style != .cancel { actions.append(action) } }
    func addTextField(configurationHandler: ((UITextField) -> Void)?) {
        let field = UITextField(); field.placeholder = "Card name or set and number"
        field.clearButtonMode = .whileEditing; field.borderStyle = .roundedRect
        configurationHandler?(field); textFields?.append(field)
    }

    fileprivate enum Group: String, CaseIterable { case game = "Game", cards = "Cards", board = "Board", more = "More" }
    fileprivate static func group(of action: BoardMenuAction) -> Group {
        let name = action.title ?? ""
        if name.hasPrefix("Load") || name.contains("Preloaded") || name.contains("Connection") || name.hasPrefix("Reset")
            || name == "Clear Board" || name == "Exit Game" || name.contains("Hand") || name.hasSuffix("on Untap") { return .game }
        if name.hasPrefix("Add") || name.hasPrefix("Drop") { return .cards }
        if name.contains("Hide") || name.contains("Selection") || name.contains("Reveal") { return .board }
        return .more
    }
    fileprivate static func icon(for title: String) -> String {
        switch title {
        case "Load Deck / JumpStart / Jump In": return "rectangle.stack.badge.plus"
        case "Preloaded Games & Artwork": return "square.grid.3x3.square"
        case "Connection…": return "antenna.radiowaves.left.and.right"
        case "Load Dandân": return "fish"
        case "Reset Decks and Life": return "arrow.counterclockwise"
        case "Clear Board": return "trash"
        case "Exit Game": return "rectangle.portrait.and.arrow.right"
        case "Reveal Hand": return "eye"
        case "Stop Revealing Hand": return "eye.slash"
        case "Draw on Untap": return "arrow.turn.up.left"
        case "Don't Draw on Untap": return "arrow.turn.up.left.circle"
        case "Turn Off Hand Smoothing": return "slider.horizontal.below.rectangle"
        case "Turn On Hand Smoothing": return "slider.horizontal.3"
        case "Add by Name": return "text.magnifyingglass"
        case "Add by Set and Number": return "number"
        case "Add Random": return "dice"
        case "Update Card Database": return "arrow.down.circle"
        case "Share Connect App": return "square.and.arrow.up"
        default:
            if title.contains("Player 2") { return "person.2" }
            if title.contains("Land Organizer") { return "square.stack.3d.up" }
            if title.hasPrefix("Drop") { return "rectangle.portrait.on.rectangle.portrait" }
            if title.contains("Selection") { return "selection.pin.in.out" }
            if title.contains("Top Card") { return "eye" }
            return "circle.grid.2x2"
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = .init(barButtonSystemItem: .done, target: self, action: #selector(done))
        let grid = BoardMenuGrid(groups: Group.allCases.compactMap { group in
            // Most used first: load, reset, clear, exit, reveal hand; the rest keep their order.
            let priority = ["Load Deck / JumpStart / Jump In", "Reset Decks and Life", "Clear Board", "Exit Game", "Reveal Hand", "Stop Revealing Hand"]
            let items = actions.filter { Self.group(of: $0) == group }.enumerated().sorted { a, b in
                let pa = priority.firstIndex(of: a.element.title ?? "") ?? priority.count + a.offset
                let pb = priority.firstIndex(of: b.element.title ?? "") ?? priority.count + b.offset
                return pa < pb
            }.map(\.element)
            return items.isEmpty && !(group == .cards && textFields?.first != nil) ? nil : (group.rawValue, items)
        }, field: textFields?.first, select: { [weak self] action in self?.select(action) })
        let host = UIHostingController(rootView: grid)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    private func select(_ action: BoardMenuAction) {
        view.endEditing(true)
        if let destination = action.destination {
            if let controller = destination() { navigationController?.pushViewController(controller, animated: true) }
            return
        }
        dismiss(animated: true) { action.handler?(action) }
    }

    @objc private func done() { dismiss(animated: true) }
}

/// The board menu's grouped icon tiles.
private struct BoardMenuGrid: View {
    let groups: [(String, [BoardMenuAction])]
    let field: UITextField?
    let select: (BoardMenuAction) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.0) { name, actions in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(name.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                        if name == "Cards", let field {
                            TextFieldHost(field: field).frame(height: 36)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                                Button { select(action) } label: {
                                    VStack(spacing: 5) {
                                        Image(systemName: BoardMenuSheetController.icon(for: action.title ?? ""))
                                            .font(.system(size: 19, weight: .semibold)).frame(height: 22)
                                        Text(action.title ?? "").font(.caption.weight(.medium))
                                            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 64)
                                    .padding(.horizontal, 4)
                                    .foregroundStyle(action.style == .destructive ? Color.red : Color.primary)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
                                    .contentShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(action.title ?? "")
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct TextFieldHost: UIViewRepresentable {
    let field: UITextField
    func makeUIView(context: Context) -> UITextField { field }
    func updateUIView(_ uiView: UITextField, context: Context) {}
}

import SwiftUI
import CardService

struct PhoneStackCardsView: View {
    let items: [PhoneGame.StackItem]
    let inspect: (CardInstance) -> Void
    let browse: () -> Void
    /// Hidden while its stand-in zooms into (or back from) the card menu.
    var concealedCardID: UUID? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static func cardSize(in size: CGSize) -> CGSize {
        let width = min(size.width / 1.62, size.height * 0.88 * 63 / 88)
        return CGSize(width: width, height: width * 88 / 63)
    }
    static func cardTransform(in size: CGSize, depth: Int) -> CGAffineTransform {
        let card = cardSize(in: size), depth = CGFloat(depth)
        let center = CGPoint(x: size.width - card.width / 2 - 5 - depth * card.width * 0.08,
                             y: size.height / 2 - depth * card.height * 0.02)
        return CGAffineTransform(translationX: center.x, y: center.y + card.height / 2)
            .rotated(by: -4 * depth * .pi / 180)
            .translatedBy(x: -card.width / 2, y: -card.height)
    }
    /// The exposed left edge, accounting for the same bottom-pivot rotation as the fan.
    static func connectionPoint(in size: CGSize, depth: Int) -> CGPoint {
        let card = cardSize(in: size)
        let depth = CGFloat(depth)
        let angle = -4 * depth * .pi / 180
        let x = size.width - card.width / 2 - 5 - depth * card.width * 0.08
        let bottom = size.height / 2 - depth * card.height * 0.02 + card.height / 2
        return CGPoint(x: x - card.width / 2 * cos(angle) + card.height / 2 * sin(angle),
                       y: bottom - card.width / 2 * sin(angle) - card.height / 2 * cos(angle))
    }
    private func face(of card: CardInstance) -> MTGCard.Face? {
        if case .alternateFace(_, let face) = card.representation { return face }
        return nil
    }
    var body: some View {
        GeometryReader { geometry in
            // Arena keeps the newest card upright, with older cards fanned to its left.
            // Bound the fan; the count button opens every item, even in a very large stack.
            let visible = Array(items.suffix(4))
            let size = Self.cardSize(in: geometry.size)
            let width = size.width
            let height = size.height
            let corner = max(4, width * 0.045)
            ZStack {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                    let depth = CGFloat(visible.count - index - 1)
                    Button {
                        if let card = item.card { inspect(card) } else { browse() }
                    } label: {
                        Group {
                            if let card = item.card {
                                HandCardView(isVisible: true, card: card.representation.card, face: face(of: card))
                            } else {
                                RoundedRectangle(cornerRadius: corner)
                                    .fill(Color(white: 0.15))
                                    .overlay(Text(item.text).font(.headline).foregroundStyle(.white).padding(8))
                            }
                        }
                        .frame(width: width, height: height)
                        .overlay(Color.black.opacity(Double(depth) * 0.06))
                        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(.white.opacity(depth == 0 ? 0.65 : 0.3), lineWidth: depth == 0 ? 1 : 0.5))
                        .shadow(color: .black.opacity(0.7), radius: depth == 0 ? 7 : 3, x: -2, y: 4)
                    }
                        .buttonStyle(.plain)
                        .opacity(item.card != nil && item.card?.uuid == concealedCardID ? 0 : 1)
                        .rotationEffect(.degrees(-4 * depth), anchor: .bottom)
                        .position(x: geometry.size.width - width / 2 - 5 - depth * width * 0.08,
                                  y: geometry.size.height / 2 - depth * height * 0.02)
                        .zIndex(Double(index))
                        .onLongPressGesture { if let card = item.card { inspect(card) } else { browse() } }

                        .accessibilityLabel(item.text)
                        .accessibilityValue((depth == 0 ? "Top of stack, resolves next" : "\(visible.count - index) from top")
                                            + ", \(item.targets?.count ?? 0) targets")
                        .accessibilityIdentifier("phone-stack-full-card")
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: items.map(\.id))
        }
    }
}

/// Drags the top card off one of a player's piles (see `BoardViewController.phonePilePanned`).
final class PhonePilePanGesture: UIPanGestureRecognizer {
    var zone: Pile.Location = .graveyard
    weak var bar: BottomBarViewController?
}

extension Optional where Wrapped == [UIGestureRecognizer] {
    var orEmpty: [UIGestureRecognizer] { self ?? [] }
}

/// Phone Play's haptics, firmer than UIKit's selection tick so they're felt mid-drag.
enum PhoneHaptics {
    /// Picking a card up, or an attach/target/block offer arming under it.
    static func pickUp() { UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9) }
    /// A dragged card landing in a new zone (or a target being set).
    static func drop() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1) }
    /// A stack card's targeting arrow passing over something it can target.
    static func hover() { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7) }
}

/// A CADisplayLink target that doesn't retain its owner.
final class PhoneDisplayLinkTarget: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func tick() { action() }
}

/// Passes touches through except where `accepts` says something is drawn.
final class PhoneTouchFilterView: UIView {
    var accepts: ((CGPoint) -> Bool)?
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard accepts?(point) == true else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Blocker-to-attacker connections, including the assignment under the dragged card.
/// Arena's blocks: a glowing golden curve from each blocker to the attacker it blocks, and a
/// golden halo arcing over the blocker's edge that faces the attacker.
final class PhoneCombatLinesView: UIView {
    struct Line { let from: CGPoint; let to: CGPoint; let preview: Bool; var blocker: CGRect? = nil }
    var lines: [Line] = [] { didSet { setNeedsDisplay() } }
    static let gold = UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let gold = Self.gold
        var haloed: Set<String> = []
        for line in lines {
            let distance = hypot(line.to.x - line.from.x, line.to.y - line.from.y)
            guard distance > 4 else { continue }
            // A gentle curve, bowing sideways like Arena's.
            let mid = CGPoint(x: (line.from.x + line.to.x) / 2, y: (line.from.y + line.to.y) / 2)
            let normal = CGPoint(x: -(line.to.y - line.from.y) / distance, y: (line.to.x - line.from.x) / distance)
            let bow = min(28, distance * 0.18)
            let control = CGPoint(x: mid.x + normal.x * bow, y: mid.y + normal.y * bow)
            let path = UIBezierPath()
            path.move(to: line.from); path.addQuadCurve(to: line.to, controlPoint: control)
            path.lineCapStyle = .round; path.lineWidth = line.preview ? 3.5 : 3
            if line.preview { path.setLineDash([7, 5], count: 2, phase: 0) }
            context.saveGState()
            context.setShadow(offset: .zero, blur: 10, color: gold.cgColor)
            gold.withAlphaComponent(line.preview ? 0.7 : 0.95).setStroke(); path.stroke()
            context.restoreGState()
            path.lineWidth = 1; UIColor.white.withAlphaComponent(0.85).setStroke(); path.stroke()

            // The halo over the blocker's facing edge (once per blocker).
            guard let card = line.blocker, haloed.insert("\(card.midX),\(card.midY)").inserted else { continue }
            let facesUp = line.to.y < card.midY
            let edgeY = facesUp ? card.minY : card.maxY
            let width = card.width * 1.15, height = max(6, card.width * 0.22)
            let oval = CGRect(x: card.midX - width / 2, y: edgeY - height / 2, width: width, height: height)
            // The half of the ellipse outside the card.
            let halo = UIBezierPath(arcCenter: .zero, radius: 1, startAngle: facesUp ? .pi : 0, endAngle: facesUp ? 2 * .pi : .pi, clockwise: true)
            halo.apply(CGAffineTransform(scaleX: width / 2, y: height / 2))
            halo.apply(CGAffineTransform(translationX: oval.midX, y: oval.midY))
            halo.lineCapStyle = .round
            context.saveGState()
            context.setShadow(offset: .zero, blur: 12, color: gold.cgColor)
            halo.lineWidth = 4; gold.withAlphaComponent(line.preview ? 0.6 : 0.9).setStroke(); halo.stroke()
            context.restoreGState()
            halo.lineWidth = 1.2; UIColor.white.withAlphaComponent(0.8).setStroke(); halo.stroke()
        }
    }
}

/// A transparent, non-interactive layer. Geometry is supplied by the actual board layout.
final class PhoneTargetArcsView: UIView {
    struct Connection {
        let source: CGPoint
        let destination: CGPoint
        let local: Bool
        let targetsStack: Bool
    }
    var connections: [Connection] = [] { didSet { setNeedsDisplay() } }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for connection in connections {
            let start = connection.source, end = connection.destination
            let distance = hypot(end.x - start.x, end.y - start.y)
            guard distance > 8 else { continue }
            let bend = min(100, max(30, distance * 0.3))
            // A response targeting a nearby spell needs to loop outside the fan;
            // a shallow curve between their edges would be entirely hidden by the cards.
            let control = connection.targetsStack
                ? CGPoint(x: min(start.x, end.x) - max(110, distance * 0.5), y: max(8, min(start.y, end.y) - 45))
                : CGPoint(x: (start.x + end.x) / 2 - bend * 0.4, y: max(8, (start.y + end.y) / 2 - bend))
            let color: UIColor = connection.local ? .systemCyan : .systemOrange
            let curve = UIBezierPath()
            curve.move(to: start)
            curve.addQuadCurve(to: end, controlPoint: control)
            curve.lineCapStyle = .round
            context.saveGState()
            context.setShadow(offset: .zero, blur: 9, color: color.cgColor)
            color.withAlphaComponent(0.9).setStroke()
            curve.lineWidth = 3.5; curve.stroke()
            context.restoreGState()
            UIColor.white.withAlphaComponent(0.8).setStroke()
            curve.lineWidth = 1; curve.stroke()
            let angle = atan2(end.y - control.y, end.x - control.x)
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: end.x - 8 * cos(angle - 0.45), y: end.y - 8 * sin(angle - 0.45)))
            arrow.addLine(to: end)
            arrow.addLine(to: CGPoint(x: end.x - 8 * cos(angle + 0.45), y: end.y - 8 * sin(angle + 0.45)))
            arrow.lineWidth = 2.5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
            color.setStroke(); arrow.stroke()
        }
    }
}

struct OfflineGamesView: View {
    var close: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private let library = OfflineGameLibrary.shared
    var body: some View {
        List {
            ForEach(["DanDân", "JumpStart", "Jump In", "Mana fixing", "Tokens"], id: \.self) { kind in
                Section(kind) {
                    ForEach(library.games.filter { $0.kind == kind && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }, id: \.name) { game in
                        NavigationLink(game.name == "Dandan" ? "DanDân" : game.name) {
                            OfflineGameCardsView(game: game)
                        }
                    }
                }
            }
        }.searchable(text: $search).navigationTitle("Preloaded Games")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if let close { close() } else { dismiss() } } } }
    }
}
private struct OfflineGameCardsView: View {
    let game: OfflineGameLibrary.Game
    private let library = OfflineGameLibrary.shared
    var body: some View {
        List(game.entries, id: \.key) { entry in
            if let card = library.card(forKey: entry.key) {
                NavigationLink {
                    OfflineCardArtworkView(card: card)
                } label: {
                    HStack {
                        if let image = card.imageIfLoaded(type: .small) {
                            Image(uiImage: image).resizable().scaledToFit().frame(width: 45, height: 63)
                        }
                        VStack(alignment: .leading) {
                            Text("\(entry.count) × \(card.name ?? "Card")")
                            Text("\(library.artworkCount(for: card)) of \(library.catalogArtworkCount(for: card)) images downloaded for offline play")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.navigationTitle(game.name)
    }
}

private struct OfflineCardArtworkView: View {
    let card: MTGCard
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let image = card.imageIfLoaded(type: .normal) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 500)
                }
                if let image = card.imageIfLoaded(type: .art) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260)
                }
                Text(card.oracleText ?? "").padding()
            }.frame(maxWidth: 600).frame(maxWidth: .infinity).padding()
        }.navigationTitle(card.name ?? "Card")
    }
}

/// One packet offer. With a JumpStart front card: just the card (its name and colors are printed
/// on it). Without one: a plain card-shaped tile with the theme name (no variant number) and the
/// colors as mana symbols, keeping the contents a mystery.
struct PacketChoiceCard: View {
    let frontCardURL: URL?
    let title: String
    let manaSymbols: String
    var body: some View {
        Group {
            if let frontCardURL {
                SwiftUI.AsyncImage(url: frontCardURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() }
                    else { mysteryTile.overlay { if phase.error == nil { ProgressView() } } }
                }
            } else {
                mysteryTile
            }
        }
        .aspectRatio(63 / 88, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var mysteryTile: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .overlay {
                VStack(spacing: 12) {
                    Text(title)
                        .font(.custom("Beleren2016-Bold", size: 22))
                        .minimumScaleFactor(0.5)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    addSymbols(string: manaSymbols, symbolLength: 22)
                }
                .padding(12)
            }
    }
}

/// Offers belong to the authoritative game, so both phones enter the same draft.
struct PhonePacketChoiceView: View {
    @ObservedObject var session: PhoneGameSession
    /// False when pushed inside an existing navigation (the board menu's Load Deck page).
    var embedsNavigation = true
    private let library = OfflineGameLibrary.shared
    var body: some View {
        if embedsNavigation { NavigationStack { choices } } else { choices }
    }

    @ViewBuilder private var choices: some View {
            if let selection = session.game.packetSelection,
               !selection.completed.contains(session.player.rawValue) {
                let player = session.player.rawValue
                let offers = selection.offers[player] ?? []
                GeometryReader { proxy in
                    VStack(spacing: 10) {
                        if let first = selection.firstChoices[player] {
                            Text("First packet: \(OfflineGameLibrary.packetDisplayName(first))").font(.footnote).foregroundStyle(.secondary)
                        }
                        // The three offers side by side, as large as the screen allows.
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(offers, id: \.self) { name in
                                Button {
                                    session.send(.choosePacket(selection.id, name))
                                } label: {
                                    PacketChoiceCard(frontCardURL: library.packetFrontCardURL(kind: selection.kind, set: selection.setCode, name: name),
                                                     title: OfflineGameLibrary.packetDisplayName(name),
                                                     manaSymbols: library.packetColorSymbols(kind: selection.kind, set: selection.setCode, name: name))
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: (proxy.size.width - 64) / 3)
                                .accessibilityIdentifier("phone-packet-choice")
                            }
                        }
                        .frame(maxHeight: max(120, proxy.size.height - 24))
                    }
                    .padding(.horizontal, 16)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .navigationTitle(selection.firstChoices[player] == nil ? "Choose First Packet" : "Choose Second Packet")
                .navigationBarTitleDisplayMode(.inline)
                .interactiveDismissDisabled()
                .navigationBarBackButtonHidden(true) // the draft has to finish
            }
    }
}

/// Transparent full-screen layer shown while the local hand is expanded. Touches on the
/// hand pass through; any other touch is consumed and only collapses the hand.
/// Non-touch hit tests (drag-and-drop targeting) always pass through.
/// Hosts a land row. In Phone Play only the drawn land stacks receive touches, so battlefield
/// cards laid out beside the lands (column layout) stay tappable under the row's empty area.
/// With no `hitRegions` (classic board) it behaves like a plain view.
final class PhoneLandContainerView: UIView {
    var hitRegions: (() -> [CGRect])?
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let hitRegions else { return super.point(inside: point, with: event) }
        let windowPoint = convert(point, to: nil)
        return hitRegions().contains { $0.insetBy(dx: -6, dy: -6).contains(windowPoint) }
    }
}

final class PhoneHandShieldView: UIView {
    var passesThrough: ((CGPoint) -> Bool)?
    var onDismiss: (() -> Void)?
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let event, event.type == .touches else { return false }
        return passesThrough?(point) != true
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { onDismiss?() }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}
}

/// Hand cards expose the same play/move choices as Board Connect, independently
/// of battlefield-only controls such as tapping, counters, and token creation.
final class PhoneHandCardController: UIViewController, PileDisplaying, UITableViewDataSource, UITableViewDelegate {
    private let session: PhoneGameSession
    private let card: CardInstance
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var moreActions: [Action] = []
    private var preview: CardImageViewController?
    var contentType: DisplayedContent { .pile(.hand) }
    var pileLocation: Pile.Location? { .hand }
    var ownerIdentifier: Player.Identifier { session.player }
    func setPile(_ pile: Pile) {}
    func pushImageViewController(for cardInstance: CardInstance) { preview?.cardInstance = cardInstance }

    init(session: PhoneGameSession, card: CardInstance) {
        self.session = session
        self.card = card
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = card.representation.name
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = .init(barButtonSystemItem: .done, target: self, action: #selector(done))
        let image = UIStoryboard(name: "Board", bundle: nil).instantiateViewController(withIdentifier: "CardImageViewController") as! CardImageViewController
        image.cardInstance = card
        image.showsOtherSideButton = true
        preview = image
        addChild(image)
        view.addSubview(image.view)
        image.didMove(toParent: self)
        view.addSubview(table)
        image.view.translatesAutoresizingMaskIntoConstraints = false
        table.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            image.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            image.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            image.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            image.view.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.43),
            table.leadingAnchor.constraint(equalTo: image.view.trailingAnchor, constant: 8),
            table.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        moreActions = actions(for: card, includeFaceCasts: false, includeIndividualCast: false).filter {
            $0.style != .cancel && !["View Card", "Reveal to Opponent", "Morph"].contains($0.title ?? "")
        }
        // Permanent spells normally go straight to the battlefield; this casts one onto the stack
        // instead (it resolves onto the battlefield).
        let type = card.representation.typeLine ?? ""
        let isPermanentSpell = !card.representation.isLand
            && ["Creature", "Artifact", "Enchantment", "Planeswalker", "Battle"].contains { type.contains($0) }
        if isPermanentSpell {
            moreActions.insert(Action(title: "Move to Stack", handler: { [session, card] _ in
                session.send(.moveToStack(card.uuid))
            }), at: 0)
        }
        // Companions: mark or unmark one; a marked companion in the sideboard can go to the hand.
        if card.representation.keywords.contains("Companion") {
            let marked = session.game.companions?[card.uuid] == session.player
            if marked, session.game.state[player: session.player].sideboard.cards.value.contains(card) {
                moreActions.insert(Action(title: "Put into Hand", handler: { [session, card] _ in
                    session.send(.moveToPlayer(card.uuid, .hand, session.player, bottom: false))
                }), at: 0)
            }
            moreActions.append(Action(title: marked ? "Not My Companion" : "Mark as Companion", handler: { [session, card] _ in
                session.send(.markCompanion(card.uuid, !marked))
            }))
        }
        if card.isCommander.value && !isInCommandZone {
            moreActions.insert(Action(title: "Move to Command Zone", handler: { [session, card] _ in
                session.send(.moveToPlayer(card.uuid, .command, card.ownerIdentifier, bottom: false))
            }), at: 0)
        }
        if session.mode == .rules { moreActions = [] }
        table.dataSource = self
        table.delegate = self
        table.accessibilityIdentifier = "phone-hand-actions"
    }
    @objc private func done() { navigationController?.dismiss(animated: true) }
    private var isInCommandZone: Bool { session.game.state[player: session.player].commandZone.cards.value.contains(card) }
    /// Commanders get a tax stepper (2 generic mana per previous cast from the command zone).
    private var showsCommanderTax: Bool { session.mode != .rules && (card.isCommander.value || isInCommandZone) }
    func numberOfSections(in tableView: UITableView) -> Int { showsCommanderTax ? 3 : 2 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? (session.mode == .rules ? 1 : 2) : section == 1 ? moreActions.count : 1 }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 2 ? "Commander" : nil }
    private func commanderTaxCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        let label = UILabel()
        func update(_ casts: Int) {
            let text = NSMutableAttributedString(string: "Commander Tax  ")
            text.append(NSAttributedString(string: "+\(casts * 2)", attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold)]))
            label.attributedText = text
            label.accessibilityValue = "\(casts * 2) mana"
        }
        update(card.commanderCasts.value)
        let stepper = UIStepper()
        stepper.minimumValue = 0
        stepper.maximumValue = 50
        stepper.value = Double(card.commanderCasts.value)
        stepper.accessibilityIdentifier = "phone-commander-tax"
        stepper.addAction(UIAction { [session, card] action in
            guard let stepper = action.sender as? UIStepper else { return }
            let casts = Int(stepper.value)
            update(casts)
            session.send(.commanderTax(card.uuid, casts))
        }, for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [label, UIView(), stepper])
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -6)
        ])
        return cell
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 2 { return commanderTaxCell() }
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = indexPath.section == 0 ? (indexPath.row == 0 ? "Play" : "Play Tapped") : moreActions[indexPath.row].title
        cell.textLabel?.textColor = indexPath.section == 1 && moreActions[indexPath.row].style == .destructive ? .systemRed : view.tintColor
        cell.accessibilityTraits = .button
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 2 { return }
        if indexPath.section == 1 {
            let action = moreActions[indexPath.row]
            navigationController?.dismiss(animated: true) { [self] in action.handler?(self) }
            return
        }
        let options = session.castOptions(for: card, tapped: indexPath.row == 1)
        if options.count == 1 { finish(options[0].parameters); return }
        let alert = UIAlertController(title: "Play", message: card.representation.name, preferredStyle: .actionSheet)
        for option in options {
            alert.addAction(.init(title: option.title, style: .default) { [weak self] _ in self?.finish(option.parameters) })
        }
        alert.addAction(.init(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
        present(alert, animated: true)
    }
    private func finish(_ parameters: Command.PlayCardParameters) {
        navigationController?.dismiss(animated: true) { [session] in session.send(.playCard(parameters)) }
    }
}

/// Arena-style attack chevron: a white core over an orange glow, independent of card rotation.
final class PhoneAttackIndicatorView: UIView {
    private let glow = CAShapeLayer()
    private let core = CAShapeLayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for shape in [glow, core] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineCap = .round
            shape.lineJoin = .round
            layer.addSublayer(shape)
        }
        glow.strokeColor = UIColor.systemOrange.cgColor
        glow.lineWidth = 7
        glow.shadowColor = UIColor.systemOrange.cgColor
        glow.shadowRadius = 7
        glow.shadowOpacity = 1
        glow.shadowOffset = .zero
        core.strokeColor = UIColor.white.cgColor
        core.lineWidth = 2.5
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: bounds.width * 0.08, y: bounds.height * 0.8))
        path.addLine(to: CGPoint(x: bounds.midX, y: bounds.height * 0.15))
        path.addLine(to: CGPoint(x: bounds.width * 0.92, y: bounds.height * 0.8))
        for shape in [glow, core] { shape.frame = bounds; shape.path = path.cgPath }
    }
}


// MARK: - Close buttons for Phone Play sheets

/// Sheets that already provide their own close/done control opt out of the automatic one.
protocol PhoneSheetProvidesClose {}
/// SwiftUI sheets (UIHostingController) with their own Done mark themselves with this view hint.
enum PhoneSheet { static let providesCloseHint = "phone-sheet-provides-close" }

extension UIViewController {
    /// iPhone 8 (iOS 16) landscape sheets are full-screen and can't be swiped away. In Phone Play,
    /// give every presented sheet an explicit close: an ✕ bar button on a navigation root, otherwise
    /// a floating close button. Alerts, share sheets and system pickers are left alone.
    func addPhoneCloseButtonIfNeeded(to presented: UIViewController) {
        guard AppDelegate.shared.usesPhoneSession else { return }
        if presented is UIAlertController || presented is UIActivityViewController
            || presented is UIDocumentPickerViewController || presented is UIImagePickerController
            || presented is PhoneSheetProvidesClose
            || presented.view.accessibilityHint == PhoneSheet.providesCloseHint { return }
        if presented.modalPresentationStyle == .popover, traitCollection.horizontalSizeClass == .regular { return }
        let close = UIAction { [weak presented] _ in presented?.dismiss(animated: true) }
        if let navigation = presented as? UINavigationController, let root = navigation.viewControllers.first,
           !navigation.isNavigationBarHidden {
            if root is PhoneSheetProvidesClose { return }
            let items = (root.navigationItem.leftBarButtonItems ?? []) + (root.navigationItem.rightBarButtonItems ?? [])
            func closes(_ item: UIBarButtonItem) -> Bool {
                let action = item.action.map(NSStringFromSelector)?.lowercased() ?? ""
                return item.title == "Done" || item.title == "Close" || ["done", "close", "dismiss"].contains { action.contains($0) }
            }
            guard !items.contains(where: closes) else { return }
            let item = UIBarButtonItem(systemItem: .close, primaryAction: close)
            item.accessibilityIdentifier = "phone-sheet-close"
            // Prefer the empty leading slot; otherwise (e.g. the pile's Shuffle) put it at the trailing end.
            if root.navigationItem.leftBarButtonItem == nil { root.navigationItem.leftBarButtonItem = item }
            else { root.navigationItem.rightBarButtonItems = [item] + (root.navigationItem.rightBarButtonItems ?? []) }
            return
        }
        let button = UIButton(type: .close, primaryAction: close)
        button.accessibilityIdentifier = "phone-sheet-close"
        button.translatesAutoresizingMaskIntoConstraints = false
        presented.view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: presented.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            button.trailingAnchor.constraint(equalTo: presented.view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        ])
    }
}


/// Full-screen pile sheets (library, graveyard, exile…) may rotate to portrait while the
/// landscape-only board is covered; dismissing returns to landscape.
final class PhonePortraitNavigationController: UINavigationController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
}

// These build their own Done/Cancel in viewDidLoad (after the automatic close button check runs).
extension NearbyGamePickerController: PhoneSheetProvidesClose {}
extension BoardMenuSheetController: PhoneSheetProvidesClose {}
extension PhoneHandCardController: PhoneSheetProvidesClose {}

// MARK: - Arena-style zone browser (search, look at, revealed cards)

/// Cards laid out large in a scrolling fan over the darkened board, as Arena shows a library search
/// or revealed cards. The board's bottom bar (your hand and piles) stays uncovered: hold a card to lift
/// it, then drop it elsewhere in the fan to reorder, on your hand, library, graveyard or exile, or on
/// the Battlefield zone at the top.
final class PhoneZoneBrowserView: UIView, UIScrollViewDelegate {
    enum Destination: Equatable {
        case hand, library, graveyard, exile, battlefield
        var title: String {
            switch self {
            case .hand: return "Hand"
            case .library: return "Library"
            case .graveyard: return "Graveyard"
            case .exile: return "Exile"
            case .battlefield: return "Battlefield"
            }
        }
    }

    /// Display order, left to right (for library modes: top of the library first).
    private(set) var cards: [CardInstance] = []
    var onMove: ((CardInstance, Destination) -> Void)?
    var onReorder: (([CardInstance]) -> Void)?
    var onDone: (() -> Void)?
    var onSecondary: (() -> Void)?
    var onShowOpponent: ((Bool) -> Void)?
    /// The board's zone (hand, library, graveyard, exile) under a point, in this view's coordinates.
    var zoneAt: ((CGPoint) -> Destination?)?
    /// Height at the bottom left uncovered (the board's own bottom bar).
    var uncoveredBottom: CGFloat = 0 { didSet { setNeedsLayout() } }
    /// The fan and scrollbar stay above this much of the bottom (the top of your hand).
    var contentBottomInset: CGFloat = 0 { didSet { setNeedsLayout() } }
    /// Where the browser's controls start (below the opponent's HUD).
    var topInset: CGFloat = 0 { didSet { setNeedsLayout() } }
    /// Called as a card is lifted (true) and put down (false), so the board can raise the browser
    /// above the hand while a card travels over it.
    var onLiftChanged: ((Bool) -> Void)?
    var isLifting: Bool { lifted != nil }
    /// Cards shown face down (the rest of the library under the cards being looked at).
    private(set) var faceDownIDs: Set<UUID> = []

    private let dim = UIView()
    private let titleLabel = UILabel()
    private let doneButton = UIButton(type: .custom)
    private let secondaryButton = UIButton(type: .custom)
    private let showButton = UIButton(type: .system)
    private let battlefieldZone = UILabel()
    /// Arena's line under the opening-hand title, and under Mulligan ("You will return 1 card…").
    private let subtitleLabel = UILabel()
    private let secondaryCaption = UILabel()
    /// Rules mode's "Return N Cards": the top zone becomes the Library, and dropping there sends
    /// the card to the bottom of the library.
    private var returnZone = false
    private let dropLabel = UILabel()
    private let scrollView = UIScrollView()
    private let track = UIView()
    private let thumb = UIView()
    private var cardViews: [UUID: PhoneBrowserCardView] = [:]
    private var didInitialScroll = false
    /// A card dragged in from the board (spring-loaded pile): where it would be inserted.
    private var externalGap: Int?
    private var externalPoint: CGPoint?
    private let moreButton = UIButton(type: .system)
    /// Extra actions (open the list view, search, shuffle…), shown as a "⋯" menu.
    var extraMenu: UIMenu? {
        didSet {
            moreButton.menu = extraMenu
            moreButton.showsMenuAsPrimaryAction = true
            moreButton.isHidden = extraMenu == nil
            setNeedsLayout()
        }
    }
    /// The number of face-down cards, shown on their condensed stack.
    private let hiddenCount = UILabel()
    private var lifted: (card: CardInstance, view: PhoneBrowserCardView, offset: CGPoint)?
    private var gapIndex: Int?
    private var hovered: Destination?
    /// Keeps scrolling while a lifted card is held near either edge.
    private var edgeScroll: CADisplayLink?
    private var liftedPoint: CGPoint?
    private(set) var showsOpponent = false
    /// The opening hand (Start Game): a large centred title, the whole hand fitting without
    /// scrolling, Mulligan and Keep side by side below it, Cancel at the top right, hand ability
    /// tiles on the cards, and no Battlefield zone.
    var isOpeningHand = false {
        didSet {
            battlefieldZone.isHidden = isOpeningHand
            cancelButton.isHidden = !isOpeningHand || onCancel == nil
            titleLabel.textAlignment = isOpeningHand ? .center : .natural
            titleLabel.font = UIFont(name: "Beleren2016-Bold", size: isOpeningHand ? 30 : 18) ?? .boldSystemFont(ofSize: isOpeningHand ? 30 : 18)
            scrollView.isScrollEnabled = !isOpeningHand
            for view in cardViews.values { view.showsAbilityTiles = isOpeningHand }
            setNeedsLayout()
        }
    }
    /// Nil hides Cancel (a Rules game's opening hand can't be cancelled; the engine owns the game).
    /// Rules mode's opening hand, as Arena words it: the title ("Opponent Goes First" /
    /// "Return 1 Card"), a line under it, the Keep and Mulligan buttons (nil hides one) with a caption
    /// under Mulligan, and whether the top zone is the Library to drag returned cards to.
    func configureOpening(title: String, subtitle: String?, done: String?, secondary: String?, secondaryCaption caption: String?, returnZone: Bool) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.font = .italicSystemFont(ofSize: 14)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        subtitleLabel.textAlignment = .center
        subtitleLabel.adjustsFontSizeToFitWidth = true
        subtitleLabel.minimumScaleFactor = 0.7
        if subtitleLabel.superview == nil { addSubview(subtitleLabel) }
        secondaryCaption.text = caption
        secondaryCaption.font = .italicSystemFont(ofSize: 12)
        secondaryCaption.textColor = UIColor.white.withAlphaComponent(0.85)
        secondaryCaption.textAlignment = .center
        secondaryCaption.numberOfLines = 2
        secondaryCaption.isHidden = caption == nil || secondary == nil
        if secondaryCaption.superview == nil { addSubview(secondaryCaption) }
        for (button, text) in [(doneButton, done), (secondaryButton, secondary)] {
            button.isHidden = text == nil
            if let text {
                let font = UIFont(name: "Beleren2016-Bold", size: 18) ?? .boldSystemFont(ofSize: 18)
                button.setAttributedTitle(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.white]), for: .normal)
                button.accessibilityLabel = text
            }
        }
        self.returnZone = returnZone
        battlefieldZone.text = returnZone ? "Library" : "Battlefield"
        battlefieldZone.isHidden = isOpeningHand && !returnZone
        setNeedsLayout()
    }

    var onCancel: (() -> Void)? { didSet { cancelButton.isHidden = !isOpeningHand || onCancel == nil } }
    private let cancelButton = UIButton(type: .custom)

    init(title: String, cards: [CardInstance], done: String = "Done", secondary: String? = nil, canShowOpponent: Bool = false) {
        super.init(frame: .zero)
        accessibilityIdentifier = "phone-zone-browser"
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.68)
        addSubview(dim)
        titleLabel.text = title
        titleLabel.font = UIFont(name: "Beleren2016-Bold", size: 18) ?? .boldSystemFont(ofSize: 18)
        titleLabel.textColor = .white
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        addSubview(titleLabel)
        let beleren = UIFont(name: "Beleren2016-Bold", size: 18) ?? .boldSystemFont(ofSize: 18)
        for (button, text, identifier, primary) in [(doneButton, done, "phone-browser-done", true), (secondaryButton, secondary ?? "", "phone-browser-secondary", false)] {
            // The stack's Resolve style: orange, Beleren, a glowing rim.
            button.setTitle(text, for: .normal)
            button.titleLabel?.font = beleren
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = primary ? UIColor(red: 0.86, green: 0.31, blue: 0.07, alpha: 1) : UIColor(white: 0.18, alpha: 0.95)
            button.layer.cornerRadius = 18
            button.layer.borderWidth = 1
            button.layer.borderColor = (primary ? UIColor.systemOrange.withAlphaComponent(0.9) : UIColor.white.withAlphaComponent(0.3)).cgColor
            button.layer.shadowColor = (primary ? UIColor.systemOrange : UIColor.black).cgColor
            button.layer.shadowOpacity = 0.4
            button.layer.shadowRadius = 6
            button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 18, bottom: 4, right: 18)
            button.accessibilityIdentifier = identifier
            addSubview(button)
        }
        secondaryButton.isHidden = secondary == nil
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = UIFont(name: "Beleren2016-Bold", size: 16) ?? .boldSystemFont(ofSize: 16)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.backgroundColor = UIColor(white: 0.18, alpha: 0.95)
        cancelButton.layer.cornerRadius = 16
        cancelButton.layer.borderWidth = 1
        cancelButton.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        cancelButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)
        cancelButton.accessibilityIdentifier = "phone-browser-cancel"
        cancelButton.isHidden = true
        cancelButton.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        addSubview(cancelButton)
        moreButton.setImage(UIImage(systemName: "ellipsis.circle.fill"), for: .normal)
        moreButton.setPreferredSymbolConfiguration(.init(pointSize: 26, weight: .semibold), forImageIn: .normal)
        moreButton.tintColor = UIColor(white: 0.85, alpha: 1)
        moreButton.accessibilityLabel = "More"
        moreButton.accessibilityIdentifier = "phone-browser-more"
        moreButton.isHidden = true
        addSubview(moreButton)
        doneButton.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)
        secondaryButton.addAction(UIAction { [weak self] _ in self?.onSecondary?() }, for: .touchUpInside)
        showButton.tintColor = .white
        showButton.titleLabel?.font = UIFont(name: "Beleren2016-Bold", size: 15) ?? .boldSystemFont(ofSize: 15)
        showButton.setTitleColor(.white, for: .normal)
        showButton.accessibilityIdentifier = "phone-browser-show-opponent"
        showButton.isHidden = !canShowOpponent
        showButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.showsOpponent.toggle()
            self.updateShowButton()
            self.onShowOpponent?(self.showsOpponent)
        }, for: .touchUpInside)
        updateShowButton()
        addSubview(showButton)
        battlefieldZone.text = "Battlefield"
        battlefieldZone.textAlignment = .center
        battlefieldZone.font = UIFont(name: "Beleren2016-Bold", size: 15) ?? .boldSystemFont(ofSize: 15)
        battlefieldZone.textColor = .white
        battlefieldZone.layer.cornerRadius = 10
        battlefieldZone.layer.masksToBounds = true
        battlefieldZone.layer.borderWidth = 1.5
        battlefieldZone.isAccessibilityElement = true
        battlefieldZone.accessibilityIdentifier = "phone-browser-zone-battlefield"
        setBattlefieldHighlighted(false)
        addSubview(battlefieldZone)
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.clipsToBounds = false
        addSubview(scrollView)
        track.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        track.layer.cornerRadius = 1.5
        addSubview(track)
        thumb.backgroundColor = UIColor(white: 0.85, alpha: 1)
        thumb.layer.cornerRadius = 12
        let arrows = UIImageView(image: UIImage(systemName: "arrowtriangle.left.and.line.vertical.and.arrowtriangle.right.fill"))
        arrows.tintColor = UIColor(white: 0.25, alpha: 1)
        arrows.contentMode = .scaleAspectFit
        arrows.frame = CGRect(x: 0, y: 0, width: 56, height: 24).insetBy(dx: 16, dy: 5)
        thumb.addSubview(arrows)
        thumb.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(scrubbed(_:))))
        thumb.accessibilityLabel = "Scroll cards"
        addSubview(thumb)
        dropLabel.font = UIFont(name: "Beleren2016-Bold", size: 14) ?? .boldSystemFont(ofSize: 14)
        dropLabel.textColor = .white
        dropLabel.backgroundColor = UIColor(red: 0.0, green: 0.36, blue: 0.68, alpha: 0.95)
        dropLabel.layer.borderColor = UIColor.systemCyan.cgColor
        dropLabel.layer.borderWidth = 1
        dropLabel.layer.cornerRadius = 6
        dropLabel.layer.masksToBounds = true
        dropLabel.textAlignment = .center
        dropLabel.isHidden = true
        addSubview(dropLabel)
        hiddenCount.font = UIFont(name: "Beleren2016-Bold", size: 16) ?? .boldSystemFont(ofSize: 16)
        hiddenCount.textColor = .white
        hiddenCount.textAlignment = .center
        hiddenCount.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        hiddenCount.layer.cornerRadius = 6
        hiddenCount.layer.masksToBounds = true
        hiddenCount.isHidden = true
        hiddenCount.accessibilityIdentifier = "phone-browser-hidden-count"
        scrollView.addSubview(hiddenCount)
        setCards(cards)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateShowButton() {
        // Arena's settings checkbox: a dark diamond when off, a glowing orange check when on.
        showButton.setImage(Self.arenaCheckbox(on: showsOpponent).withRenderingMode(.alwaysOriginal), for: .normal)
        showButton.setTitle("  Show Opponent", for: .normal)
        showButton.setTitleColor(showsOpponent ? .white : UIColor(white: 0.85, alpha: 1), for: .normal)
        showButton.accessibilityValue = showsOpponent ? "On" : "Off"
    }

    private static func arenaCheckbox(on: Bool) -> UIImage {
        let size = CGSize(width: 22, height: 22)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            if on {
                let check = UIBezierPath()
                check.move(to: CGPoint(x: 3, y: 12))
                check.addLine(to: CGPoint(x: 8.5, y: 18))
                check.addLine(to: CGPoint(x: 20, y: 3))
                check.lineWidth = 3.5
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                cg.setShadow(offset: .zero, blur: 4, color: UIColor(red: 1, green: 0.55, blue: 0.1, alpha: 0.9).cgColor)
                UIColor(red: 0.98, green: 0.62, blue: 0.2, alpha: 1).setStroke()
                check.stroke()
                cg.setShadow(offset: .zero, blur: 0, color: nil)
                check.lineWidth = 1.4
                UIColor(red: 1, green: 0.88, blue: 0.62, alpha: 1).setStroke()
                check.stroke()
            } else {
                let diamond = UIBezierPath()
                diamond.move(to: CGPoint(x: 11, y: 3)); diamond.addLine(to: CGPoint(x: 19, y: 11))
                diamond.addLine(to: CGPoint(x: 11, y: 19)); diamond.addLine(to: CGPoint(x: 3, y: 11)); diamond.close()
                UIColor(white: 0.04, alpha: 1).setFill(); diamond.fill()
                diamond.lineWidth = 1.2
                UIColor(white: 0.45, alpha: 1).setStroke(); diamond.stroke()
            }
        }
    }

    private func setBattlefieldHighlighted(_ on: Bool) {
        battlefieldZone.backgroundColor = on ? UIColor(red: 0.0, green: 0.36, blue: 0.68, alpha: 0.95) : UIColor(white: 0.1, alpha: 0.85)
        battlefieldZone.layer.borderColor = (on ? UIColor.systemCyan : UIColor.white.withAlphaComponent(0.35)).cgColor
    }

    /// The bottom bar stays uncovered and usable while the browser is up (unless a card is lifted).
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if lifted == nil, point.y > bounds.height - uncoveredBottom { return nil }
        return super.hitTest(point, with: event)
    }

    /// Replaces the shown cards (keeping views for cards still shown). `faceDown` cards show their back.
    func setCards(_ newCards: [CardInstance], faceDown: Set<UUID> = []) {
        let ids = Set(newCards.map(\.uuid))
        for (id, view) in cardViews where !ids.contains(id) && lifted?.view !== view { view.removeFromSuperview(); cardViews[id] = nil }
        // A card turning face up or down gets a fresh view.
        for id in faceDown.symmetricDifference(faceDownIDs) where cardViews[id] !== lifted?.view {
            cardViews[id]?.removeFromSuperview(); cardViews[id] = nil
        }
        faceDownIDs = faceDown
        cards = newCards
        for card in cards where cardViews[card.uuid] == nil {
            let hidden = faceDown.contains(card.uuid)
            let view = PhoneBrowserCardView(image: hidden ? UIImage.resource(named: "mtg-card-back-png-1")
                                   : card.representation.imageIfLoaded(type: .normal) ?? card.representation.image(type: .normal))
            view.isUserInteractionEnabled = true
            view.isAccessibilityElement = true
            view.accessibilityLabel = hidden ? "Face-down card" : card.representation.name
            view.accessibilityIdentifier = "phone-browser-card"
            view.accessibilityTraits = .button
            view.card = hidden ? nil : card
            view.showsAbilityTiles = isOpeningHand
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.minimumPressDuration = 0.15
            view.addGestureRecognizer(hold)
            scrollView.addSubview(view)
            cardViews[card.uuid] = view
        }
        setNeedsLayout()
    }

    /// The darkened area (everything above the uncovered bottom bar).
    private var coveredHeight: CGFloat { bounds.height - uncoveredBottom }
    /// Face-down cards condense into one stack (Look at); a whole face-down library (opened from its
    /// pile) stays spread out so cards can be dropped at exact positions.
    var condensesFaceDown = true

    /// A card dragged from the board over the fan: opens a gap where it would be inserted.
    func externalDragMoved(to point: CGPoint) {
        externalPoint = point
        if edgeScroll == nil {
            let link = CADisplayLink(target: PhoneDisplayLinkTarget { [weak self] in self?.scrollAtEdge() }, selector: #selector(PhoneDisplayLinkTarget.tick))
            link.add(to: .main, forMode: .common)
            edgeScroll = link
        }
        let gap = fanDropArea.contains(point) ? insertionIndex(at: point) : nil
        guard gap != externalGap else { return }
        externalGap = gap
        if gap != nil { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7) }
        layoutCards(animated: true)
    }

    /// Where a board card released at `point` goes in the fan (display order), or nil off the fan.
    func externalDrop(at point: CGPoint) -> Int? {
        externalPoint = nil
        edgeScroll?.invalidate(); edgeScroll = nil
        let index = fanDropArea.contains(point) ? insertionIndex(at: point) : nil
        externalGap = nil
        layoutCards(animated: true)
        return index
    }

    /// Where a card dragged in from the board drops into the fan: the band the cards occupy
    /// (full width, so the ends of a scrolled fan count), with a little slack above and below.
    private var fanDropArea: CGRect {
        let frames = cardViews.values.map { convert($0.frame, from: $0.superview) }
        guard let first = frames.first else { return scrollView.frame }
        let band = frames.dropFirst().reduce(first) { $0.union($1) }
        return CGRect(x: 0, y: band.minY - 24, width: bounds.width, height: band.height + 48)
    }

    /// Over the fan, where a card dragged in from the board would drop.
    func isOverFan(_ point: CGPoint) -> Bool { fanDropArea.contains(point) }

    /// The height of the cards in the fan (a card dragged over it matches them).
    var fanCardHeight: CGFloat { cardSize.height }

    /// Over the browser's dimmed area (not the uncovered bottom bar), where board drops don't fall through.
    func covers(_ point: CGPoint) -> Bool {
        bounds.contains(point) && point.y < bounds.height - uncoveredBottom
    }

    /// Over the "Battlefield" zone at the top, where a card dragged from the hand is played.
    func isOverBattlefieldZone(_ point: CGPoint) -> Bool {
        !battlefieldZone.isHidden && battlefieldZone.frame.insetBy(dx: -10, dy: -10).contains(point)
    }

    func cancelExternalDrag() {
        externalPoint = nil
        edgeScroll?.invalidate(); edgeScroll = nil
        guard externalGap != nil else { return }
        externalGap = nil
        layoutCards(animated: true)
    }

    /// Space for the fan: below the controls, above the scrollbar and the uncovered bottom bar.
    private var fanArea: CGRect {
        let top = (showButton.isHidden ? titleLabel.frame.maxY : showButton.frame.maxY) + 12
        let bottom = min(coveredHeight, bounds.height - contentBottomInset)
        // The opening hand keeps a strip below the fan for Mulligan and Keep.
        return CGRect(x: 0, y: top, width: bounds.width, height: max(80, bottom - top - (isOpeningHand ? Self.openingButtonStrip : 34)))
    }
    private static let openingButtonStrip: CGFloat = 60
    private var cardSize: CGSize {
        // Fills the space the controls leave (bigger on large screens), within the width too.
        var height = min(fanArea.height * 0.86, 460, bounds.width * 0.42 * 88 / 63)
        if isOpeningHand, cards.count > 0 {
            // The whole hand fits across, without scrolling.
            let safe = safeAreaInsets
            let available = bounds.width - max(24, safe.left + 12) - max(24, safe.right + 12) - 40
            let width = available / (1 + 0.6 * CGFloat(cards.count - 1))
            height = min(height, width * 88 / 63)
        }
        return CGSize(width: height * 63 / 88, height: height)
    }
    private var spacing: CGFloat { cardSize.width * 0.6 }

    override func layoutSubviews() {
        super.layoutSubviews()
        dim.frame = CGRect(x: 0, y: 0, width: bounds.width, height: coveredHeight)
        let safe = safeAreaInsets
        let left = max(16, safe.left + 12), right = max(16, safe.right + 12)
        let top = max(8, safe.top + 4, topInset + 6)
        titleLabel.frame = isOpeningHand
            ? CGRect(x: bounds.width * 0.2, y: top, width: bounds.width * 0.6, height: 40)
            : CGRect(x: left, y: top, width: bounds.width * 0.3, height: 32)
        let doneSize = doneButton.intrinsicContentSize
        doneButton.frame = CGRect(x: bounds.width - right - doneSize.width, y: top, width: doneSize.width, height: 36)
        let secondarySize = secondaryButton.intrinsicContentSize
        secondaryButton.frame = CGRect(x: doneButton.frame.minX - 10 - secondarySize.width, y: top, width: secondarySize.width, height: 36)
        let cancelSize = cancelButton.intrinsicContentSize
        cancelButton.frame = CGRect(x: bounds.width - right - cancelSize.width, y: top + 2, width: cancelSize.width, height: 32)
        let moreX = (secondaryButton.isHidden ? doneButton.frame.minX : secondaryButton.frame.minX) - 46
        moreButton.frame = CGRect(x: moreX, y: top, width: 36, height: 36)
        let zoneWidth = min(220, bounds.width * 0.26)
        battlefieldZone.frame = CGRect(x: (bounds.width - zoneWidth) / 2, y: top, width: zoneWidth, height: 36)
        let showSize = showButton.intrinsicContentSize
        showButton.frame = CGRect(x: left, y: titleLabel.frame.maxY + 2, width: showSize.width, height: 28)
        let size = cardSize
        let area = fanArea
        // The fan sits centred in its space.
        let fanTop = area.minY + max(0, (area.height - size.height - 30) / 2)
        scrollView.frame = CGRect(x: 0, y: fanTop, width: bounds.width, height: size.height + 30)
        track.frame = CGRect(x: bounds.width * 0.3, y: min(scrollView.frame.maxY + 6, min(coveredHeight, bounds.height - contentBottomInset) - 16), width: bounds.width * 0.4, height: 3)
        subtitleLabel.frame = CGRect(x: bounds.width * 0.15, y: titleLabel.frame.maxY, width: bounds.width * 0.7, height: subtitleLabel.text?.isEmpty == false ? 20 : 0)
        if returnZone {
            battlefieldZone.frame = CGRect(x: (bounds.width - zoneWidth) / 2, y: subtitleLabel.frame.maxY + 6, width: zoneWidth, height: 40)
        }
        if isOpeningHand {
            // Mulligan and Keep side by side, centred in the strip below the fan.
            let width = max(doneSize.width, secondarySize.width, 120)
            let stripTop = scrollView.frame.maxY
            let stripBottom = min(coveredHeight, bounds.height - contentBottomInset)
            let y = stripTop + max(0, (stripBottom - stripTop - 40) / 2)
            secondaryButton.frame = CGRect(x: bounds.midX - 8 - width, y: y, width: width, height: 40)
            doneButton.frame = CGRect(x: bounds.midX + 8, y: y, width: width, height: 40)
            secondaryCaption.frame = CGRect(x: secondaryButton.frame.midX - 130, y: secondaryButton.frame.maxY + 2, width: 260, height: secondaryCaption.isHidden ? 0 : 30)
        }
        layoutCards(animated: false)
        // Opens at the right end, where the top of the library is.
        if !didInitialScroll, bounds.width > 0 {
            didInitialScroll = true
            scrollView.contentOffset.x = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        }
    }

    private func layoutCards(animated: Bool) {
        let size = cardSize
        var order = cards.filter { $0.uuid != lifted?.card.uuid }
        if let gapIndex, let lifted { order.insert(lifted.card, at: min(gapIndex, order.count)) }
        // Face-down cards (the rest of the library) condense into a tight stack, as on Arena.
        var offsets: [CGFloat] = []
        var x: CGFloat = 0
        for (index, card) in order.enumerated() {
            if index > 0 {
                let previousHidden = faceDownIDs.contains(order[index - 1].uuid), hidden = faceDownIDs.contains(card.uuid)
                x += previousHidden && hidden && condensesFaceDown ? min(3, size.width * 0.02) : spacing
            }
            // A card dragged in from the board opens a gap where it would go.
            if index == externalGap { x += spacing }
            offsets.append(x)
        }
        if externalGap == order.count { x += spacing }
        let contentWidth = size.width + max(offsets.last ?? 0, x) + 80
        scrollView.contentSize = CGSize(width: max(bounds.width, contentWidth), height: scrollView.bounds.height)
        let startX = max(40, (bounds.width - contentWidth) / 2 + 40)
        let hidden = order.filter { faceDownIDs.contains($0.uuid) }
        let changes = {
            for (index, card) in order.enumerated() {
                guard let view = self.cardViews[card.uuid], view !== self.lifted?.view else { continue }
                view.transform = .identity
                view.bounds = CGRect(origin: .zero, size: size)
                view.cornerRadius = size.width * 0.045
                view.center = CGPoint(x: startX + size.width / 2 + offsets[index], y: 10 + size.height / 2)
                self.scrollView.bringSubviewToFront(view)
            }
            self.applyFan()
            // The hidden stack's count sits on its top card.
            if let top = hidden.last.flatMap({ self.cardViews[$0.uuid] }), top !== self.lifted?.view {
                self.hiddenCount.text = "\(hidden.count)"
                self.hiddenCount.bounds.size = CGSize(width: 40, height: 28)
                self.hiddenCount.center = CGPoint(x: top.center.x, y: top.center.y)
                self.hiddenCount.isHidden = false
                self.scrollView.bringSubviewToFront(self.hiddenCount)
            } else {
                self.hiddenCount.isHidden = true
            }
        }
        if animated { UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes) } else { changes() }
        updateScrollbar()
    }

    /// Arena's arc: cards tilt and dip away from the middle of the visible window.
    private func applyFan() {
        let middle = scrollView.contentOffset.x + scrollView.bounds.width / 2
        for view in cardViews.values where view !== lifted?.view {
            let position = (view.center.x - middle) / max(1, scrollView.bounds.width / 2)
            let clamped = max(-1.2, min(1.2, position))
            view.transform = CGAffineTransform(translationX: 0, y: clamped * clamped * 16).rotated(by: clamped * 0.12)
        }
    }

    private func updateScrollbar() {
        let content = scrollView.contentSize.width, visible = scrollView.bounds.width
        let scrolls = content > visible + 1
        track.isHidden = !scrolls; thumb.isHidden = !scrolls
        guard scrolls else { return }
        let progress = scrollView.contentOffset.x / max(1, content - visible)
        let thumbWidth: CGFloat = 56
        thumb.frame = CGRect(x: track.frame.minX + (track.frame.width - thumbWidth) * max(0, min(1, progress)),
                             y: track.frame.midY - 12, width: thumbWidth, height: 24)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { applyFan(); updateScrollbar() }

    @objc private func scrubbed(_ pan: UIPanGestureRecognizer) {
        let x = pan.location(in: self).x
        let progress = max(0, min(1, (x - track.frame.minX) / max(1, track.frame.width)))
        scrollView.contentOffset.x = progress * max(0, scrollView.contentSize.width - scrollView.bounds.width)
    }

    /// The zone a lifted card at `point` would go to: the Battlefield zone up top, or the board's.
    private func destination(at point: CGPoint) -> Destination? {
        if !battlefieldZone.isHidden, battlefieldZone.frame.insetBy(dx: -8, dy: -8).contains(point) { return returnZone ? .library : .battlefield }
        guard point.y > coveredHeight - 6 else { return nil }
        return zoneAt?(point)
    }

    private func showDropLabel(for destination: Destination?, above view: UIView) {
        guard let destination, destination != .battlefield, !(returnZone && destination == .library) else { dropLabel.isHidden = true; return }
        dropLabel.text = "Move to \(destination.title)"
        let size = (dropLabel.text! as NSString).size(withAttributes: [.font: dropLabel.font!])
        dropLabel.bounds.size = CGSize(width: size.width + 14, height: size.height + 6)
        let box = view.frame
        dropLabel.center = CGPoint(x: min(max(box.midX, dropLabel.bounds.width / 2 + 8), bounds.width - dropLabel.bounds.width / 2 - 8),
                                   y: max(box.minY - dropLabel.bounds.height / 2 - 8, dropLabel.bounds.height))
        dropLabel.isHidden = false
        bringSubviewToFront(dropLabel)
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            guard let view = gesture.view as? PhoneBrowserCardView,
                  let card = cards.first(where: { cardViews[$0.uuid] === view }) else { return }
            let center = scrollView.convert(view.center, to: self)
            addSubview(view)
            view.center = center
            lifted = (card, view, CGPoint(x: center.x - point.x, y: center.y - point.y))
            onLiftChanged?(true)
            gapIndex = cards.firstIndex { $0.uuid == card.uuid }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
            UIView.animate(withDuration: 0.15) { view.transform = CGAffineTransform(scaleX: 1.08, y: 1.08) }
            view.isHighlighted = true
        case .changed:
            guard let lifted else { return }
            let destination = destination(at: point)
            // Over the uncovered bottom bar the card shrinks so the zones under it stay readable.
            let scale: CGFloat = destination != nil && destination != .battlefield ? 0.55 : 1.08
            UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                lifted.view.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
            lifted.view.center = CGPoint(x: point.x + lifted.offset.x * scale, y: point.y + lifted.offset.y * scale)
            if destination != hovered {
                hovered = destination
                if destination != nil { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7) }
            }
            setBattlefieldHighlighted(destination == .battlefield || (returnZone && destination == .library))
            showDropLabel(for: destination, above: lifted.view)
            let newGap = destination == nil && scrollView.frame.insetBy(dx: 0, dy: -30).contains(point) ? insertionIndex(at: point) : gapIndex
            if newGap != gapIndex {
                gapIndex = newGap
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7) // reordering tick
                layoutCards(animated: true)
            }
            liftedPoint = point
            if edgeScroll == nil {
                let link = CADisplayLink(target: PhoneDisplayLinkTarget { [weak self] in self?.scrollAtEdge() }, selector: #selector(PhoneDisplayLinkTarget.tick))
                link.add(to: .main, forMode: .common)
                edgeScroll = link
            }
        case .ended, .cancelled, .failed:
            guard let lifted else { return }
            let destination = gesture.state == .ended ? destination(at: point) : nil
            edgeScroll?.invalidate(); edgeScroll = nil; liftedPoint = nil
            setBattlefieldHighlighted(false)
            dropLabel.isHidden = true
            hovered = nil
            lifted.view.isHighlighted = false
            self.lifted = nil
            onLiftChanged?(false)
            if let destination {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1)
                let card = lifted.card
                UIView.animate(withDuration: 0.18) {
                    lifted.view.alpha = 0
                    lifted.view.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
                } completion: { _ in lifted.view.removeFromSuperview() }
                cardViews[card.uuid] = nil
                cards.removeAll { $0.uuid == card.uuid }
                gapIndex = nil
                layoutCards(animated: true)
                onMove?(card, destination)
            } else {
                // Back into the fan, at the gap it was held over.
                let center = convert(lifted.view.center, to: scrollView)
                scrollView.addSubview(lifted.view)
                lifted.view.center = center
                var order = cards.filter { $0.uuid != lifted.card.uuid }
                order.insert(lifted.card, at: min(gapIndex ?? order.count, order.count))
                let reordered = order.map(\.uuid) != cards.map(\.uuid)
                cards = order
                gapIndex = nil
                layoutCards(animated: true)
                if reordered { onReorder?(cards) }
            }
        default: break
        }
    }

    /// While a lifted card is held near the left or right edge, the fan keeps scrolling that way
    /// (faster nearer the edge), so a card can travel from the top of the library to the bottom.
    private func scrollAtEdge() {
        if let point = externalPoint, lifted == nil {
            // A card dragged in from the board scrolls the fan the same way.
            guard externalGap != nil else { return }
            let zone: CGFloat = 70
            let speed: CGFloat = point.x < zone ? -(zone - point.x) / zone * 18
                : point.x > bounds.width - zone ? (point.x - (bounds.width - zone)) / zone * 18 : 0
            let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
            let offset = max(0, min(maxOffset, scrollView.contentOffset.x + speed))
            guard speed != 0, offset != scrollView.contentOffset.x else { return }
            scrollView.contentOffset.x = offset
            let gap = insertionIndex(at: point)
            if gap != externalGap { externalGap = gap; layoutCards(animated: true) }
            return
        }
        guard let point = liftedPoint, lifted != nil, destination(at: point) == nil else { return }
        let zone: CGFloat = 70
        let speed: CGFloat
        if point.x < zone { speed = -(zone - point.x) / zone * 18 }
        else if point.x > bounds.width - zone { speed = (point.x - (bounds.width - zone)) / zone * 18 }
        else { return }
        let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let offset = max(0, min(maxOffset, scrollView.contentOffset.x + speed))
        guard offset != scrollView.contentOffset.x else { return }
        scrollView.contentOffset.x = offset
        // The gap follows the card's place in the scrolled fan.
        let newGap = insertionIndex(at: point)
        if newGap != gapIndex {
            gapIndex = newGap
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
            layoutCards(animated: true)
        }
    }

    private func insertionIndex(at point: CGPoint) -> Int {
        let x = convert(point, to: scrollView).x
        let others = cards.filter { $0.uuid != lifted?.card.uuid }
        return others.filter { (cardViews[$0.uuid]?.center.x ?? 0) < x }.count
    }
}


/// A card in the browser: the image is clipped to the card's rounded corners, with a thin dark
/// edge and a soft shadow behind it, so overlapping cards (and the condensed stack) stay distinct.
final class PhoneBrowserCardView: UIView {
    let imageView: UIImageView
    /// The card shown (nil face down), for its hand ability tiles.
    var card: CardInstance?
    /// Arena's hand ability tiles on the card's left edge (the opening hand shows them).
    var showsAbilityTiles = false { didSet { if showsAbilityTiles != oldValue { tilesHeight = 0; setNeedsLayout() } } }
    private var tilesHost: UIView?
    private var tilesHeight: CGFloat = 0
    var cornerRadius: CGFloat = 0 { didSet { setNeedsLayout() } }
    /// Lifted: a bright blue rim.
    var isHighlighted = false {
        didSet {
            imageView.layer.borderWidth = isHighlighted ? 2 : 0.75
            imageView.layer.borderColor = (isHighlighted ? UIColor(red: 0.35, green: 0.75, blue: 1, alpha: 0.9) : UIColor.black.withAlphaComponent(0.7)).cgColor
        }
    }
    init(image: UIImage?) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerCurve = .continuous
        addSubview(imageView)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.6
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: -2, height: 2)
        isHighlighted = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        imageView.layer.cornerRadius = cornerRadius
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
        updateAbilityTiles()
    }

    private func updateAbilityTiles() {
        guard showsAbilityTiles, let card, !PhoneHandAbilityTiles.icons(for: card).isEmpty else {
            tilesHost?.removeFromSuperview(); tilesHost = nil; return
        }
        // Rebuilt only when the card's size changes.
        if tilesHost == nil || abs(tilesHeight - bounds.height) > 0.5 {
            tilesHost?.removeFromSuperview()
            let host = UIHostingController(rootView: PhoneHandAbilityTileStack(card: card, height: bounds.height)
                .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)).view!
            host.backgroundColor = .clear
            host.isUserInteractionEnabled = false
            addSubview(host)
            tilesHost = host
            tilesHeight = bounds.height
        }
        tilesHost?.frame = bounds
    }
}
