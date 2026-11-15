import UIKit
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

final class PhoneStackController: UITableViewController {
    private let session: PhoneGameSession
    private var subscriptions = Set<AnyCancellable>()
    var inspect: ((CardInstance) -> Void)?
    init(session: PhoneGameSession) { self.session = session; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stack"
        navigationItem.leftBarButtonItem = .init(barButtonSystemItem: .done, target: self, action: #selector(done))
        navigationItem.rightBarButtonItems = [
            .init(title: "Resolve Top", primaryAction: UIAction { [weak self] _ in
                guard let self, let item = self.session.game.stack.last else { return }
                self.session.send(.resolve(item.id))
            })
        ]
        session.$game.sink { [weak self] _ in
            // @Published emits before assignment; reload after the new snapshot is installed.
            DispatchQueue.main.async { self?.tableView.reloadData() }
        }.store(in: &subscriptions)
    }
    @objc private func done() { dismiss(animated: true) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { session.game.stack.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { "Top resolves first · swipe to counter/remove" }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = Array(session.game.stack.reversed())[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = item.text
        cell.detailTextLabel?.text = session.game.state[player: item.player].name.value
        cell.accessoryType = item.card == nil ? .none : .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let card = Array(session.game.stack.reversed())[indexPath.row].card { inspect?(card) }
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        session.send(.counterStack(Array(session.game.stack.reversed())[indexPath.row].id))
    }
}

// The original board menu's actions, organized into a scrollable native sheet.
final class BoardMenuAction {
    let title: String?
    let style: UIAlertAction.Style
    let handler: ((BoardMenuAction) -> Void)?
    init(title: String?, style: UIAlertAction.Style, handler: ((BoardMenuAction) -> Void)? = nil) {
        self.title = title; self.style = style; self.handler = handler
    }
}

/// The long-press board menu: actions split into pages (segmented control in the navigation bar,
/// or swipe left/right), with Reset and Done in the bar on every page.
final class BoardMenuSheetController: UITableViewController {
    private enum Page: Int, CaseIterable {
        case game, cards, board, more
        var title: String { ["Game", "Cards", "Board", "More"][rawValue] }
    }
    private var actions: [BoardMenuAction] = []
    var textFields: [UITextField]? = []
    /// Shown as the Reset bar button on every page.
    var onReset: (() -> Void)?
    private var page = Page.game
    private let pagePicker = UISegmentedControl(items: Page.allCases.map(\.title))

    init(title: String?, message: String?, preferredStyle: UIAlertController.Style) {
        super.init(style: .insetGrouped); self.title = title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func addAction(_ action: BoardMenuAction) { if action.style != .cancel { actions.append(action) } }
    func addTextField(configurationHandler: ((UITextField) -> Void)?) {
        let field = UITextField(); field.placeholder = "Card name or set and number"
        field.clearButtonMode = .whileEditing; configurationHandler?(field); textFields?.append(field)
    }
    private func page(of action: BoardMenuAction) -> Page {
        let name = action.title ?? ""
        if name.hasPrefix("Load") || name.contains("Preloaded") || name.contains("Connection") { return .game }
        if name.hasPrefix("Add") || name.hasPrefix("Drop") { return .cards }
        if name.contains("Hide") || name.contains("Selection") || name.contains("Reveal") { return .board }
        return .more
    }
    private var rows: [BoardMenuAction] { actions.filter { page(of: $0) == page } }
    /// The card text field leads the Cards page.
    private var hasField: Bool { page == .cards && textFields?.first != nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        pagePicker.selectedSegmentIndex = page.rawValue
        pagePicker.accessibilityIdentifier = "board-menu-pages"
        pagePicker.addAction(UIAction { [weak self] _ in
            guard let self, let page = Page(rawValue: self.pagePicker.selectedSegmentIndex) else { return }
            self.show(page)
        }, for: .valueChanged)
        navigationItem.titleView = pagePicker
        navigationItem.rightBarButtonItem = .init(barButtonSystemItem: .done, target: self, action: #selector(done))
        if onReset != nil {
            let reset = UIBarButtonItem(title: "Reset", primaryAction: UIAction { [weak self] _ in self?.onReset?() })
            reset.tintColor = .systemRed
            reset.accessibilityIdentifier = "board-menu-reset"
            navigationItem.leftBarButtonItem = reset
        }
        tableView.keyboardDismissMode = .onDrag
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            tableView.addGestureRecognizer(swipe)
        }
    }
    private func show(_ newPage: Page) {
        guard newPage != page else { return }
        let forward = newPage.rawValue > page.rawValue
        page = newPage
        pagePicker.selectedSegmentIndex = newPage.rawValue
        view.endEditing(true)
        let transition = CATransition()
        transition.type = .push
        transition.subtype = forward ? .fromRight : .fromLeft
        transition.duration = 0.2
        tableView.layer.add(transition, forKey: "page")
        tableView.reloadData()
    }
    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        let next = page.rawValue + (gesture.direction == .left ? 1 : -1)
        if let target = Page(rawValue: next) { show(target) }
    }
    @objc private func done() { dismiss(animated: true) }
    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count + (hasField ? 1 : 0) }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        if hasField && indexPath.row == 0, let field = textFields?.first {
            field.removeFromSuperview()
            field.translatesAutoresizingMaskIntoConstraints = false; cell.contentView.addSubview(field)
            NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor), field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor), field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12), field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)])
            cell.selectionStyle = .none
        } else {
            let action = rows[indexPath.row - (hasField ? 1 : 0)]
            cell.textLabel?.text = action.title; cell.textLabel?.numberOfLines = 0
            cell.textLabel?.textColor = action.style == .destructive ? .systemRed : .label
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if hasField && indexPath.row == 0 { return }
        let action = rows[indexPath.row - (hasField ? 1 : 0)]
        dismiss(animated: true) { action.handler?(action) }
    }
}

import SwiftUI
import CardService

struct PhoneStackCardsView: View {
    let items: [PhoneGame.StackItem]
    let inspect: (CardInstance) -> Void
    private func face(of card: CardInstance) -> MTGCard.Face? {
        if case .alternateFace(_, let face) = card.representation { return face }
        return nil
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ForEach(Array(items.compactMap(\.card).enumerated()), id: \.element.uuid) { index, card in
                    HandCardView(isVisible: true, card: card.representation.card, face: face(of: card))
                        .frame(width: geometry.size.width, height: geometry.size.width * 88 / 63)
                        .clipShape(RoundedRectangle(cornerRadius: max(5,geometry.size.width * 0.045),style: .continuous))
                        .offset(y: CGFloat(index) * min(34, geometry.size.height * 0.08))
                        .onTapGesture { inspect(card) }
                        .onLongPressGesture { inspect(card) }
                        .drag(card: card)
                        .accessibilityLabel(card.representation.name ?? "Spell on Stack")
                        .accessibilityIdentifier("phone-stack-full-card")
                }
            }
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
    private let library = OfflineGameLibrary.shared
    var body: some View {
        NavigationStack {
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
            }
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
        table.dataSource = self
        table.delegate = self
        table.accessibilityIdentifier = "phone-hand-actions"
    }
    @objc private func done() { navigationController?.dismiss(animated: true) }
    func numberOfSections(in tableView: UITableView) -> Int { 2 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 2 : moreActions.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = indexPath.section == 0 ? (indexPath.row == 0 ? "Play" : "Play Tapped") : moreActions[indexPath.row].title
        cell.textLabel?.textColor = indexPath.section == 1 && moreActions[indexPath.row].style == .destructive ? .systemRed : view.tintColor
        cell.accessibilityTraits = .button
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 1 {
            let action = moreActions[indexPath.row]
            navigationController?.dismiss(animated: true) { [self] in action.handler?(self) }
            return
        }
        let options = Command.PlayCardParameters.options(for: card, tapped: indexPath.row == 1)
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
extension PhoneStackController: PhoneSheetProvidesClose {}
extension BoardMenuSheetController: PhoneSheetProvidesClose {}
extension PhoneHandCardController: PhoneSheetProvidesClose {}
