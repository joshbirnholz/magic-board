//
//  BoardViewController.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/12/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import CardService
import RxSwift
import RxCocoa
import CardView
import SwiftUI
import Combine

class BoardViewController: UIViewController {

    /// The board is landscape only; pile sheets (PhonePortraitNavigationController) may rotate to portrait.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        addPhoneCloseButtonIfNeeded(to: viewControllerToPresent)
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }
	
	@IBOutlet weak var scrollView: UIScrollView!
	@IBOutlet weak var board: UIView!
	@IBOutlet weak var boardWidthConstraint: NSLayoutConstraint!
	
	@IBOutlet weak var player1BarContainerView: UIView!
	@IBOutlet weak var player2BarContainerView: UIView!
  @IBOutlet weak var landOrganizerContainerView: UIView!
	
	weak var focusViewController: UIViewController?
  
  private var isSelectionEnabled: Bool = true
  private var phoneSubscriptions = Set<AnyCancellable>()
  private var savedPhoneConstraints: [(NSLayoutConstraint, CGFloat)] = []
  private var previousPhoneHandIDs: Set<UUID>?
  private var phoneLayoutInProgress = false
  private var phoneHandShield: PhoneHandShieldView?
  private var phoneOpponentLandContainer: PhoneLandContainerView?
  private var phoneLandContentMaxX: CGFloat?
  /// Column layout: reserved right edge of the land rows for this game (only grows, with one stack of slack).
  private var phoneLandReservation: (gameID: UUID, maxX: CGFloat)?
  private var phoneRulesLandReservationSize: CGSize?
  private weak var phoneBackgroundLogo: UIImageView?
  private var phoneAttackIndicators: [UUID: PhoneAttackIndicatorView] = [:]
  /// Glows around attacking (orange) and blocking (blue) cards' actual art.
  private var phoneCombatGlows: [UUID: UIView] = [:]
  private var phoneGroupButtons: [UIButton] = []
  private var phoneRowOffsets: [String: Int] = [:]
  private var phoneDraggedCard: CardInstance?
  /// Screen size of a battlefield card at the current zoom (hand drags shrink to it).
  private var phoneFieldCardExtent: CGFloat = 100
  /// Set by the start menu; acted on once the board is on screen.
  var pendingDestination: AppDestination?
  /// The card a drag is hovering for attachment; `armed` once the delay passed and the Attach glow shows.
  private var phoneAttachHover: (intent: PhoneDropIntent, armed: Bool, generation: Int)?
  private var phoneAttachLabel: UILabel?
  private var phoneLastDragPoint: CGPoint?
  private var phoneAttachGeneration = 0
  private var phoneAttachIndicator: UIView?
  private var phoneDragPreview: UIView?
  /// The hand card being dragged (or landing), with where it was picked up.
  private var phoneHandDrag: PhoneHandDragState?
  private var phoneHandPreviewHost: UIHostingController<PhoneHandCardFace>?
  private var phoneHandMiniPreview: UIView?
  private var phoneHandMiniHost: UIViewController?
  private var phoneStackButton: UIButton?
  private var phoneStackCards: UIHostingController<PhoneStackCardsView>?
  /// Full-screen holder of the stack's hosting view that only takes touches on drawn stack cards,
  /// so the empty part of the fan's frame doesn't block the battlefield (or its page buttons).
  private var phoneStackContainer: PhoneTouchFilterView?
  /// Rules mode's prompt panel, kept above the board and just above the local phase button (Arena).
  private var rulesPromptHost: UIViewController?
  private var rulesBannerHost: UIViewController?
  /// The banner's vertical position in the gap between the two players' permanents.
  private var rulesBannerCenterY: NSLayoutConstraint?
  /// Rules mode's phase lights beside each life total: local, then opponent.
  private var rulesPhaseMarkerHosts: [UIHostingController<PhonePhaseMarkers>] = []
  private var phoneLifeHosts: [Player.Identifier: UIHostingController<LifeTracker>] = [:]
  private var rulesFastForwardHost: UIViewController?
  private var rulesFastForwardConstraints: [NSLayoutConstraint] = []
  /// Full-screen Rules decisions (mulligan, choices, game over); hidden when there's none.
  private var rulesModalHost: UIViewController?
  private var rulesPromptRestoreHost: UIViewController?
  private var phoneSettingsButton: UIButton?
  /// Arena's phase row, second button and fast-forward pill, just above the main button.
  private var rulesActionHost: UIViewController?
  private var rulesActionConstraints: [NSLayoutConstraint] = []
  private var rulesPromptBottom: NSLayoutConstraint?
  private var phoneStackResolveButton: UIButton?
  private var phoneStackCollapsed = false
  private var phoneTargetArcs: PhoneTargetArcsView?
  private var phoneKnownStack: (gameID: UUID, ids: Set<UUID>)?
  private var phoneStackDrag: PhoneStackDragState?
  private var phoneStackDragOutline: UIView?
  private var phoneInspectionOutline: UIView?
  private var phoneZoneHoverKey: String?
  /// Cards revealed to this phone's player, listed by the Revealed Cards sheet.
  private let phoneRevealedToMe = BehaviorRelay<OrderedSet<CardInstance>>(value: [])
  private var phoneRevealedShownIDs: Set<UUID> = []
  /// Shuffle counts already seen (nil until the first snapshot, which never animates).
  private var phoneSeenShuffles: [String: Int]?
  private var phoneBrowser: PhoneZoneBrowserView?
  private var phoneBrowserMode: PhoneBrowserMode?
  /// The opening deal this phone's player kept (so a late update doesn't reopen its browser).
  private var phoneKeptOpeningID: UUID?
  /// Spring-loaded piles: the pile a dragged card is held over, since when, and the browser it opened.
  private var phoneSpringPile: (location: Pile.Location, player: Player.Identifier, since: CFTimeInterval)?
  private var phoneSpringTimer: Timer?
  private var phoneSpringOpened = false
  private var phoneSpringPoint: CGPoint = .zero
  private var phoneSpringCard: CardInstance?
  /// The browser's cards, in its current order.
  private var phoneBrowserIDs: [UUID] = []
  /// The cards Look at turned face up (they stay face up wherever they're moved to in the fan).
  private var phoneBrowserLookedAt: Set<UUID> = []
  /// Cards dropped face up into an open browser: they were just seen, so they stay face up in
  /// their spot (in a library too) until the browser closes.
  private var phoneBrowserSeen: Set<UUID> = []
  /// Arena's blue "release to play" glow around the dragged hand card.
  private var phoneHandPlayGlow: PhoneHandPlayGlow?
  /// The battlefield band along the right edge (where the stack shows), for the "Move to Stack"
  /// drop area that appears when a dragged card nears the edge.
  private var phoneStackCastBand: CGRect = .zero
  private var phoneStackCastZone: UIView?
  private var phoneStackCastArmed = false
  private var phoneStackArcLink: CADisplayLink?
  /// The arc following the finger during a stack drag; faded out separately when the drag ends.
  private var phoneStackDragArc: PhoneTargetArcsView?
  private var phoneStackDragLabel: UILabel?
  private var phoneStackPeekButton: UIButton?
  private var phoneStackSlideAnimator: UIViewPropertyAnimator?
  private var phoneCombatLines: PhoneCombatLinesView?
  private var phoneCombatPreview: (blocker: UUID, attacker: UUID)?
  private var phonePreviousStack: [PhoneGame.StackItem] = []
  private var phonePreviousStackFrames: [UUID: CGRect] = [:]
  private var phoneResolutionHosts: [UUID: UIViewController] = [:]
  /// Where each of the opponent's cards was at the last refresh (and where their battlefield cards
  /// were drawn at the last layout), so a move between zones can fly from the old spot to the new one.
  private var phoneOpponentZones: (gameID: UUID, zones: [UUID: PhoneOpponentZone])?
  private var phonePreviousFieldGeometry: [UUID: PhoneFlightGeometry] = [:]
  /// A spell flying onto the stack: its stack card stays invisible until the flight lands.
  private var phoneConcealedArrival: UUID?
  private var phoneBarBackgrounds: [UIView] = []
  private var lastPhoneBounds = CGRect.zero
  private var compactBarConstraints: [NSLayoutConstraint] = []
  private var phoneStateBag = DisposeBag()
  private weak var phonePacketChooser: UIViewController?
  private var phonePacketSelectionID: UUID?
  override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
    phoneMode == nil ? [] : .bottom
  }

  // Keep auto-hide disabled: bottom-edge swipe protection takes precedence.
  override var prefersHomeIndicatorAutoHidden: Bool { false }

  private var phoneMode: PhoneGameSession? { AppDelegate.shared.phoneSession }

  
  
  var dropFaceUp: Bool = true
  
  @AppStorage("showLandOrganizer") var showLandOrganizer: Bool = true
	
	var loadDeckPlayerIdentifier: Player.Identifier?
	
	//	var cards: [MiniCardView: CardInstance] = [:]
	
	private let bag = DisposeBag()
	
	override func viewDidLoad() {
		// Cards laid out past the board view's edges (Phone Play's field is wider than the zoomed
		// board) must still get touches.
		if type(of: board!) == UIView.self { object_setClass(board!, PhoneBoardContentView.self) }
		super.viewDidLoad()
        AppDelegate.shared.boardController = self
		
		UIView.setAnimationsEnabled(false)
		
		splitViewController?.preferredDisplayMode = .primaryHidden
		splitViewController?.view.backgroundColor = .clear
		view.window?.backgroundColor = .black
		
		boardWidthConstraint.constant = UIScreen.main.bounds.width * 10
		
		let tap = UITapGestureRecognizer(target: self, action: #selector(tapRecognized(gestureRecognizer:)))
		board.addGestureRecognizer(tap)
		
		let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressRecognized(gestureRecognizer:)))
		board.addGestureRecognizer(longPress)
		
		let dropInteraction = UIDropInteraction(delegate: self)
		board.addInteraction(dropInteraction)
		
		//		for card in cards.values {
		//			card.remove.onNext(())
		//		}
		
		for card in GameState.current.battlefield.value {
			addCardViewToBattlefield(for: card)
		}
    
    updateLandOrganizerLands()
		
		GameState.current.player2.name
			.subscribe(onNext: { (name) in
				if GameState.current.player1.name.value == name {
					GameState.current.player1.name.accept("\(name) (2)")
				}
			}).disposed(by: bag)
		
		UIView.setAnimationsEnabled(true)
    
    updateSelection()
    
//    setupLandOrganizer()
		
		AppDelegate.shared.transceiver.receive(Command.self) { [weak self] command, peer in
      self?.perform(command)
		}
    AppDelegate.shared.webServer.handleCommand = perform(_:)
		
//		GameState.current.accept(self.displayedGameState())
	}
  
  func perform(_ command: Command) {
    if let phoneMode { phoneMode.send(command); return }
    guard AppDelegate.shared.role.isBoard else { return }
    switch command {
    case .rebroadcast:
      AppDelegate.shared.transceiver.broadcast(GameState.current)
    case .moveCardsToBattlefield(let parameters):
      let cardInstances = GameState.current.cardInstances(with: parameters.map { $0.cardInstanceID })
      
      let shouldFocus = cardInstances.values.count == 1 && cardInstances.values.first?.pile?.location == .hand
      
      for param in parameters {
        guard let cardInstance = cardInstances[param.cardInstanceID] else { continue }
        cardInstance.revealedPlayers.mutate {
          $0.remove(cardInstance.ownerIdentifier)
        }
        switch param.faceIndex {
        case _ where param.mode == .morph:
          cardInstance.representation = .morph(cardInstance.representation.card)
        case _ where param.mode == .foretell:
          cardInstance.representation = .foretold(cardInstance.representation.card)
        case _ where param.mode == .manifest:
          cardInstance.representation = .manifest(cardInstance.representation.card)
        case _ where param.mode == .cloak || param.mode == .disguise:
          cardInstance.representation = .mysterious(cardInstance.representation.card)
        case _ where param.mode == .prototype:
          cardInstance.representation = .prototyped(cardInstance.representation.card)
        case (0...)?:
          guard let index = param.faceIndex, let face = cardInstance.representation.card.cardFaces?[index] else { fallthrough }
          cardInstance.representation = .alternateFace(cardInstance.representation.card, face)
        case (..<0)?:
          cardInstance.representation = .faceDown(cardInstance.representation)
        default:
          break
        }
        
        if param.increaseTax {
          cardInstance.commanderCasts.mutate { value in
            value += 1
          }
        }
        
        if param.tapped {
          cardInstance.isTapped.accept(true)
        }
      }
      
      // Plotted cards go to their owner's exile instead of the battlefield.
      let plotted = Set(parameters.filter { $0.mode == .plot }.map(\.cardInstanceID))
      for card in cardInstances.values where plotted.contains(card.uuid) {
        GameState.current.move(cardInstances: [card], to: GameState.current[player: card.ownerIdentifier].exile)
      }
      self.moveCardItemsToBattlefield(cardInstances.values.filter { !plotted.contains($0.uuid) }, at: self.visibleBoardCenter)
      
      if shouldFocus, let cardInstance: CardInstance = cardInstances.values.first, let typeLine = cardInstance.representation.typeLine, typeLine.contains("Instant") || typeLine.contains("Sorcery") {
        focus(on: cardInstance, view: nil)
      }
    case .moveCards(let parameters):
      guard let destinationPile = parameters.destination.pile else { return }
      
      let cardInstances = GameState.current.cardInstances(with: parameters.cardInstanceIDs).values.sorted { (first, second) -> Bool in
        if let firstIndex = first.indexInPile, let secondIndex = second.indexInPile {
          return firstIndex > secondIndex
        }
        return false
      }
      
      cardInstances.forEach { cardInstance in
        cardInstance.revealedPlayers.mutate {
          $0.remove(cardInstance.ownerIdentifier)
        }
      }
      
      GameState.current.move(cardInstances: cardInstances, to: destinationPile, at: parameters.insertionIndex)
    case .loadDeck(let parameters):
      switch parameters.source {
      case .decklist:
        let groups = DeckParser.parse(deckList: parameters.deckList, autofix: true)
        self.loadDeck(groups, playerIdentifier: parameters.playerIdentifier, handSmoothing: parameters.handSmoothing)
      case .remoteURL:
        guard let url = URL(string: parameters.deckList) else { return }
        Task {
          do {
            let groups = try await DeckParser.load(fromURL: url)
            DispatchQueue.main.async {
              self.loadDeck(groups, playerIdentifier: parameters.playerIdentifier)
            }
          } catch {
            print(error)
          }
        }
      }
    case .revealCardsToPlayer(let parameters):
      GameState.current.cardInstances(with: parameters.cardInstanceIDs).values.forEach {
        $0.revealedPlayers.mutate { $0.insert(parameters.playerIdentifier) }
      }
      try? GameState.current.save()
    case .removeAllRevealedCards(let playerIdentifier):
      for cardInstance in GameState.current.allCards.values {
        cardInstance.revealedPlayers.mutate {
          $0.remove(playerIdentifier)
        }
      }
      try? GameState.current.save()
    case .unrevealCardsToPlayer(let parameters):
      GameState.current.cardInstances(with: parameters.cardInstanceIDs).values.forEach {
        $0.revealedPlayers.mutate { $0.remove(parameters.playerIdentifier) }
      }
      try? GameState.current.save()
    case .reorderHand(let parameters):
      let cardInstances = GameState.current.cardInstances(with: parameters.cardInstanceIDs)
      
      let handCardsNotThere = GameState.current[player: parameters.playerIdentifier].hand.cards.value.filter {
        cardInstances[$0.uuid] == nil
      }
      
      let reorderedCards = parameters.cardInstanceIDs.compactMap { cardInstances[$0] } + handCardsNotThere
      
      GameState.current[player: parameters.playerIdentifier].hand.cards.accept(OrderedSet(reorderedCards))
      
//        GameState.current.cardInstances(with: parameters.cardInstanceIDs).values.forEach {
//          $0.revealedPlayers.mutate { $0.insert(parameters.playerIdentifier) }
//        }
//        try? GameState.current.save()
    }
  }
	
	var visibleBoardCenter: CGPoint {
		let visibleRect = scrollView.convert(scrollView.bounds, to: board!)
		return CGPoint(x: visibleRect.midX, y: visibleRect.midY)
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		
		scrollView.zoomScale = 0.35
		centerScrollView()
		
		for cardInstance in GameState.current.allCards.values {
			cardView(for: cardInstance)?.cardView.layoutSubviews()
		}
		
		updatePlayersHidden()
        if phoneMode != nil { if phoneSubscriptions.isEmpty { attachPhoneSession() } else { refreshPhoneBoard() } }
        if let destination = pendingDestination {
            pendingDestination = nil
            switch destination {
            case .board: break
            case .host(let resume): startPhoneGame(resume: resume)
            case .join: joinPhoneGame()
            case .rules(let adapter): startRulesGame(adapter)
            case .hand: showExistingCompanion(exitsToStart: true)
            }
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--phone-companion-fixture"), !AppDelegate.shared.didPresentCompanionFixture {
            AppDelegate.shared.didPresentCompanionFixture = true
            AppDelegate.shared.transceiver.stop()
            GameState.sessionSave = { _ in }
            if let fixture = try? PhoneGame.boardFixture() { GameState.current.update(withValuesFrom: fixture.state) }
            showExistingCompanion()
        } else if ProcessInfo.processInfo.arguments.contains("--phone-board-fixture") || ProcessInfo.processInfo.arguments.contains("--phone-network-host"), phoneMode == nil {
            startPhoneGame(resume: false, fixture: true)
        } else if ProcessInfo.processInfo.arguments.contains("--phone-network-join"), phoneMode == nil {
            let session = PhoneGameSession()
            AppDelegate.shared.phoneSession = session
            session.joinFixture()
            attachPhoneSession()
        }
        #endif
	}
	
//  func setupLandOrganizer() {
//    let relay: BehaviorRelay<OrderedSet<CardInstance>> = BehaviorRelay(value: [])
//    
//    GameState.current.battlefield
//      .map { [weak self] set -> OrderedSet<CardInstance> in
//        guard let self else { return OrderedSet() }
//        return OrderedSet(set.filter {
//          $0.ownerIdentifier == .a &&
//          $0.representation.typeLine?.lowercased().contains("land") == true &&
//          !$0.isPowerToughnessVisible.value
//        })
//      }.bind(to: relay)
//      .disposed(by: bag)
//    
//    let landOrganizer = LandOrganizer(cardInstances: ObservableBridge(relay))
//    
//    let viewController = UIHostingController(rootView: landOrganizer)
//    addChild(viewController)
//    view.addSubview(viewController.view)
//    viewController.didMove(toParent: self)
//    
//    viewController.view.translatesAutoresizingMaskIntoConstraints = false
//    NSLayoutConstraint.activate([
//      viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
//      viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
//      viewController.view.heightAnchor.constraint(equalToConstant: 130),
//      viewController.view.topAnchor.constraint(equalTo: view.topAnchor)
//      
////      viewController.view.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 1),
////      viewController.view.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 130),
////      viewController.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
////      viewController.view.centerYAnchor.constraint(equalTo: view.centerYAnchor)
//    ])
//  }
  
	func updatePlayersHidden() {
		player1BarContainerView.isHidden = GameState.current.player1.isHidden
		player2BarContainerView.isHidden = GameState.current.player2.isHidden
		player1BarContainerView.isUserInteractionEnabled = !GameState.current.player1.isHidden
		player2BarContainerView.isUserInteractionEnabled = !GameState.current.player2.isHidden
	}
  
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if phoneMode != nil, !phoneLayoutInProgress { layoutPhoneBattlefield() }
        if phoneMode != nil { layoutPhoneHandOverlay() }
        // The zone browser covers everything, including the hand.
        if let browser = phoneBrowser {
            browser.frame = view.bounds
            browser.uncoveredBottom = phoneBrowserUncoveredBottom
            browser.topInset = phoneBrowserTopInset
            browser.contentBottomInset = phoneBrowserContentBottomInset
            orderPhoneBrowser()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard phoneMode != nil else { return }
        // Fold/unfold and rotation: re-place the hand overlay once the new bounds are final.
        // A card held in the hand can't survive the size change; put it back.
        abandonPhoneHandDrag()
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.view.setNeedsLayout()
            self?.layoutPhoneHandOverlay()
            // Once more after the child HUD has settled at the new size.
            DispatchQueue.main.async { self?.layoutPhoneHandOverlay() }
        }
    }

  private var bottomBarA: BottomBarViewController?
  private var bottomBarB: BottomBarViewController?
  private var landOrganizer: LandOrganizerViewController?
  private var opponentLandOrganizer: LandOrganizerViewController?
  
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "EmbedPlayer2Bar" {
			let bottomBar = segue.destination as? BottomBarViewController
			bottomBar?.player = GameState.current.player2
			bottomBar?.delegate = self
			segue.destination.view.transform = CGAffineTransform(rotationAngle: .pi)
      
      // This doesn't update the card on the phone (commander tax)
//      bottomBar?.focusOn = { [weak self] cardInstance in
//        self?.focusViewController?.dismiss(animated: true)
//        if let cardInstance {
//          self?.focus(on: cardInstance, view: nil)
//        }
//      }
      
      self.bottomBarA = bottomBar
      
//      var elements: [UIMenuElement] = []
//      
//      let toggleButton = UIAction(title: "Toggle Mode") { [weak self] _ in
//        self?.isEditing.toggle()
//      }
//      elements.append(toggleButton)
//      
//      bottomBar?.untapButton.menu = UIMenu(children: elements)
		} else if segue.identifier == "EmbedPlayer1Bar" {
			let bottomBar = segue.destination as? BottomBarViewController
			bottomBar?.player = GameState.current.player1
			bottomBar?.delegate = self
      
      // This doesn't update the card on the phone (commander tax)
//      bottomBar?.focusOn = { [weak self] cardInstance in
//        self?.focusViewController?.dismiss(animated: true)
//        if let cardInstance {
//          self?.focus(on: cardInstance, view: nil)
//        }
//      }
      
      self.bottomBarB = bottomBar
    } else if segue.identifier == "EmbedLandOrganizer", let organizer = segue.destination as? LandOrganizerViewController {
      organizer.onLongPress = { [weak self] card in
        self?.focus(on: card, view: nil)
      }
      organizer.playerIdentifier = .a
      self.landOrganizer = organizer
    }
	}
	
	func cardView(for cardInstance: CardInstance) -> MiniCardView? {
		board.subviews.first { (view) -> Bool in
			guard let cardView = view as? MiniCardView else { return false }
			return cardView.cardInstance == cardInstance
		} as? MiniCardView
	}
	
	private var cardInstanceDisposeBags: [UUID: DisposeBag] = [:]
  
  @objc private func tapUnTapGestureRecognized(_ gestureRecognizer: UIGestureRecognizer) {
    guard let view = gestureRecognizer.view as? MiniCardView, let cardInstance = view.cardInstance else { return }
    if let session = phoneMode, session.mode == .rules {
        session.send(.tap(cardInstance.uuid))
        return
    }
    // During your combat, tapping one of your creatures marks or unmarks it as an attacker
    // (tapping or untapping it unless it has vigilance). The card menu can still just tap it.
    if let session = phoneMode, session.game.attackingPlayer == session.player,
       cardInstance.controllerIdentifier.value == session.player, cardInstance.isPhoneCreature,
       session.game.attachments[cardInstance.uuid] == nil, session.game.state.battlefield.value.contains(cardInstance) {
        session.send(.attack(cardInstance.uuid, tap: !cardInstance.hasVigilance))
        return
    }
    // During the opponent's combat, tapping one of your creatures blocks: it blocks the first
    // attacker, each further tap moves it to the next attacker, and after the last it stops blocking.
    if let session = phoneMode, canPhoneBlock(with: cardInstance.uuid, session: session) {
        let attackers = session.game.state.battlefield.value.filter { session.game.combat?.attackers.contains($0.uuid) == true }.map(\.uuid)
        guard !attackers.isEmpty else { return }
        let next: UUID?
        if let current = session.game.combat?.blockers[cardInstance.uuid], let index = attackers.firstIndex(of: current) {
            next = attackers.indices.contains(index + 1) ? attackers[index + 1] : nil
        } else {
            next = attackers.first
        }
        session.send(.block(cardInstance.uuid, next))
        return
    }
    cardInstance.isTapped.toggle()
    try? GameState.current.save()
  }
  
  private func tapUnTap() {
    
  }
	
  fileprivate func addCardViewToBattlefield(for cardInstance: CardInstance) {
    let point: CGPoint
    if let existing = cardInstance.center.value { point = existing }
    else if phoneMode != nil { point = visibleBoardCenter }
    else { return }
    
    if let cardView = self.cardView(for: cardInstance) {
      cardView.center = point
      return
    }
		
		let cardView = MiniCardView(frame: CGRect(x: point.x, y: point.y, width: 500, height: 500))
		
        cardView.usesPlayerPerspective = phoneMode != nil
		cardView.cardInstance = cardInstance
    
    // This is buggy!
    if !dropFaceUp && phoneMode == nil {
      cardInstance.representation = .faceDown(cardInstance.representation)
    }
    
		let panGesture = UIPanGestureRecognizer(target: self, action: #selector(panRecognized(gestureRecognizer:)))
		panGesture.maximumNumberOfTouches = 1
		cardView.addGestureRecognizer(panGesture)
		
//		let focusGesture = UILongPressGestureRecognizer(target: self, action: #selector(longPressOnCardRecognized(gestureRecognizer:)))
//		focusGesture.minimumPressDuration = 0.3
//		cardView.addGestureRecognizer(focusGesture)
    
    let focusInteracion = UIContextMenuInteraction(delegate: self)
    cardView.addInteraction(focusInteracion)
    
    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapUnTapGestureRecognized))
    cardView.addGestureRecognizer(tapGesture)
		
		board.addSubview(cardView)
		cardView.center = point
    
    cardView.isHidden = showLandOrganizer && self.landOrganizer?.shouldIncludeCard(cardInstance) == true
		
		if cardInstanceDisposeBags[cardInstance.uuid] == nil {
			let cardBag = DisposeBag()
			
			cardInstance.remove
				.subscribe(onNext: { [weak self] (_) in
          self?.selectedCardInstances.remove(cardView.cardInstance)
					cardView.removeFromSuperview()
					
					if GameState.current.battlefield.value.contains(cardInstance) {
						GameState.current.battlefield.mutate {
							$0.remove(cardInstance)
						}
					}
					
					if let presentedViewController = self?.presentedViewController, presentedViewController == self?.focusViewController {
						self?.dismiss(animated: true, completion: nil)
					}
					
					self?.cardInstanceDisposeBags[cardInstance.uuid] = nil
				}).disposed(by: cardBag)
			
			cardInstance.createCards
				.subscribe(onNext: { getter in
					guard var center = cardInstance.center.value ?? (self.phoneMode != nil ? self.visibleBoardCenter : nil) else { return }
					center.x += 28
					center.y += 72
					self.createCards(at: center, getter: getter)
				}).disposed(by: cardBag)
			
			cardInstanceDisposeBags[cardInstance.uuid] = cardBag
		}
		
//		cardInstance.center
//			.subscribe(onNext: { [weak self] _ in
//				if let presentedController = self?.presentedViewController, presentedController == self?.focusViewController {
//					self?.dismiss(animated: true, completion: nil)
//				}
//			}).disposed(by: bag)
		
		
		
//		let interaction = UIDragInteraction(delegate: self)
//		cardView.cardView.addInteraction(interaction)
	}
	
	var scrollViewCenter: CGPoint {
		let centerOffsetX = (scrollView.contentSize.width - scrollView.frame.size.width) / 2
		let centerOffsetY = (scrollView.contentSize.height - scrollView.frame.size.height) / 2
		let centerPoint = CGPoint(x: centerOffsetX, y: centerOffsetY)
		return centerPoint
	}
	
	func centerScrollView() {
		scrollView.setContentOffset(scrollViewCenter, animated: false)
	}
	
	@objc func tapRecognized(gestureRecognizer: UITapGestureRecognizer) {
		if let presentedViewController = presentedViewController, presentedViewController == focusViewController {
			dismiss(animated: true, completion: nil)
		}
    
    selectionStartPoint = nil
    selectionEndPoint = nil
    selectionView.isHidden = true
    selectedCardInstances = []
	}
	
  @objc private func phoneCardHeld(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .began, let cardView = gesture.view as? MiniCardView else { return }
    clearPhoneDragPreview()
    focus(on: cardView.cardInstance, view: cardView)
  }

  @objc func longPressOnCardRecognized(gestureRecognizer: UIGestureRecognizer) {
    guard let cardView = (gestureRecognizer.view as? MiniCardView) else { return }
    
    if selectedCardInstances.count > 1 {
      presentSelectedMenu(from: cardView.cardInstance)
      return
    }
    
    
    guard gestureRecognizer.state == .began else { return }
    
    focus(on: cardView.cardInstance, view: cardView)
  }
  
  func focus(on cardInstance: CardInstance, view cardView: MiniCardView?) {
        if let session = phoneMode, session.game.state[player: session.player].hand.cards.value.contains(cardInstance)
            || session.game.state[player: session.player].commandZone.cards.value.contains(cardInstance)
            || session.game.castableCards(for: session.player).contains(cardInstance) {
            let controller = PhoneHandCardController(session: session, card: cardInstance)
            let navigation = UINavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .pageSheet
            presentPhoneCardMenu(navigation, card: cardInstance, fallback: cardView)
            return
        }
        focusViewController?.dismiss(animated: true, completion: nil)

        struct InspectorPage {
            let card: CardInstance
            let image: UIViewController?
            let controls: [UIViewController]
        }
        var dismissInspector: () -> Void = {}
        // In a Rules game the engine owns power/toughness, keywords and counters: no manual editors.
        let rulesGame = phoneMode?.mode == .rules
        func makePage(for cardInstance: CardInstance) -> InspectorPage {
            var controllers = rulesGame ? [] : SideTableViewController.SectionModel.viewControllerCombinations.compactMap { sections -> UIViewController? in
                guard let controller = storyboard?.instantiateViewController(identifier: "SideTableViewController") as? SideTableViewController else { return nil }
                controller.card = cardInstance
                controller.sectionModel = sections
                return controller
            }
            if !rulesGame, let counters = storyboard?.instantiateViewController(identifier: "CountersViewController") as? CountersViewController {
                counters.cardInstance = cardInstance
                controllers.append(counters)
            }
            struct RulingsListView: View {
                let rulings: [MTGRuling]
                var body: some View {
                    VStack {
                        Text("Rulings").font(.headline).padding()
                        List(rulings, id: \.self) { ruling in
                            VStack(alignment: .leading) {
                                Text(ruling.comment).font(.system(.subheadline))
                                Text(ruling.publishedAt).italic().foregroundColor(.secondary)
                            }.padding(.vertical, 4)
                        }.listStyle(.insetGrouped)
                    }.environment(\.horizontalSizeClass, .regular)
                }
            }
            let rulings: [MTGRuling] = {
                if ProcessInfo.processInfo.arguments.contains("--phone-board-fixture") { return [] }
                guard let id = cardInstance.representation.card.oracleID else { return [] }
                switch cardInstance.representation {
                case .faceDown, .morph, .manifest, .mysterious, .foretold: return []
                default: return CardService.shared.getRulings(oracleID: id)
                }
            }()
            if !rulings.isEmpty { controllers.append(UIHostingController(rootView: RulingsListView(rulings: rulings))) }
            let image = storyboard?.instantiateViewController(identifier: "CardImageViewController") as? CardImageViewController
            var showCard = cardInstance.representation.card.language == .english
            if case .faceDown = cardInstance.representation { showCard = true }
            if showCard { image?.cardInstance = cardInstance }
            image?.showsOtherSideButton = true
            let controls = UIHostingController(rootView: CardControlView(card: cardInstance, dismiss: { dismissInspector() }))
            controllers.insert(controls, at: 0)
            return InspectorPage(card: cardInstance, image: image, controls: controllers)
        }

        var cards = [cardInstance]
        if let session = phoneMode {
            var base = cardInstance
            var visited: Set<UUID> = [base.uuid]
            while let parent = session.game.attachments[base.uuid].flatMap({ session.game.cards[$0] }), visited.insert(parent.uuid).inserted {
                base = parent
            }
            cards = [base] + session.game.attachedCards(to: base.uuid)
        }
        let pages = cards.map { makePage(for: $0) }

        struct ViewControllerView: UIViewControllerRepresentable {
            let viewController: UIViewController
            func makeUIViewController(context: Context) -> UIViewController { viewController }
            func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
        }
        struct ControlView: View {
            @State var pages: [InspectorPage]
            @State var selectedCard: UUID
            @State var controlIndex: Int
            let close: () -> Void

            private var current: InspectorPage { pages.first { $0.card.uuid == selectedCard } ?? pages[0] }
            var body: some View {
                NavigationStack {
                    HStack(spacing: 8) {
                        TabView(selection: $selectedCard) {
                            ForEach(pages, id: \.card.uuid) { page in
                                if let image = page.image {
                                    ViewControllerView(viewController: image).tag(page.card.uuid)
                                }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .always : .never))
                        .accessibilityIdentifier("phone-inspector-pages")
                        TabView(selection: $controlIndex) {
                            ForEach(current.controls.indices, id: \.self) { index in
                                ViewControllerView(viewController: current.controls[index]).tag(index)
                            }
                        }
                        .id(current.card.uuid)
                        .tabViewStyle(.page)
                        .accessibilityIdentifier("phone-inspector-controls")
                    }
                    .navigationTitle(current.card.representation.name ?? "Card")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
                }
                .onChange(of: selectedCard) { _ in
                    controlIndex = min(current.card.previouslyViewedFocusIndex, current.controls.count - 1)
                }
                .onChange(of: controlIndex) { value in current.card.previouslyViewedFocusIndex = value }
                .onReceive(NotificationCenter.default.publisher(for: .phoneGameDidChange)) { _ in
                    guard let session = AppDelegate.shared.phoneSession, let base = pages.first else { return }
                    let attachedIDs = Set(session.game.attachedCards(to: base.card.uuid).map(\.uuid))
                    let remaining = pages.filter { $0.card.uuid == base.card.uuid || attachedIDs.contains($0.card.uuid) }
                    if remaining.count != pages.count {
                        selectedCard = base.card.uuid
                        pages = remaining
                        controlIndex = min(base.card.previouslyViewedFocusIndex, base.controls.count - 1)
                    }
                }
            }
        }
        let content = ControlView(pages: pages, selectedCard: cards[0].uuid,
                                  controlIndex: min(cards[0].previouslyViewedFocusIndex, pages[0].controls.count - 1),
                                  close: { dismissInspector() })
        let host = UIHostingController(rootView: content)
        host.view.accessibilityHint = PhoneSheet.providesCloseHint // inspector has its own Done
        host.modalPresentationStyle = .pageSheet
        host.modalTransitionStyle = .crossDissolve
        if cardInstance.controllerIdentifier.value == .b && phoneMode == nil { host.view.transform = .init(rotationAngle: .pi) }
        focusViewController = host
        dismissInspector = { [weak host] in host?.dismiss(animated: true) }
        if phoneMode != nil { presentPhoneCardMenu(host, card: cardInstance, fallback: cardView) }
        else { present(host, animated: true) }
  }

    private func phoneCardMenuSource(_ card: CardInstance, fallback: UIView?, zooming controller: UIViewController? = nil) -> UIView? {
        if let mini = cardView(for: card), !mini.isHidden, mini.window != nil { return mini.cardView }
        if let source = localPhoneBar?.handViewController?.phonePresentation.menuSources[card.uuid]?.view, source.window != nil {
            // Artwork may finish loading after SwiftUI last updated this background source.
            (source as? UIImageView)?.image = card.representation.imageIfLoaded(type: .normal)
            return source
        }
        if let stand = phoneMenuStandIn(for: card, zooming: controller) { return stand }
        return fallback?.window != nil ? fallback : nil
    }

    // MARK: Menu zoom stand-ins (organized lands, stack cards)

    /// Lands and stack cards are SwiftUI, with no UIKit view for the zoom transition to lift.
    /// A UIKit stand-in takes the card's place (the real one is concealed) for each zoom, in and
    /// out, and is removed as soon as that transition ends so the board stays live meanwhile.
    private struct PhoneMenuStandIn {
        let card: UUID
        let view: UIView
        let host: UIViewController?
        let isStack: Bool
    }
    private var phoneMenuStandIn: PhoneMenuStandIn?

    private func phoneMenuStandIn(for card: CardInstance, zooming controller: UIViewController?) -> UIView? {
        if let current = phoneMenuStandIn, current.card == card.uuid, current.view.superview != nil { return current.view }
        removePhoneMenuStandIn()
        let stand: PhoneMenuStandIn
        if let organizer = [landOrganizer, opponentLandOrganizer].compactMap({ $0 }).first(where: { $0.landFrame(for: card.uuid) != nil }),
           let frame = organizer.landFrame(for: card.uuid), organizer.view.window != nil {
            let rect = view.convert(frame, from: nil)
            let host = UIHostingController(rootView: SwiftUICardView(card: card, isRotationEnabled: false))
            if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            host.view.bounds = CGRect(origin: .zero, size: rect.size)
            host.view.center = CGPoint(x: rect.midX, y: rect.midY)
            if card.isTapped.value { host.view.transform = CGAffineTransform(rotationAngle: .pi / 15) }
            view.addSubview(host.view)
            host.view.layoutIfNeeded()
            organizer.concealCard(card.uuid, true)
            stand = PhoneMenuStandIn(card: card.uuid, view: host.view, host: host, isStack: false)
        } else if let session = phoneMode, !phoneStackCollapsed, let stackView = phoneStackCards?.view, !stackView.isHidden,
                  stackView.window != nil,
                  let index = session.game.stack.firstIndex(where: { $0.card?.uuid == card.uuid }),
                  session.game.stack.count - 1 - index < 4 {
            let depth = session.game.stack.count - 1 - index
            let size = PhoneStackCardsView.cardSize(in: stackView.bounds.size)
            let transform = PhoneStackCardsView.cardTransform(in: stackView.bounds.size, depth: depth)
            let center = CGPoint(x: size.width / 2, y: size.height / 2).applying(transform)
            let item = session.game.stack[index]
            let standView: UIView
            let standHost: UIViewController?
            if item.isAbility == true {
                // The details page still shows the source card. Its transition source and return
                // destination must remain the same ability face that's actually on the stack.
                let host = UIHostingController(rootView:
                    PhoneAbilityPanel(source: card, text: item.text, width: size.width, depth: CGFloat(depth))
                        .frame(width: size.width, height: size.height, alignment: .top))
                if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
                host.view.backgroundColor = .clear
                host.view.accessibilityIdentifier = "phone-stack-ability-transition"
                standView = host.view
                standHost = host
            } else {
                let image = UIImageView(image: card.representation.imageIfLoaded(type: .normal)
                                        ?? card.representation.image(type: .normal))
                image.contentMode = .scaleAspectFill
                image.clipsToBounds = true
                image.layer.cornerCurve = .continuous
                image.layer.cornerRadius = max(4, size.width * 0.045)
                standView = image
                standHost = nil
            }
            standView.isUserInteractionEnabled = false
            standView.bounds = CGRect(origin: .zero, size: size)
            standView.center = stackView.convert(center, to: view)
            standView.transform = CGAffineTransform(rotationAngle: -4 * CGFloat(depth) * .pi / 180)
            view.addSubview(standView)
            standView.layoutIfNeeded()
            stand = PhoneMenuStandIn(card: card.uuid, view: standView, host: standHost, isStack: true)
            phoneStackCards?.rootView = makePhoneStackView(session, concealing: card.uuid)
        } else {
            return nil
        }
        phoneMenuStandIn = stand
        watchPhoneMenuTransition(controller, standIn: stand.view)
        return stand.view
    }

    /// Removes the stand-in once the transition that uses it has finished.
    private func watchPhoneMenuTransition(_ controller: UIViewController?, standIn: UIView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 30) { [weak self, weak controller, weak standIn] in
            guard let self, let standIn, self.phoneMenuStandIn?.view === standIn else { return }
            if let controller, controller.transitionCoordinator != nil || controller.isBeingPresented || controller.isBeingDismissed {
                self.watchPhoneMenuTransition(controller, standIn: standIn)
            } else {
                self.removePhoneMenuStandIn()
            }
        }
    }

    private func removePhoneMenuStandIn() {
        guard let stand = phoneMenuStandIn else { return }
        phoneMenuStandIn = nil
        stand.view.removeFromSuperview()
        if stand.isStack {
            if let session = phoneMode { phoneStackCards?.rootView = makePhoneStackView(session) }
        } else {
            landOrganizer?.concealCard(stand.card, false)
            opponentLandOrganizer?.concealCard(stand.card, false)
        }
    }

    private func presentPhoneCardMenu(_ controller: UIViewController, card: CardInstance, fallback: UIView?) {
        if #available(iOS 18.0, *), !UIAccessibility.isReduceMotionEnabled,
           phoneCardMenuSource(card, fallback: fallback, zooming: controller) != nil {
            controller.preferredTransition = .zoom { [weak self, weak fallback] context in
                self?.phoneCardMenuSource(card, fallback: fallback, zooming: context.zoomedViewController)
            }
        }
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.prepare()
        present(controller, animated: true)
        // A battlefield card's menu shows as a white outline on the opponent's phone.
        if let session = phoneMode, session.game.state.battlefield.value.contains(card) {
            session.trackInspection(.card(card.uuid), while: controller)
        }
        // With the zoom, as the card starts to lift, rather than once the sheet has settled.
        feedback.impactOccurred()
    }

	func toggleSidebar() {
		guard let splitViewController = splitViewController else { return }
		
		UIView.animate(withDuration: 0.15) {
			if splitViewController.displayMode == .primaryHidden {
				splitViewController.preferredDisplayMode = .primaryOverlay
			} else {
				splitViewController.preferredDisplayMode = .primaryHidden
			}
		}
		
//		let target = splitViewController.displayModeButtonItem.target
//		let action = splitViewController.displayModeButtonItem.action
//		_ = target?.perform(action)
	}
	
	@objc func panRecognized(gestureRecognizer: UIPanGestureRecognizer) {
        if phoneMode != nil { handlePhoneCardPan(gestureRecognizer); return }
		guard gestureRecognizer.state != . cancelled && gestureRecognizer.state != .failed else { return }
		guard let cardView = gestureRecognizer.view as? MiniCardView else { return }
    
    if !selectedCardInstances.contains(cardView.cardInstance) {
      selectedCardInstances.removeAll()
    }
    
//    presentedViewController?.dismiss(animated: true)
    
    let cardInstances = selectedCardInstances.isEmpty ? [cardView.cardInstance!] : Array(selectedCardInstances)
    let cardViews = selectedCardInstances.isEmpty ? [cardView] : selectedCardInstances.compactMap(cardView(for:))
    
    // Bring the cardviews to front, keeping the relative order the moved views already had.
    var cardViewZOrders: [CardInstance: Int] = [:]
    for cardInstance in cardInstances {
      guard let cardView = self.cardView(for: cardInstance), let index = cardView.superview?.subviews.firstIndex(of: cardView) else { continue }
      cardViewZOrders[cardInstance] = index
    }
    let sortedCardViews = cardViews.sorted { first, second in
      let firstZPosition = cardViewZOrders[first.cardInstance] ?? 0
      let secondZPosition = cardViewZOrders[second.cardInstance] ?? 0
      return firstZPosition < secondZPosition
    }
    
    for cardView in sortedCardViews {
      cardView.superview?.bringSubviewToFront(cardView)
      let translation = gestureRecognizer.translation(in: board)
      
      let newCenter = CGPoint(x: cardView.center.x + translation.x, y: cardView.center.y + translation.y)
      cardView.center = newCenter
      cardView.cardInstance.center.accept(newCenter)
    }
    
    gestureRecognizer.setTranslation(.zero, in: board)
		
		guard !cardView.cardInstance.representation.isEmblem else { return }
		
		// recognize groups
		
//		let tolerance: CGFloat = 300
//		for otherCardInstance in GameState.current.battlefield where otherCardInstance != cardView.cardInstance {
//			let rect = CGRect(origin: otherCardInstance.center.value.applying(CGAffineTransform(translationX: -tolerance/2, y: -tolerance/2)), size: CGSize(width: tolerance, height: tolerance))
//			if rect.contains(cardView.center) {
//
//			} else {
//
//			}
//		}
		
		var destinationPileView: HUDCardPileView?
		
		if gestureRecognizer.state == .ended {
			let endedPile: Pile? = {
				for (playerIdentifier, containerView) in zip([Player.Identifier.a, Player.Identifier.b], [player1BarContainerView, player2BarContainerView]) {
					guard let bottomBar = containerView?.subviews.first, !GameState.current[player: playerIdentifier].isHidden else { continue }
					
					if let handViewControllerContainer = bottomBar.subviews.first(where: { $0 is HandViewControllerContainerView }) {
						let viewPoint = gestureRecognizer.location(in: handViewControllerContainer)
						if handViewControllerContainer.point(inside: viewPoint, with: nil) {
							return GameState.current[player: playerIdentifier].hand
						}
					}
					
					for location: Pile.Location in [.graveyard, .library, .exile] {
						guard let pileView = bottomBar.subviews.compactMap({ $0 as? HUDCardPileView }).first(where: { $0.pile.location == location && $0.pile.playerIdentifier == playerIdentifier }) else { continue }
						let viewPoint = gestureRecognizer.location(in: pileView)
						if pileView.point(inside: viewPoint, with: nil) {
							destinationPileView = pileView
							return pileView.pile
						}
					}
				}
        
//        if let commandZone = self.commandZone, let commandZoneView = commandZone.view {
//          let viewPoint = gestureRecognizer.location(in: commandZoneView)
//          if commandZoneView.point(inside: viewPoint, with: nil) {
//            return commandZone.commandZone
//          }
//        }
        
				return nil
			}()
				
			if let destinationPile = endedPile {
        func continuation(insertionIndex: Int? = nil, pile: Pile = destinationPile) {
          if pile.location != .command && cardInstances.contains(where: \.isCommander.value) {
            let commanders = cardInstances.filter(\.isCommander.value)
            let commanderIDs = Set(commanders.map(\.uuid))
            
            let alert = UIAlertController(title: cardInstances.count > 1 ? "Move commander\(commanders.count == 1 ? "" : "s") to…" : nil, message: nil, preferredStyle: .actionSheet)

            let defaultAction = UIAlertAction(title: pile.location.rawValue, style: .default) { (_) in
              GameState.current.move(cardInstances: cardInstances, to: pile, at: insertionIndex)
            }
            alert.addAction(defaultAction)
            let commandZoneAction = UIAlertAction(title: "Command Zone", style: .default) { _ in
              var cardInstances = cardInstances
              cardInstances.removeAll(where: { commanderIDs.contains($0.uuid) })
              GameState.current.move(cardInstances: cardInstances, to: pile, at: insertionIndex)
              GameState.current.move(cardInstances: commanders, to: GameState.current[player: pile.playerIdentifier].commandZone)
            }
            alert.addAction(commandZoneAction)

            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            alert.addAction(cancelAction)

            alert.popoverPresentationController?.permittedArrowDirections = [.up, .down]

            if destinationPile.playerIdentifier == .b {
              alert.view.transform = CGAffineTransform(rotationAngle: .pi)
              alert.popoverPresentationController?.sourceView = destinationPileView ?? self.player2BarContainerView
            } else {
              alert.popoverPresentationController?.sourceView = destinationPileView ?? self.player1BarContainerView
            }
            
            self.present(alert, animated: true, completion: nil)
          } else {
            GameState.current.move(cardInstances: cardInstances, to: pile, at: insertionIndex)
          }
				}
				
//				continuation()
				
        if destinationPile.location == .library && !destinationPile.cards.value.isEmpty && !cardView.cardInstance.representation.isToken {
          let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
          
          let topAction = UIAlertAction(title: "Top", style: .default) { (_) in
            continuation(insertionIndex: nil)
          }
          alert.addAction(topAction)
          
          if !selectedCardInstances.isEmpty {
            let shuffleAction = UIAlertAction(title: "Shuffle In", style: .default) { (_) in
              continuation(insertionIndex: nil)
              destinationPile.cards.mutate { $0 = OrderedSet($0.contents.shuffled()) }
            }
            alert.addAction(shuffleAction)
          }
          
					let bottomAction = UIAlertAction(title: "Bottom", style: .default) { _ in
						continuation(insertionIndex: -1) // TODO: Figure out why -1 is needed here and not 0
					}
					alert.addAction(bottomAction)

					let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
					alert.addAction(cancelAction)

					alert.popoverPresentationController?.sourceView = destinationPileView
					alert.popoverPresentationController?.permittedArrowDirections = [.up, .down]

					if destinationPile.playerIdentifier == .b {
						alert.view.transform = CGAffineTransform(rotationAngle: .pi)
					}

					self.present(alert, animated: true, completion: nil)
        }/* else if destinationPile.location == .hand && cardView.cardInstance.isCommander.value {
          let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

          let topAction = UIAlertAction(title: "Hand", style: .default) { (_) in
            continuation()
          }
          alert.addAction(topAction)
          let bottomAction = UIAlertAction(title: "Command Zone", style: .default) { _ in
            continuation(pile: GameState.current[player: destinationPile.playerIdentifier].commandZone)
          }
          alert.addAction(bottomAction)

          let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
          alert.addAction(cancelAction)

          alert.popoverPresentationController?.permittedArrowDirections = [.up, .down]

          if destinationPile.playerIdentifier == .b {
            alert.view.transform = CGAffineTransform(rotationAngle: .pi)
            alert.popoverPresentationController?.sourceView = self.player2BarContainerView
          } else {
            alert.popoverPresentationController?.sourceView = self.player1BarContainerView
          }
          
          self.present(alert, animated: true, completion: nil)
        }*/ else {
					continuation()
				}
				
			} else {
				try? GameState.current.save()
			}
		}
	}
	
	private func createCards(at center: CGPoint, getter: (@escaping () throws -> [(Player.Identifier, CardRepresentation)])) {
		var center = center
		
		DispatchQueue.global(qos: .userInteractive).async {
			do {
				let cards = try getter()
				
				DispatchQueue.main.async {
					var instances: Set<CardInstance> = []
					for (owner, card) in cards {
						let instance = CardInstance(card: card, center: self.phoneMode == nil ? center : nil, ownerIdentifier: owner)
						instances.insert(instance)
						self.addCardViewToBattlefield(for: instance)
						center.x += 28
						center.y += 72
					}
					GameState.current.battlefield.mutate {
						$0.formUnion(instances)
					}
					try? GameState.current.save()
				}
			} catch {
				DispatchQueue.main.async {
					let alert = UIAlertController(title: "Error", message: String(describing: error), preferredStyle: .alert)
					let okAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
					alert.addAction(okAction)
					self.present(alert, animated: true, completion: nil)
				}
			}
		}
	}
	
  fileprivate func loadDeck(_ groups: [DeckParser.CardGroup], playerIdentifier: Player.Identifier, handSmoothing: Bool = false) {

		let player = playerIdentifier == .a ? GameState.current.player1 : GameState.current.player2
		GameState.current.deckLayout = (GameState.current.deckLayout ?? [:]).merging([playerIdentifier.rawValue: [:]]) { $1 }
		
		DispatchQueue.global(qos: .userInitiated).sync {
			player.allPiles.forEach {
				$0.cards.mutate {
					$0.removeAll()
				}
			}
			
			for group in groups {
				let identifiers = group.cardCounts.map { $0.identifier }
				
				do {
          print("Getting cards for \(identifiers.count) identifiers…")
					let list = try CardService.shared.getCollection(identifiers: identifiers)
          print("Loaded \(list.cards.count) identifiers (\(list.notFound.count) not found)")
					
					guard list.cards.count == group.cardCounts.count else {
						DispatchQueue.main.async {
							let cards = list.notFound.map(String.init(describing:)).joined(separator: "\n")
							let alert = UIAlertController(title: "Unable to Load Deck", message: "The following cards from your deck list could not be found:\n\n\(cards)", preferredStyle: .alert)
							let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
							alert.addAction(okAction)
							self.present(alert, animated: true, completion: nil)
						}
						return
					}
					
					var pile: Pile
					
					switch group.name {
					case DeckParser.CardGroup.GroupName.deck.rawValue:
						pile = player.library
					case DeckParser.CardGroup.GroupName.sideboard.rawValue:
						pile = player.sideboard
					case DeckParser.CardGroup.GroupName.command.rawValue:
						pile = player.commandZone
					default:
						continue
					}
          
          print("Loading group \(group.name ?? "") into \(pile.location)")
					
					var cards: [MTGCard] = []
					
					for (card, count) in zip(list.cards, group.cardCounts.map { $0.count }) {
						for _ in 0 ..< count {
							cards.append(card)
						}
					}
					
					DispatchQueue.main.async {
						if pile.location == .library {
              if handSmoothing {
                let landCount = cards.count(where: { $0.isLand })
                let landRatio = Double(landCount)/Double(cards.count)
                
                let shuffledA = cards.shuffled()
                let openingHandA = shuffledA.suffix(7)
                let landCountA = openingHandA.count(where: { $0.isLand })
                let landRatioA = Double(landCountA)/Double(openingHandA.count)
                
                let shuffledB = cards.shuffled()
                let openingHandB = shuffledB.suffix(7)
                let landCountB = openingHandB.count(where: { $0.isLand })
                let landRatioB = Double(landCountB)/Double(openingHandB.count)
                
                if landCountA == 0 {
                  cards = shuffledB
                } else {
                  let diffA = abs(landRatio-landRatioA)
                  let diffB = abs(landRatio-landRatioB)
                  
                  if diffA < diffB {
                    cards = shuffledA
                  } else {
                    cards = shuffledB
                  }
                }
              } else {
                cards.shuffle()
              }
						}
						
						let instances = OrderedSet(cards.map { CardInstance(card: $0, center: nil, ownerIdentifier: playerIdentifier) })
            
            if pile.location == .command {
              for instance in instances {
                instance.isCommander.accept(true)
              }
            }
            
						pile.cards.accept(instances)
						GameState.current.deckLayout?[playerIdentifier.rawValue, default: [:]][pile.location.rawValue, default: []]
							.append(contentsOf: instances.map(\.uuid))
					}
					
				} catch {
					DispatchQueue.main.async {
						let alert = UIAlertController(title: "Unable to Load Deck", message: "An error occurred: \(error)", preferredStyle: .alert)
						let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
						alert.addAction(okAction)
						self.present(alert, animated: true, completion: nil)
					}
				}
				
			}
			
			DispatchQueue.main.async {
				if !player.commandZone.cards.value.isEmpty {
					if player.library.cards.value.count + player.commandZone.cards.value.count == 100 {
						player.life.accept(40)
						
						GameState.current.player2.isHidden = true
					} else {
						player.life.accept(20)
						
						GameState.current.player2.isHidden = false
					}
          self.updatePlayersHidden()
					
//					let multiplier: CGFloat = playerIdentifier == .a ? 1 : -1
//					let modifier: CGFloat = 400 * multiplier
//					
//					var center = self.visibleBoardCenter
//					center.y += modifier
//					self.moveCardItemsToBattlefield(player.commandZone.cards.value, at: center)
				} else {
					try? GameState.current.save()
				}
        
        for card in GameState.current.allCards.values {
          CardService.shared.cacheImagesIfNeeded(for: card.representation.card, types: [.art, .small, .large])
        }
			}
		}
	}
	
	fileprivate func loadJumpstart() {
		func askForJumpstartDecks(player: Player, completion: (() -> ())? = nil) {
			var lists: [(decklist: String, packName: String)] = []
			for _ in 0 ..< 3 {
				var list: (decklist: String, packName: String)
				repeat {
					list = try! CardService.shared.getJumpstartDecklist()
				} while lists.contains(where: { $0.packName == list.packName })
				lists.append(list)
			}
			
			var packA: (decklist: String, packName: String)!
			
			let firstChoiceAlert = UIAlertController(title: "\(player.name.value), choose your first pack.", message: "Twice, you choose one packet from among three. Each packet is 20 cards including lands.", preferredStyle: .alert)
			for list in lists {
				let action = UIAlertAction(title: list.packName, style: .default) { _ in
					packA = list
					
					var lists2: [(decklist: String, packName: String)] = []
					for _ in 0 ..< 3 {
						var list: (decklist: String, packName: String)
						repeat {
							list = try! CardService.shared.getJumpstartDecklist()
						} while lists2.contains(where: { $0.packName == list.packName })
						lists2.append(list)
					}
					
					let secondChoiceAlert = UIAlertController(title: "\(player.name.value), choose your second pack.", message: "First pack: \(packA.packName)", preferredStyle: .alert)
					for list in lists2 {
						let action = UIAlertAction(title: list.packName, style: .default) { _ in
							
							let combinedList = [packA.decklist, list.decklist].joined(separator: "\n")
							let groups = DeckParser.parse(deckList: combinedList, autofix: true)
							self.loadDeck(groups, playerIdentifier: player.identifier)
							
							completion?()
						}
						secondChoiceAlert.addAction(action)
					}
					
					let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
					secondChoiceAlert.addAction(cancelAction)
					
					self.present(secondChoiceAlert, animated: true)
				}
				firstChoiceAlert.addAction(action)
			}
			
			let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
			firstChoiceAlert.addAction(cancelAction)
			
			self.present(firstChoiceAlert, animated: true)
		}
		
		askForJumpstartDecks(player: GameState.current.player1) {
			askForJumpstartDecks(player: GameState.current.player2)
		}
	}
  
  fileprivate func loadDandan() {
    if let phoneMode { phoneMode.send(.dandan); return }
    let list = try! CardService.shared.getDandanDecklist()
    let groups = DeckParser.parse(deckList: list, autofix: true)
    self.loadDeck(groups, playerIdentifier: .a)
  }
  
  func presentSelectedMenu(from cardInstance: CardInstance?) {
    let actions = makeSelectedMenuActions(from: cardInstance).map { $0.alertAction }
    
    let alert = UIAlertController(title: "\(selectedCardInstances.count) Card\(selectedCardInstances.count == 1 ? "" : "s")", message: nil, preferredStyle: .alert)
    actions.forEach(alert.addAction(_:))
    self.present(alert, animated: true)
  }
  
  func makeSelectedMenuActions(from cardInstance: CardInstance?) -> [Action] {
    var actions: [Action] = []
    
    actions.append(.init(title: "Tap", style: .default) { _ in
      self.selectedCardInstances.forEach {
        $0.isTapped.accept(true)
      }
      try? GameState.current.save()
    })
    
    actions.append(.init(title: "Untap", style: .default) { _ in
      self.selectedCardInstances.forEach {
        $0.isTapped.accept(false)
      }
      try? GameState.current.save()
    })
    
    let containsFaceDown = selectedCardInstances.contains(where: { $0.representation.isFaceDown })
    
    if containsFaceDown {
      actions.append(.init(title: "Turn Face-Up", style: .default) { [weak self] _ in
        guard let selectedCardInstances = self?.selectedCardInstances else { return }
        
        for cardInstance in selectedCardInstances {
          if case .faceDown(let representation) = cardInstance.representation {
            cardInstance.representation = representation
          } else if case .morph(let card) = cardInstance.representation {
            cardInstance.representation = .card(card)
          } else if case .manifest(let card) = cardInstance.representation {
            cardInstance.representation = .card(card)
          } else if case .mysterious(let card) = cardInstance.representation {
            cardInstance.representation = .card(card)
          } else if case .foretold(let card) = cardInstance.representation {
            cardInstance.representation = .card(card)
          }
        }
        
        try? GameState.current.save()
      })
    }
    
    let containsFaceUp = selectedCardInstances.contains(where: {
      if case .faceDown(_) = $0.representation {
        return false
      }
      return true
    })
    
    if containsFaceUp {
      actions.append(.init(title: "Turn Face-Down", style: .default) { [weak self] _ in
        guard let selectedCardInstances = self?.selectedCardInstances else { return }
        
        for cardInstance in selectedCardInstances {
          if case .faceDown(_) = cardInstance.representation {
            
          } else {
            cardInstance.representation = .faceDown(cardInstance.representation)
          }
        }
        
        try? GameState.current.save()
      })
    }
    
    actions.append(.init(title: "Create Stack", style: .default) { [weak self] _ in
      guard let selectedCardInstances = self?.selectedCardInstances else { return }
      let sorted: [CardInstance] = selectedCardInstances.sorted(by: { first, second in
        let firstCenter = first.center.value ?? .zero
        let secondCenter = second.center.value ?? .zero
        return firstCenter.x < secondCenter.x && firstCenter.y < secondCenter.y
      })
      
      guard let first = /*cardInstance ?? */ sorted.first, let center = first.center.value, let firstCardView = self?.cardView(for: first) else { return }
      
      var others = OrderedSet(sorted)
      others.remove(first)
      
      firstCardView.superview?.bringSubviewToFront(firstCardView)
      
      for cardInstance in others {
        guard let cardView = self?.cardView(for: cardInstance) else { continue }
        
        cardView.superview?.bringSubviewToFront(cardView)
        
        cardInstance.center.accept(center)
        cardView.center = center
      }
      
      self?.selectedCardInstances = [first] + others
      try? GameState.current.save()
    })
    
    let centers = selectedCardInstances.compactMap(\.center.value)
    let stacked = !centers.isEmpty && centers.dropFirst().allSatisfy({
      let center = centers[0]
      let allowedDifference: CGFloat = 150
      let bounds = CGRect(x: center.x-allowedDifference, y: center.y-allowedDifference, width: allowedDifference*2, height: allowedDifference*2)
      return bounds.contains($0)
    })
    if stacked {
      actions.append(.init(title: "Shuffle Stack", style: .default) { _ in
        let cardViews = self.selectedCardInstances.compactMap(self.cardView(for:)).shuffled()
        
        for cardView in cardViews {
          cardView.superview?.bringSubviewToFront(cardView)
        }
      })
      
      actions.append(.init(title: "View Stack", style: .default) { _ in
        self.viewStack(cards: self.selectedCardInstances, fromView: cardInstance.flatMap(self.cardView(for:)))
      })
    }
    
//    actions.append(.init(title: "Spread", style: .default) { [weak self] _ in
//      guard let selectedCardInstances = self?.selectedCardInstances else { return }
//      let sorted: [CardInstance] = selectedCardInstances.sorted(by: { first, second in
//        let firstCenter = first.center.value ?? .zero
//        let secondCenter = second.center.value ?? .zero
//        return firstCenter.x < secondCenter.x && firstCenter.y < secondCenter.y
//      })
//      
//      guard let first = cardInstance ?? sorted.first, var center = first.center.value, let firstCardView = self?.cardView(for: first) else { return }
//      
//      var others = OrderedSet(sorted)
//      others.remove(first)
//      
//      firstCardView.superview?.bringSubviewToFront(firstCardView)
//      
//      for cardInstance in others {
//        guard let cardView = self?.cardView(for: cardInstance) else { continue }
//        
//        cardView.superview?.bringSubviewToFront(cardView)
//        
//        center.x += 28
//        center.y += 72
//        
//        cardInstance.center.accept(center)
//        cardView.center = center
//      }
//      
//      self?.selectedCardInstances = [first] + others
//      try? GameState.current.save()
//    })
    
    actions.append(.init(title: "Remove", style: .destructive, handler: { _ in
      for cardInstance in self.selectedCardInstances {
        cardInstance.remove.on(.next(()))
      }
      try? GameState.current.save()
    }))
    
    actions.append(.init(title: "Cancel", style: .cancel, handler: nil))
    
    return actions
  }
	
    @objc func longPressRecognized(gestureRecognizer: UIGestureRecognizer) {
        // Phone battlefields use the visible gear; keep the original iPad board gesture.
        guard phoneMode == nil else { return }
        showBattlefieldMenu()
    }

    @objc private func showBattlefieldMenu() {
        guard presentedViewController == nil else { return }
        if phoneMode?.mode == .rules {
            let menu = BoardMenuSheetController(title: "Battlefield", message: nil, preferredStyle: .alert)
            if let engine = phoneMode?.rulesAdapter?.engine, engine.status == .connected, engine.result == nil {
                menu.addAction(BoardMenuAction(title: engine.holdingPriority ? "Release Full Control" : "Hold Full Control", style: .default) { _ in
                    Task { await engine.controlPriority(engine.holdingPriority ? .release : .hold) }
                })
                if engine.prompt?.method == "GAME_SELECT" {
                    let priorityActions: [(String, RulesPriorityAction)] = [
                        ("Resolve Stack", .resolveStack), ("Stop at Next Main Phase", .nextMain),
                        ("Stop at End Step", .endStep), ("Pass Until Your Turn", .yourTurn)
                    ]
                    for (title, action) in priorityActions {
                        menu.addAction(BoardMenuAction(title: title, style: .default) { _ in
                            Task { await engine.controlPriority(action) }
                        })
                    }
                }
                menu.addAction(BoardMenuAction(title: "Cancel Auto-Pass", style: .default) { _ in
                    Task { await engine.controlPriority(.cancelAutoPass) }
                })
                menu.addAction(BoardMenuAction(title: engine.autoOrderTriggers ? "Order Triggers Manually" : "Order Triggers Automatically", style: .default) { _ in
                    Task { await engine.setAutoOrderTriggers(!engine.autoOrderTriggers) }
                })
                menu.addAction(BoardMenuAction(title: "Concede", style: .destructive) { [weak self] _ in
                    guard let self else { return }
                    let confirm = UIAlertController(title: "Concede game?", message: "This game will end in a loss.", preferredStyle: .alert)
                    confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                    confirm.addAction(UIAlertAction(title: "Concede", style: .destructive) { _ in Task { await engine.concede() } })
                    self.present(confirm, animated: true)
                })
                let autoPay = RulesPhoneAdapter.autoPaysMana
                menu.addAction(BoardMenuAction(title: autoPay ? "Turn Off Mana Auto-Pay" : "Turn On Mana Auto-Pay", style: .default) { _ in
                    RulesPhoneAdapter.autoPaysMana = !autoPay
                })
            }
            menu.addAction(BoardMenuAction(title: "Connection…") { [weak self] in self?.showConnectionOptions(); return nil })
            menu.addAction(BoardMenuAction(title: "Exit Game", style: .destructive) { [weak self] _ in self?.exitGame() })
            present(UINavigationController(rootViewController: menu), animated: true)
            return
        }
    
    if selectedCardInstances.count > 1 {
      presentSelectedMenu(from: nil)
      return
    }
		
		let alert = BoardMenuSheetController(title: "Battlefield", message: nil, preferredStyle: .alert)
		alert.addTextField(configurationHandler: nil)
		
		let action = BoardMenuAction(title: "Add by Name", style: .default) { (_) in
			guard let name = alert.textFields?.first?.text else { return }
			self.createCards(at: self.visibleBoardCenter) {
        do {
          let card = try CardService.shared.getCard(name: name)
          return [(.a, .card(card))]
        } catch {
          let card = try CardService.shared.getCard(fuzzy: name)
          return [(.a, .card(card))]
        }
			}
		}
		alert.addAction(action)
		
		let addCodeAction = BoardMenuAction(title: "Add by Set and Number", style: .default) { (_) in
			guard let text = alert.textFields?.first?.text else { return }
			self.createCards(at: self.visibleBoardCenter) {
				let split = text.split(separator: " ")
				guard split.count == 2 else { return [] }
				let code = String(split[0])
				let num = String(split[1])
				return [(.a, .card(try CardService.shared.getCard(code: code, number: num)))]
			}
		}
		alert.addAction(addCodeAction)
		
		let randomAction = BoardMenuAction(title: "Add Random", style: .default) { (_) in
			self.createCards(at: self.visibleBoardCenter) {
				return [(.a, .card(try CardService.shared.getRandomCard(query: alert.textFields?.first?.text)))]
			}
		}
		alert.addAction(randomAction)
		
//		let boosterPackAction = BoardMenuAction(title: "Booster Pack", style: .default) { _ in
//			guard let setCode = alert.textFields?.first?.text else { return }
//			self.createCards(at: self.visibleBoardCenter) { () -> [(Player.Identifier, CardRepresentation)] in
//				let pack = try CardService.shared.generateBoosterPack(setCode: setCode, includeExtendedArt: true, specialOptions: [])
//
//				return pack.map { (.a, .card($0)) }
//			}
//		}
//		alert.addAction(boosterPackAction)
		
//		let loadDeckActionA = BoardMenuAction(title: "Load Deck (\(GameState.current.player1.name.value))", style: .default) { (_) in
//			if let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, let url = URL(string: text) {
//				Task {
//					do {
//						let deck = try await DeckParser.load(fromURL: url)
//						DispatchQueue.main.async {
//							self.loadDeck(deck, playerIdentifier: .a)
//						}
//					} catch {
//						print(error)
//					}
//				}
//			} else {
//				let picker = UIDocumentPickerViewController(documentTypes: ["public.plain-text"], in: .import)
//				picker.allowsMultipleSelection = false
//				picker.delegate = self
//				self.loadDeckPlayerIdentifier = .a
//				self.present(picker, animated: true, completion: nil)
//			}
//		}
//		alert.addAction(loadDeckActionA)
//
//		let loadDeckActionB = BoardMenuAction(title: "Load Deck (\(GameState.current.player2.name.value))", style: .default) { (_) in
//			if let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, let url = URL(string: text) {
//				Task {
//					do {
//						let deck = try await DeckParser.load(fromURL: url)
//						DispatchQueue.main.async {
//							self.loadDeck(deck, playerIdentifier: .b)
//						}
//					} catch {
//						print(error)
//					}
//				}
//			} else {
//				let picker = UIDocumentPickerViewController(documentTypes: ["public.plain-text"], in: .import)
//				picker.allowsMultipleSelection = false
//				picker.delegate = self
//				self.loadDeckPlayerIdentifier = .b
//				self.present(picker, animated: true, completion: nil)
//			}
//		}
//		alert.addAction(loadDeckActionB)
		
//		let jumpstartAction = BoardMenuAction(title: "Jumpstart", style: .default) { _ in
//			self.loadJumpstart()
//		}
//		alert.addAction(jumpstartAction)
		
//		let setPlayer1NameAction = BoardMenuAction(title: "Set Player 1 Name", style: .default) { _ in
//			guard let text = alert.textFields?.first?.text else { return }
//			GameState.current.player1.name.accept(text)
//		}
//		alert.addAction(setPlayer1NameAction)
//
//		let setPlayer2NameAction = BoardMenuAction(title: "Set Player 2 Name", style: .default) { _ in
//			guard let text = alert.textFields?.first?.text else { return }
//			GameState.current.player2.name.accept(text)
//		}
//		alert.addAction(setPlayer2NameAction)
    
    let dandanAction = BoardMenuAction(title: "Load Dandân", style: .default) { _ in
      self.loadDandan()
    }
    alert.addAction(dandanAction)
    // The reset options sit right on the menu's first group (they used to hide behind Reset).
    alert.addAction(BoardMenuAction(title: "Reset Decks and Life", style: .default) { [weak self] _ in self?.resetDecksAndLife() })
    alert.addAction(BoardMenuAction(title: "Clear Board", style: .destructive) { [weak self] _ in self?.clearBoard() })
    alert.addAction(BoardMenuAction(title: "Exit Game", style: .destructive) { [weak self] _ in self?.exitGame() })
    if let session = phoneMode {
      // Show the whole hand to the opponent (their phone opens its revealed-cards browser).
      let hand = session.game.state[player: session.player].hand.cards.value.contents
      let revealed = !hand.isEmpty && hand.allSatisfy { $0.revealedPlayers.value.contains(session.opponent) }
      alert.addAction(BoardMenuAction(title: revealed ? "Stop Revealing Hand" : "Reveal Hand", style: .default) { _ in
        session.send(.reveal(hand.map(\.uuid), session.opponent, !revealed))
      })
      // The phase button's Untap + Draw draws a card unless this is turned off (a per-phone setting).
      alert.addAction(BoardMenuAction(title: PhoneGame.untapDraws ? "Don't Draw on Untap" : "Draw on Untap", style: .default) { [weak self] _ in
        PhoneGame.untapDraws.toggle()
        self?.localPhoneBar?.refreshForPhoneSession()
      })
      // Smooths the first hand of a JumpStart or Jump In game, as the iPad does (for both players).
      let smoothing = session.game.handSmoothing != false
      alert.addAction(BoardMenuAction(title: smoothing ? "Turn Off Hand Smoothing" : "Turn On Hand Smoothing", style: .default) { _ in
        session.send(.setHandSmoothing(!smoothing))
      })
    }
    if phoneMode != nil {
      // An alert over the menu, which stays open underneath.
      alert.addAction(BoardMenuAction(title: "Connection…") { [weak self] in self?.showConnectionOptions(); return nil })
    }
    alert.addAction(BoardMenuAction(title: "Load Deck / JumpStart / Jump In") { [weak self] in self?.makePhoneDeckPicker() })
    alert.addAction(BoardMenuAction(title: "Preloaded Games & Artwork") { [weak self] in
      UIHostingController(rootView: OfflineGamesView(close: { [weak self] in self?.dismiss(animated: true) }))
    })
		
		// Phone play keeps only the library top-card reveals in the Board section.
		if phoneMode == nil {
		let togglePlayer2Action = BoardMenuAction(title: "Show/Hide Player 2", style: .default) { _ in
			GameState.current.player2.isHidden.toggle()
			self.updatePlayersHidden()
		}
		alert.addAction(togglePlayer2Action)
    
    let toggleLandOrganizerAction = BoardMenuAction(title: "Show/Hide Land Organizer", style: .default) { _ in
      self.showLandOrganizer.toggle()
      
      self.updateLandOrganizerLands()
    }
    alert.addAction(toggleLandOrganizerAction)
		}
    
    let dropModeAction = BoardMenuAction(title: "Drop Cards \(self.dropFaceUp ? "Face-Down" : "Face-Up")", style: .default) { _ in
      self.dropFaceUp.toggle()
    }
    alert.addAction(dropModeAction)
    
		if phoneMode == nil {
    let toggleSelectionAction = BoardMenuAction(title: "\(isSelectionEnabled ? "Disable" : "Enable") Selection", style: .default) { _ in
      self.isSelectionEnabled.toggle()
      self.updateSelection()
    }
    alert.addAction(toggleSelectionAction)
		}
    
    // In phone play the reveal goes through the shared game, to both players.
    let toggleTopCard: (Player.Identifier) -> Void = { [weak self] owner in
      if let session = self?.phoneMode {
        let revealed = !(session.game.revealedTops?[owner.rawValue] ?? []).isEmpty
        session.send(.revealTopCard(owner, revealed ? [] : [.a, .b]))
        return
      }
      GameState.current.effectivePile(.library, player: owner).isTopCardRevealed.mutate {
        $0.toggle()
      }
      try? GameState.current.save()
    }
    let player1TopCardAction = BoardMenuAction(title: "Reveal Player 1 Library Top Card", style: .default) { _ in
      toggleTopCard(.a)
    }
    alert.addAction(player1TopCardAction)
    
    if phoneMode != nil || !GameState.current.player2.isHidden {
      let player2TopCardAction = BoardMenuAction(title: "Reveal Player 2 Library Top Card", style: .default) { _ in
        toggleTopCard(.b)
      }
      alert.addAction(player2TopCardAction)
    }
		
		let updateAction = BoardMenuAction(title: "Update Card Database", style: .default) { _ in
			CardService.shared.updateDatabase()
		}
		alert.addAction(updateAction)
		
//		let loadDeckFromURLA = BoardMenuAction(title: "Load Deck From URL (Player 1)", style: .default) { [weak self] (_) in
//			guard let text = alert.textFields?.first?.text else { return }
//			guard let url = URL(string: text) else { return }
//			self?.loadDeck(from: url, for: .a)
//		}
//		alert.addAction(loadDeckFromURLA)
//
//		let loadDeckFromURLB = BoardMenuAction(title: "Load Deck From URL (Player 2)", style: .default) { [weak self] (_) in
//			guard let text = alert.textFields?.first?.text else { return }
//			guard let url = URL(string: text) else { return }
//			self?.loadDeck(from: url, for: .b)
//		}
//		alert.addAction(loadDeckFromURLB)
		if let url = URL(string: "https://testflight.apple.com/join/VbVcGZw1") {
			let shareLinkAction = BoardMenuAction(title: "Share Connect App", style: .default) { [weak self] _ in
				guard let self = self else { return }
				let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
				activityViewController.popoverPresentationController?.sourceView = self.player1BarContainerView
				activityViewController.popoverPresentationController?.sourceRect = self.player1BarContainerView.bounds
				
				self.present(activityViewController, animated: true, completion: nil)
			}
			alert.addAction(shareLinkAction)
		}
		
		alert.onReset = { [weak self, weak alert] in
			guard let self, let alert else { return }
			self.presentResetOptions(from: alert)
		}
		
		let cancel = BoardMenuAction(title: "Cancel", style: .cancel, handler: nil)
		alert.addAction(cancel)
		
		present(UINavigationController(rootViewController: alert), animated: true, completion: nil)
		
	}
	
//	private func displayedGameState() -> GameState {
//		let cardPositions: [GameState.CardPosition] = self.cards.keys.map { (cardView) in
//			return GameState.CardPosition(card: cardView.cardInstance, frameOrigin: cardView.frame.origin)
//		}
//
//		return GameState(cardPositions: cardPositions)
//	}
  
  private func updateLandOrganizerLands() {
    landOrganizer?.view.isHidden = !showLandOrganizer
    landOrganizerContainerView.isUserInteractionEnabled = showLandOrganizer
    
    for cardInstance in GameState.current.battlefield.value {
      self.cardView(for: cardInstance)?.isHidden = showLandOrganizer && self.landOrganizer?.shouldIncludeCard(cardInstance) == true
    }
  }
  
  private lazy var selectionGestureRecognizer: UIGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(recognizePan(_:)))
  
  private lazy var selectionView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    
    view.backgroundColor = .clear
    view.layer.borderWidth = 2
    view.layer.borderColor = UIColor.secondarySystemFill.cgColor
    view.backgroundColor = UIColor.white.withAlphaComponent(0.1)
    
    view.isUserInteractionEnabled = false
    
    return view
  }()
  
  func updateSelection() {
    self.scrollView.isScrollEnabled = !isSelectionEnabled && phoneMode == nil
    selectionGestureRecognizer.isEnabled = isSelectionEnabled && phoneMode == nil
    
    if selectionGestureRecognizer.view == nil {
      scrollView.addGestureRecognizer(selectionGestureRecognizer)
    }
    
    if selectionView.superview == nil {
      scrollView.addSubview(selectionView)
    }
  }
  
  private var selectionStartPoint: CGPoint?
  private var selectionEndPoint: CGPoint?
  private var selectedCardInstances: OrderedSet<CardInstance> = [] {
    didSet {
      let cardViews = GameState.current.battlefield.value.compactMap { self.cardView(for: $0) }
      for cardView in cardViews {
        if selectedCardInstances.contains(cardView.cardInstance) {
          cardView.layer.shadowColor = #colorLiteral(red: 0, green: 0.7107098699, blue: 0.9997602105, alpha: 1).cgColor
          cardView.layer.shadowRadius = 25
          cardView.layer.shadowOpacity = 1
          cardView.layer.shadowOffset = .zero
          cardView.layer.masksToBounds = false
        } else {
          cardView.layer.shadowOpacity = 0
        }
      }
      
      if selectedCardInstances.isEmpty {
        presentedViewController?.dismiss(animated: true)
      }
    }
  }
  
  @objc private func recognizePan(_ gestureRecognizer: UIGestureRecognizer) {
    let cardViews = GameState.current.battlefield.value.compactMap { self.cardView(for: $0) }
    
    let location = gestureRecognizer.location(in: scrollView)
    
    switch gestureRecognizer.state {
    case .began:
      selectionStartPoint = location
      selectionEndPoint = location
      selectionView.isHidden = false
      selectedCardInstances = []
    case .changed:
      selectionEndPoint = location
      selectionView.isHidden = false
    case .ended:
      selectionStartPoint = nil
      selectionEndPoint = nil
      selectionView.isHidden = true
      return
    default:
      break
    }
    
    guard let selectionStartPoint, let selectionEndPoint else { return }
    
    let selectionRect = CGRect(
      x: min(selectionStartPoint.x, selectionEndPoint.x),
      y: min(selectionStartPoint.y, selectionEndPoint.y),
      width: abs(selectionStartPoint.x - selectionEndPoint.x),
      height: abs(selectionStartPoint.y - selectionEndPoint.y)
    )
    
    selectionView.frame = selectionRect
    
    let selected = cardViews.filter { cardView in
      let frame = self.scrollView.convert(cardView.frame, from: cardView.superview)
      return selectionRect.intersects(frame) && !cardView.isHidden
    }
    
    self.selectedCardInstances = OrderedSet(selected.compactMap(\.cardInstance))
  }
  
  func viewStack(cards: OrderedSet<CardInstance>, fromView sourceView: UIView?) {
    guard !cards.isEmpty else { return }
    guard let owner = cards.first?.ownerIdentifier, cards.allSatisfy({ $0.ownerIdentifier == owner }) else { return }
    guard let pileViewController = self.storyboard?.instantiateViewController(identifier: "PileViewController") as? PileViewController else { return }
    
    pileViewController.setStack(sourceView: sourceView, owner: owner, sort: self.sortByZOrder)
    
    let navigationController = UINavigationController(rootViewController: pileViewController)
    navigationController.modalPresentationStyle = .popover
    navigationController.popoverPresentationController?.permittedArrowDirections = [.left, .right]
    navigationController.popoverPresentationController?.sourceView = sourceView
    navigationController.popoverPresentationController?.passthroughViews = [self.view]
    
    if owner == .b {
      navigationController.view.transform = CGAffineTransform(rotationAngle: .pi)
    }
    
    self.present(navigationController, animated: true, completion: nil)
  }
  
  private func sortByZOrder(_ cardInstances: [CardInstance]) -> [CardInstance] {
        let cardViews = cardInstances.compactMap(cardView(for:))
    
        // Bring the cardviews to front, keeping the relative order the moved views already had.
        var cardViewZOrders: [CardInstance: Int] = [:]
        for cardInstance in cardInstances {
          guard let cardView = self.cardView(for: cardInstance), let index = cardView.superview?.subviews.firstIndex(of: cardView) else { continue }
          cardViewZOrders[cardInstance] = index
        }
        let sortedCardViews = cardViews.sorted { first, second in
          let firstZPosition = cardViewZOrders[first.cardInstance] ?? 0
          let secondZPosition = cardViewZOrders[second.cardInstance] ?? 0
          return firstZPosition < secondZPosition
        }
        let sortedCards = sortedCardViews.compactMap(\.cardInstance)
    
        return sortedCards
  }
}

extension BoardViewController: UIContextMenuInteractionDelegate {
  func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
    let cardInstance = GameState.current.battlefield.value.first { cardInstance in
      self.cardView(for: cardInstance)?.interactions.contains(where: { $0 as? UIContextMenuInteraction == interaction }) == true
    }
    
    if let cardInstance, !selectedCardInstances.contains(cardInstance) {
      selectedCardInstances.removeAll()
    }
    
    let cardInstances: [CardInstance] = selectedCardInstances.isEmpty ? [cardInstance].compactMap { $0 } : Array(selectedCardInstances)
    
    guard cardInstances.count > 1 else {
      if let cardInstance = cardInstances.first {
        self.focus(on: cardInstance, view: cardView(for: cardInstance))
      }
      return nil
    }
    
    let configuration =  UIContextMenuConfiguration {
      // Preview provider
      guard let vc = self.storyboard?.instantiateViewController(identifier: "CardImageViewController") as? CardImageViewController else { return UIViewController() }
      
      guard cardInstances.count == 1 else {
        struct CardStack: View {
          let cardInstances: [CardInstance]
          
          var body: some View {
            GeometryReader { proxy in
              VStack(spacing: -proxy.size.width*0.6) {
                ForEach(cardInstances, id: \.uuid) { cardInstance in
                  SwiftUICardView(card: cardInstance, isRotationEnabled: false)
                }
              }
            }
          }
        }
        
        let cardViews = cardInstances.compactMap(self.cardView(for:))
        
        // Bring the cardviews to front, keeping the relative order the moved views already had.
        var cardViewZOrders: [CardInstance: Int] = [:]
        for cardInstance in cardInstances {
          guard let cardView = self.cardView(for: cardInstance), let index = cardView.superview?.subviews.firstIndex(of: cardView) else { continue }
          cardViewZOrders[cardInstance] = index
        }
        let sortedCardViews = cardViews.sorted { first, second in
          let firstZPosition = cardViewZOrders[first.cardInstance] ?? 0
          let secondZPosition = cardViewZOrders[second.cardInstance] ?? 0
          return firstZPosition < secondZPosition
        }
        let sortedCards = sortedCardViews.compactMap(\.cardInstance)
        
        return UIHostingController(rootView: CardStack(cardInstances: sortedCards))
      }
      
      vc.cardInstance = cardInstance
      
      return vc
    } actionProvider: { suggestedActions in
      if cardInstances.count == 1, let cardInstance {
        var actions: [UIMenuElement] = []
        actions.append(UIAction(title: "More…") { _ in
          self.focus(on: cardInstance, view: self.cardView(for: cardInstance))
        })
        return UIMenu(title: cardInstance.representation.name ?? "", children: actions)
      } else {
        let actions = self.makeSelectedMenuActions(from: cardInstance).filter { $0.style != .cancel }.map { $0.uiAction }
        return UIMenu(title: "\(cardInstances.count) card\(cardInstances.count == 1 ? "" : "s")", children: actions)
      }
    }
    
    return configuration

  }
  
  
}

extension BoardViewController: UIScrollViewDelegate {
	func viewForZooming(in scrollView: UIScrollView) -> UIView? {
		return board
	}
	
	func scrollViewDidZoom(_ scrollView: UIScrollView) {
		
	}
	
	func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
		print("zoomed to scale: \(scale)")
		print("Offset: \(scrollView.contentOffset)")
		print("Visible size: \(scrollView.visibleSize)")
	}
}

extension BoardViewController: UIDocumentPickerDelegate {
	fileprivate func loadDeck(from url: URL, for playerIdentifier: Player.Identifier) {
		DispatchQueue.global(qos: .userInteractive).async {
			do {
				let data = try Data(contentsOf: url)
				DispatchQueue.main.async {
					guard let string = String(data: data, encoding: .utf8) else {
						return
					}
                    if let phoneMode = self.phoneMode {
                        phoneMode.send(Command.loadDeck(.init(playerIdentifier: playerIdentifier, deckList: string, source: .decklist)))
                    } else {
                        let groups = DeckParser.parse(deckList: string, autofix: true)
                        self.loadDeck(groups, playerIdentifier: playerIdentifier)
                    }
				}
			} catch {
				DispatchQueue.main.async {
					let alert = UIAlertController(title: "Error Loading Deck", message: String(describing: error), preferredStyle: .alert)
					let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
					alert.addAction(okAction)
					self.present(alert, animated: true, completion: nil)
				}
			}
		}
	}
	
	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
		guard let loadDeckPlayerIdentifier = self.loadDeckPlayerIdentifier else { return }
		self.loadDeckPlayerIdentifier = nil
		guard urls.count == 1, let url = urls.first else { return }
		
		loadDeck(from: url, for: loadDeckPlayerIdentifier)
		// Phone Play picks the file over the board menu's Load Deck page; close that too.
		if phoneMode != nil, presentedViewController != nil, presentedViewController !== controller { dismiss(animated: true) }
	}
	
	func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
		self.loadDeckPlayerIdentifier = nil
	}
}

extension BoardViewController: UIDropInteractionDelegate {
	
	func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
		return session.canLoadObjects(ofClass: CardInstance.self)
	}
	
	func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        if phoneMode != nil {
            updatePhoneAttachHover(at: session.location(in: view), excluding: localCardIDs(in: session))
        }
		return UIDropProposal(operation: .move)
	}

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
        clearPhoneAttachHover()
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
        clearPhoneAttachHover()
    }

    private func localCardIDs(in session: UIDropSession) -> Set<UUID> {
        Set(session.items.compactMap { item -> UUID? in
            if let card = item.localObject as? CardInstance { return card.uuid }
            guard let data = item.itemProvider.teamData, let text = String(data: data, encoding: .utf8) else { return nil }
            return UUID(uuidString: text)
        })
    }
	
	func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        let location = session.location(in: view)
        if performPhoneCombatDrop(at: location, ids: localCardIDs(in: session)) { return }
        // Only an armed (glowing "Attach") target attaches; decide now, before any async loading.
        let attachTarget = armedPhoneAttachTarget(at: location, excluding: localCardIDs(in: session))
        if let phoneMode, phoneUnattachArmed, let id = localCardIDs(in: session).first, phoneMode.game.attachments[id] != nil {
            clearPhoneAttachHover()
            phoneMode.send(.attach(id, nil))
            return
        }
        clearPhoneAttachHover()

        // SwiftUI drags are not guaranteed to expose a UIKit localDragSession.
        // Resolve our local UUID metadata first, then use the asynchronous item
        // provider API for other valid card drags instead of blocking the UI.
        let localCards = session.items.compactMap { item -> CardInstance? in
            if let card = item.localObject as? CardInstance { return card }
            guard let data = item.itemProvider.teamData,
                  let text = String(data: data, encoding: .utf8),
                  let id = UUID(uuidString: text) else { return nil }
            return GameState.current.cardInstance(with: id)
        }
        if localCards.count == session.items.count {
            finishDroppedCards(localCards, at: location, attachTo: attachTarget)
        } else {
            session.loadObjects(ofClass: CardInstance.self) { [weak self] objects in
                DispatchQueue.main.async { [weak self] in
                    self?.finishDroppedCards(objects.compactMap { $0 as? CardInstance }, at: location, attachTo: attachTarget)
                }
            }
        }
	}
	
    private func phoneAttachmentTarget(at point: CGPoint, excluding ids: Set<UUID>) -> CardInstance? {
        guard phoneMode != nil else { return nil }
        if let target = board.subviews.reversed().compactMap({ $0 as? MiniCardView }).first(where: {
            !$0.isHidden && !ids.contains($0.cardInstance.uuid) && $0.bounds.contains($0.convert(point, from: view))
        }) { return target.cardInstance }
        let windowPoint = view.convert(point, to: view.window)
        return [landOrganizer, opponentLandOrganizer].compactMap { $0 }
            .compactMap { $0.card(at: windowPoint, excluding: ids) }.first
    }

    /// What dropping here would do besides a plain move.
    private enum PhoneDropIntent: Equatable { case attach(UUID), unattach, block(UUID), unblock, target(UUID) }

    /// Hovering a dragged card over another starts a short delay; then the target glows blue with
    /// "Attach" floating above it. Dragging an attached card off its host offers "Unattach" instead
    /// (cancelled by moving back onto the host). Changing intent restarts the delay.
    private func updatePhoneAttachHover(at point: CGPoint, excluding ids: Set<UUID>, dragged: UUID? = nil) {
        phoneLastDragPoint = point
        let draggedID = dragged ?? (ids.count == 1 ? ids.first : nil)
        let parent = draggedID.flatMap { phoneMode?.game.attachments[$0] }
        let target = phoneHandDropRegionContains(point) ? nil : phoneAttachmentTarget(at: point, excluding: ids)
        let blocker = draggedID.flatMap { id in phoneMode.flatMap { canPhoneBlock(with: id, session: $0) ? $0.game.cards[id] : nil } }
        let blocking = blocker.flatMap { phoneMode?.game.combat?.blockers[$0.uuid] }
        let intent: PhoneDropIntent?
        if let draggedID, let target, isPhoneTargetingSpellInHand(draggedID) {
            // An instant, sorcery or Aura from your hand: offer to cast it targeting this card.
            intent = .target(target.uuid)
        } else if blocker != nil, let target, phoneMode?.game.combat?.attackers.contains(target.uuid) == true {
            // Your creature over one of the opponent's attackers: block it.
            intent = target.uuid == blocking ? nil : .block(target.uuid)
        } else if blocking != nil, !phoneHandDropRegionContains(point), phonePileZone(at: point) == nil {
            // Over a pile the card just moves there (which also ends its block).
            intent = .unblock
        } else if let target {
            intent = target.uuid == parent ? nil : .attach(target.uuid)
        } else if parent != nil, !phoneHandDropRegionContains(point) {
            intent = .unattach
        } else {
            intent = nil
        }
        let combatPreview = blocker.flatMap { card -> (blocker: UUID, attacker: UUID)? in
            guard let target, phoneMode?.game.combat?.attackers.contains(target.uuid) == true else { return nil }
            return (card.uuid, target.uuid)
        }
        if let intent, intent == phoneAttachHover?.intent {
            phoneCombatPreview = combatPreview
            updatePhoneCombatLines()
            if phoneAttachHover?.armed == true { showPhoneDropIntent(intent, at: point) } // follow the finger/relayouts
            return
        }
        clearPhoneAttachHover()
        phoneCombatPreview = combatPreview
        updatePhoneCombatLines()
        guard let intent else { return }
        phoneAttachGeneration += 1
        let generation = phoneAttachGeneration
        phoneAttachHover = (intent, false, generation)
        // GCD's main queue also runs while UIKit tracks a drag (unlike a default-mode Timer).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, let hover = self.phoneAttachHover, hover.generation == generation else { return }
            self.phoneAttachHover?.armed = true
            PhoneHaptics.pickUp()
            self.showPhoneDropIntent(intent, at: self.phoneLastDragPoint ?? point)
        }
    }

    /// Instants, sorceries and Auras in your hand go onto the stack, possibly already targeting.
    private func isPhoneTargetingSpellInHand(_ id: UUID) -> Bool {
        guard let session = phoneMode,
              let card = session.game.state[player: session.player].hand.cards.value.first(where: { $0.uuid == id }) else { return false }
        return card.isPhoneTargetingSpell
    }

    /// The permanent an armed "Target" hover would target.
    private func armedPhoneSpellTarget(at point: CGPoint, excluding ids: Set<UUID>) -> CardInstance? {
        guard let hover = phoneAttachHover, hover.armed, case .target(let id) = hover.intent,
              let target = phoneAttachmentTarget(at: point, excluding: ids), target.uuid == id else { return nil }
        return target
    }

    private func armedPhoneAttachTarget(at point: CGPoint, excluding ids: Set<UUID>) -> CardInstance? {
        guard let hover = phoneAttachHover, hover.armed, case .attach(let id) = hover.intent,
              let target = phoneAttachmentTarget(at: point, excluding: ids), target.uuid == id else { return nil }
        return target
    }

    /// The attacker an armed "Block" hover would block.
    private func armedPhoneBlockTarget(at point: CGPoint, excluding ids: Set<UUID>) -> CardInstance? {
        guard let hover = phoneAttachHover, hover.armed, case .block(let id) = hover.intent,
              let target = phoneAttachmentTarget(at: point, excluding: ids), target.uuid == id else { return nil }
        return target
    }

    /// Whether the dragged card can block: your untapped-or-not creature on the battlefield, while
    /// the opponent is attacking.
    private func canPhoneBlock(with id: UUID, session: PhoneGameSession) -> Bool {
        let game = session.game
        guard let attacking = game.attackingPlayer, attacking != session.player,
              let card = game.cards[id], game.state.battlefield.value.contains(card),
              card.controllerIdentifier.value == session.player, card.isPhoneCreature,
              game.attachments[id] == nil else { return false }
        return true
    }

    /// Drops that declare or cancel a block. Returns true when the drop was a combat drop.
    private func performPhoneCombatDrop(at point: CGPoint, ids: Set<UUID>) -> Bool {
        guard let session = phoneMode, ids.count == 1, let id = ids.first else { return false }
        // A Rules blocker drop is an explicit declaration. It needn't dwell until the
        // sandbox attach/block hover arms; the adapter retains the attacker for XMage's
        // asynchronous follow-up question.
        let immediate = session.mode == .rules && canPhoneBlock(with: id, session: session)
            ? phoneAttachmentTarget(at: point, excluding: ids).flatMap {
                session.game.combat?.attackers.contains($0.uuid) == true ? $0 : nil
            } : nil
        if let target = immediate ?? armedPhoneBlockTarget(at: point, excluding: ids) {
            clearPhoneAttachHover()
            session.send(.block(id, target.uuid))
            return true
        }
        if phoneAttachHover?.armed == true, phoneAttachHover?.intent == .unblock, session.game.combat?.blockers[id] != nil,
           phonePileZone(at: point) == nil {
            clearPhoneAttachHover()
            session.send(.block(id, nil))
            return true
        }
        return false
    }

    private var phoneUnattachArmed: Bool {
        phoneAttachHover?.armed == true && phoneAttachHover?.intent == .unattach
    }

    private func clearPhoneAttachHover() {
        phoneCombatPreview = nil
        updatePhoneCombatLines()
        phoneAttachHover = nil
        phoneAttachIndicator?.removeFromSuperview()
        phoneAttachIndicator = nil
        phoneAttachLabel?.removeFromSuperview()
        phoneAttachLabel = nil
        if phoneStackDrag == nil { hidePhoneDragHover() }
    }

    /// The card's drawn art (not its padded frame): center, size and rotation in view coordinates.
    private func phoneCardGeometry(_ card: CardInstance) -> (center: CGPoint, size: CGSize, angle: CGFloat)? {
        if let mini = cardView(for: card), !mini.isHidden, mini.window != nil, let art = mini.cardView {
            var rect = art.bounds
            if let fraction = mini.renderedCardFraction {
                // A rendered mini card: just the card, not the padding drawn around it.
                rect = CGRect(x: rect.minX + rect.width * fraction.minX, y: rect.minY + rect.height * fraction.minY,
                              width: rect.width * fraction.width, height: rect.height * fraction.height)
            } else if let image = art.image, image.size.width > 0, image.size.height > 0 {
                let scale = min(rect.width / image.size.width, rect.height / image.size.height)
                let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                rect = CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
            }
            let origin = art.convert(rect.origin, to: view)
            let right = art.convert(CGPoint(x: rect.maxX, y: rect.minY), to: view)
            let down = art.convert(CGPoint(x: rect.minX, y: rect.maxY), to: view)
            return (art.convert(CGPoint(x: rect.midX, y: rect.midY), to: view),
                    CGSize(width: hypot(right.x - origin.x, right.y - origin.y), height: hypot(down.x - origin.x, down.y - origin.y)),
                    atan2(right.y - origin.y, right.x - origin.x))
        }
        guard let frame = [landOrganizer, opponentLandOrganizer].compactMap({ $0?.landFrame(for: card.uuid) }).first
            .map({ view.convert($0, from: nil) }) else { return nil }
        return (CGPoint(x: frame.midX, y: frame.midY), frame.size, 0)
    }

    private func phoneDropLabel(_ text: String) -> UILabel {
        let label = phoneAttachLabel ?? UILabel()
        label.text = text
        label.font = UIFont(name: "Beleren2016-Bold", size: 14) ?? .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = .systemBlue
        label.textAlignment = .center
        label.layer.cornerRadius = 6
        label.layer.masksToBounds = true
        label.isUserInteractionEnabled = false
        label.accessibilityIdentifier = "phone-drop-intent"
        let size = label.intrinsicContentSize
        label.bounds.size = CGSize(width: size.width + 14, height: size.height + 6)
        if label.superview == nil { view.addSubview(label) }
        phoneAttachLabel = label
        return label
    }

    private func showPhoneDropIntent(_ intent: PhoneDropIntent, at point: CGPoint) {
        switch intent {
        case .attach(let id), .block(let id), .target(let id):
            let isBlock = intent == .block(id)
            let color: UIColor = isBlock ? .systemOrange : .systemBlue
            guard let card = phoneMode?.game.cards[id] ?? GameState.current.cardInstance(with: id),
                  let geometry = phoneCardGeometry(card) else { return }
            let indicator: UIView
            if let existing = phoneAttachIndicator { indicator = existing } else {
                indicator = UIView()
                indicator.isUserInteractionEnabled = false
                indicator.layer.borderWidth = 3
                indicator.layer.shadowOpacity = 1
                indicator.layer.shadowRadius = 10
                indicator.layer.shadowOffset = .zero
                indicator.accessibilityIdentifier = "phone-attach-indicator"
                phoneAttachIndicator = indicator
            }
            indicator.layer.borderColor = color.cgColor
            indicator.layer.shadowColor = color.cgColor
            indicator.backgroundColor = color.withAlphaComponent(0.15)
            indicator.transform = .identity
            if let mini = cardView(for: card), !mini.isHidden, mini.window != nil {
                // Inside the mini card, around the drawn card only, like the combat glow: it
                // follows the card's tap rotation instead of being placed from a computed angle.
                let host = phoneOutlineHost(mini)
                if indicator.superview !== host { host.addSubview(indicator) }
                host.bringSubviewToFront(indicator)
                let scale = max(0.01, scrollView.zoomScale * hypot(mini.transform.a, mini.transform.b))
                indicator.frame = phoneDrawnCardRect(in: mini).insetBy(dx: -2 / scale, dy: -2 / scale)
                indicator.layer.borderWidth = 3 / scale
                indicator.layer.shadowRadius = 10 / scale
                indicator.layer.cornerRadius = min(10 / scale, indicator.bounds.width * 0.05)
            } else {
                // Organized lands are SwiftUI; outline their frame on the board.
                if indicator.superview !== view { view.addSubview(indicator) }
                indicator.layer.borderWidth = 3
                indicator.layer.shadowRadius = 10
                indicator.bounds.size = CGSize(width: geometry.size.width + 4, height: geometry.size.height + 4)
                indicator.center = geometry.center
                indicator.layer.cornerRadius = min(10, geometry.size.width * 0.05)
                indicator.transform = CGAffineTransform(rotationAngle: geometry.angle)
                // Under the card being dragged.
                if let preview = phoneDragPreview, preview.superview === view { view.insertSubview(indicator, belowSubview: preview) }
                else { view.bringSubviewToFront(indicator) }
            }
            let label = phoneDropLabel(isBlock ? "Block" : intent == .target(id) ? "Target" : "Attach")
            label.backgroundColor = color
            label.center = phoneDragLabelCenter(for: label, finger: point)
            view.bringSubviewToFront(label)
        case .unattach, .unblock:
            phoneAttachIndicator?.removeFromSuperview()
            phoneAttachIndicator = nil
            let label = phoneDropLabel(intent == .unblock ? "Stop Blocking" : "Unattach")
            label.backgroundColor = .systemBlue
            label.center = phoneDragLabelCenter(for: label, finger: point)
            view.bringSubviewToFront(label)
        }
    }

    /// Drops on the hand's visible area or the empty part of the local HUD band go to the hand.
    /// (The piles in the band have their own drop interactions and are hit first.)
    private func phoneHandDropRegionContains(_ point: CGPoint) -> Bool {
        guard phoneMode != nil, let container = localPhoneBar?.handContainerView,
              container.superview === view, !container.isHidden else { return false }
        // Only where the hand sits (or would sit, when empty) — not the HUD between the piles.
        let content = container.phoneContentFrame ?? container.bounds
        return view.convert(content, from: container).contains(point)
    }

    private func finishDroppedCards(_ cards: [CardInstance], at point: CGPoint, attachTo attachTarget: CardInstance?) {
        if let session = phoneMode, phoneHandDropRegionContains(point) {
            let inHand = Set(session.game.state[player: session.player].hand.cards.value.map(\.uuid))
            for card in cards where !inHand.contains(card.uuid) { session.send(.moveToPlayer(card.uuid, .hand, session.player, bottom: false)) }
        } else if let session = phoneMode, let target = attachTarget {
            for card in cards where card.uuid != target.uuid { session.send(.attachDroppedCard(card.uuid, target.uuid)) }
        } else {
            moveCardItemsToBattlefield(cards, at: board.convert(point, from: view))
        }
    }

	func moveCardItemsToBattlefield<S: Sequence>(_ cardInstances: S, at location: CGPoint) where S.Element == CardInstance {
        if let phoneMode {
            for card in cardInstances {
                playPhoneCard(card, session: phoneMode)
            }
            return
        }
		for cardInstance in cardInstances {
			cardInstance.pile?.cards.mutate {
				$0.remove(cardInstance)
			}
//			cardInstance.reset() // this doesn't need to be called here because cards get reset when they change to a different zone
			
			cardInstance.center.accept(location)
			addCardViewToBattlefield(for: cardInstance)
		}
		
		GameState.current.battlefield.mutate {
			$0.formUnion(cardInstances)
		}
		
		try? GameState.current.save()
	}
	
}

extension BoardViewController: UIDragInteractionDelegate {
	
	func dragItem(for cardInstance: CardInstance) -> UIDragItem {
		let item = NSItemProvider(card: cardInstance)
		let dragItem = UIDragItem(itemProvider: item)
		dragItem.localObject = cardInstance
//		dragItem.previewProvider = { [weak self] in
//			let image: UIImage? = {
//				UIGraphicsBeginImageContextWithOptions(cardView.bounds.size, false, 0)
//
//				defer {
//					UIGraphicsEndImageContext()
//				}
//
//				guard let context = UIGraphicsGetCurrentContext() else { return nil }
//				cardView.layer.render(in: context)
//				return UIGraphicsGetImageFromCurrentImageContext()
//
//			}()
//			let imageView = UIImageView(image: image ?? UIImage.resource(named: "mtg-card-back-png-1")!)
//
////			imageView.layer.masksToBounds = true
////			imageView.layer.cornerRadius = 5
//			imageView.contentMode = .scaleAspectFit
//
//			imageView.frame.size = cardView.bounds.size
//
//			let parameters = UIDragPreviewParameters()
//			parameters.backgroundColor = .clear
//			return UIDragPreview(view: imageView, parameters: parameters)
//		}
		return dragItem
	}
	
	func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
		guard let cardView = (interaction.view as? MiniCardView) ?? interaction.view?.superview?.superview as? MiniCardView, let cardInstance = cardView.cardInstance else { return [] }
		
		return [dragItem(for: cardInstance)]
	}
	
    func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
        guard phoneMode != nil else { return }
        let cardView = (interaction.view as? MiniCardView) ?? interaction.view?.superview?.superview as? MiniCardView
        cardView?.alpha = 0
    }

    func dragInteraction(_ interaction: UIDragInteraction, sessionDidEnd session: UIDragSession) {
        guard phoneMode != nil else { return }
        let cardView = (interaction.view as? MiniCardView) ?? interaction.view?.superview?.superview as? MiniCardView
        cardView?.alpha = 1
    }

	func dragInteraction(_ interaction: UIDragInteraction, itemsForAddingTo session: UIDragSession, withTouchAt point: CGPoint) -> [UIDragItem] {
		guard let cardView = (interaction.view as? MiniCardView) ?? interaction.view?.superview?.superview as? MiniCardView, let cardInstance = cardView.cardInstance else { return [] }
		
		return [dragItem(for: cardInstance)]
	}
	
}

extension BoardViewController: BottomBarViewControllerDelegate {
	func bottomBarViewController(_ bottomBarViewController: BottomBarViewController, passthroughViewsFor navigationController: UINavigationController) -> [UIView]? {
		dismiss(animated: true, completion: nil)
		self.focusViewController = navigationController
		
		return [view]
	}
}

// MARK: - Phone adaptation of the existing board
extension BoardViewController {
    private func startRulesGame(_ adapter: RulesPhoneAdapter) {
        let session = PhoneGameSession()
        AppDelegate.shared.phoneSession = session
        session.beginRules(adapter)
        attachPhoneSession()
        let prompt = UIHostingController(rootView: RulesPromptBar(session: adapter.engine, exit: { [weak self] in self?.leavePhoneGame(showingStart: true) }))
        prompt.view.backgroundColor = .clear
        // Grow with longer prompts instead of keeping the first prompt's height (which truncated text).
        if #available(iOS 16.0, *) { prompt.sizingOptions = .intrinsicContentSize }
        addChild(prompt)
        view.addSubview(prompt.view)
        prompt.view.translatesAutoresizingMaskIntoConstraints = false
        // Just above the hand and the main phase button, clear of both hands.
        let bottom = prompt.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -64)
        bottom.priority = .defaultHigh // a tall prompt slides up, but never past the top
        NSLayoutConstraint.activate([
            bottom,
            // Centred above the hand, where Arena shows "Pay {W}" or "Choose a target": clear of the
            // stack and the main button at the right.
            prompt.view.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            prompt.view.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            prompt.view.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -24),
            prompt.view.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)
        ])
        prompt.didMove(toParent: self)
        rulesPromptHost = prompt
        rulesPromptBottom = bottom
        // Arena's centre instruction band never intercepts card taps or combat drags.
        let banner = UIHostingController(rootView: RulesBoardBanner(session: adapter.engine))
        banner.view.backgroundColor = .clear
        banner.view.isUserInteractionEnabled = false
        if #available(iOS 16.0, *) { banner.sizingOptions = .intrinsicContentSize }
        addChild(banner)
        view.addSubview(banner.view)
        banner.view.translatesAutoresizingMaskIntoConstraints = false
        let bannerCenter = banner.view.centerYAnchor.constraint(equalTo: view.topAnchor, constant: view.bounds.midY)
        rulesBannerCenterY = bannerCenter
        NSLayoutConstraint.activate([
            banner.view.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            bannerCenter,
            banner.view.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -24)
        ])
        banner.didMove(toParent: self)
        rulesBannerHost = banner
        // Decisions that aren't on the board take over the screen (Arena); the layer hides itself
        // between them so it never swallows touches meant for the board.
        let modal = UIHostingController(rootView: RulesPromptModal(session: adapter.engine,
            exit: { [weak self] in self?.leavePhoneGame(showingStart: true) },
            onVisibilityChange: { [weak self] visible in self?.rulesModalHost?.view.isHidden = !visible }))
        modal.view.backgroundColor = .clear
        modal.view.isHidden = true
        addChild(modal)
        view.addSubview(modal.view)
        modal.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            modal.view.topAnchor.constraint(equalTo: view.topAnchor),
            modal.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            modal.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            modal.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        modal.didMove(toParent: self)
        rulesModalHost = modal
        let restore = UIHostingController(rootView: RulesPromptRestoreButton(session: adapter.engine))
        restore.view.backgroundColor = .clear
        if #available(iOS 16.0, *) { restore.sizingOptions = .intrinsicContentSize }
        addChild(restore); view.addSubview(restore.view); restore.didMove(toParent: self)
        restore.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            restore.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            restore.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
        rulesPromptRestoreHost = restore
        let actions = UIHostingController(rootView: RulesActionStack(session: adapter.engine, adapter: adapter))
        actions.view.backgroundColor = .clear
        if #available(iOS 16.0, *) { actions.sizingOptions = .intrinsicContentSize }
        addChild(actions)
        view.addSubview(actions.view)
        actions.view.translatesAutoresizingMaskIntoConstraints = false
        actions.didMove(toParent: self)
        rulesActionHost = actions
        let skip = UIHostingController(rootView: RulesFastForwardPill(session: adapter.engine))
        skip.view.backgroundColor = .clear
        if #available(iOS 16.0, *) { skip.sizingOptions = .intrinsicContentSize }
        addChild(skip); view.addSubview(skip.view); skip.didMove(toParent: self)
        skip.view.translatesAutoresizingMaskIntoConstraints = false
        rulesFastForwardHost = skip
    }

    private func showRulesToast(_ message: String) {
        view.subviews.filter { $0.accessibilityIdentifier == "rules-toast" }.forEach { $0.removeFromSuperview() }
        let label = PaddedToastLabel()
        label.text = message
        label.numberOfLines = 2
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        label.layer.cornerRadius = 12
        label.layer.masksToBounds = true
        label.accessibilityIdentifier = "rules-toast"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
        label.alpha = 0
        UIView.animate(withDuration: 0.15) { label.alpha = 1 }
        UIView.animate(withDuration: 0.3, delay: 2.2, options: []) { label.alpha = 0 } completion: { _ in label.removeFromSuperview() }
    }

    /// Keeps the Rules prompt above everything the board re-raises, sitting just above the local
    /// phase button (or near the bottom when that button isn't laid out yet).
    /// Just above the local life total (bottom right) and just below the opponent's (top left).
    private func positionRulesPhaseMarkers() {
        func lifeContainer(_ identifier: String) -> UIView? {
            var queue = [bottomBarA?.view, bottomBarB?.view].compactMap { $0 }
            while !queue.isEmpty {
                let next = queue.removeFirst()
                if next.accessibilityIdentifier == identifier { return next }
                queue += next.subviews
            }
            return nil
        }
        for (host, mine) in zip(rulesPhaseMarkerHosts, [true, false]) where host.view.superview === view {
            let player = mine ? phoneMode?.player : phoneMode?.opponent
            guard let life = player.flatMap({ phoneLifeHosts[$0]?.view }) ?? lifeContainer(mine ? "phone-life-local" : "phone-life-opponent"), life.window != nil, !life.isHidden else {
                host.view.isHidden = true; continue
            }
            let lifeFrame = view.convert(life.bounds, from: life)
            let size = host.sizeThatFits(in: CGSize(width: 400, height: 100))
            var x = lifeFrame.midX - size.width / 2
            var y = lifeFrame.maxY + 2
            if mine, let button = localPhoneBar?.untapButton, button.window != nil {
                let action = view.convert(button.bounds, from: button)
                let extraTop = rulesActionHost?.view.flatMap { !$0.isHidden && $0.bounds.height > 0 ? $0.frame.minY : nil } ?? action.minY
                x = action.midX - size.width / 2
                y = min(action.minY, extraTop) - size.height - 4
            }
            let frame = CGRect(x: x, y: y, width: size.width, height: size.height).integral
            host.view.isHidden = false
            if host.view.frame != frame { host.view.frame = frame }
            view.bringSubviewToFront(host.view)
        }
    }

    private func positionRulesPrompt() {
        guard let host = rulesPromptHost?.view, host.superview === view else { return }
        // Above both the phase button and the top of the hand fan, so no hand card hides under it.
        let tops = [localPhoneBar?.handContainerView].compactMap { $0 }
            .filter { $0.window != nil && !$0.isHidden }
            .map { view.convert($0.bounds, from: $0).minY }
        if let top = tops.min() {
            let constant = -(view.safeAreaLayoutGuide.layoutFrame.maxY - top + 8)
            if rulesPromptBottom?.constant != constant { rulesPromptBottom?.constant = constant }
        }
        positionRulesPhaseMarkers()
        if let banner = rulesBannerHost?.view, banner.superview === view {
            view.bringSubviewToFront(banner)
            // In the open space between the opponent's permanents and yours, so it never covers a
            // card's power and toughness (Josh: it hid an attacker's).
            if let session = phoneMode, let center = rulesBannerCenterY {
                var opponentBottom = view.safeAreaLayoutGuide.layoutFrame.minY
                var localTop = view.safeAreaLayoutGuide.layoutFrame.maxY
                for case let card as MiniCardView in board.subviews where !card.isHidden && card.alpha > 0.01 {
                    guard let instance = card.cardInstance else { continue }
                    let frame = view.convert(card.bounds, from: card)
                    if instance.controllerIdentifier.value == session.player { localTop = min(localTop, frame.minY) }
                    else { opponentBottom = max(opponentBottom, frame.maxY) }
                }
                let target = localTop > opponentBottom ? (opponentBottom + localTop) / 2 : view.bounds.midY
                if abs(center.constant - target) > 0.5 { center.constant = target }
            }
        }
        view.bringSubviewToFront(host)
        // Arena's controls sit right above the main (phase) button.
        if let actions = rulesActionHost?.view, actions.superview === view, let button = localPhoneBar?.untapButton, button.window != nil {
            if rulesActionConstraints.isEmpty || rulesActionConstraints.first?.secondItem as? UIView !== button {
                NSLayoutConstraint.deactivate(rulesActionConstraints)
                rulesActionConstraints = [
                    actions.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -6),
                    actions.trailingAnchor.constraint(equalTo: button.trailingAnchor)
                ]
                NSLayoutConstraint.activate(rulesActionConstraints)
            }
            view.bringSubviewToFront(actions)
            // Arena hides the turn controls while the opening hand is being decided.
            actions.isHidden = phoneBrowserMode == .openingHand
        }
        if let skip = rulesFastForwardHost?.view, let button = localPhoneBar?.untapButton, button.window != nil {
            if rulesFastForwardConstraints.isEmpty {
                rulesFastForwardConstraints = [skip.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -8),
                                               skip.centerYAnchor.constraint(equalTo: button.centerYAnchor)]
                NSLayoutConstraint.activate(rulesFastForwardConstraints)
            }
            skip.isHidden = phoneBrowserMode == .openingHand
            view.bringSubviewToFront(skip)
        }
        // The open hand draws over the turn controls and prompt strip (as on Arena); decisions that
        // take over the screen stay above it.
        if localPhoneBar?.handViewController?.phonePresentation.isExpanded == true,
           let hand = localPhoneBar?.handContainerView, hand.superview === view {
            view.bringSubviewToFront(hand)
            if let preview = phoneDragPreview { view.bringSubviewToFront(preview) }
        }
        if localPhoneBar?.handViewController?.phonePresentation.isExpanded != true {
            for host in phoneLifeHosts.values { view.bringSubviewToFront(host.view) }
            positionRulesPhaseMarkers()
        }
        if let modal = rulesModalHost?.view, modal.superview === view { view.bringSubviewToFront(modal) }
        if let restore = rulesPromptRestoreHost?.view { view.bringSubviewToFront(restore) }
    }

    private func showConnectionOptions() {
        guard let session = phoneMode else { return }
        let alert = UIAlertController(title: "Connection", message: session.status, preferredStyle: .alert)
        if session.mode == .join { alert.addAction(.init(title: "Reconnect", style: .default) { _ in session.reconnect() }) }
        alert.addAction(.init(title: "Cancel", style: .cancel))
        phonePresenter.present(alert, animated: true)
    }

    /// The menu's Reset button: reset decks and life, clear the board, or exit to the start screen.
    fileprivate func presentResetOptions(from presenter: UIViewController) {
        let alert = UIAlertController(title: "Reset", message: nil, preferredStyle: .alert)
        alert.addAction(.init(title: "Reset Decks and Life", style: .default) { [weak self] _ in
            self?.dismiss(animated: true) { self?.resetDecksAndLife() }
        })
        alert.addAction(.init(title: "Clear Board", style: .destructive) { [weak self] _ in
            self?.dismiss(animated: true) { self?.clearBoard() }
        })
        alert.addAction(.init(title: "Exit Game", style: .destructive) { [weak self] _ in
            self?.dismiss(animated: true) { self?.exitGame() }
        })
        alert.addAction(.init(title: "Cancel", style: .cancel))
        presenter.present(alert, animated: true)
    }

    private func resetDecksAndLife() {
        if let session = phoneMode {
            collapsePhoneHand()
            session.send(.resetDecks)
            return
        }
        let state = GameState.current
        // Tokens and emblems are deleted wherever they are.
        for card in state.allCards.values where card.representation.isToken || card.representation.isEmblem {
            if let pile = card.pile { pile.cards.mutate { $0.remove(card) } } else { card.remove.onNext(()) }
        }
        // Each player's last loaded deck goes back where it was loaded (move() also resets the cards).
        for (playerRaw, layout) in state.deckLayout ?? [:] {
            guard let identifier = Player.Identifier(rawValue: playerRaw) else { continue }
            for (locationRaw, ids) in layout {
                guard let location = Pile.Location(rawValue: locationRaw) else { continue }
                let cards = ids.compactMap { state.allCards[$0] }
                state.move(cardInstances: cards, to: state[player: identifier][location])
            }
        }
        for card in GameState.current.allCards.values {
            card.reset(removingCounters: true)
            card.commanderCasts.accept(0)
            card.revealedPlayers.accept([])
        }
        for player in state.allPlayers {
            player.library.cards.mutate { $0 = OrderedSet($0.contents.shuffled()) }
            player.library.isTopCardRevealed.accept(false)
            // Same starting life as loading: 40 for a 100-card commander deck, otherwise 20.
            let loaded = state.deckLayout?[player.identifier.rawValue] != nil
            let commander = !player.commandZone.cards.value.isEmpty
                && player.library.cards.value.count + player.commandZone.cards.value.count == 100
            player.life.accept(loaded ? (commander ? 40 : 20) : 40)
        }
        try? GameState.current.save()
    }

    private func clearBoard() {
        if let session = phoneMode {
            collapsePhoneHand()
            session.send(.reset)
            return
        }
        for card in GameState.current.battlefield.value { card.remove.onNext(()) }
        GameState.current = GameState()
        GameState.current.player2.isHidden.toggle()
        updatePlayersHidden()
        AppRouter.open(.board)
    }

    private func exitGame() {
        if phoneMode != nil {
            leavePhoneGame(showingStart: true)
        } else {
            try? GameState.current.save()
            AppRouter.showStart()
        }
    }

    private func startPhoneGame(resume: Bool, fixture: Bool = false) {
        let session = PhoneGameSession()
        AppDelegate.shared.phoneSession = session
        #if DEBUG
        if fixture { session.hostFixture() } else { session.host(resume: resume) }
        #else
        session.host(resume: resume)
        #endif
        attachPhoneSession()
    }

    private func joinPhoneGame() {
        let session = PhoneGameSession()
        AppDelegate.shared.phoneSession = session
        session.browse()
        attachPhoneSession()
        let picker = NearbyGamePickerController(session: session)
        let navigation = UINavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .formSheet
        picker.onJoined = { [weak self, weak navigation] in
            navigation?.dismiss(animated: true)
            self?.refreshPhoneBoard()
        }
        picker.onCancel = { [weak self, weak navigation] in
            navigation?.dismiss(animated: true)
            self?.leavePhoneGame()
        }
        present(navigation, animated: true)
    }

    private func attachPhoneSession() {
        guard let session = phoneMode else { return }
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        if !view.interactions.contains(where: { $0 is UIDropInteraction }) {
            view.addInteraction(UIDropInteraction(delegate: self))
        }
        if rulesPhaseMarkerHosts.isEmpty {
            rulesPhaseMarkerHosts = [true, false].map { mine in
                let host = UIHostingController(rootView: PhonePhaseMarkers(session: session, mine: mine))
                host.view.backgroundColor = .clear
                host.view.isUserInteractionEnabled = false
                addChild(host); view.addSubview(host.view); host.didMove(toParent: self)
                return host
            }
        }
        session.onUpdate = { [weak self] in self?.refreshPhoneBoard() }
        session.$error.compactMap { $0 }.sink { [weak self, weak session] message in
            guard let self else { return }
            // Rules mode: a refused gesture is a brief note over the board (Arena), not an alert that
            // stops play. Losing the connection still gets the alert.
            if session?.mode == .rules, session?.connected == true {
                self.showRulesToast(message)
                session?.error = nil
                return
            }
            let alert = UIAlertController(title: session?.connected == false && message.localizedCaseInsensitiveContains("disconnected") ? "Disconnected" : "Game", message: message, preferredStyle: .alert)
            alert.addAction(.init(title: "OK", style: .default) { _ in session?.error = nil })
            self.phonePresenter.present(alert, animated: true)
        }.store(in: &phoneSubscriptions)
        session.chooseCommanderZone = { [weak self] card, location, completion in
            guard let self else { completion(false); return }
            let names: [Pile.Location: String] = [.hand: "Hand", .graveyard: "Graveyard", .exile: "Exile", .library: "Library", .sideboard: "Sideboard"]
            let alert = UIAlertController(title: "Move \(card.representation.name ?? "commander") to…", message: nil, preferredStyle: .alert)
            alert.addAction(.init(title: names[location] ?? location.rawValue, style: .default) { _ in completion(false) })
            alert.addAction(.init(title: "Command Zone", style: .default) { _ in completion(true) })
            alert.addAction(.init(title: "Cancel", style: .cancel))
            self.phonePresenter.present(alert, animated: true)
        }
        for child in [bottomBarA, bottomBarB].compactMap({ $0 }) {
            // The top card of a graveyard, exile or library drags like a hand card.
            for (pileView, zone) in [(child.graveyardPileView, Pile.Location.graveyard), (child.exilePileView, .exile), (child.libraryPileView, .library)] {
                guard let pileView, !pileView.gestureRecognizers.orEmpty.contains(where: { $0 is PhonePilePanGesture }) else { continue }
                let pan = PhonePilePanGesture(target: self, action: #selector(phonePilePanned(_:)))
                pan.zone = zone
                pan.bar = child
                pan.maximumNumberOfTouches = 1
                pileView.addGestureRecognizer(pan)
            }
            child.focusOn = { [weak self] card in
                guard let self, let card, card.ownerIdentifier == session.player else { return }
                self.focus(on: card, view: nil)
            }
            child.handViewController?.bindHandCards()
        }
        localPhoneBar?.handViewController?.phonePresentation.onChange = { [weak self] in
            guard let self else { return }
            self.updatePhoneHandShield()
            // Expansion is animated only inside the hand's SwiftUI tree.
            self.layoutPhoneHandOverlay()
        }
        // Leaving the app ends any hand drag (its touch is gone), and coming back re-places the hand
        // for whatever size the scene has now.
        NotificationCenter.default.publisher(for: UIScene.willDeactivateNotification).sink { [weak self] _ in
            self?.abandonPhoneHandDrag()
            self?.clearPhoneResolutionAnimations()
        }.store(in: &phoneSubscriptions)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--phone-board-background-traits") {
            // UI tests: stand in for the other-size snapshot iOS takes of the app in the background.
            NotificationCenter.default.publisher(for: UIScene.didEnterBackgroundNotification).sink { [weak self] _ in
                guard let self else { return }
                let flipped = UITraitCollection(horizontalSizeClass: self.traitCollection.horizontalSizeClass == .compact ? .regular : .compact)
                for child in [self.bottomBarA, self.bottomBarB].compactMap({ $0 }) { self.setOverrideTraitCollection(flipped, forChild: child) }
            }.store(in: &phoneSubscriptions)
            NotificationCenter.default.publisher(for: UIScene.willEnterForegroundNotification).sink { [weak self] _ in
                guard let self else { return }
                for child in [self.bottomBarA, self.bottomBarB].compactMap({ $0 }) { self.setOverrideTraitCollection(nil, forChild: child) }
            }.store(in: &phoneSubscriptions)
        }
        #endif
        NotificationCenter.default.publisher(for: UIScene.didActivateNotification).sink { [weak self] _ in
            guard let self else { return }
            self.abandonPhoneHandDrag()
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
            self.layoutPhoneHandOverlay()
        }.store(in: &phoneSubscriptions)
        localPhoneBar?.handViewController?.phonePresentation.onCardDrag = { [weak self] card, phase, windowPoint in
            self?.handlePhoneHandDrag(card, phase: phase, windowPoint: windowPoint) ?? false
        }
        adoptPhoneHandContainer()
        if phoneHandShield == nil {
            // Swallows taps outside the expanded hand: they only collapse it, nothing underneath reacts.
            let shield = PhoneHandShieldView(frame: view.bounds)
            shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            shield.isHidden = true
            shield.passesThrough = { [weak self] point in
                guard let self, let hand = self.localPhoneBar?.handContainerView else { return false }
                return hand.point(inside: hand.convert(point, from: self.view), with: nil)
            }
            shield.onDismiss = { [weak self] in self?.collapsePhoneHand() }
            view.addSubview(shield)
            phoneHandShield = shield
        }
        let opponentLands = LandOrganizerViewController(playerIdentifier: session.opponent, isOpponentRow: true)
        opponentLands.onLongPress = { [weak self] card in self?.focus(on: card, view: nil) }
        addChild(opponentLands)
        let opponentLandContainer = PhoneLandContainerView()
        opponentLands.view.backgroundColor = .clear
        opponentLandContainer.addSubview(opponentLands.view)
        // The organizer's view uses Auto Layout (translatesAutoresizingMaskIntoConstraints = false): pin it.
        opponentLands.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            opponentLands.view.leadingAnchor.constraint(equalTo: opponentLandContainer.leadingAnchor),
            opponentLands.view.trailingAnchor.constraint(equalTo: opponentLandContainer.trailingAnchor),
            opponentLands.view.topAnchor.constraint(equalTo: opponentLandContainer.topAnchor),
            opponentLands.view.bottomAnchor.constraint(equalTo: opponentLandContainer.bottomAnchor)
        ])
        view.addSubview(opponentLandContainer)
        opponentLands.didMove(toParent: self)
        opponentLands.view.accessibilityIdentifier = "phone-opponent-lands"
        opponentLandOrganizer = opponentLands
        phoneOpponentLandContainer = opponentLandContainer
        // Land rows only catch touches on actual land stacks, so cards beside them stay tappable;
        // when the lands' width changes, the battlefield may switch between row and column layout.
        opponentLandContainer.hitRegions = { [weak opponentLands] in opponentLands?.landContentFrames ?? [] }
        (landOrganizerContainerView as? PhoneLandContainerView)?.hitRegions = { [weak self] in self?.landOrganizer?.landContentFrames ?? [] }
        for organizer in [landOrganizer, opponentLands].compactMap({ $0 }) {
            organizer.onLandContentChanged = { [weak self] in
                // Deferred: frames often arrive during a layout pass, and must not be dropped.
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.updatePhoneTargetArcs()
                    // Only growth past the reservation can change the battlefield layout.
                    if (self.currentPhoneLandMaxX() ?? 0) > (self.phoneLandReservation?.maxX ?? -.infinity) { self.view.setNeedsLayout() }
                }
            }
        }
        for organizer in [landOrganizer, opponentLandOrganizer].compactMap({ $0 }) {
            organizer.onDragChanged = { [weak self] card, point, size in
                guard let self else { return }
                self.movePhoneCardPreview(card, to: self.view.convert(point, from: self.view.window), sourceSize: size)
            }
            organizer.onDragCancelled = { [weak self] in self?.clearPhoneDragPreview() }
            organizer.onDragEnded = { [weak self] card, point in
                guard let self else { return }
                self.finishPhoneCardDrag(card, at: self.view.convert(point, from: self.view.window))
            }
        }
        refreshPhoneBoard()
    }

    func restorePhonePresentation() {
        guard phoneMode != nil, isViewLoaded else { return }
        UIView.performWithoutAnimation {
            refreshPhoneBoard()
            layoutPhoneHandOverlay()
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    private func refreshPhoneBoard() {
        guard let session = phoneMode, isViewLoaded else { return }
        // Before the previous stack/frames are replaced: they're where the opponent's cards started.
        let opponentMoves = phoneOpponentMoves(session)
        let stackIDs = Set(session.game.stack.map(\.id))
        let departures = phoneKnownStack?.gameID == session.game.id
            ? phonePreviousStack.filter { !stackIDs.contains($0.id) }.compactMap { item in
                phonePreviousStackFrames[item.id].map { (item, $0) }
            } : []
        phonePreviousStack = session.game.stack
        phoneKnownStack = (session.game.id, stackIDs)
        if let drag = phoneStackDrag, !stackIDs.contains(drag.itemID) { endPhoneStackDrag() }
        DispatchQueue.main.async { [weak self] in self?.presentPhonePacketChoices() }
        let cards = Array(session.game.cards.values)
        let fieldIDs = Set(session.game.state.battlefield.value.map(\.uuid) + session.game.stack.compactMap { $0.card?.uuid })
        let handIDs = Set(session.game.state[player: session.player].hand.cards.value.map(\.uuid))
        // A card that left the hand (played, discarded, put back…) closes the open hand, as on Arena.
        if let previousPhoneHandIDs, !previousPhoneHandIDs.subtracting(handIDs).isEmpty, phoneHandDrag == nil {
            collapsePhoneHand()
        }
        previousPhoneHandIDs = handIDs
        updatePhoneRevealedCards(session)
        refreshPhoneBrowser(session)
        updatePhoneOpeningHand(session)
        updatePhoneRulesChoice(session)
        // Libraries whose top card is kept revealed to this phone's player show it.
        for bar in [bottomBarA, bottomBarB].compactMap({ $0 }) {
            let viewers = session.game.revealedTops?[bar.player.identifier.rawValue] ?? []
            bar.libraryPileView?.revealsTopCardOverride = viewers.contains(session.player.rawValue)
        }
        // A shuffled library gives a quick wiggle.
        let shuffles = session.game.shuffles ?? [:]
        if let seen = phoneSeenShuffles {
            for (player, count) in shuffles where count > (seen[player] ?? 0) {
                let bar = [bottomBarA, bottomBarB].compactMap { $0 }.first { $0.player.identifier.rawValue == player }
                if let pile = bar?.libraryPileView { wigglePhoneLibrary(pile) }
            }
        }
        phoneSeenShuffles = shuffles
        // Cards castable from the graveyard or exile sit beside the hand with a glow.
        if let presentation = localPhoneBar?.handViewController?.phonePresentation {
            let castable = session.game.castableCards(for: session.player)
            if castable.count != presentation.castable.count || !zip(castable, presentation.castable).allSatisfy({ $0 === $1 }) {
                presentation.castable = castable
            }
            let inExile = Set(castable.filter { session.game.state[player: session.player].exile.cards.value.contains($0) }.map(\.uuid))
            if inExile != presentation.castableInExile { presentation.castableInExile = inExile }
            let companions = Set(castable.filter { session.game.state[player: session.player].sideboard.cards.value.contains($0) }.map(\.uuid))
            if companions != presentation.castableCompanions { presentation.castableCompanions = companions }
            let playable = session.mode == .rules ? session.game.rulesPlayable ?? [] : []
            if playable != presentation.playable { presentation.playable = playable }
        }
        for cardView in board.subviews.compactMap({ $0 as? MiniCardView }) where !fieldIDs.contains(cardView.cardInstance.uuid) {
            cardInstanceDisposeBags[cardView.cardInstance.uuid] = nil
            cardView.removeFromSuperview()
        }
        for card in cards where fieldIDs.contains(card.uuid) { addCardViewToBattlefield(for: card) }
        phoneStateBag = DisposeBag()
        // Existing card controls sometimes update relays before calling save.
        // Refresh placement immediately for tap, type, and control changes.
        for card in cards {
            Observable.combineLatest(card.isTapped, card.controllerIdentifier, card.isPowerToughnessVisible)
                .skip(1).subscribe(onNext: { [weak self] _ in self?.view.setNeedsLayout() }).disposed(by: phoneStateBag)
        }
        for child in [bottomBarA, bottomBarB].compactMap({ $0 }) { child.refreshForPhoneSession() }
        if landOrganizer?.playerIdentifier != session.player { landOrganizer?.playerIdentifier = session.player }
        let landAttachments = Dictionary(uniqueKeysWithValues: session.game.state.battlefield.value
            .filter { $0.representation.isLand }
            .map { ($0.uuid, session.game.attachedCards(to: $0.uuid)) })
        for organizer in [landOrganizer, opponentLandOrganizer].compactMap({ $0 }) {
            organizer.updateAttachments(landAttachments)
        }
        updateLandOrganizerLands()
        updatePlayersHidden()
        phoneStackCards?.rootView = makePhoneStackView(session)
        view.setNeedsLayout()
        if !departures.isEmpty || !opponentMoves.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.view.layoutIfNeeded()
                for (item, frame) in departures { self.animatePhoneStackDeparture(item, from: frame) }
                for (index, move) in opponentMoves.enumerated() { self.flyPhoneOpponentCard(move, delay: Double(index) * 0.06) }
            }
        }
    }

    private func layoutPhoneSettingsButton() {
        guard phoneMode != nil else { phoneSettingsButton?.isHidden = true; return }
        let button = phoneSettingsButton ?? {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
            button.setPreferredSymbolConfiguration(.init(pointSize: 23, weight: .semibold), forImageIn: .normal)
            button.tintColor = .white.withAlphaComponent(0.85)
            button.backgroundColor = UIColor.black.withAlphaComponent(0.35)
            button.layer.cornerRadius = 22
            button.accessibilityIdentifier = "phone-settings"
            button.accessibilityLabel = "Settings"
            button.addTarget(self, action: #selector(showBattlefieldMenu), for: .touchUpInside)
            view.addSubview(button)
            phoneSettingsButton = button
            return button
        }()
        let safe = view.safeAreaInsets
        button.frame = CGRect(x: view.bounds.maxX - safe.right - 48, y: max(4, safe.top), width: 44, height: 44)
        button.isHidden = false
        view.bringSubviewToFront(button)
    }

    private func layoutPhoneBattlefield() {
        guard let session = phoneMode, view.bounds.width > 0 else { return }
        defer { layoutPhoneSettingsButton() }
        phoneLayoutInProgress = true
        defer { phoneLayoutInProgress = false }
        // Don't reset these transforms to identity each pass: briefly moving a bar back to its
        // storyboard position flips its safe-area insets, which re-lays out the hosted SwiftUI
        // views and re-triggers this layout forever (seen as guest on home-indicator devices).
        // Measure the untransformed frame instead and only assign a transform when it changes.
        func untransformedFrame(_ view: UIView) -> CGRect { view.frame.offsetBy(dx: -view.transform.tx, dy: -view.transform.ty) }
        func translate(_ view: UIView, x: CGFloat = 0, y: CGFloat) {
            let target = CGAffineTransform(translationX: x.rounded(), y: y.rounded())
            if view.transform != target { view.transform = target }
        }
        let localIsA = session.player == .a
        let bottom = localIsA ? player1BarContainerView! : player2BarContainerView!
        let top = localIsA ? player2BarContainerView! : player1BarContainerView!
        // Swap the two existing bars for player 2; preserve their original views.
        let barHeight: CGFloat = min(104, max(52, view.bounds.height * 0.10))
        if phoneBackgroundLogo == nil, let logo = board.subviews.compactMap({ $0 as? UIImageView }).first {
            // The playmat belongs to the screen, independently of card zoom and paging.
            for constraint in board.constraints where constraint.firstItem as? UIView === logo || constraint.secondItem as? UIView === logo {
                constraint.isActive = false
            }
            logo.removeFromSuperview()
            logo.translatesAutoresizingMaskIntoConstraints = true
            logo.accessibilityIdentifier = "phone-background-logo"
            view.insertSubview(logo, belowSubview: scrollView)
            phoneBackgroundLogo = logo
        }
        phoneBackgroundLogo?.frame = view.bounds.insetBy(dx: 0, dy: barHeight)
        // Both bars contain only their HUD; the local hand has a separate board overlay.
        let bottomSpan = barHeight
        for container in [player1BarContainerView!, player2BarContainerView!] {
            for constraint in container.constraints where constraint.firstAttribute == .height && constraint.secondItem == nil {
                rememberPhoneConstraint(constraint)
                constraint.constant = container === bottom ? bottomSpan : barHeight // both bars share one height
            }
        }
        let landHeight: CGFloat = showLandOrganizer ? min(100, max(44, view.bounds.height * 0.10)) : 0
        for constraint in landOrganizerContainerView.constraints where constraint.firstAttribute == .height && constraint.secondItem == nil {
            rememberPhoneConstraint(constraint); constraint.constant = landHeight
        }
        view.layoutIfNeeded()
        bottom.subviews.first?.transform = .identity
        top.subviews.first?.transform = .identity
        bottom.isUserInteractionEnabled = session.canAct
        view.bringSubviewToFront(bottom)
        // The opponent's public piles are still inspectable; disable their life/hand actions in the bar itself.
        top.isUserInteractionEnabled = session.hasSnapshot
        var safe = view.safeAreaInsets
        safe.left += 24; safe.right += 24
        safe.top += 8
        // Each bar reaches as close to the edges as the system allows along its own band: on a
        // closed iPhone Duo only the camera's strip is avoided, not the whole side of the safe area.
        let barHeightEstimate = min(104, max(52, min(view.bounds.width, view.bounds.height) * 0.10))
        let topBand = phoneBandInsets(0...(barHeightEstimate + view.safeAreaInsets.top))
        let bottomBand = phoneBandInsets((view.bounds.height - barHeightEstimate - view.safeAreaInsets.bottom)...view.bounds.height)
        landOrganizerContainerView.accessibilityIdentifier = "phone-local-lands"
        landOrganizerContainerView.backgroundColor = .clear
        landOrganizer?.hideOrganizerBackground()
        opponentLandOrganizer?.hideOrganizerBackground()
        for child in [bottomBarA, bottomBarB].compactMap({ $0 }) { child.view.backgroundColor = .clear }
        for constraint in view.constraints {
            let first = constraint.firstItem as? UIView
            let second = constraint.secondItem as? UIView
            func band(_ container: UIView?) -> (left: CGFloat, right: CGFloat) {
                // The visible gear has its own slot; it must not cover the opponent's graveyard.
                container === top ? (topBand.left, max(topBand.right, view.safeAreaInsets.right + 52)) : bottomBand
            }
            if (first === player1BarContainerView || first === player2BarContainerView) && constraint.firstAttribute == .leading {
                rememberPhoneConstraint(constraint); constraint.constant = band(first).left - (constraint.secondItem is UILayoutGuide ? view.safeAreaInsets.left : 0)
            }
            if (second === player1BarContainerView || second === player2BarContainerView) && constraint.firstAttribute == .trailing {
                rememberPhoneConstraint(constraint); constraint.constant = band(second).right - (constraint.firstItem is UILayoutGuide ? view.safeAreaInsets.right : 0)
            }
        }
        for child in [bottomBarA, bottomBarB].compactMap({ $0 }) { child.refreshForPhoneSession() }
        view.layoutIfNeeded()
        let bottomTargetY = view.bounds.height - bottom.bounds.height
        let bottomHUDTop = view.bounds.height - barHeight
        translate(top, y: view.safeAreaInsets.top - untransformedFrame(top).minY)
        translate(bottom, y: bottomTargetY - untransformedFrame(bottom).minY)
        // Both land rows: same left edge as the battlefield, same gap to their player's bar.
        let landGap = (6 * min(2.4, max(1, view.bounds.height / 375))).rounded()
        let landBase = untransformedFrame(landOrganizerContainerView)
        let ownLandTop = bottomHUDTop - landGap - landHeight
        let ownLandBand = phoneBandInsets(ownLandTop...max(ownLandTop, ownLandTop + landHeight), margin: 32, minimum: 32)
        translate(landOrganizerContainerView, x: ownLandBand.left - landBase.minX, y: ownLandTop - landBase.minY)
        if phoneBarBackgrounds.isEmpty {
            for _ in 0..<2 {
                let background = UIView(); background.backgroundColor = UIColor.black.withAlphaComponent(0.6)
                background.isUserInteractionEnabled = false
                view.insertSubview(background, belowSubview: top)
                phoneBarBackgrounds.append(background)
            }
        }
        phoneBarBackgrounds[0].frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: top.frame.maxY)
        phoneBarBackgrounds[1].frame = CGRect(x: 0, y: bottomHUDTop, width: view.bounds.width, height: view.bounds.height - bottomHUDTop)
        view.bringSubviewToFront(top); view.bringSubviewToFront(bottom)
        layoutPhoneHandOverlay()
        if let shield = phoneHandShield, !shield.isHidden { view.bringSubviewToFront(shield) }
        let opponentLandHeight = min(100, max(44, view.bounds.height * 0.10))
        let landRowTop = top.frame.maxY + landGap
        // Each band of the field keeps clear only of the reserved regions (camera) it crosses.
        let opponentLandBand = phoneBandInsets(landRowTop...(landRowTop + opponentLandHeight), margin: 32, minimum: 32)
        (phoneOpponentLandContainer ?? opponentLandOrganizer?.view)?.frame = CGRect(x: opponentLandBand.left, y: landRowTop, width: view.bounds.width - opponentLandBand.left - opponentLandBand.right - 84, height: opponentLandHeight)
        let topY = landRowTop + opponentLandHeight
        let bottomY = bottomHUDTop - landHeight - landGap
        let rowBand = phoneBandInsets((topY + 4)...max(topY + 4, bottomY - 4), margin: 32, minimum: 32)
        let rowVisible = CGRect(x: rowBand.left, y: topY + 4, width: max(100, view.bounds.width - rowBand.left - rowBand.right), height: max(90, bottomY - topY - 8))
        // Column layout: land rows only occupy the left of their rows. When their lands are narrow,
        // the battlefield can use the full height between the bars beside them (much larger cards on
        // short screens). It stays clear of the compact hand's top edge in the middle.
        let measuredLandMaxX = currentPhoneLandMaxX() ?? (safe.left + 8)
        phoneLandContentMaxX = measuredLandMaxX
        // Tapping a land splits its stack (wider row). Reserve one stack of slack and never shrink
        // within a game, so land taps don't move the battlefield.
        let landStackWidth = max(landHeight, opponentLandHeight) * 480 / 420 * 1.5 + 14 // a tapped (rotated) stack is wider than a card
        // A reservation belongs to the current viewport. Keeping the wide-screen value after
        // resizing can leave no centered column on the smaller display.
        if session.mode == .rules, phoneRulesLandReservationSize != view.bounds.size {
            phoneLandReservation = nil
            phoneRulesLandReservationSize = view.bounds.size
        }
        if phoneLandReservation?.gameID != session.game.id { phoneLandReservation = nil }
        if measuredLandMaxX > (phoneLandReservation?.maxX ?? -.infinity) {
            phoneLandReservation = (session.game.id, measuredLandMaxX + landStackWidth)
        }
        let landMaxX = phoneLandReservation?.maxX ?? measuredLandMaxX
        let handHeight = min(360, max(150, min(view.bounds.width, view.bounds.height) * 0.40))
        // A reserved region (the camera's strip) that only nicks the top or bottom of the column
        // shortens it a little rather than narrowing the whole field.
        let columnRange = phoneTrimmedBand((top.frame.maxY + landGap)...min(bottomHUDTop - landGap, view.bounds.height - handHeight * 0.44 - 4))
        let columnTop = columnRange.lowerBound
        let columnBottom = columnRange.upperBound
        let columnBand = phoneBandInsets(columnRange, margin: 8, minimum: 8)
        let columnX = landMaxX + 12
        if ProcessInfo.processInfo.arguments.contains("--phone-board-log-regions"), let logo = phoneBackgroundLogo {
            // Debug: the reserved regions, readable by a UI test (simctl can't reach the app's log reliably).
            var text = "bounds=\(view.bounds.size) safe=\(view.safeAreaInsets) top=\(top.frame.maxY) hud=\(bottomHUDTop) land=\(landOrganizerContainerView.frame)"
            if #available(iOS 27.1, *) {
                for region in view.reservedRegions(kind: .occlusion, options: .includeInactive) { text += " region=\(region.frame) active=\(region.isActive)" }
            }
            logo.isAccessibilityElement = true
            logo.accessibilityIdentifier = "phone-regions"
            logo.accessibilityLabel = text
        }
        // Symmetric about the screen center, so the column layout's cards stay centered like the row layout's.
        let columnInset = max(columnX, columnBand.left, columnBand.right)
        let columnVisible = CGRect(x: columnInset, y: columnTop, width: max(100, view.bounds.width - 2 * columnInset), height: max(90, columnBottom - columnTop))
        // Arena's back row: with a land row shown, a player's other noncreature permanents sit in it,
        // right-aligned opposite the lands (laid out below); the band in the middle holds creatures
        // (and planeswalkers, sagas and battles at its right end).
        let opponentBackRow = opponentLandOrganizer != nil
        let ownBackRow = showLandOrganizer && landOrganizer != nil
        var descriptors: [(Player.Identifier, PhoneBattlefieldLayout.Row)] = [(session.opponent, .creatures), (session.player, .creatures)]
        if !opponentBackRow { descriptors.insert((session.opponent, .support), at: 0) }
        let ownSupport = PhoneBattlefieldLayout.groups(in: session.game, player: session.player, row: .support).filter {
            !(showLandOrganizer && landOrganizer?.shouldIncludeCard($0.top) == true)
        }
        if !ownSupport.isEmpty && !ownBackRow { descriptors.append((session.player, .support)) }
        for player in [session.opponent, session.player]
        where !PhoneBattlefieldLayout.groups(in: session.game, player: player, row: .side).isEmpty {
            descriptors.append((player, .side))
        }
        // Identical non-land permanents are laid out one by one when that fits without shrinking
        // the cards or paging a row; otherwise (or for 5+ copies) they stack. Lands keep their stacking.
        var splitDuplicates = false
        // Keep the Rules instruction lane reserved even with no prompt. Prompt updates must
        // never move or resize permanents; sandbox keeps its existing spacing.
        let instructionGap: CGFloat = session.mode == .rules
            ? UIFont.preferredFont(forTextStyle: .headline).lineHeight * 2 + 12 : 4
        func groups(for player: Player.Identifier, row: PhoneBattlefieldLayout.Row, ignoringTapped: Bool = false) -> [PhoneCardGroup] {
            func visible(_ groups: [PhoneCardGroup]) -> [PhoneCardGroup] {
                groups.filter {
                    if player == session.opponent && opponentLandOrganizer?.shouldIncludeCard($0.top) == true { return false }
                    return !(showLandOrganizer && player == session.player && landOrganizer?.shouldIncludeCard($0.top) == true)
                }
            }
            let base = visible(PhoneBattlefieldLayout.groups(in: session.game, player: player, row: row, ignoringTapped: ignoringTapped))
            guard splitDuplicates else { return base }
            // Copy counts ignore tapped state, so tapping one copy never flips the decision.
            let largeClusters = Set(visible(PhoneBattlefieldLayout.groups(in: session.game, player: player, row: row, ignoringTapped: true))
                .filter { $0.cards.count >= PhoneBattlefieldLayout.stackThreshold }.flatMap { $0.cards.map(\.uuid) })
            return base.flatMap { group -> [PhoneCardGroup] in
                guard group.cards.count > 1, !group.top.representation.isLand,
                      !largeClusters.contains(group.top.uuid) else { return [group] }
                return group.cards.map { PhoneCardGroup(cards: [$0]) }
            }
        }
        // Reserve the tapped footprint in both states; tapping never changes card scale.
        let rotationSpill = ceil(250 * (cos(CGFloat.pi / 15) + sin(CGFloat.pi / 15) - 1))
        let topSpill = rotationSpill
        /// Groups in a row that is laid out on the field (own lands may live in the land organizer).
        func laidOut(_ player: Player.Identifier, _ row: PhoneBattlefieldLayout.Row) -> Int {
            descriptors.contains { $0.0 == player && $0.1 == row } ? groups(for: player, row: row).count : 0
        }
        // Arena shows each attached card (Equipment, Auras) about a quarter of a card to the left of
        // the card it's on, so its name and some art stay readable. Crowded rows tighten the step.
        var attachmentStep: CGFloat = 130
        func attachmentOffset(_ layer: Int) -> CGPoint {
            CGPoint(x: -attachmentStep * CGFloat(layer + 1), y: -6 - CGFloat(layer) * 6)
        }
        let cellWidth = 520 + rotationSpill * 2
        func extraWidth(_ group: PhoneCardGroup) -> CGFloat {
            max(CGFloat(min(2, group.cards.count - 1)) * 22,
                CGFloat(session.game.attachedCards(to: group.top.uuid).count) * attachmentStep)
        }
        func laneExtra(_ player: Player.Identifier, _ row: PhoneBattlefieldLayout.Row) -> CGFloat {
            guard laidOut(player, row) > 0 else { return 0 }
            return groups(for: player, row: row).reduce(0) { $0 + extraWidth($1) }
        }
        func lanes(for player: Player.Identifier, width: CGFloat) -> (support: PhoneLane, creatures: PhoneLane, side: PhoneLane) {
            phoneLanes(fieldWidth: width, cellWidth: cellWidth,
                support: laidOut(player, .support), creatures: laidOut(player, .creatures), side: laidOut(player, .side),
                supportExtra: laneExtra(player, .support), creatureExtra: laneExtra(player, .creatures), sideExtra: laneExtra(player, .side))
        }
        struct FieldPlan { var bottomSpill: CGFloat; var useColumn: Bool; var visible: CGRect; var extent: CGFloat }
        func plan() -> FieldPlan {
            // A player's lanes (other permanents, creatures, planeswalkers) share one band, so size
            // the cards for the fullest band, not just its longest row.
            let largestRow = Set(descriptors.map(\.0)).map { player in
                descriptors.filter { $0.0 == player }.reduce(0) { $0 + groups(for: player, row: $1.1, ignoringTapped: true).count }
            }.max() ?? 0
            // A row includes its fanned duplicates and attachments. Keep that entire
            // footprint inside its player's half, clear of both land organizers.
            // Fanned duplicates (up to 3 layers at 22/18 per layer) and attachments only reserve space when present.
            let maxLayers = min(3, descriptors.flatMap { groups(for: $0.0, row: $0.1) }.map(\.cards.count).max() ?? 1)
            // Attachments tuck behind their card, each one attachmentStep further to the left (and a bit up).
            let bottomSpill: CGFloat = CGFloat(maxLayers - 1) * 18 + rotationSpill
            func extent(in rect: CGRect) -> CGFloat {
                // Two card footprints share one instruction gap, not one gap per player.
                let availableHeight = session.mode == .rules ? (rect.height - instructionGap) / 2 : rect.height / 2 - instructionGap
                let heightFit = max(24, availableHeight / (1 + (topSpill + bottomSpill) / 500))
                return min(heightFit, PhoneBattlefieldLayout.cardExtent(screenWidth: rect.width, screenHeight: view.bounds.height, groups: largestRow))
            }
            // The column must fit its largest row without paging (cards shrink within it if needed);
            // otherwise the row layout (which pages dense rows) is used.
            func fittedColumnExtent() -> CGFloat {
                var fitted = extent(in: columnVisible)
                let needed = max(500, Set(descriptors.map(\.0)).map { player in
                    descriptors.filter { $0.0 == player }.reduce(CGFloat(0)) { total, descriptor in
                        total + groups(for: player, row: descriptor.1, ignoringTapped: true).reduce(CGFloat(0)) { $0 + cellWidth + extraWidth($1) }
                    }
                }.max() ?? 500) - 20
                // The stack overlays the battlefield (Arena), so it never changes this layout.
                let available = columnVisible.width
                if needed * fitted / 500 > available { fitted = max(24, available * 500 / needed) }
                return fitted
            }
            let centeredColumnFits = session.mode != .rules || view.bounds.width - 2 * columnInset >= 100
            let useColumn = centeredColumnFits && fittedColumnExtent() > extent(in: rowVisible) * 1.05
            return FieldPlan(bottomSpill: bottomSpill, useColumn: useColumn,
                             visible: useColumn ? columnVisible : rowVisible,
                             extent: useColumn ? fittedColumnExtent() : extent(in: rowVisible))
        }
        /// Mirrors the row/lane sizing below: true when no row of this plan would page.
        func fitsWithoutPaging(_ plan: FieldPlan) -> Bool {
            let zoom = plan.extent / 500
            let fieldWidth = max(500, plan.visible.width / zoom)
            return descriptors.allSatisfy { player, row in
                let rowGroups = groups(for: player, row: row)
                let lanes = lanes(for: player, width: fieldWidth)
                let rowWidth = row == .support ? lanes.support.width : row == .side ? lanes.side.width : lanes.creatures.width
                return rowGroups.reduce(CGFloat(0)) { $0 + cellWidth + extraWidth($1) } - 20 <= rowWidth
            }
        }
        func choosePlan() -> FieldPlan {
            splitDuplicates = false
            let stackedPlan = plan()
            splitDuplicates = true
            let splitPlan = plan()
            splitDuplicates = splitPlan.extent >= stackedPlan.extent * 0.82 && fitsWithoutPaging(splitPlan)
            return splitDuplicates ? splitPlan : stackedPlan
        }
        // Use the widest attachment step that doesn't noticeably shrink the cards or make a row
        // page; fall back to a narrow peek when space is tight.
        let tightStep: CGFloat = 34
        attachmentStep = tightStep
        let tightPlan = choosePlan()
        let roomyStep = [130, 100, 70].first { (step: CGFloat) in
            attachmentStep = step
            let candidate = choosePlan()
            return candidate.extent >= tightPlan.extent * 0.92 && (fitsWithoutPaging(candidate) || !fitsWithoutPaging(tightPlan))
        }
        attachmentStep = roomyStep ?? tightStep
        let fieldPlan = choosePlan() // also leaves splitDuplicates set for the chosen step
        let bottomSpill = fieldPlan.bottomSpill
        let visible = fieldPlan.visible
        let extent = fieldPlan.extent
        scrollView.minimumZoomScale = 0.04
        phoneFieldCardExtent = extent
        let desiredScale = extent / 500
        if abs(scrollView.zoomScale - desiredScale) > 0.001 || lastPhoneBounds != view.bounds {
            scrollView.zoomScale = desiredScale
            centerScrollView()
            lastPhoneBounds = view.bounds
        }
        scrollView.isScrollEnabled = false
        scrollView.pinchGestureRecognizer?.isEnabled = false
        selectionGestureRecognizer.isEnabled = false
        let world = board.convert(visible, from: view)
        // Cards on the stack never move the battlefield: the stack draws over it (hide it to uncover).
        let field = CGRect(x: world.minX, y: world.minY, width: max(500, world.width), height: world.height)
        for button in phoneGroupButtons { button.removeFromSuperview() }
        phoneGroupButtons.removeAll()
        for cardView in board.subviews.compactMap({ $0 as? MiniCardView }) {
            cardView.isHidden = true
            cardView.layoutScale = 1
            for gesture in cardView.gestureRecognizers ?? [] where gesture is UIPanGestureRecognizer { gesture.isEnabled = true }
            for interaction in cardView.interactions.compactMap({ $0 as? UIDragInteraction }) { interaction.isEnabled = true }
            // Holding opens the inspector after 0.35 s without moving; any drag wins first.
            for interaction in cardView.interactions.compactMap({ $0 as? UIContextMenuInteraction }) { cardView.removeInteraction(interaction) }
            if !(cardView.gestureRecognizers ?? []).contains(where: { $0.name == "phone-hold" }) {
                let hold = UILongPressGestureRecognizer(target: self, action: #selector(phoneCardHeld(_:)))
                hold.name = "phone-hold"
                hold.minimumPressDuration = 0.35 // a quick hold opens the card's menu
                hold.allowableMovement = 8
                cardView.addGestureRecognizer(hold)
                // The board's own long press (its menu) waits, so holding a card opens the card.
                for boardHold in board.gestureRecognizers ?? [] where boardHold is UILongPressGestureRecognizer {
                    boardHold.require(toFail: hold)
                }
            }
            cardView.usesPlayerPerspective = true
            cardView.isAccessibilityElement = true
            cardView.accessibilityIdentifier = cardView.cardInstance.isPowerToughnessVisible.value ? "phone-creature-card" : "phone-permanent-card"
            cardView.accessibilityLabel = cardView.cardInstance.representation.name ?? "Face-down card"
            cardView.accessibilityTraits = .button
            let attacking = session.game.combat?.attackers.contains(cardView.cardInstance.uuid) == true
            let blocking = session.game.combat?.blockers[cardView.cardInstance.uuid] != nil
            cardView.layer.borderWidth = 0
            cardView.accessibilityValue = attacking ? "Attacking" : blocking ? "Blocking" : cardView.cardInstance.isTapped.value ? "Tapped" : "Untapped"
            cardView.showsRulesSummoningSickness = session.mode == .rules
                && cardView.cardInstance.isPhoneCreature && cardView.cardInstance.isSummoningSick.value
            if cardView.showsRulesSummoningSickness {
                cardView.accessibilityValue = (cardView.accessibilityValue ?? "") + ", Summoning sick"
            }
            // A Room's locked doors, by name.
            if cardView.cardInstance.representation.isRoom, let faces = cardView.cardInstance.representation.card.cardFaces {
                let locked = [Counter.lockedDoorLeft, .lockedDoorRight].enumerated()
                    .filter { cardView.cardInstance.counters.value.contains($0.element) && faces.indices.contains($0.offset) }
                    .map { "\(faces[$0.offset].name ?? "Door") locked" }
                if !locked.isEmpty { cardView.accessibilityValue = ([cardView.accessibilityValue ?? ""] + locked).joined(separator: ", ") }
            }
            cardView.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Inspect", actionHandler: { [weak self, weak cardView] _ in
                guard let self, let cardView else { return false }
                self.focus(on: cardView.cardInstance, view: cardView)
                return true
            })]
        }
        // Each player's creature lane (board units), so blockers can push the rest of the row aside.
        var creatureLanes: [Player.Identifier: ClosedRange<CGFloat>] = [:]
        for descriptor in descriptors {
            let allGroups = groups(for: descriptor.0, row: descriptor.1)
            let key = descriptor.0.rawValue + (descriptor.1 == .creatures ? "creatures" : descriptor.1 == .side ? "side" : "support")
            // Support permanents, creatures and planeswalkers/sagas use separate horizontal lanes in
            // the same player band. Four fractional rows could overlap vertically.
            let lanes = lanes(for: descriptor.0, width: field.width)
            let lane = descriptor.1 == .support ? lanes.support : descriptor.1 == .side ? lanes.side : lanes.creatures
            let rowX = field.minX + lane.minX
            let rowWidth = lane.width
            // A paging row reserves room at its end for the page button, so it never covers a card.
            let pageReserve = 76 / max(0.01, scrollView.zoomScale)
            // A full row first overlaps its cards (as on Arena), down to 45% of a card apart;
            // it pages only beyond that.
            let minSpacing = cellWidth * 0.45
            func overlapCapacity(_ groups: [PhoneCardGroup], width: CGFloat) -> Int {
                var extras: CGFloat = 0
                var count = 0
                for group in groups {
                    extras += extraWidth(group)
                    if cellWidth + CGFloat(count) * minSpacing + extras - 20 > width { break }
                    count += 1
                }
                return max(1, count)
            }
            let pages = overlapCapacity(allGroups, width: rowWidth) < allGroups.count
            let layoutWidth = pages ? max(cellWidth, rowWidth - pageReserve) : rowWidth
            let startIndex = min(phoneRowOffsets[key] ?? 0, max(0, allGroups.count - 1))
            let remaining = Array(allGroups.dropFirst(startIndex))
            let capacity = pages ? overlapCapacity(remaining, width: layoutWidth) : max(1, allGroups.count)
            let pageGroups = Array(remaining.prefix(capacity))
            let fraction: CGFloat = descriptor.0 == session.player ? 0.75 : 0.25
            let rowMidY: CGFloat
            if session.mode == .rules {
                // Keep the same clear lane in screen points at every card scale. Pack each
                // row against it so sparse boards use their available height, without
                // responding to the appearance or disappearance of a prompt.
                let offset = (500 + topSpill + bottomSpill + instructionGap / scrollView.zoomScale) / 2
                rowMidY = field.midY + (descriptor.0 == session.player ? offset : -offset)
            } else {
                rowMidY = field.minY + field.height * fraction
            }
            let centerY = rowMidY - (bottomSpill - topSpill) / 2
            let row = CGRect(x: rowX, y: centerY - 250, width: layoutWidth, height: 500)
            if descriptor.1 == .creatures { creatureLanes[descriptor.0] = rowX...(rowX + layoutWidth) }
            if allGroups.count > capacity {
                let button = UIButton(type: .system)
                button.setTitle("\(startIndex + 1)–\(startIndex + pageGroups.count) ›", for: .normal)
                button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
                button.backgroundColor = .secondarySystemBackground
                button.layer.cornerRadius = 8
                let y = board.convert(CGPoint(x: field.maxX, y: centerY), to: view).y
                let rowEnd = board.convert(CGPoint(x: rowX + layoutWidth, y: centerY), to: view).x
                button.frame = CGRect(x: rowEnd + 6, y: y - 15, width: 64, height: 32)
                button.accessibilityLabel = "Next battlefield cards, \(allGroups.count) groups total"
                button.accessibilityValue = "\(startIndex + 1)–\(startIndex + pageGroups.count)"
                button.addAction(UIAction { [weak self] _ in
                    self?.phoneRowOffsets[key] = startIndex + capacity >= allGroups.count ? 0 : startIndex + capacity
                    self?.view.setNeedsLayout()
                }, for: .touchUpInside)
                view.addSubview(button); phoneGroupButtons.append(button)
            }
            let packed = PhoneBattlefieldLayout.packedRow(extras: pageGroups.map(extraWidth), availableWidth: layoutWidth,
                cellWidth: cellWidth, rotationSpill: rotationSpill)
            // Center a sparse group as a compact visual unit, including only its own attachment fans.
            var start = row.minX
            if descriptor.1 == .creatures {
                let screenMidX = board.convert(CGPoint(x: view.bounds.midX, y: 0), from: view).x
                let centered = screenMidX - packed.width / 2
                start = min(max(centered, row.minX), max(row.minX, row.minX + layoutWidth - packed.width))
            }
            for (column, group) in pageGroups.enumerated() {
                let point = CGPoint(x: start + packed.centers[column], y: row.midY)
                for (layer, card) in group.cards.prefix(3).enumerated().reversed() {
                    if let cardView = cardView(for: card) {
                        cardView.isHidden = false
                        cardView.center = CGPoint(x: point.x - CGFloat(layer) * 22, y: point.y + CGFloat(layer) * 18)
                        board.bringSubviewToFront(cardView)
                    }
                }
                // Arena labels a stack just above its top-left corner (the fanned copies reach left).
                if group.cards.count > 1 {
                    let fan = CGFloat(min(3, group.cards.count) - 1) * 22
                    addPhoneBadge("x\(group.cards.count)", above: CGPoint(x: point.x - 238 - fan, y: point.y - 214), cards: group.cards)
                }
                let attached = session.game.attachedCards(to: group.top.uuid)
                // Each attachment goes under the one before it: the ones peeking out furthest are
                // the furthest back, so every one shows a strip (two Equipment used to stack wrong).
                var above = self.cardView(for: group.top)
                for (layer, attachment) in attached.enumerated() {
                    if let cardView = cardView(for: attachment) {
                        cardView.isHidden = false
                        // Arena tucks equipment and Auras right behind the card: each one peeks
                        // out a little further to the left (and a touch higher).
                        let offset = attachmentOffset(layer)
                        cardView.center = CGPoint(x: point.x + offset.x, y: point.y + offset.y)
                        if let parent = self.cardView(for: group.top) {
                            // Same size as its card, so the smaller artifact/enchantment drawing can't hide behind it.
                            cardView.layoutScale = cardView.layoutScale(matching: parent)
                            board.insertSubview(cardView, belowSubview: above ?? parent)
                            above = cardView
                        }
                    }
                }
            }
        }
        // The back rows: noncreature permanents at land size, right-aligned in each land row's band,
        // overlapping (rather than paging) when there are many.
        for (player, organizer, bandTop, bandHeight) in [
            (session.opponent, opponentBackRow ? opponentLandOrganizer : nil, landRowTop, opponentLandHeight),
            (session.player, ownBackRow ? landOrganizer : nil, ownLandTop, landHeight)
        ] {
            guard let organizer, bandHeight > 20 else { continue }
            let backGroups = groups(for: player, row: .support)
            guard !backGroups.isEmpty else { continue }
            let zoom = max(0.01, scrollView.zoomScale)
            let scale = min(1, bandHeight * 1.1 / max(1, 500 * zoom))
            let band = phoneBandInsets(bandTop...(bandTop + bandHeight), margin: 32, minimum: 32)
            let landsMaxX = organizer.landContentFrames.map { view.convert($0, from: nil).maxX }.max() ?? band.left
            // Clear of the stack's controls (its button, Resolve) where they share the band.
            let bandRect = CGRect(x: 0, y: bandTop, width: view.bounds.width, height: bandHeight)
            let controls = [phoneStackButton, phoneStackResolveButton].compactMap { $0 }
                .filter { !$0.isHidden && $0.alpha > 0.01 && $0.superview != nil }
                .map { view.convert($0.bounds, from: $0) }
                .filter { $0.intersects(bandRect) }
            let rightEdge = min(view.bounds.width - band.right, controls.map(\.minX).min().map { $0 - 8 } ?? .greatestFiniteMagnitude)
            let available = max(0, rightEdge - landsMaxX - 16) / zoom // board units
            let cell = 500 * scale
            let natural = 520 * scale
            let spacing = backGroups.count > 1 ? max(cell * 0.3, min(natural, (available - cell) / CGFloat(backGroups.count - 1))) : natural
            let anchor = board.convert(CGPoint(x: rightEdge, y: bandTop + bandHeight / 2), from: view)
            for (index, group) in backGroups.enumerated() {
                // The first permanent sits at the right end; the rest step left, each on top of the
                // one to its right so its name stays readable.
                let point = CGPoint(x: anchor.x - cell / 2 - CGFloat(index) * spacing, y: anchor.y)
                for (layer, card) in group.cards.prefix(3).enumerated().reversed() {
                    guard let cardView = cardView(for: card) else { continue }
                    cardView.isHidden = false
                    cardView.layoutScale = scale
                    cardView.center = CGPoint(x: point.x - CGFloat(layer) * 22 * scale, y: point.y + CGFloat(layer) * 18 * scale)
                    board.bringSubviewToFront(cardView)
                }
                if group.cards.count > 1 {
                    let fan = CGFloat(min(3, group.cards.count) - 1) * 22 * scale
                    addPhoneBadge("x\(group.cards.count)", above: CGPoint(x: point.x - 238 * scale - fan, y: point.y - 214 * scale), cards: group.cards)
                }
                var above = cardView(for: group.top)
                for (layer, attachment) in session.game.attachedCards(to: group.top.uuid).enumerated() {
                    guard let attachedView = cardView(for: attachment), let parent = cardView(for: group.top) else { continue }
                    attachedView.isHidden = false
                    attachedView.layoutScale = attachedView.layoutScale(matching: parent)
                    let offset = attachmentOffset(layer)
                    attachedView.center = CGPoint(x: point.x + offset.x * scale, y: point.y + offset.y * scale)
                    // Under the previous attachment, so the further-out ones sit further back.
                    board.insertSubview(attachedView, belowSubview: above ?? parent)
                    above = attachedView
                }
            }
        }
        // Blockers leave their row and sit against the attacker they block, on their own side
        // (Arena). Several blockers on one attacker sit side by side.
        if let combat = session.game.combat {
            var blockersPerAttacker: [UUID: Int] = [:]
            for (blockerID, attackerID) in combat.blockers.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
                guard let blocker = session.game.cards[blockerID], let blockerView = cardView(for: blocker),
                      let attacker = session.game.cards[attackerID], let attackerView = cardView(for: attacker),
                      !attackerView.isHidden else { continue }
                let index = blockersPerAttacker[attackerID, default: 0]
                blockersPerAttacker[attackerID] = index + 1
                let towardBlocker: CGFloat = blocker.controllerIdentifier.value == session.player ? 1 : -1
                // A card's height plus room for the attacker's arrow between them.
                let gap = 500 + 40 / max(0.01, scrollView.zoomScale)
                let target = CGPoint(x: attackerView.center.x + CGFloat(index) * 150,
                                     y: attackerView.center.y + towardBlocker * gap)
                let delta = CGPoint(x: target.x - blockerView.center.x, y: target.y - blockerView.center.y)
                blockerView.isHidden = false
                blockerView.center = target
                board.bringSubviewToFront(blockerView)
                // Its attachments come along.
                for attachment in session.game.attachedCards(to: blockerID) {
                    guard let attachedView = cardView(for: attachment) else { continue }
                    attachedView.center = CGPoint(x: attachedView.center.x + delta.x, y: attachedView.center.y + delta.y)
                    board.insertSubview(attachedView, belowSubview: blockerView)
                }
            }
            pushPhoneCreaturesAsideForBlockers(session, combat: combat, groups: { groups(for: $0, row: .creatures) }, lanes: creatureLanes)
        }
        layoutPhoneStack(session, top: top.frame.maxY + 4, bottom: bottomHUDTop - 6)
        // The stack draws over the battlefield; a row's page button must stay reachable above it.
        for button in phoneGroupButtons where button.superview === view { view.bringSubviewToFront(button) }
        updatePhoneAttackIndicators()
        updatePhoneTargetArcs()
        updatePhoneCombatLines()
        view.bringSubviewToFront(bottom)
        positionRulesPrompt()
        for badge in phoneGroupButtons where badge.superview === board { board.bringSubviewToFront(badge) }
        layoutPhoneHandOverlay()
        if let shield = phoneHandShield, !shield.isHidden { view.bringSubviewToFront(shield) }
        if let drag = phoneStackDrag { updatePhoneStackDragHover(drag) }
        phonePreviousStackFrames = Dictionary(uniqueKeysWithValues: session.game.stack.compactMap { item in
            phoneStackCardFrame(item.id).map { (item.id, $0) }
        })
        phonePreviousFieldGeometry = Dictionary(uniqueKeysWithValues: session.game.state.battlefield.value.compactMap { card in
            guard card.controllerIdentifier.value == session.opponent, let geometry = phoneCardGeometry(card) else { return nil }
            return (card.uuid, PhoneFlightGeometry(center: geometry.center, size: geometry.size, angle: geometry.angle))
        })
    }

    /// Blockers jump out of their row to sit against their attacker, which can land them on top of
    /// creatures that stayed home. Those creatures slide aside, away from the blockers, as one block
    /// (keeping their own spacing), and squeeze together if that would run them out of their lane.
    private func pushPhoneCreaturesAsideForBlockers(_ session: PhoneGameSession, combat: PhoneGame.Combat,
                                                    groups: (Player.Identifier) -> [PhoneCardGroup],
                                                    lanes: [Player.Identifier: ClosedRange<CGFloat>]) {
        let gap: CGFloat = 20
        for player in [session.opponent, session.player] {
            let obstacles = combat.blockers.keys.compactMap { id -> CGRect? in
                guard let card = session.game.cards[id], card.controllerIdentifier.value == player,
                      let view = cardView(for: card), !view.isHidden else { return nil }
                return view.frame
            }
            guard !obstacles.isEmpty else { continue }
            // Each creature that stayed home moves with its stacked copies and attachments.
            struct Unit { var views: [UIView]; var frame: CGRect }
            var units: [Unit] = groups(player).compactMap { group in
                guard !group.cards.contains(where: { combat.blockers[$0.uuid] != nil || combat.attackers.contains($0.uuid) }) else { return nil }
                let views = (group.cards.prefix(3) + session.game.attachedCards(to: group.top.uuid))
                    .compactMap { cardView(for: $0) }.filter { !$0.isHidden }
                guard let first = views.first else { return nil }
                return Unit(views: views, frame: views.dropFirst().reduce(first.frame) { $0.union($1.frame) })
            }
            let rowBand = obstacles.reduce(obstacles[0]) { $0.union($1) }
            units.removeAll { !$0.frame.intersects(CGRect(x: -.greatestFiniteMagnitude / 2, y: rowBand.minY,
                                                          width: .greatestFiniteMagnitude, height: rowBand.height)) }
            guard !units.isEmpty else { continue }
            let center = obstacles.map(\.midX).reduce(0, +) / CGFloat(obstacles.count)
            func hits(_ frame: CGRect) -> [CGRect] {
                obstacles.filter { $0.minY < frame.maxY && frame.minY < $0.maxY && $0.minX < frame.maxX + gap && frame.minX - gap < $0.maxX }
            }
            var offsets = [CGFloat](repeating: 0, count: units.count)
            // Rightward: nearest first, each shift carried on to everything beyond it.
            let right = units.indices.filter { units[$0].frame.midX >= center }.sorted { units[$0].frame.minX < units[$1].frame.minX }
            let left = units.indices.filter { units[$0].frame.midX < center }.sorted { units[$0].frame.maxX > units[$1].frame.maxX }
            var shift: CGFloat = 0
            for index in right {
                var frame = units[index].frame.offsetBy(dx: shift, dy: 0)
                while let push = hits(frame).map({ $0.maxX + gap - frame.minX }).max(), push > 0 {
                    shift += push; frame = frame.offsetBy(dx: push, dy: 0)
                }
                offsets[index] = shift
            }
            shift = 0
            for index in left {
                var frame = units[index].frame.offsetBy(dx: shift, dy: 0)
                while let push = hits(frame).map({ frame.maxX + gap - $0.minX }).max(), push > 0 {
                    shift -= push; frame = frame.offsetBy(dx: -push, dy: 0)
                }
                offsets[index] = shift
            }
            // Squeeze a side that ran past its lane back in, nearest card staying put.
            let visible = board.convert(view.bounds, from: view)
            let lane = lanes[player].map { max($0.lowerBound, visible.minX)...min($0.upperBound, visible.maxX) }
                ?? visible.minX...visible.maxX
            func squeeze(_ side: [Int], limit: CGFloat, rightward: Bool) {
                guard let near = side.first, let far = side.last, near != far else {
                    if let only = side.first {
                        let frame = units[only].frame.offsetBy(dx: offsets[only], dy: 0)
                        if rightward, frame.maxX > limit { offsets[only] -= frame.maxX - limit }
                        if !rightward, frame.minX < limit { offsets[only] += limit - frame.minX }
                    }
                    return
                }
                let nearX = units[near].frame.midX + offsets[near], farFrame = units[far].frame.offsetBy(dx: offsets[far], dy: 0)
                let overrun = rightward ? farFrame.maxX - limit : limit - farFrame.minX
                guard overrun > 0 else { return }
                let span = abs(farFrame.midX - nearX)
                let factor = max(0, (span - overrun) / max(1, span))
                for index in side {
                    let x = units[index].frame.midX + offsets[index]
                    offsets[index] = nearX + (x - nearX) * factor - units[index].frame.midX
                }
            }
            squeeze(right, limit: lane.upperBound, rightward: true)
            squeeze(left, limit: lane.lowerBound, rightward: false)
            for (index, unit) in units.enumerated() where offsets[index] != 0 {
                for view in unit.views { view.center.x += offsets[index] }
            }
        }
    }

    // MARK: Stack card drags — targets and zones

    /// Dragging a stack card draws a live arc from it. Released on a permanent, a player or another
    /// spell, it toggles that target; released on a pile or the hand, the card moves there
    /// without resolving. There is no separate targeting mode.
    private struct PhoneStackDragState {
        let itemID: UUID
        let card: CardInstance
        var finger: CGPoint
        var target: PhoneGame.Target?
        var zone: (location: Pile.Location, player: Player.Identifier, view: UIView?)?
    }

    /// The visible stack item under a point in view coordinates (newest first).
    private func phoneStackItem(at point: CGPoint) -> PhoneGame.StackItem? {
        guard let session = phoneMode, let stackView = phoneStackCards?.view, !phoneStackCollapsed, !stackView.isHidden else { return nil }
        let local = stackView.convert(point, from: view)
        let size = PhoneStackCardsView.cardSize(in: stackView.bounds.size)
        for (depth, item) in session.game.stack.suffix(4).reversed().enumerated() {
            let transform = PhoneStackCardsView.cardTransform(in: stackView.bounds.size, depth: depth)
            if CGRect(origin: .zero, size: size).contains(local.applying(transform.inverted())) { return item }
        }
        return nil
    }

    @objc private func phoneStackPanned(_ pan: UIPanGestureRecognizer) {
        guard let session = phoneMode else { return }
        // Rules targets belong to the engine, including objects controlled by the opponent.
        guard session.mode != .rules else { endPhoneStackDrag(); return }
        let point = pan.location(in: view)
        switch pan.state {
        case .began:
            let start = CGPoint(x: point.x - pan.translation(in: view).x, y: point.y - pan.translation(in: view).y)
            guard session.canAct, let item = phoneStackItem(at: start), let card = item.card else {
                pan.isEnabled = false; pan.isEnabled = true // not on a card: cancel
                return
            }
            collapsePhoneHand()
            phoneStackDrag = PhoneStackDragState(itemID: item.id, card: card, finger: point)
            PhoneHaptics.pickUp()
            fallthrough
        case .changed:
            guard var drag = phoneStackDrag else { return }
            drag.finger = point
            let zone = phoneStackDropZone(at: point, card: drag.card)
            drag.zone = zone
            let previous = drag.target
            drag.target = zone == nil ? phoneStackDropTarget(at: point, excluding: drag) : nil
            // A small tick as the arrow reaches something it could target.
            if let target = drag.target, target != previous { PhoneHaptics.hover() }
            phoneStackDrag = drag
            updatePhoneStackDragHover(drag)
            updatePhoneTargetArcs()
        case .ended:
            guard let drag = phoneStackDrag else { return }
            endPhoneStackDrag()
            if let zone = drag.zone {
                if zone.location == .library { promptPhoneLibraryDrop(drag.card, session: session) }
                else { session.send(.moveToPlayer(drag.card.uuid, zone.location, zone.player, bottom: false)) }
                PhoneHaptics.drop()
            } else if let target = drag.target,
                      let item = session.game.stack.first(where: { $0.id == drag.itemID }), item.player == session.player {
                var targets = item.targets ?? []
                if let index = targets.firstIndex(of: target) { targets.remove(at: index) } else { targets.append(target) }
                session.send(.setStackTargets(item.id, targets))
                PhoneHaptics.drop()
            }
        default:
            endPhoneStackDrag()
        }
    }

    private func endPhoneStackDrag() {
        phoneStackDrag = nil
        phoneZoneHoverKey = nil
        hidePhoneDragHover()
        // The arc that followed the finger fades away rather than vanishing.
        if let arc = phoneStackDragArc {
            phoneStackDragArc = nil
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.1 : 0.25, delay: 0, options: [.beginFromCurrentState]) {
                arc.alpha = 0
            } completion: { _ in arc.removeFromSuperview() }
        }
        updatePhoneTargetArcs()
    }

    /// The live arc from the dragged stack card to the finger. None while the finger is over a
    /// zone: moving a card to the hand or a pile isn't targeting.
    private func updatePhoneStackDragArc() {
        guard let drag = phoneStackDrag, drag.zone == nil, let source = phoneStackAnchor(drag.itemID) else {
            phoneStackDragArc?.isHidden = true
            return
        }
        let arc = phoneStackDragArc ?? {
            let arc = PhoneTargetArcsView()
            arc.isOpaque = false; arc.backgroundColor = .clear
            arc.isUserInteractionEnabled = false
            arc.accessibilityElementsHidden = true
            phoneStackDragArc = arc
            return arc
        }()
        arc.frame = view.bounds
        if arc.superview !== view {
            if let stack = phoneStackContainer, stack.superview === view { view.insertSubview(arc, belowSubview: stack) }
            else { view.addSubview(arc) }
        }
        arc.isHidden = false
        arc.connections = [.init(source: source, destination: drag.finger, local: true, targetsStack: false)]
    }

    /// Room a horizontal band of the board (a bar, the stack, the hand) leaves at its left and
    /// right edges. On iOS 27.1 it avoids only the reserved regions that cross the band — on a
    /// closed iPhone Duo, the outer camera and its bar strip — plus `margin` and room for the
    /// rounded screen corners, instead of the whole side of the safe area. Earlier: the safe area.
    func phoneBandInsets(_ band: ClosedRange<CGFloat>, margin: CGFloat = 24, minimum: CGFloat = 24) -> (left: CGFloat, right: CGFloat) {
        let safe = view.safeAreaInsets
        guard #available(iOS 27.1, *) else { return (safe.left + margin, safe.right + margin) }
        let regions = view.reservedRegions(kind: .occlusion)
        // No regions reported (a device or state without any): keep to the safe area.
        guard !regions.isEmpty else { return (safe.left + margin, safe.right + margin) }
        var left: CGFloat = 0, right: CGFloat = 0
        for region in regions where region.frame.maxY > band.lowerBound && region.frame.minY < band.upperBound {
            if region.frame.midX < view.bounds.midX { left = max(left, region.frame.maxX) }
            else { right = max(right, view.bounds.maxX - region.frame.minX) }
        }
        // `minimum` (24 pt for the bars) clears the rounded corners along the top and bottom edges.
        return (max(minimum, left + margin), max(minimum, right + margin))
    }

    /// A vertical band shortened past any reserved region that only intrudes a little (under a
    /// quarter of its height) at its top or bottom edge, e.g. the closed iPhone Duo's camera strip
    /// reaching just below the top bar.
    func phoneTrimmedBand(_ band: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> {
        var top = band.lowerBound, bottom = band.upperBound
        guard #available(iOS 27.1, *) else { return band }
        let height = bottom - top
        for region in view.reservedRegions(kind: .occlusion) where region.frame.maxY > top && region.frame.minY < bottom {
            if region.frame.minY <= top, region.frame.maxY - top < height * 0.25 { top = region.frame.maxY + 4 }
            else if region.frame.maxY >= bottom, bottom - region.frame.minY < height * 0.25 { bottom = region.frame.minY - 4 }
        }
        return top...max(top, bottom)
    }

    /// Either player's graveyard, exile or library pile under a point.
    private func phonePileZone(at point: CGPoint, underHand: Bool = false) -> (location: Pile.Location, player: Player.Identifier, view: UIView)? {
        // Piles the open hand's cards cover aren't drop targets there (but holding a card over one
        // still spring-loads it: `underHand`).
        if !underHand, localPhoneBar?.handViewController?.phonePresentation.isExpanded == true, phoneHandDropRegionContains(point) { return nil }
        for bar in [bottomBarA, bottomBarB].compactMap({ $0 }) {
            let piles: [(UIView?, Pile.Location)] = [(bar.graveyardPileView, .graveyard), (bar.exilePileView, .exile), (bar.libraryPileView, .library)]
            for (pile, location) in piles {
                guard let pile, !pile.isHidden, pile.window != nil,
                      pile.point(inside: pile.convert(point, from: view), with: nil) else { continue }
                return (location, bar.player.identifier, pile)
            }
        }
        return nil
    }

    /// A pile (either player's graveyard, exile or library) or your hand under the finger.
    private func phoneStackDropZone(at point: CGPoint, card: CardInstance) -> (location: Pile.Location, player: Player.Identifier, view: UIView?)? {
        guard let session = phoneMode else { return nil }
        if let pile = phonePileZone(at: point) { return (pile.location, pile.player, pile.view) }
        // Your life total sits in the HUD band over the hand: there it's a target, not the hand.
        if phoneTargetFrame(.player(session.player))?.contains(point) == true { return nil }
        if phoneHandDropRegionContains(point) { return (.hand, session.player, nil) }
        return nil
    }

    /// A player, a battlefield card or land, or another visible spell under the finger.
    private func phoneStackDropTarget(at point: CGPoint, excluding drag: PhoneStackDragState) -> PhoneGame.Target? {
        guard let session = phoneMode else { return nil }
        for player in [session.player, session.opponent] {
            if phoneTargetFrame(.player(player))?.contains(point) == true { return .player(player) }
        }
        if let item = phoneStackItem(at: point) {
            return item.id == drag.itemID ? nil : item.card.map { .card($0.uuid) }
        }
        if let card = phoneAttachmentTarget(at: point, excluding: [drag.card.uuid]) { return .card(card.uuid) }
        return nil
    }

    /// Outlines what releasing would do: the target (around the drawn mini card itself) or the zone.
    private func updatePhoneStackDragHover(_ drag: PhoneStackDragState) {
        guard let session = phoneMode else { return }
        if let zone = drag.zone {
            showPhoneZoneHover(zone.location, zoneView: zone.view)
        } else if let target = drag.target,
                  let item = session.game.stack.first(where: { $0.id == drag.itemID }), item.player == session.player {
            phoneZoneHoverKey = nil
            let text = (item.targets ?? []).contains(target) ? "Remove Target" : "Target"
            if case .card(let id) = target, let card = session.game.cards[id], let mini = cardView(for: card), !mini.isHidden {
                let scale = max(0.01, scrollView.zoomScale * hypot(mini.transform.a, mini.transform.b))
                showPhoneDragHover(text, in: phoneOutlineHost(mini), frame: phoneDrawnCardRect(in: mini).insetBy(dx: -2 / scale, dy: -2 / scale), scale: scale)
            } else {
                showPhoneDragHover(text, in: view, frame: phoneBoardTargetFrame(target)?.insetBy(dx: -3, dy: -3), scale: 1)
            }
        } else {
            phoneZoneHoverKey = nil
            hidePhoneDragHover()
        }
    }

    /// "Move to Graveyard/Exile/Library/Hand": the zone a dragged card would go to, outlined.
    /// Shared by stack, hand, pile and battlefield drags.
    private func showPhoneZoneHover(_ location: Pile.Location, zoneView: UIView?) {
        let names: [Pile.Location: String] = [.graveyard: "Graveyard", .exile: "Exile", .library: "Library", .hand: "Hand"]
        let frame: CGRect? = zoneView.map { view.convert($0.bounds, from: $0) } ?? localPhoneBar?.handContainerView.map { container in
            view.convert(container.phoneContentFrame ?? container.bounds, from: container)
        }
        // A tick each time the card comes over a zone it would move to.
        let key = "\(location.rawValue)-\(zoneView.map { ObjectIdentifier($0).hashValue } ?? 0)"
        if key != phoneZoneHoverKey { phoneZoneHoverKey = key; PhoneHaptics.hover() }
        showPhoneDragHover("Move to \(names[location] ?? "Zone")", in: view, frame: frame?.insetBy(dx: -2, dy: -2), scale: 1, outlined: false)
    }

    /// The zone outline for a hand, pile or battlefield card dragged to `point` (nil: none).
    private func updatePhoneZoneHover(at point: CGPoint, includesHand: Bool) {
        updatePhoneSpringLoad(at: point)
        if let pile = phonePileZone(at: point), let card = phoneSpringDraggedCard,
           phonePile(pile.location, of: pile.player, holds: card) {
            // Back over the pile it came off: letting go puts it back, so no "Move to".
            phoneZoneHoverKey = nil
            hidePhoneDragHover()
        } else if let pile = phonePileZone(at: point) {
            showPhoneZoneHover(pile.location, zoneView: pile.view)
        } else if includesHand, phoneHandDropRegionContains(point),
                  phoneTargetFrame(.player(phoneMode?.player ?? .a))?.contains(point) != true {
            showPhoneZoneHover(.hand, zoneView: nil)
        } else {
            phoneZoneHoverKey = nil // left every zone: entering one again ticks
            hidePhoneDragHover()
        }
    }

    /// Whether `card` is in that pile now (a card dragged off it and dropped back stays put).
    private func phonePile(_ location: Pile.Location, of player: Player.Identifier, holds card: CardInstance) -> Bool {
        guard let session = phoneMode else { return false }
        let pile = location == .library ? session.game.library(player) : session.game.state[player: player][location]
        return pile.cards.value.contains(card)
    }

    // MARK: Move to Stack drop area

    /// Shows the "Move to Stack" area along the right edge while a dragged card is near it, lit
    /// while the card is over it (nil: hides it).
    private func updatePhoneStackCastZone(at point: CGPoint?) {
        // Rules mode: XMage decides where a card goes (spells to the stack, permanents to the
        // battlefield), so there's no separate drop area for "Move to Stack".
        if phoneMode?.mode == .rules { if phoneStackCastArmed { phoneStackCastArmed = false }; return }
        let band = phoneStackCastBand
        let near = point.map { !band.isEmpty && $0.x >= band.minX - 70 && $0.y >= band.minY - 30 && $0.y <= band.maxY + 30 } ?? false
        let armed = point.map { near && $0.x >= band.minX && $0.y >= band.minY - 20 && $0.y <= band.maxY + 20 } ?? false
        guard near else {
            phoneStackCastArmed = false
            if let zone = phoneStackCastZone, zone.alpha > 0 {
                UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { zone.alpha = 0 }
            }
            return
        }
        let zone = phoneStackCastZone ?? {
            let zone = UIView()
            zone.isUserInteractionEnabled = false
            zone.layer.cornerRadius = 14
            zone.layer.cornerCurve = .continuous
            zone.layer.borderWidth = 2
            zone.layer.shadowColor = UIColor.systemCyan.cgColor
            zone.layer.shadowOffset = .zero
            zone.layer.shadowRadius = 10
            zone.accessibilityIdentifier = "phone-stack-cast-zone"
            let icon = UIImageView(image: UIImage(systemName: "square.stack.3d.up.fill"))
            icon.tintColor = .white
            icon.contentMode = .scaleAspectFit
            icon.tag = 1
            let label = UILabel()
            label.text = "Move to Stack"
            label.font = UIFont(name: "Beleren2016-Bold", size: 14) ?? .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .white
            label.textAlignment = .center
            label.numberOfLines = 2
            label.tag = 2
            zone.addSubview(icon); zone.addSubview(label)
            zone.alpha = 0
            view.addSubview(zone)
            phoneStackCastZone = zone
            return zone
        }()
        zone.frame = band
        if let icon = zone.viewWithTag(1) { icon.frame = CGRect(x: band.width / 2 - 16, y: band.height / 2 - 34, width: 32, height: 32) }
        if let label = zone.viewWithTag(2) { label.frame = CGRect(x: 6, y: band.height / 2 + 4, width: band.width - 12, height: 40) }
        if armed != phoneStackCastArmed {
            phoneStackCastArmed = armed
            if armed { PhoneHaptics.hover() }
        }
        // Dark blue at rest, brighter with a glow while letting go would cast it.
        zone.backgroundColor = UIColor(red: 0.0, green: 0.25, blue: 0.5, alpha: armed ? 0.75 : 0.45)
        zone.layer.borderColor = (armed ? UIColor.systemCyan : UIColor.systemCyan.withAlphaComponent(0.5)).cgColor
        zone.layer.shadowOpacity = armed ? 0.9 : 0
        zone.accessibilityValue = armed ? "Armed" : nil
        if armed { hidePhoneDragHover() }
        if zone.alpha < 1 {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { zone.alpha = 1 }
        }
        view.bringSubviewToFront(zone)
        if let preview = phoneDragPreview, preview.superview === view { view.bringSubviewToFront(preview) }
    }

    // MARK: Spring-loaded piles

    /// The card being dragged (from the hand, a pile or the battlefield).
    private var phoneSpringDraggedCard: CardInstance? { phoneHandDrag?.card ?? phoneDraggedCard }

    /// Holding a dragged card over a graveyard, exile or library opens its browser, so the card
    /// can be dropped at an exact spot; moving over the fan opens a gap where it would go.
    private func updatePhoneSpringLoad(at point: CGPoint) {
        phoneSpringPoint = point
        guard let card = phoneSpringDraggedCard else { return }
        phoneSpringCard = card
        // An open browser (spring-loaded or not) takes the card: a gap opens where it would go.
        if let browser = phoneBrowser {
            if phoneBrowserDropZone != nil { browser.externalDragMoved(to: point) }
            return
        }
        guard let pile = phonePileZone(at: point, underHand: true) else {
            phoneSpringPile = nil; phoneSpringTimer?.invalidate(); phoneSpringTimer = nil
            return
        }
        if let current = phoneSpringPile, current.location == pile.location, current.player == pile.player { return }
        phoneSpringPile = (pile.location, pile.player, CACurrentMediaTime())
        phoneSpringTimer?.invalidate()
        // Under the open hand (where a quick drop reorders the hand), it takes a slightly longer hold.
        let covered = phonePileZone(at: point) == nil
        phoneSpringTimer = Timer.scheduledTimer(withTimeInterval: covered ? 0.9 : 0.65, repeats: false) { [weak self] _ in self?.springOpenPhonePile() }
    }

    private func springOpenPhonePile() {
        guard let session = phoneMode, let spring = phoneSpringPile, let card = phoneSpringDraggedCard,
              let pile = phonePileZone(at: phoneSpringPoint, underHand: true), pile.location == spring.location, pile.player == spring.player else { return }
        let source = spring.location == .library ? session.game.library(spring.player) : session.game.state[player: spring.player][spring.location]
        // Already in that pile (dragged off it), or nothing there to browse: nothing to place.
        guard !source.cards.value.contains(card), !source.cards.value.isEmpty else { return }
        PhoneHaptics.pickUp()
        showPhoneZoneBrowser(.pile(spring.location, spring.player))
        phoneSpringOpened = true
        hidePhoneDragHover()
        phoneZoneHoverKey = nil
        // The dragged card stays above the browser.
        if let preview = phoneDragPreview { view.bringSubviewToFront(preview) }
        phoneBrowser?.externalDragMoved(to: phoneSpringPoint)
    }

    /// The zone an open browser shows, which a card dragged onto its fan goes into.
    private var phoneBrowserDropZone: (location: Pile.Location, owner: Player.Identifier)? {
        guard let session = phoneMode, let mode = phoneBrowserMode else { return nil }
        switch mode {
        case .pile(let location, let owner): return (location, owner)
        case .search, .look: return (.library, session.player)
        case .revealed, .openingHand, .rulesChoice: return nil
        }
    }

    /// A drag ended over an open browser: a card released over its fan goes into that spot of the
    /// zone. Returns false when it wasn't released over the fan (a spring-loaded browser closes).
    /// `faceUp`: the card was showing its face while dragged, so it stays face up in the browser.
    private func finishPhoneSpringLoad(_ card: CardInstance, at point: CGPoint, faceUp: Bool) -> Bool {
        phoneSpringTimer?.invalidate(); phoneSpringTimer = nil
        phoneSpringPile = nil
        phoneSpringCard = nil
        let springLoaded = phoneSpringOpened
        phoneSpringOpened = false
        guard let session = phoneMode, let browser = phoneBrowser, let zone = phoneBrowserDropZone else { return false }
        let location = zone.location, owner = zone.owner
        guard let index = browser.externalDrop(at: point) else {
            if springLoaded { closePhoneZoneBrowser() }
            return false
        }
        // In Look at, a card you put in stays visible to you.
        if case .look = phoneBrowserMode {
            if phoneBrowserLookedAt.isEmpty { phoneBrowserLookedAt = Set(phoneBrowserIDs.filter { !phoneBrowserFaceDown.contains($0) }) }
            phoneBrowserLookedAt.insert(card.uuid)
        }
        if faceUp { phoneBrowserSeen.insert(card.uuid) }
        var display = browser.cards.filter { $0.uuid != card.uuid }
        display.insert(card, at: min(index, display.count))
        let topFirst = display.reversed().map(\.uuid)
        session.send(.moveToPlayer(card.uuid, location, owner, bottom: false))
        if owner == session.player { session.send(.arrangePile(location, topFirst)) }
        else if location == .library, topFirst.last == card.uuid {
            // Dropped at the far left of a library: its bottom.
            session.send(.moveToPlayer(card.uuid, location, owner, bottom: true))
        }
        PhoneHaptics.drop()
        // A spring-loaded browser stays open briefly so the card can be seen in place; one the
        // player opened stays open.
        if springLoaded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                if self?.phoneBrowser === browser { self?.closePhoneZoneBrowser() }
            }
        }
        return true
    }

    /// Released over an open browser's dimmed area but not into it: the card goes back rather
    /// than landing on the battlefield (or stack) hidden behind the browser.
    private func phoneDropBlockedByBrowser(at point: CGPoint) -> Bool {
        guard let browser = phoneBrowser, browser.covers(point) else { return false }
        return phonePileZone(at: point) == nil && !browser.isOverBattlefieldZone(point)
    }

    /// A drag was cancelled or ended elsewhere: forget the spring-loaded pile.
    private func cancelPhoneSpringLoad() {
        phoneBrowser?.cancelExternalDrag()
        phoneSpringTimer?.invalidate(); phoneSpringTimer = nil
        phoneSpringPile = nil
        phoneSpringCard = nil
        if phoneSpringOpened {
            phoneSpringOpened = false
            closePhoneZoneBrowser()
        }
    }

    /// `outlined: false` (zones) shows just the label over the zone; targets get the cyan outline too.
    private func showPhoneDragHover(_ text: String, in container: UIView, frame: CGRect?, scale: CGFloat, outlined: Bool = true) {
        let outline = phoneStackDragOutline ?? {
            let outline = UIView()
            outline.isUserInteractionEnabled = false
            outline.backgroundColor = UIColor.systemCyan.withAlphaComponent(0.12)
            outline.layer.borderColor = UIColor.systemCyan.cgColor
            outline.layer.shadowColor = UIColor.systemCyan.cgColor
            outline.layer.shadowOpacity = 1
            outline.layer.shadowOffset = .zero
            outline.accessibilityIdentifier = "phone-stack-drag-outline"
            phoneStackDragOutline = outline
            return outline
        }()
        let label = phoneStackDragLabel ?? {
            let label = UILabel()
            label.font = UIFont(name: "Beleren2016-Bold", size: 14) ?? .systemFont(ofSize: 13, weight: .semibold)
            // White on a deep blue keeps it readable over any card art (contrast ~6:1).
            label.textColor = .white
            label.backgroundColor = UIColor(red: 0.0, green: 0.36, blue: 0.68, alpha: 0.95)
            label.layer.borderColor = UIColor.systemCyan.cgColor
            label.layer.borderWidth = 1
            label.textAlignment = .center
            label.layer.cornerRadius = 6
            label.layer.masksToBounds = true
            label.isUserInteractionEnabled = false
            label.accessibilityIdentifier = "phone-stack-drag-intent"
            phoneStackDragLabel = label
            return label
        }()
        outline.transform = .identity
        place(outline, in: container, frame: frame, scale: scale)
        // The (invisible) box still positions the label over the zone.
        outline.backgroundColor = outlined ? UIColor.systemCyan.withAlphaComponent(0.12) : .clear
        outline.layer.shadowOpacity = outlined ? 1 : 0
        if !outlined { outline.layer.borderWidth = 0 }
        guard outline.superview != nil else { label.removeFromSuperview(); return }
        label.text = text
        let size = (text as NSString).size(withAttributes: [.font: label.font!])
        label.bounds.size = CGSize(width: size.width + 14, height: size.height + 6)
        label.center = phoneDragLabelCenter(for: label, finger: phoneStackDrag?.finger ?? phoneLastDragPoint)
        if label.superview !== view { view.addSubview(label) }
        view.bringSubviewToFront(label)
        if let preview = phoneDragPreview, preview.superview === view { view.bringSubviewToFront(preview) }
    }

    /// Hides the outline. The zone the card is over is still remembered (it's redrawn on each
    /// move), so its haptic plays once on entering, not on every move.
    /// Drop labels ("Attach", "Block", "Target", "Move to …") sit just above the dragged card, so
    /// neither the card nor the finger covers them; with no card (a stack card's arrow), above the finger.
    private func phoneDragLabelCenter(for label: UIView, finger: CGPoint?) -> CGPoint {
        let half = label.bounds.height / 2
        let anchor: CGPoint
        if let preview = phoneDragPreview, preview.superview === view {
            let box = preview.layer.presentation()?.frame ?? preview.frame
            anchor = CGPoint(x: box.midX, y: box.minY - half - 8)
        } else {
            let point = finger ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            anchor = CGPoint(x: point.x, y: point.y - 44 - half)
        }
        let halfWidth = label.bounds.width / 2
        return CGPoint(x: min(max(anchor.x, halfWidth + 8), view.bounds.width - halfWidth - 8),
                       y: max(anchor.y, view.safeAreaInsets.top + half + 4))
    }

    private func hidePhoneDragHover() {
        phoneStackDragOutline?.removeFromSuperview()
        phoneStackDragLabel?.removeFromSuperview()
    }

    private func place(_ outline: UIView, in container: UIView, frame: CGRect?, scale: CGFloat) {
        guard let frame else { outline.removeFromSuperview(); return }
        if outline.superview !== container { container.addSubview(outline) }
        container.bringSubviewToFront(outline)
        outline.frame = frame
        outline.layer.borderWidth = 3 / scale
        outline.layer.shadowRadius = 9 / scale
        outline.layer.cornerRadius = min(10 / scale, frame.width * 0.05)
    }

    private func phoneStackCardFrame(_ itemID: UUID) -> CGRect? {
        guard let session = phoneMode, let stackView = phoneStackCards?.view,
              let index = session.game.stack.firstIndex(where: { $0.id == itemID }) else { return nil }
        let depth = session.game.stack.count - 1 - index
        guard depth < 4 else { return nil }
        let transform = PhoneStackCardsView.cardTransform(in: stackView.bounds.size, depth: depth)
        let rect = CGRect(origin: .zero, size: PhoneStackCardsView.cardSize(in: stackView.bounds.size)).applying(transform)
        return stackView.convert(rect, to: view)
    }

    private func phoneStackAnchor(_ itemID: UUID) -> CGPoint? {
        guard let session = phoneMode, let stackView = phoneStackCards?.view, !stackView.isHidden,
              let index = session.game.stack.firstIndex(where: { $0.id == itemID }) else { return nil }
        let depth = session.game.stack.count - 1 - index
        guard depth < 4 else { return nil }
        var point = stackView.convert(PhoneStackCardsView.connectionPoint(in: stackView.bounds.size, depth: depth), to: view)
        // Mid-slide, follow where the cards are drawn rather than where they're headed.
        if let shown = stackView.layer.presentation()?.affineTransform() { point.x += shown.tx - stackView.transform.tx }
        return point
    }

    private func phoneBoardTargetFrame(_ target: PhoneGame.Target) -> CGRect? {
        if case .card(let id) = target, let item = phoneMode?.game.stack.first(where: { $0.card?.uuid == id }) {
            return phoneStackCardFrame(item.id)
        }
        return phoneTargetFrame(target)
    }

    private func phoneTargetFrame(_ target: PhoneGame.Target) -> CGRect? {
        guard let session = phoneMode else { return nil }
        switch target {
        case .player(let player):
            if let life = phoneLifeHosts[player]?.view { return life.convert(life.bounds, to: view) }
            guard let bar = [bottomBarA, bottomBarB].compactMap({ $0 }).first(where: { $0.player.identifier == player }),
                  let life = bar.children.first(where: { $0 is LifeTrackerViewController })?.view else { return nil }
            return life.convert(life.bounds, to: view)
        case .card(let id):
            if let item = session.game.stack.first(where: { $0.card?.uuid == id }) {
                guard let point = phoneStackAnchor(item.id) else { return phoneStackButton?.frame }
                return CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
            }
            guard let card = session.game.publicCard(id) else { return nil }
            if let geometry = phoneCardGeometry(card) {
                return CGRect(x: geometry.center.x - geometry.size.width / 2, y: geometry.center.y - geometry.size.height / 2,
                              width: geometry.size.width, height: geometry.size.height)
            }
            // Offscreen battlefield pages have no visible endpoint. Public piles use their HUD preview.
            for bar in [bottomBarA, bottomBarB].compactMap({ $0 }) {
                let player = bar.player.identifier
                let piles: [(Pile, UIView?)] = [(session.game.graveyard(player), bar.graveyardPileView),
                                               (session.game.state[player: player].exile, bar.exilePileView)]
                for (pile, preview) in piles where pile.cards.value.contains(card) {
                    if let preview { return preview.convert(preview.bounds, to: view) }
                }
            }
            return nil
        }
    }

    private func updatePhoneTargetArcs() {
        guard let session = phoneMode, let stackView = phoneStackCards?.view else { return }
        if phoneTargetArcs == nil {
            let arcs = PhoneTargetArcsView()
            arcs.isOpaque = false; arcs.backgroundColor = .clear
            arcs.isUserInteractionEnabled = false
            arcs.accessibilityElementsHidden = true
            phoneTargetArcs = arcs
        }
        guard let arcs = phoneTargetArcs else { return }
        arcs.frame = view.bounds
        if arcs.superview !== view || view.subviews.firstIndex(of: arcs) != (view.subviews.firstIndex(of: phoneStackContainer ?? stackView) ?? 0) - 1 {
            view.insertSubview(arcs, belowSubview: phoneStackContainer ?? stackView)
        }
        var connections: [PhoneTargetArcsView.Connection] = []
        // Drawn while the stack is collapsed too, from the edges of the cards left showing.
        for item in session.game.stack {
            guard let source = phoneStackAnchor(item.id) else { continue }
            // Arena distinguishes an ability's origin (white, towards the stack) from its targets.
            // The mapping exists only in Rules mode and only for sources visible to this seat.
            if let id = session.rulesAdapter?.abilitySources[item.id], let frame = phoneTargetFrame(.card(id)),
               frame.width > 0, frame.height > 0 {
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let dx = source.x - center.x, dy = source.y - center.y
                let scale = min(frame.width / 2 / max(0.001, abs(dx)), frame.height / 2 / max(0.001, abs(dy)))
                let start = CGPoint(x: center.x + dx * min(1, scale), y: center.y + dy * min(1, scale))
                connections.append(.init(source: start, destination: source, local: item.player == session.player,
                                         targetsStack: false, isAbilitySource: true))
            }
            let targets = item.targets ?? []
            for target in targets {
                guard let frame = phoneTargetFrame(target), frame.width > 0, frame.height > 0 else { continue }
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let dx = source.x - center.x, dy = source.y - center.y
                let scale = min(frame.width / 2 / max(0.001, abs(dx)), frame.height / 2 / max(0.001, abs(dy)))
                let end = CGPoint(x: center.x + dx * min(1, scale), y: center.y + dy * min(1, scale))
                let targetsStack: Bool
                if case .card(let id) = target { targetsStack = session.game.stack.contains { $0.card?.uuid == id } }
                else { targetsStack = false }
                connections.append(.init(source: source, destination: end, local: item.player == session.player, targetsStack: targetsStack))
            }
        }
        updatePhoneStackDragArc()
        arcs.connections = connections
        arcs.isHidden = connections.isEmpty
        let sourceCount = connections.filter(\.isAbilitySource).count
        let targetCount = connections.count - sourceCount
        phoneStackButton?.accessibilityValue = "\(targetCount) target connections"
            + (sourceCount > 0 ? ", \(sourceCount) ability source connections" : "")
    }

    private func makePhoneStackView(_ session: PhoneGameSession, concealing: UUID? = nil) -> PhoneStackCardsView {
        PhoneStackCardsView(items: session.game.stack,
                            inspect: { [weak self] card in
                                guard let self else { return }
                                if self.phoneStackCollapsed { self.setPhoneStackCollapsed(false, animated: true) }
                                else { self.focus(on: card, view: nil) }
                            },
                            browse: { [weak self] in self?.showPhoneAbilityOptions() },
                            concealedCardID: concealing ?? phoneConcealedArrival ?? (phoneMenuStandIn?.isStack == true ? phoneMenuStandIn?.card : nil),
                            chosenX: session.mode == .rules ? session.rulesAdapter?.stackChosenX ?? [:] : [:])
    }

    private func layoutPhoneStack(_ session: PhoneGameSession, top: CGFloat, bottom: CGFloat) {
        if phoneStackCards == nil {
            let host = UIHostingController(rootView: makePhoneStackView(session))
            if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
            host.view.backgroundColor = .clear
            let container = PhoneTouchFilterView()
            container.accepts = { [weak self, weak container] point in
                guard let self, let container else { return false }
                return self.phoneStackItem(at: self.view.convert(point, from: container)) != nil
            }
            view.addSubview(container)
            phoneStackContainer = container
            addChild(host); container.addSubview(host.view); host.didMove(toParent: self)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(phoneStackPanned(_:)))
            pan.maximumNumberOfTouches = 1
            host.view.addGestureRecognizer(pan)
            phoneStackCards = host
        }
        if phoneStackButton == nil {
            let button = UIButton(type: .system)
            // One control: chevron and count, expanding or collapsing the stack.
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.setPhoneStackCollapsed(!self.phoneStackCollapsed, animated: true)
            }, for: .touchUpInside)
            button.setPreferredSymbolConfiguration(.init(pointSize: 18, weight: .semibold), forImageIn: .normal)
            button.tintColor = .white
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor.black.withAlphaComponent(0.75)
            button.layer.cornerRadius = 18
            button.accessibilityIdentifier = "phone-stack"
            view.addSubview(button); phoneStackButton = button
        }
        if phoneStackResolveButton == nil {
            let button = UIButton(type: .system)
            button.setTitle("Resolve", for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor(red: 0.86, green: 0.31, blue: 0.07, alpha: 1)
            button.layer.cornerRadius = 20
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.systemOrange.withAlphaComponent(0.9).cgColor
            button.layer.shadowColor = UIColor.systemOrange.cgColor
            button.layer.shadowOpacity = 0.4
            button.layer.shadowRadius = 6
            button.accessibilityIdentifier = "phone-stack-resolve"
            button.addAction(UIAction { [weak self] _ in
                guard let session = self?.phoneMode, let item = session.game.stack.last else { return }
                session.send(.resolve(item.id))
            }, for: .touchUpInside)
            view.addSubview(button); phoneStackResolveButton = button
        }
        let empty = session.game.stack.isEmpty
        if empty { phoneStackCollapsed = false }
        let right = view.bounds.width - phoneBandInsets(top...bottom, margin: 8, minimum: 8).right
        let availableHeight = max(120, bottom - top)
        let width = min(300, view.bounds.width * 0.30, (availableHeight - 46) * 0.88 * 63 / 88 * 1.62)
        // Leave the card title below the count/chevron. Older cards pivot upward from
        // their bottom edge so the fan stays clear of Resolve on short landscape phones.
        let frame = CGRect(x: right - width, y: top + 20, width: width, height: availableHeight - 46)
        phoneStackCastBand = CGRect(x: right - min(140, view.bounds.width * 0.16), y: top + 8,
                                    width: min(140, view.bounds.width * 0.16), height: max(60, bottom - top - 16))
        phoneStackCards?.view.transform = .identity
        phoneStackCards?.view.frame = frame
        let cardWidth = PhoneStackCardsView.cardSize(in: frame.size).width
        let shift = phoneStackCollapsed ? cardWidth + 5 - 18 : 0
        // Keep the fan rendered beyond the edge: each older card leaves a narrow exposed strip.
        phoneStackCards?.view.transform = CGAffineTransform(translationX: shift, y: 0)
        phoneStackCards?.view.isHidden = empty
        phoneStackCards?.view.accessibilityElementsHidden = phoneStackCollapsed
        phoneStackCards?.view.isUserInteractionEnabled = !phoneStackCollapsed
        if phoneStackPeekButton == nil {
            let button = UIButton(type: .custom)
            button.accessibilityIdentifier = "phone-stack-peek"
            button.accessibilityLabel = "Show Stack cards"
            button.addAction(UIAction { [weak self] _ in self?.setPhoneStackCollapsed(false, animated: true) }, for: .touchUpInside)
            view.addSubview(button); phoneStackPeekButton = button
        }
        // Only the exposed sliver plus a minimum touch target: a wider strip would steal presses
        // from battlefield cards sitting under the tucked-away stack.
        let peekWidth = min(width, 44)
        phoneStackPeekButton?.frame = CGRect(x: right - peekWidth, y: frame.minY + 16, width: view.bounds.width - right + peekWidth, height: frame.height - 24)
        phoneStackPeekButton?.isHidden = empty || !phoneStackCollapsed
        let font = UIFont(name: "Beleren2016-Bold", size: min(24, max(17, view.bounds.height * 0.045))) ?? .boldSystemFont(ofSize: 17)
        phoneStackButton?.titleLabel?.font = font
        // Just a stack icon: filled while the stack is shown, outlined while it's tucked away.
        phoneStackButton?.setImage(UIImage(systemName: phoneStackCollapsed ? "square.stack.3d.up" : "square.stack.3d.up.fill"), for: .normal)
        phoneStackButton?.setTitle(nil, for: .normal)
        phoneStackButton?.accessibilityLabel = "Stack · \(session.game.stack.count)"
        phoneStackButton?.accessibilityHint = phoneStackCollapsed ? "Shows the stack" : "Hides the stack"
        phoneStackButton?.frame = CGRect(x: right - 52, y: top, width: 52, height: 36)
        phoneStackButton?.isHidden = empty
        phoneStackResolveButton?.titleLabel?.font = font
        phoneStackResolveButton?.frame = CGRect(x: right - max(100, cardWidth), y: bottom - 40,
                                                width: max(100, cardWidth), height: 40)
        // A Rules game resolves with the main button ("Resolve"), as on Arena: no second one here,
        // and nothing on the battlefield moves aside for it.
        phoneStackResolveButton?.isHidden = empty || phoneStackCollapsed || session.mode == .rules
        phoneStackResolveButton?.isEnabled = session.canAct
        phoneStackContainer?.frame = view.bounds
        for control in [phoneStackContainer, phoneStackPeekButton, phoneStackButton, phoneStackResolveButton].compactMap({ $0 }) {
            view.bringSubviewToFront(control)
        }
    }

    private func setPhoneStackCollapsed(_ collapsed: Bool, animated: Bool) {
        guard phoneStackCollapsed != collapsed else { return }
        let stack = phoneStackCards?.view
        let current = stack?.layer.presentation()?.affineTransform() ?? stack?.transform ?? .identity
        phoneStackSlideAnimator?.stopAnimation(true)
        phoneStackArcLink?.invalidate()
        phoneStackCollapsed = collapsed
        view.setNeedsLayout(); view.layoutIfNeeded()
        guard let stack else { return }
        let destination = stack.transform
        if animated && !UIAccessibility.isReduceMotionEnabled {
            stack.transform = current
            let animator = UIViewPropertyAnimator(duration: 0.25, curve: .easeInOut) { stack.transform = destination }
            // Arcs stay drawn, following the cards frame by frame as they slide.
            let link = CADisplayLink(target: PhoneDisplayLinkTarget { [weak self] in self?.updatePhoneTargetArcs() },
                                     selector: #selector(PhoneDisplayLinkTarget.tick))
            phoneStackArcLink?.invalidate()
            link.add(to: .main, forMode: .common)
            phoneStackArcLink = link
            animator.addCompletion { [weak self] _ in
                link.invalidate()
                self?.updatePhoneTargetArcs()
            }
            phoneStackSlideAnimator = animator
            animator.startAnimation()
        }
    }

    private func phoneEdgePoint(_ rect: CGRect, toward point: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = point.x - center.x, dy = point.y - center.y
        let scale = min(rect.width / 2 / max(0.001, abs(dx)), rect.height / 2 / max(0.001, abs(dy)))
        return CGPoint(x: center.x + dx * min(1, scale), y: center.y + dy * min(1, scale))
    }

    private func updatePhoneCombatLines() {
        guard let session = phoneMode else { return }
        if phoneCombatLines == nil {
            let lines = PhoneCombatLinesView()
            lines.isOpaque = false; lines.backgroundColor = .clear; lines.isUserInteractionEnabled = false
            lines.accessibilityElementsHidden = true
            phoneCombatLines = lines
        }
        guard let lines = phoneCombatLines else { return }
        lines.frame = view.bounds
        lines.color = session.mode == .rules ? PhoneCombatLinesView.arenaYellow : PhoneCombatLinesView.gold
        if let anchor = phoneTargetArcs ?? phoneStackCards?.view,
           lines.superview !== view || view.subviews.firstIndex(of: lines) != (view.subviews.firstIndex(of: anchor) ?? 0) - 1 {
            view.insertSubview(lines, belowSubview: anchor)
        }
        var assignments: [PhoneCombatLinesView.Line] = []
        func append(_ blocker: UUID, _ attacker: UUID, preview: Bool) {
            guard let from = phoneTargetFrame(.card(blocker)), let to = phoneTargetFrame(.card(attacker)) else { return }
            // From the middle of the blocker's facing edge to the middle of the attacker's.
            let up = to.midY < from.midY
            assignments.append(.init(from: CGPoint(x: from.midX, y: up ? from.minY : from.maxY),
                                     to: CGPoint(x: to.midX, y: up ? to.maxY : to.minY), preview: preview, blocker: from))
        }
        for (blocker, attacker) in session.game.combat?.blockers ?? [:] { append(blocker, attacker, preview: false) }
        if let preview = phoneCombatPreview,
           session.game.combat?.attackers.contains(preview.attacker) == true,
           canPhoneBlock(with: preview.blocker, session: session) {
            append(preview.blocker, preview.attacker, preview: true)
        } else { phoneCombatPreview = nil }
        lines.lines = assignments
        lines.isHidden = assignments.isEmpty
        localPhoneBar?.untapButton.accessibilityValue = "\(session.game.combat?.blockers.count ?? 0) blocking assignments"
    }

    private func clearPhoneResolutionAnimations() {
        for (id, host) in phoneResolutionHosts {
            if let card = phoneMode?.game.cards[id] { cardView(for: card)?.alpha = 1 }
            host.view.layer.removeAllAnimations()
            host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent()
        }
        phoneResolutionHosts.removeAll()
        if phoneConcealedArrival != nil, let session = phoneMode {
            phoneConcealedArrival = nil
            phoneStackCards?.rootView = makePhoneStackView(session)
        }
    }

    // MARK: Opponent zone moves

    /// The opponent's cards that changed zones since the last refresh, with where each was drawn.
    /// Hidden zones are whole-zone spots (the hand is never tracked per card), so nothing about
    /// the order of the opponent's hand or library is revealed.
    private func phoneOpponentMoves(_ session: PhoneGameSession) -> [PhoneOpponentMove] {
        let opponent = session.opponent
        var current: [UUID: (card: CardInstance, zone: PhoneOpponentZone)] = [:]
        for location in [Pile.Location.library, .hand, .graveyard, .exile, .command, .sideboard] {
            for card in session.game.pile(location, player: opponent).cards.value { current[card.uuid] = (card, .pile(location)) }
        }
        for card in session.game.state.battlefield.value where card.controllerIdentifier.value == opponent {
            current[card.uuid] = (card, .battlefield)
        }
        for item in session.game.stack where item.player == opponent {
            if let card = item.card { current[card.uuid] = (card, .stack) }
        }
        let previous = phoneOpponentZones
        phoneOpponentZones = (session.game.id, current.mapValues(\.zone))
        guard let previous, previous.gameID == session.game.id, !UIAccessibility.isReduceMotionEnabled,
              UIApplication.shared.applicationState == .active else { return [] }
        var moves: [PhoneOpponentMove] = []
        for (id, now) in current {
            guard let before = previous.zones[id], before != now.zone else { continue }
            // Resolving spells already fly from the stack to the battlefield, graveyard or exile.
            if before == .stack, [PhoneOpponentZone.battlefield, .pile(.graveyard), .pile(.exile)].contains(now.zone) { continue }
            let start: PhoneFlightGeometry?
            switch before {
            case .battlefield: start = phonePreviousFieldGeometry[id]
            case .stack:
                start = phonePreviousStack.first(where: { $0.card?.uuid == id })
                    .flatMap { phonePreviousStackFrames[$0.id] }.map(PhoneFlightGeometry.init(rect:))
            case .pile(let location): start = phonePileFlightGeometry(location, player: opponent)
            }
            guard let start else { continue }
            moves.append(PhoneOpponentMove(card: now.card, from: before, to: now.zone, start: start))
        }
        // A whole hand shuffled away or drawn is a quick burst, not a long parade.
        return Array(moves.prefix(8))
    }

    /// A card-sized spot on the opponent's HUD for a whole zone.
    private func phonePileFlightGeometry(_ location: Pile.Location, player: Player.Identifier) -> PhoneFlightGeometry? {
        guard let bar = [bottomBarA, bottomBarB].compactMap({ $0 }).first(where: { $0.player.identifier == player }) else { return nil }
        let zone: UIView?
        switch location {
        case .hand, .command: zone = bar.handContainerView
        case .library: zone = bar.libraryPileView
        case .graveyard: zone = bar.graveyardPileView
        case .exile: zone = bar.exilePileView
        case .sideboard: zone = nil
        }
        guard let zone, zone.window != nil, !zone.isHidden else { return nil }
        var shown: UIView = zone
        if let pile = zone as? HUDCardPileView, let top = pile.topCardImageView, !top.isHidden, top.bounds.height > 0 { shown = top }
        let frame = shown.convert(shown.bounds, to: view)
        guard frame.width > 0, frame.height > 0 else { return nil }
        let height = min(frame.height, 110)
        return PhoneFlightGeometry(center: CGPoint(x: frame.midX, y: frame.midY), size: CGSize(width: height * 63 / 88, height: height), angle: 0)
    }

    private func flyPhoneOpponentCard(_ move: PhoneOpponentMove, delay: TimeInterval) {
        guard let session = phoneMode else { return }
        let card = move.card
        let end: PhoneFlightGeometry
        var mini: MiniCardView?
        switch move.to {
        case .battlefield:
            guard let geometry = phoneCardGeometry(card) else { return }
            end = PhoneFlightGeometry(center: geometry.center, size: geometry.size, angle: geometry.angle)
            mini = cardView(for: card)
        case .stack:
            guard let item = session.game.stack.first(where: { $0.card?.uuid == card.uuid }),
                  let frame = phoneStackCardFrame(item.id) else { return }
            end = PhoneFlightGeometry(rect: frame)
        case .pile(let location):
            guard let geometry = phonePileFlightGeometry(location, player: session.opponent) else { return }
            end = geometry
        }
        if let old = phoneResolutionHosts.removeValue(forKey: card.uuid) {
            old.view.layer.removeAllAnimations()
            old.willMove(toParent: nil); old.view.removeFromSuperview(); old.removeFromParent()
        }
        // Between two hidden zones (drawn, put back, shuffled in) only the back shows, as does
        // anything face down.
        let faceUp = !(move.from.isHidden && move.to.isHidden) && !card.representation.isFaceDown
        let face: MTGCard.Face?
        if case .alternateFace(_, let selected) = card.representation { face = selected } else { face = nil }
        let host = UIHostingController(rootView: HandCardView(isVisible: faceUp, card: card.representation.card, face: face))
        if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.accessibilityElementsHidden = true
        host.view.accessibilityIdentifier = "phone-opponent-move-preview"
        // Laid out once at its landing size and scaled, so the SwiftUI content never re-lays out mid-flight.
        host.view.bounds = CGRect(origin: .zero, size: end.size)
        host.view.layer.cornerRadius = max(4, end.size.width * 0.045)
        host.view.layer.cornerCurve = .continuous
        host.view.clipsToBounds = true
        host.view.center = move.start.center
        let startScale = move.start.size.height / max(1, end.size.height)
        host.view.transform = CGAffineTransform(rotationAngle: move.start.angle).scaledBy(x: startScale, y: startScale)
        addChild(host); view.addSubview(host.view); host.didMove(toParent: self)
        phoneResolutionHosts[card.uuid] = host
        mini?.alpha = 0
        if move.to == .stack, phoneMenuStandIn == nil {
            phoneConcealedArrival = card.uuid
            phoneStackCards?.rootView = makePhoneStackView(session)
        }
        let flight = 0.42
        UIView.animate(withDuration: flight, delay: delay, options: [.curveEaseInOut]) {
            host.view.center = end.center
            host.view.transform = CGAffineTransform(rotationAngle: end.angle)
        }
        // Lands, then hands over to the real card (or the pile it joined).
        UIView.animate(withDuration: 0.14, delay: delay + flight - 0.06, options: [.curveEaseIn]) {
            host.view.alpha = 0
            mini?.alpha = 1
        } completion: { [weak self, weak host] _ in
            mini?.alpha = 1
            guard let self else { return }
            if self.phoneConcealedArrival == card.uuid {
                self.phoneConcealedArrival = nil
                if let session = self.phoneMode { self.phoneStackCards?.rootView = self.makePhoneStackView(session) }
            }
            guard let host, self.phoneResolutionHosts[card.uuid] === host else { return }
            self.phoneResolutionHosts[card.uuid] = nil
            host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent()
        }
    }

    private func animatePhoneStackDeparture(_ item: PhoneGame.StackItem, from frame: CGRect) {
        guard let session = phoneMode, let card = item.card else { return }
        let destination: CGRect
        let mini: MiniCardView?
        if session.game.state.battlefield.value.contains(card), let geometry = phoneCardGeometry(card) {
            destination = CGRect(x: geometry.center.x - geometry.size.width / 2, y: geometry.center.y - geometry.size.height / 2,
                                 width: geometry.size.width, height: geometry.size.height)
            mini = cardView(for: card)
        } else if session.game.graveyard(card.ownerIdentifier).cards.value.contains(card)
                    || session.game.state[player: card.ownerIdentifier].exile.cards.value.contains(card),
                  let target = phoneTargetFrame(.card(card.uuid)) {
            destination = target; mini = nil
        } else { return }
        let face: MTGCard.Face?
        if case .alternateFace(_, let selected) = card.representation { face = selected } else { face = nil }
        let host = UIHostingController(rootView: HandCardView(isVisible: true, card: card.representation.card, face: face))
        if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
        host.view.backgroundColor = .clear; host.view.isUserInteractionEnabled = false
        host.view.accessibilityIdentifier = "phone-resolution-preview"
        host.view.frame = frame
        host.view.layer.cornerRadius = max(4, frame.width * 0.045); host.view.clipsToBounds = true
        addChild(host); view.addSubview(host.view); host.didMove(toParent: self)
        phoneResolutionHosts[card.uuid] = host
        mini?.alpha = 0
        let reduced = UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: reduced ? 0.15 : 0.42, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            if !reduced { host.view.frame = destination }
            host.view.alpha = 0.05
            mini?.alpha = 1
        } completion: { [weak self, weak host] _ in
            guard let self, let host, self.phoneResolutionHosts[card.uuid] === host else { return }
            self.phoneResolutionHosts[card.uuid] = nil
            mini?.alpha = 1
            host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent()
        }
    }

    private func updatePhoneAttackIndicators() {
        guard let session = phoneMode else { return }
        updatePhoneCombatGlows(session)
        updatePhoneInspectionOutline(session)
        let attacking = session.game.combat?.attackers ?? []
        let visible = board.subviews.compactMap { $0 as? MiniCardView }.filter {
            !$0.isHidden && attacking.contains($0.cardInstance.uuid)
        }
        let visibleIDs = Set(visible.map { $0.cardInstance.uuid })
        for id in Array(phoneAttackIndicators.keys) where !visibleIDs.contains(id) {
            phoneAttackIndicators.removeValue(forKey: id)?.removeFromSuperview()
        }
        for card in visible {
            let indicator: PhoneAttackIndicatorView
            if let existing = phoneAttackIndicators[card.cardInstance.uuid] { indicator = existing }
            else {
                indicator = PhoneAttackIndicatorView()
                indicator.accessibilityIdentifier = "phone-attack-indicator"
                view.addSubview(indicator)
                phoneAttackIndicators[card.cardInstance.uuid] = indicator
            }
            let frame = view.convert(card.bounds, from: card)
            let local = card.cardInstance.controllerIdentifier.value == session.player
            // Rules mode (Arena): a blocked attacker's chevron turns the blockers' yellow.
            let blocked = session.mode == .rules
                && session.game.combat?.blockers.values.contains(card.cardInstance.uuid) == true
            indicator.glowColor = blocked ? PhoneCombatLinesView.arenaYellow : .systemOrange
            indicator.accessibilityValue = blocked ? "Blocked" : "Attacking"
            indicator.bounds.size = CGSize(width: min(72, max(28, frame.width * 0.6)), height: 20)
            indicator.center = CGPoint(x: frame.midX, y: local ? frame.minY - 13 : frame.maxY + 13)
            indicator.transform = local ? .identity : CGAffineTransform(rotationAngle: .pi)
            // Above the battlefield but under the stack, which draws over the field.
            if let stack = phoneStackContainer, stack.superview === view { view.insertSubview(indicator, belowSubview: stack) }
            else { view.bringSubviewToFront(indicator) }
        }
    }

    /// The hand's playable rim colour (`PhoneHandPlayRim`), for Rules-mode permanents.
    private static let phonePlayableGlow = UIColor(red: 0.2, green: 0.62, blue: 1, alpha: 1)

    private func updatePhoneCombatGlows(_ session: PhoneGameSession) {
        let combat = session.game.combat
        var wanted: [UUID: UIColor] = [:]
        // Rules mode: permanents the engine says can act now, or legal targets while choosing them,
        // glow blue (Arena); combat overrides.
        if session.mode == .rules {
            let field = session.game.state.battlefield.value
            for id in session.game.rulesPlayable ?? [] {
                if let card = session.game.cards[id], field.contains(card) { wanted[id] = Self.phonePlayableGlow }
            }
        }
        for id in combat?.attackers ?? [] { wanted[id] = .systemOrange }
        // Blockers glow gold, matching their golden lines (Arena).
        let blockColor = session.mode == .rules ? PhoneCombatLinesView.arenaYellow : PhoneCombatLinesView.gold
        for id in combat?.blockers.keys.map({ $0 }) ?? [] { wanted[id] = blockColor }
        for (id, glow) in phoneCombatGlows where wanted[id] == nil {
            glow.removeFromSuperview()
            phoneCombatGlows[id] = nil
        }
        for (id, color) in wanted {
            guard let card = session.game.cards[id], let mini = cardView(for: card), !mini.isHidden,
                  mini.cardView != nil else {
                phoneCombatGlows.removeValue(forKey: id)?.removeFromSuperview()
                continue
            }
            let glow = phoneCombatGlows[id] ?? {
                let glow = UIView()
                glow.isUserInteractionEnabled = false
                glow.layer.borderWidth = 2.5
                glow.layer.shadowOpacity = 1
                glow.layer.shadowRadius = 9
                glow.layer.shadowOffset = .zero
                glow.accessibilityIdentifier = "phone-combat-glow"
                phoneCombatGlows[id] = glow
                return glow
            }()
            glow.layer.borderColor = color.cgColor
            glow.layer.shadowColor = color.cgColor
            glow.accessibilityValue = color == .systemOrange ? "Attacking" : color == Self.phonePlayableGlow ? "Playable" : "Blocking"
            // The outline belongs to the card's unrotated coordinate space. It inherits the
            // card's in-flight tap/flying transform rather than jumping to the model angle.
            let host = phoneOutlineHost(mini)
            if glow.superview !== host { host.addSubview(glow) }
            host.bringSubviewToFront(glow)
            let scale = max(0.01, scrollView.zoomScale * hypot(mini.transform.a, mini.transform.b))
            glow.frame = phoneDrawnCardRect(in: mini).insetBy(dx: -1.5 / scale, dy: -1.5 / scale)
            glow.layer.borderWidth = 2.5 / scale
            glow.layer.shadowRadius = 9 / scale
            glow.layer.cornerRadius = min(10 / scale, glow.bounds.width * 0.05)
        }
    }

    /// Arena's "opponent is looking at this": a thin white outline on the battlefield card whose
    /// menu the opponent has open, or on the small top card of the pile they're viewing.
    private func updatePhoneInspectionOutline(_ session: PhoneGameSession) {
        let outline = phoneInspectionOutline ?? {
            let outline = UIView()
            outline.isUserInteractionEnabled = false
            outline.backgroundColor = .clear
            outline.layer.borderColor = UIColor.white.cgColor
            outline.layer.cornerCurve = .continuous
            outline.accessibilityIdentifier = "phone-opponent-inspecting"
            phoneInspectionOutline = outline
            return outline
        }()
        var inspectedLand: UUID?
        defer { [landOrganizer, opponentLandOrganizer].forEach { $0?.setInspectedCard(inspectedLand) } }
        switch session.game.inspecting?[session.opponent.rawValue] {
        case .card(let id)?:
            if let card = session.game.cards[id], let mini = cardView(for: card), !mini.isHidden {
                let scale = max(0.01, scrollView.zoomScale * hypot(mini.transform.a, mini.transform.b))
                let host = phoneOutlineHost(mini)
                if outline.superview !== host { host.addSubview(outline) }
                host.bringSubviewToFront(outline)
                let cardRect = phoneDrawnCardRect(in: mini)
                outline.frame = cardRect.insetBy(dx: -1.5 / scale, dy: -1.5 / scale)
                outline.layer.borderWidth = 1.5 / scale
                // The card's own corner (MTGCardView: 4.55% of its width), widened by the gap.
                outline.layer.cornerRadius = cardRect.width * 0.0455 + 1.5 / scale
                inspectedLand = nil
            } else {
                // Lands in the land rows draw the outline on the card itself, so it hugs that
                // card (not its whole stack) and tilts with it when tapped.
                outline.removeFromSuperview()
                inspectedLand = [landOrganizer, opponentLandOrganizer].contains { $0?.containsLand(id) == true } ? id : nil
            }
        case .pile(let player, let location)?:
            let bar = [bottomBarA, bottomBarB].compactMap { $0 }.first { $0.player.identifier == player }
            let pileView: HUDCardPileView? = {
                switch location {
                case .graveyard: return bar?.graveyardPileView
                case .exile: return bar?.exilePileView
                case .library: return bar?.libraryPileView
                default: return nil
                }
            }()
            guard let pileView else { outline.removeFromSuperview(); return }
            let card: UIView = pileView.topCardImageView.isHidden ? pileView : pileView.topCardImageView
            if outline.superview !== pileView { pileView.addSubview(outline) }
            pileView.bringSubviewToFront(outline)
            outline.frame = pileView.convert(card.bounds, from: card).insetBy(dx: -1.5, dy: -1.5)
            outline.layer.borderWidth = 1.5
            outline.layer.cornerRadius = min(4, outline.bounds.width * 0.08)
        case nil:
            outline.removeFromSuperview()
        }
    }

    private func wigglePhoneLibrary(_ pile: UIView) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let wiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        wiggle.values = [0, -0.16, 0.14, -0.1, 0.06, 0]
        wiggle.keyTimes = [0, 0.18, 0.4, 0.6, 0.8, 1]
        wiggle.duration = 0.4
        wiggle.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeOut), count: 5)
        let target = (pile as? HUDCardPileView)?.topCardImageView ?? pile
        target.layer.add(wiggle, forKey: "shuffle")
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
    }

    /// Cards revealed to this phone's player (searching, "reveal the top card…") open the card
    /// browser in Revealed Cards mode; closing it stops revealing them to this player.
    private func updatePhoneRevealedCards(_ session: PhoneGameSession) {
        let me = session.player
        let revealed = OrderedSet(session.game.cards.values
            .filter { $0.revealedPlayers.value.contains(me) }
            .sorted { ($0.representation.name ?? "") < ($1.representation.name ?? "") })
        phoneRevealedToMe.accept(revealed)
        let ids = Set(revealed.map(\.uuid))
        guard !ids.isEmpty else { phoneRevealedShownIDs = []; return }
        // Only newly revealed cards bring the sheet up (again).
        guard !ids.subtracting(phoneRevealedShownIDs).isEmpty else {
            phoneRevealedShownIDs.formUnion(ids)
            return
        }
        phoneRevealedShownIDs = ids
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phoneBrowserMode == nil else { self?.refreshPhoneBrowser(session); return }
            self.showPhoneZoneBrowser(.revealed)
        }
    }

    // MARK: Zone browser (search, scry, surveil, revealed)

    enum PhoneBrowserMode: Equatable { case search, look(Int), revealed, pile(Pile.Location, Player.Identifier), openingHand, rulesChoice }

    /// After Start Game, this phone's player sees their new seven in the browser, with who goes
    /// first, until they keep (Mulligan deals another seven into it).
    /// Rules mode: Arena's wording for the opening hand ("Keep 6", "Return 2 Cards"…).
    private func configureRulesOpening(_ browser: PhoneZoneBrowserView, session: PhoneGameSession) {
        guard session.mode == .rules, let opening = session.game.opening else { return }
        let first = opening.firstPlayer == session.player ? "You Go First" : "Opponent Goes First"
        if let returning = opening.returning {
            browser.configureOpening(title: "Return \(returning) Card\(returning == 1 ? "" : "s")",
                                     subtitle: "Drag \(returning) card\(returning == 1 ? "" : "s") to the bottom of your library.",
                                     done: nil, secondary: nil, secondaryCaption: nil, returnZone: true)
        } else {
            let returns = opening.mulliganReturns ?? 1
            browser.configureOpening(title: first, subtitle: nil,
                                     done: "Keep \(opening.keepCount ?? 7)", secondary: "Mulligan",
                                     secondaryCaption: "You will return \(returns) card\(returns == 1 ? "" : "s") to the bottom of your library.",
                                     returnZone: false)
        }
    }

    /// A Rules game's card choice (a library search, choosing among revealed cards…) in the same
    /// fanned browser as Phone Play's searches: tap a card to choose it; cards that can't be chosen
    /// are dimmed; an optional choice is finished with the main button's Done.
    private func updatePhoneRulesChoice(_ session: PhoneGameSession) {
        guard session.mode == .rules else { return }
        guard let choice = session.game.rulesChoice else {
            if phoneBrowserMode == .rulesChoice { closePhoneZoneBrowser() }
            return
        }
        if phoneBrowserMode != .rulesChoice {
            guard phoneBrowserMode != .openingHand else { return }
            showPhoneZoneBrowser(.rulesChoice)
        }
        guard let browser = phoneBrowser, phoneBrowserMode == .rulesChoice else { return }
        browser.configureChoice(title: choice.title, subtitle: choice.subtitle,
                                confirm: choice.kind == .choose,
                                confirmEnabled: session.rulesAdapter?.canConfirmBrowserChoice == true,
                                // Arena's scry / surveil: the chosen cards on the left, the rest on top.
                                split: choice.kind == .scry ? ("Bottom", "Top") : choice.kind == .surveil ? ("Graveyard", "Top") : nil)
        browser.onDone = { session.rulesAdapter.map { adapter in Task { await adapter.confirmBrowserChoice() } } }
        browser.setChoiceStates(selectable: choice.selectable, selected: choice.selected,
                                identifiers: Dictionary(uniqueKeysWithValues: choice.cardIDs.map { ($0, "rules-prompt-card-\($0.uuidString.lowercased())") }))
        browser.onTapCard = { card in session.rulesAdapter.map { adapter in Task { await adapter.chooseInBrowser(card.uuid) } } }
    }

    private func updatePhoneOpeningHand(_ session: PhoneGameSession) {
        if let browser = phoneBrowser, phoneBrowserMode == .openingHand { configureRulesOpening(browser, session: session) }
        guard let opening = session.game.opening, opening.deciding.contains(session.player.rawValue),
              phoneKeptOpeningID != opening.id else {
            if phoneBrowserMode == .openingHand { closePhoneZoneBrowser() }
            return
        }
        guard phoneBrowserMode != .openingHand else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phoneBrowserMode != .openingHand, self.phoneMode?.game.opening?.id == opening.id else { return }
            self.showPhoneZoneBrowser(.openingHand)
        }
    }

    /// The cards a browser mode shows, top of the library first.
    private func phoneBrowserSource(_ mode: PhoneBrowserMode, session: PhoneGameSession) -> [CardInstance] {
        let library = Array(session.game.library(session.player).cards.value.contents.reversed())
        switch mode {
        case .search: return library
        case .look: return library // the rest of the library follows, face down
        case .revealed: return phoneRevealedToMe.value.contents
        case .openingHand: return session.game.state[player: session.player].hand.cards.value.contents
        case .rulesChoice:
            // In the order the player arranged them (scry / surveil), else XMage's.
            guard let adapter = session.rulesAdapter else { return [] }
            let order = adapter.arrangedLibraryOrder
            func rank(_ index: Int, _ card: CardInstance) -> Int { order.firstIndex(of: card.uuid) ?? order.count + index }
            return adapter.choiceCards.enumerated().sorted { rank($0.offset, $0.element) < rank($1.offset, $1.element) }.map(\.element)
        case .pile(let location, let owner):
            let pile = location == .library ? session.game.library(owner) : session.game.state[player: owner][location]
            return Array(pile.cards.value.contents.reversed())
        }
    }

    /// Height of the bottom bar (your HUD and collapsed hand) the browser leaves uncovered.
    /// The browser darkens everything down to the bottom row (your HUD); the hand stays above it.
    private var phoneBrowserUncoveredBottom: CGFloat {
        let top = phoneBarBackgrounds.count > 1 ? phoneBarBackgrounds[1].frame.minY : view.bounds.maxY - 60
        return max(0, view.bounds.maxY - top)
    }
    private var phoneBrowserTopInset: CGFloat { phoneBarBackgrounds.first?.frame.maxY ?? 0 }
    /// The collapsed hand peeks above the HUD; the fan stays clear of it.
    private var phoneBrowserContentBottomInset: CGFloat {
        var top = view.bounds.maxY - phoneBrowserUncoveredBottom
        // The opening hand hides your hand (those cards aren't drawn until you keep).
        if phoneBrowserMode != .openingHand, let container = localPhoneBar?.handContainerView, container.superview === view {
            var content = view.convert(container.phoneContentFrame ?? container.bounds, from: container)
            // Always the collapsed hand's height: the expanded hand opens over the browser
            // rather than squeezing its cards.
            if localPhoneBar?.handViewController?.phonePresentation.isExpanded == true {
                // (see layoutPhoneHandOverlay: the collapsed frame starts 48% down the expanded one)
                content = CGRect(x: content.minX, y: content.minY + content.height * 0.48, width: content.width, height: content.height * 0.7)
            }
            top = min(top, content.minY)
        }
        return max(0, view.bounds.maxY - top)
    }

    /// The browser sits over the board but under your hand (so the hand stays visible and usable),
    /// except while a lifted card travels over it.
    private func orderPhoneBrowser() {
        guard let browser = phoneBrowser else { return }
        view.bringSubviewToFront(browser)
        if !browser.isLifting, let hand = localPhoneBar?.handContainerView, hand.superview === view { view.bringSubviewToFront(hand) }
        // A card being dragged always stays on top of everything.
        if let preview = phoneDragPreview, preview.superview === view { view.bringSubviewToFront(preview) }
    }

    /// Arena's card browser over the darkened board (your bottom bar stays usable): search your
    /// library, look at its top cards (scry, surveil…), or see revealed cards. Cards drag to reorder,
    /// onto your hand, library, graveyard or exile, or onto the Battlefield zone at the top.
    func showPhoneZoneBrowser(_ mode: PhoneBrowserMode) {
        guard let session = phoneMode else { return }
        // The opening hand stays up until it's kept.
        if phoneBrowserMode == .openingHand, mode != .openingHand { return }
        closePhoneZoneBrowser()
        collapsePhoneHand()
        // A sheet that led here (the library, a reveal) closes for the browser.
        if presentedViewController != nil { dismiss(animated: true) }
        let cards = phoneBrowserSource(mode, session: session)
        let title: String
        switch mode {
        case .search: title = "Library — \(cards.count)"
        case .look(let count): title = "Top \(count) of Library"
        case .revealed: title = "Revealed Cards"
        case .openingHand: title = session.game.opening?.firstPlayer == session.player ? "You Go First" : "Opponent Goes First"
        case .rulesChoice: title = session.game.rulesChoice?.title ?? "Choose"
        case .pile(let location, let owner):
            let name = location == .library ? "Library" : location.rawValue
            title = (owner == session.player ? name : "Opponent's \(name)") + " — \(cards.count)"
        }
        let browser = PhoneZoneBrowserView(title: title, cards: phoneBrowserDisplayOrder(cards, mode: mode),
                                           done: mode == .openingHand ? "Keep" : "Done",
                                           secondary: mode == .search ? "Shuffle & Done" : mode == .openingHand ? "Mulligan" : nil,
                                           canShowOpponent: { if case .pile = mode { return false }; return mode != .revealed && mode != .openingHand && mode != .rulesChoice }())
        if case .pile(let location, let owner) = mode {
            browser.condensesFaceDown = false
            browser.extraMenu = phonePileBrowserMenu(location, owner: owner, session: session)
            if location == .library {
                // Face down, except a top card kept revealed to this player.
                var hidden = Set(cards.map(\.uuid))
                if (session.game.revealedTops?[owner.rawValue] ?? []).contains(session.player.rawValue), let top = cards.first { hidden.remove(top.uuid) }
                browser.setCards(phoneBrowserDisplayOrder(cards, mode: mode), faceDown: hidden)
            }
        }
        browser.zoneAt = { [weak self] point in
            guard let self else { return nil }
            // In a Rules game XMage moves cards between zones; a card can only be played (the
            // Battlefield zone) or, from the opening hand, put on the bottom of the library.
            if session.mode == .rules {
                guard let pile = self.phonePileZone(at: point), pile.player == session.player else { return nil }
                // Scry: the library (its bottom). Surveil: the graveyard. Phone Play's own flow.
                if self.phoneBrowserMode == .rulesChoice {
                    switch session.game.rulesChoice?.kind {
                    case .scry: return pile.location == .library ? .library : nil
                    case .surveil: return pile.location == .graveyard ? .graveyard : nil
                    default: return nil
                    }
                }
                guard self.phoneBrowserMode == .openingHand, pile.location == .library else { return nil }
                return .library
            }
            if let pile = self.phonePileZone(at: point), pile.player == session.player {
                switch pile.location {
                case .graveyard: return .graveyard
                case .exile: return .exile
                case .library: return .library
                default: return nil
                }
            }
            if self.phoneBrowserMode == .openingHand { return nil }
            return self.phoneHandDropRegionContains(point) ? .hand : nil
        }
        browser.onMove = { [weak self] card, destination in
            guard let self else { return }
            if self.phoneBrowserMode == .rulesChoice {
                // Scry / surveil: dropping a card on its pile chooses it (XMage moves it once Done);
                // the browser keeps showing it, rimmed, until then.
                if let adapter = session.rulesAdapter { Task { await adapter.chooseInBrowser(card.uuid) } }
                self.refreshPhoneBrowser(session)
                return
            }
            let position = self.phoneBrowserIDs.firstIndex(of: card.uuid)
            self.phoneBrowserIDs.removeAll { $0 == card.uuid }
            let owner = card.ownerIdentifier
            switch destination {
            case .hand: session.send(.moveToPlayer(card.uuid, .hand, session.player, bottom: false))
            case .graveyard: session.send(.moveToPlayer(card.uuid, .graveyard, owner, bottom: false))
            case .exile: session.send(.moveToPlayer(card.uuid, .exile, owner, bottom: false))
            case .battlefield: session.send(.play(card.uuid, face: nil, faceDown: false, tapped: false, directly: true))
            case .library where mode == .openingHand:
                // Putting cards back from an opening hand: always the bottom. In a Rules game it
                // answers XMage's "put a card on the bottom of your library".
                if session.mode == .rules { session.send(.moveToPlayer(card.uuid, .library, owner, bottom: true)) }
                else { session.sendDirectly(.moveToPlayer(card.uuid, .library, owner, bottom: true)) }
            case .library:
                self.promptPhoneLibraryDrop(card, session: session) { [weak self] in
                    // Left where it was: back into the browser.
                    guard let self else { return }
                    self.phoneBrowserIDs.insert(card.uuid, at: min(position ?? self.phoneBrowserIDs.count, self.phoneBrowserIDs.count))
                    self.refreshPhoneBrowser(session)
                }
            }
        }
        browser.onReorder = { [weak self] cards in
            guard let self else { return }
            // Back to top-first (the browser shows a library with its top on the right).
            self.phoneBrowserIDs = self.phoneBrowserDisplayOrder(cards, mode: mode).map(\.uuid)
            switch mode {
            case .revealed: break
            // Scry / surveil: XMage's follow-up order questions answer from this arrangement.
            case .rulesChoice: session.rulesAdapter?.arrangeChoice(self.phoneBrowserIDs)
            case .openingHand: session.send(.reorderHand(self.phoneBrowserIDs))
            case .pile(let location, let owner):
                if owner == session.player { session.send(.arrangePile(location, self.phoneBrowserIDs)) }
            default: session.send(.arrangeLibraryTop(self.phoneBrowserIDs))
            }
        }
        browser.onShowOpponent = { [weak self] show in
            guard let self else { return }
            let shown = self.phoneBrowserIDs.filter { !self.phoneBrowserFaceDown.contains($0) }
            session.send(.reveal(shown, session.opponent, show))
        }
        browser.onDone = { [weak self] in
            guard let self else { return }
            if mode == .openingHand {
                self.phoneKeptOpeningID = session.game.opening?.id
                self.closePhoneZoneBrowser()
                session.send(.keepHand)
            } else { self.closePhoneZoneBrowser() }
        }
        browser.onSecondary = { [weak self] in
            // Mulligan: a new seven replaces the hand in the browser.
            if mode == .openingHand { session.send(.mulligan); return }
            self?.closePhoneZoneBrowser()
            session.send(.shuffle)
        }
        if mode == .openingHand {
            if session.mode != .rules {
                browser.onCancel = { [weak self] in
                    self?.closePhoneZoneBrowser()
                    session.send(.cancelStart)
                }
            }
            browser.isOpeningHand = true
        }
        phoneBrowser = browser
        phoneBrowserMode = mode
        if mode == .openingHand { configureRulesOpening(browser, session: session) }
        localPhoneBar?.handContainerView.isHidden = mode == .openingHand
        phoneBrowserIDs = cards.map(\.uuid)
        // The opponent's phone outlines the pile while its browser is open, as for the sheet.
        let inspectedPile: (Player.Identifier, Pile.Location)? = {
            switch mode {
            case .pile(let location, let owner) where [.graveyard, .exile, .library].contains(location): return (owner, location)
            case .search, .look: return (session.player, .library)
            default: return nil
            }
        }()
        if let inspectedPile {
            session.trackInspection(.pile(inspectedPile.0, inspectedPile.1)) { [weak self, weak browser] in
                guard let self, let browser else { return false }
                return self.phoneBrowser === browser && self.phoneBrowserMode == mode
            }
        }
        if case .look(let count) = mode { phoneBrowserLookedAt = Set(cards.prefix(count).map(\.uuid)) } else { phoneBrowserLookedAt = [] }
        phoneBrowserSeen = []
        browser.frame = view.bounds
        browser.uncoveredBottom = phoneBrowserUncoveredBottom
        browser.topInset = phoneBrowserTopInset
        browser.contentBottomInset = phoneBrowserContentBottomInset
        browser.onLiftChanged = { [weak self] _ in self?.orderPhoneBrowser() }
        if case .look(let count) = mode {
            browser.setCards(phoneBrowserDisplayOrder(cards, mode: mode), faceDown: Set(cards.dropFirst(count).map(\.uuid)))
        }
        browser.alpha = 0
        view.addSubview(browser)
        orderPhoneBrowser()
        UIView.animate(withDuration: 0.2) { browser.alpha = 1 }
        UIAccessibility.post(notification: .screenChanged, argument: browser)
    }

    /// Keeps the browser in step with the game: cards that left its zone disappear.
    private func refreshPhoneBrowser(_ session: PhoneGameSession) {
        guard let browser = phoneBrowser, let mode = phoneBrowserMode else { return }
        let source = phoneBrowserSource(mode, session: session)
        let sourceIDs = Set(source.map(\.uuid))
        // Newly revealed cards join the revealed browser; library modes follow the library's order
        // (a card put on the bottom shows up at the end).
        if mode == .revealed { phoneBrowserIDs += source.map(\.uuid).filter { !phoneBrowserIDs.contains($0) } }
        else { phoneBrowserIDs = source.map(\.uuid) }
        phoneBrowserIDs = phoneBrowserIDs.filter { sourceIDs.contains($0) }
        let cards = phoneBrowserDisplayOrder(phoneBrowserIDs.compactMap { id in source.first { $0.uuid == id } }, mode: mode)
        if cards.map(\.uuid) != browser.cards.map(\.uuid) || !zip(cards, browser.cards).allSatisfy({ $0 === $1 })
            || browser.faceDownIDs != phoneBrowserFaceDown {
            browser.setCards(cards, faceDown: phoneBrowserFaceDown)
        }
        orderPhoneBrowser()
    }

    /// A library reads left to right from the bottom to the top (the top card on the right, as on
    /// Arena). Reversing is its own inverse, so this also turns the browser's order back to top-first.
    private func phoneBrowserDisplayOrder(_ cards: [CardInstance], mode: PhoneBrowserMode) -> [CardInstance] {
        mode == .revealed || mode == .openingHand || mode == .rulesChoice ? cards : cards.reversed()
    }

    /// The browser's "⋯" menu for a pile: the list view, and for your library its search, look at,
    /// shuffle and top-card choices.
    private func phonePileBrowserMenu(_ location: Pile.Location, owner: Player.Identifier, session: PhoneGameSession) -> UIMenu {
        var items: [UIMenuElement] = [UIAction(title: "Open List", image: UIImage(systemName: "list.bullet")) { [weak self] _ in
            guard let self, let bar = [self.bottomBarA, self.bottomBarB].compactMap({ $0 }).first(where: { $0.player.identifier == owner }) else { return }
            let pileView: HUDCardPileView? = location == .graveyard ? bar.graveyardPileView : location == .exile ? bar.exilePileView : bar.libraryPileView
            self.closePhoneZoneBrowser()
            if let pileView { bar.presentPileSheet(from: pileView) }
        }]
        if location == .library && owner == session.player {
            items.append(UIAction(title: "Search", image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in self?.showPhoneZoneBrowser(.search) })
            items.append(UIMenu(title: "Look at", image: UIImage(systemName: "eye"), children: (1...10).map { count in
                UIAction(title: count == 1 ? "1 card" : "\(count) cards") { [weak self] _ in self?.showPhoneZoneBrowser(.look(count)) }
            }))
            items.append(UIMenu(title: "Draw", image: UIImage(systemName: "hand.draw"), children: (1...10).map { count in
                UIAction(title: count == 1 ? "1 card" : "\(count) cards") { _ in session.send(.drawCards(count, opening: false)) }
            }))
            items.append(UIMenu(title: "Mill", image: UIImage(systemName: "arrow.down.to.line"), children: (1...10).map { count in
                UIAction(title: count == 1 ? "1 card" : "\(count) cards") { _ in
                    // Top card first, so the graveyard ends up in the order they came off.
                    for card in session.game.library(session.player).cards.value.contents.suffix(count).reversed() {
                        session.send(.moveToPlayer(card.uuid, .graveyard, card.ownerIdentifier, bottom: false))
                    }
                }
            }))
            items.append(UIAction(title: "Shuffle", image: UIImage(systemName: "shuffle")) { _ in session.send(.shuffle) })
        }
        if location == .library {
            let current = Set(session.game.revealedTops?[owner.rawValue] ?? [])
            items.append(UIMenu(title: "Keep Top Card Revealed To", image: UIImage(systemName: "eye.circle"), children: [
                ("Me", [session.player]), ("Opponent", [session.opponent]), ("Both", [session.player, session.opponent]), ("No One", [])
            ].map { title, viewers in
                UIAction(title: title, state: Set(viewers.map(\.rawValue)) == current ? .on : .off) { _ in session.send(.revealTopCard(owner, viewers)) }
            }))
        }
        return UIMenu(children: items)
    }

    /// In Look at, everything below the cards being looked at stays face down.
    private var phoneBrowserFaceDown: Set<UUID> {
        if case .pile(.library, let owner) = phoneBrowserMode {
            // A library stays hidden, except a top card kept revealed to this player.
            var hidden = Set(phoneBrowserIDs)
            if let session = phoneMode, (session.game.revealedTops?[owner.rawValue] ?? []).contains(session.player.rawValue),
               let top = phoneBrowserIDs.first { hidden.remove(top) }
            return hidden.subtracting(phoneBrowserSeen)
        }
        guard case .look(let count) = phoneBrowserMode else { return [] }
        if phoneBrowserLookedAt.isEmpty { return Set(phoneBrowserIDs.dropFirst(count)).subtracting(phoneBrowserSeen) }
        return Set(phoneBrowserIDs.filter { !phoneBrowserLookedAt.contains($0) && !phoneBrowserSeen.contains($0) })
    }

    /// A card dropped on a library: on top or at the bottom (and, for a commander, the command
    /// zone instead). `cancelled` runs if the player backs out.
    func promptPhoneLibraryDrop(_ card: CardInstance, session: PhoneGameSession, cancelled: (() -> Void)? = nil) {
        let owner = card.ownerIdentifier
        let alert = UIAlertController(title: card.representation.name, message: "Put it on the top or bottom of the library?", preferredStyle: .alert)
        alert.addAction(.init(title: "Top", style: .default) { _ in session.sendDirectly(.moveToPlayer(card.uuid, .library, owner, bottom: false)) })
        alert.addAction(.init(title: "Bottom", style: .default) { _ in session.sendDirectly(.moveToPlayer(card.uuid, .library, owner, bottom: true)) })
        if card.isCommander.value {
            alert.addAction(.init(title: "Command Zone", style: .default) { _ in session.sendDirectly(.moveToPlayer(card.uuid, .command, owner, bottom: false)) })
        }
        alert.addAction(.init(title: "Cancel", style: .cancel) { _ in cancelled?() })
        phonePresenter.present(alert, animated: true)
    }

    private func closePhoneZoneBrowser() {
        guard let browser = phoneBrowser else { return }
        if let session = phoneMode, session.canAct {
            if phoneBrowserMode == .revealed {
                // Done looking: stop revealing these cards to this player.
                let ids = phoneRevealedToMe.value.map(\.uuid)
                if !ids.isEmpty { session.send(.reveal(ids, session.player, false)) }
            } else if browser.showsOpponent, !phoneBrowserIDs.isEmpty {
                // Shown to the opponent while looking; put away with the browser.
                session.send(.reveal(phoneBrowserIDs.filter { !phoneBrowserFaceDown.contains($0) }, session.opponent, false))
            }
        }
        phoneBrowser = nil
        phoneBrowserMode = nil
        localPhoneBar?.handContainerView.isHidden = false
        phoneBrowserIDs = []
        phoneBrowserSeen = []
        UIView.animate(withDuration: 0.18) { browser.alpha = 0 } completion: { _ in browser.removeFromSuperview() }
    }

    /// The card as drawn (not its padded frame), in the mini card's own unrotated coordinates, so
    /// outlines added to the mini card follow its tap rotation and any in-flight transform.
    /// Outlines live inside the mini card's image view, so they follow its tap rotation and its
    /// flying wiggle and lift.
    private func phoneOutlineHost(_ mini: MiniCardView) -> UIView { mini.cardView ?? mini }

    private func phoneDrawnCardRect(in mini: MiniCardView) -> CGRect {
        guard let art = mini.cardView else { return mini.bounds }
        var rect = art.bounds
        if let fraction = mini.renderedCardFraction {
            rect = CGRect(x: rect.minX + rect.width * fraction.minX, y: rect.minY + rect.height * fraction.minY,
                          width: rect.width * fraction.width, height: rect.height * fraction.height)
        } else if let image = art.image, image.size.width > 0, image.size.height > 0 {
            let scale = min(rect.width / image.size.width, rect.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            rect = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        }
        return rect // in the image view's coordinates (see phoneOutlineHost)
    }

    /// Horizontal lanes (offsets within the field) of one player's band: other permanents on the
    /// left, creatures in the middle, planeswalkers/sagas/battles on the right. A lane only takes
    /// room when the band has something else to share it with.
    private struct PhoneLane { var minX: CGFloat; var width: CGFloat }

    private func phoneLanes(fieldWidth: CGFloat, cellWidth: CGFloat, support: Int, creatures: Int, side: Int,
                            supportExtra: CGFloat = 0, creatureExtra: CGFloat = 0, sideExtra: CGFloat = 0)
        -> (support: PhoneLane, creatures: PhoneLane, side: PhoneLane) {
        let others = support + creatures
        // Lanes get the room their cards need when everything fits; otherwise a share in
        // proportion to their card counts (at least one card each). No fixed caps, so two
        // planeswalkers beside one creature both show when there's space.
        let totalWidth = max(cellWidth, CGFloat(support + creatures + side) * cellWidth + supportExtra + creatureExtra + sideExtra)
        let fits = totalWidth <= fieldWidth + 20
        func share(_ count: Int, extra: CGFloat) -> CGFloat {
            guard count > 0 else { return 0 }
            let wanted = CGFloat(count) * cellWidth + extra
            return fits ? wanted : max(cellWidth, fieldWidth * wanted / totalWidth)
        }
        let sideWidth: CGFloat = side == 0 ? 0 : others > 0
            ? min(share(side, extra: sideExtra), fieldWidth - cellWidth)
            : min(fieldWidth, max(cellWidth, CGFloat(side) * cellWidth + sideExtra))
        let remaining = fieldWidth - (others > 0 ? sideWidth : 0)
        let supportWidth: CGFloat = support > 0 && creatures > 0
            ? min(share(support, extra: supportExtra), remaining - cellWidth)
            : (creatures > 0 ? 0 : remaining)
        // Alone in the band, planeswalkers and sagas still sit at its right end.
        return (PhoneLane(minX: 0, width: max(0, supportWidth)),
                PhoneLane(minX: supportWidth, width: max(0, remaining - supportWidth)),
                PhoneLane(minX: fieldWidth - sideWidth, width: sideWidth))
    }

    /// Right edge (in view coordinates) of the land stacks drawn in either land row, or nil if none.
    private func currentPhoneLandMaxX() -> CGFloat? {
        let frames = [landOrganizer, opponentLandOrganizer].compactMap { $0 }.flatMap(\.landContentFrames)
        guard !frames.isEmpty else { return nil }
        return frames.map { view.convert($0, from: nil).maxX }.max()
    }

    /// Moves the local hand (container and controller) out of its HUD bar onto the board, where it
    /// is laid out by explicit frames. Idempotent, and run on every layout pass: if anything ever
    /// puts the container back into the bar (UIKit's background-snapshot layout passes once did,
    /// leaving the hand off-screen until the game was reopened), the board takes it back.
    private func adoptPhoneHandContainer() {
        guard let bar = localPhoneBar, let hand = bar.handViewController, let container = bar.handContainerView else { return }
        if container.superview === view, hand.parent === self, hand.view.superview === container { return }
        // Reparent both the view and its controller: the hand owns no HUD constraints.
        hand.willMove(toParent: nil)
        hand.view.removeFromSuperview()
        hand.removeFromParent()
        for constraint in bar.view.constraints where constraint.firstItem as? UIView === container || constraint.secondItem as? UIView === container {
            constraint.isActive = false
        }
        NSLayoutConstraint.deactivate(container.constraints)
        container.removeFromSuperview()
        container.translatesAutoresizingMaskIntoConstraints = true
        container.transform = .identity
        view.addSubview(container)
        addChild(hand)
        hand.view.translatesAutoresizingMaskIntoConstraints = true
        hand.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hand.view.frame = container.bounds
        container.addSubview(hand.view)
        // The container remains a drop destination even when SwiftUI has no cards to hit.
        if !container.interactions.contains(where: { $0 is UIDropInteraction }) {
            container.addInteraction(UIDropInteraction(delegate: hand))
        }
        hand.didMove(toParent: self)
        if #available(iOS 16.4, *) { hand.safeAreaRegions = [] }
    }

    private func layoutPhoneLifeOverlays() {
        guard let session = phoneMode else { return }
        let diameter = min(68, max(42, min(view.bounds.width, view.bounds.height) * 0.12))
        for bar in [bottomBarA, bottomBarB].compactMap({ $0 }) {
            guard let tracker = bar.children.first(where: { $0 is LifeTrackerViewController }) as? LifeTrackerViewController,
                  let value = tracker.value else { continue }
            let player = bar.player.identifier
            let mine = player == session.player
            let host = phoneLifeHosts[player] ?? {
                let host = UIHostingController(rootView: LifeTracker(life: value,
                    showsMarks: mine && session.mode != .rules, showsChanges: true, circular: true))
                host.view.backgroundColor = .clear
                if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
                host.view.layer.borderColor = UIColor.white.withAlphaComponent(0.65).cgColor
                host.view.layer.borderWidth = 1.5
                host.view.layer.shadowColor = UIColor.black.cgColor
                host.view.layer.shadowOpacity = 0.65
                host.view.layer.shadowRadius = 4
                addChild(host); view.addSubview(host.view); host.didMove(toParent: self)
                phoneLifeHosts[player] = host
                return host
            }()
            let y = mine ? view.bounds.maxY - diameter * 1.25 : max(4, view.safeAreaInsets.top + 2)
            host.view.frame = CGRect(x: view.bounds.midX - diameter / 2, y: y, width: diameter, height: diameter)
            host.view.layer.cornerRadius = diameter / 2
            host.view.isUserInteractionEnabled = mine && session.mode != .rules
            host.view.accessibilityIdentifier = mine ? "phone-life-local" : "phone-life-opponent"
            host.view.accessibilityValue = String(value.value)
            view.bringSubviewToFront(host.view)
        }
        positionRulesPhaseMarkers()
    }

    private func layoutPhoneHandOverlay() {
        adoptPhoneHandContainer()
        guard let bar = localPhoneBar, let hand = bar.handViewController,
              let container = bar.handContainerView, container.superview === view else { return }
        let shortSide = min(view.bounds.width, view.bounds.height)
        let scale = min(2.4, max(1, shortSide / 375))
        let height = min(360, max(150, shortSide * 0.40))
        let handBand = phoneBandInsets((view.bounds.height - height)...view.bounds.height, margin: 12)
        let margin = max(36 * scale, max(handBand.left, handBand.right))
        let width = max(0, view.bounds.width - 2 * margin)
        // Always derived from the current bounds; the bottom 8% intentionally sits below the screen edge.
        let frame = CGRect(x: margin, y: view.bounds.maxY - height * 0.92, width: width, height: height)
        if container.transform != .identity { container.transform = .identity }
        defer {
            // A card being dragged (and its Attach glow) always draws above the hand.
            if let indicator = phoneAttachIndicator { view.bringSubviewToFront(indicator) }
            if let preview = phoneDragPreview { view.bringSubviewToFront(preview) }
            // Hand layout also runs independently after battlefield layout. Keep the Rules
            // overlay above its transparent hit area; this is a no-op in normal Phone Play.
            layoutPhoneLifeOverlays()
            positionRulesPrompt()
        }
        if container.frame != frame { container.frame = frame }
        if hand.view.frame != container.bounds { hand.view.frame = container.bounds }
        let expanded = hand.phonePresentation.isExpanded
        // The collapsed hand sits between the HUD's piles and its untap/life controls, never over them.
        // Lay the HUD out first: right after a size change (fold/unfold, or the snapshots iOS takes
        // when the app is switched away from) its controls still have their old frames, which would
        // place the collapsed hand for the previous screen size — possibly entirely off-screen.
        bar.view.layoutIfNeeded()
        let controls = bar.phoneHUDSideControls
        let leftEdge = controls.left.map { view.convert($0.bounds, from: $0).maxX }.max() ?? 0
        let rightEdge = controls.right.map { view.convert($0.bounds, from: $0).minX }.min() ?? view.bounds.maxX
        let band: ClosedRange<CGFloat>? = rightEdge - leftEdge > 80
            ? (leftEdge + 10 - margin)...(rightEdge - 10 - margin) : nil
        if hand.phonePresentation.compactBand != band { hand.phonePresentation.compactBand = band }
        let compactWidth = min(width * 0.55, band.map { max(60, $0.upperBound - $0.lowerBound) } ?? .infinity)
        // Centered on screen when it fits; otherwise slid just far enough to clear the controls.
        let compactCenter = PhoneHandFanView.compactCenter(width: width, compactWidth: compactWidth, band: band)
        let size = CGSize(width: expanded ? width : compactWidth, height: height * (expanded ? 1 : 0.7))
        container.phoneContentFrame = CGRect(x: expanded ? 0 : compactCenter - size.width / 2,
                                            y: height - size.height + (expanded ? 0 : height * 0.18),
                                            width: size.width, height: size.height)
        container.accessibilityValue = expanded ? "Expanded" : "Compact"
        view.bringSubviewToFront(container)
    }

    private func rememberPhoneConstraint(_ constraint: NSLayoutConstraint) {
        if !savedPhoneConstraints.contains(where: { $0.0 === constraint }) { savedPhoneConstraints.append((constraint, constraint.constant)) }
    }
    /// Arena's stack count: a small dark label with white text, sitting just above the stack's
    /// top-left corner (`corner`, in board coordinates) rather than over the card.
    private func addPhoneBadge(_ text: String, above corner: CGPoint, cards: [CardInstance]) {
        let button = UIButton(type: .system)
        button.setTitle(text, for: .normal)
        let scale = max(0.04, scrollView.zoomScale)
        let uiScale = min(2.4, max(1, min(view.bounds.width, view.bounds.height) / 375))
        let unit = uiScale / scale
        let font = UIFont.systemFont(ofSize: 10 * unit, weight: .semibold)
        button.titleLabel?.font = font
        button.setTitleColor(UIColor(white: 0.95, alpha: 1), for: .normal)
        button.backgroundColor = UIColor(white: 0.1, alpha: 0.85)
        button.layer.cornerRadius = 3 * unit
        button.layer.borderWidth = 0.75 * unit
        button.layer.borderColor = UIColor(white: 1, alpha: 0.18).cgColor
        let measured = (text as NSString).size(withAttributes: [.font: font])
        let size = CGSize(width: ceil(measured.width) + 8 * unit, height: ceil(measured.height) + 3 * unit)
        button.frame = CGRect(x: corner.x, y: corner.y - 3 * unit - size.height, width: size.width, height: size.height)
        button.accessibilityLabel = "Choose individual cards (\(cards.count))"
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let alert = UIAlertController(title: "Cards", message: nil, preferredStyle: .actionSheet)
            for (index, card) in cards.enumerated() {
                alert.addAction(.init(title: "\(card.representation.name ?? "Card") \(index + 1)\(card.isTapped.value ? " · tapped" : "")", style: .default) { [weak self] _ in self?.focus(on: card, view: self?.cardView(for: card)) })
            }
            alert.addAction(.init(title: "Cancel", style: .cancel))
            alert.popoverPresentationController?.sourceView = button
            self.present(alert, animated: true)
        }, for: .touchUpInside)
        // Count badges always render above the stacked cards they label, whatever is re-fronted later.
        button.layer.zPosition = 1000
        board.addSubview(button); phoneGroupButtons.append(button)
    }

    private func playPhoneCard(_ card: CardInstance, session: PhoneGameSession, completion: ((Bool) -> Void)? = nil) {
        let options = session.castOptions(for: card)
        if options.count == 1 { session.send(.playCard(options[0].parameters)); completion?(true); return }
        // Centered, with no arrow: the card was dropped, so there's nothing for it to point at.
        let chooser = UIAlertController(title: "Play", message: card.representation.name, preferredStyle: .alert)
        for option in options {
            chooser.addAction(.init(title: option.title, style: .default) { _ in session.send(.playCard(option.parameters)); completion?(true) })
        }
        chooser.addAction(.init(title: "Cancel", style: .cancel) { _ in completion?(false) })
        present(chooser, animated: true)
    }

    private func clearPhoneDragPreview() {
        cancelPhoneSpringLoad()
        phoneZoneHoverKey = nil
        if let card = phoneDraggedCard {
            cardView(for: card)?.alpha = 1
            landOrganizer?.concealCard(card.uuid, false)
        }
        phoneHandMiniPreview?.removeFromSuperview()
        phoneHandMiniPreview = nil
        phoneHandMiniHost = nil
        phoneDragPreview?.removeFromSuperview()
        phoneDragPreview = nil
        phoneDraggedCard = nil
        clearPhoneAttachHover()
    }

    private func movePhoneCardPreview(_ card: CardInstance, to point: CGPoint, sourceSize: CGSize? = nil) {
        guard phoneMode?.canAct == true else { return }
        defer { updatePhoneZoneHover(at: point, includesHand: true) } // runs after the attach hover below
        defer { updatePhoneAttachHover(at: point, excluding: [card.uuid]) }
        if phoneDraggedCard?.uuid != card.uuid {
            clearPhoneDragPreview()
            phoneDraggedCard = card
            guard let source = cardView(for: card) else { return }
            PhoneHaptics.pickUp()
            var image = source.cardView.image
            let size: CGSize
            let angle: CGFloat
            if let sourceSize {
                size = sourceSize
                angle = card.isTapped.value ? .pi / 15 : 0
                // Organizer thumbnails use the same cropped 480×420 canvas.
                if let original = image, let pixels = original.cgImage,
                   let crop = pixels.cropping(to: CGRect(x: 0, y: CGFloat(pixels.height) * 30 / 480, width: CGFloat(pixels.width), height: CGFloat(pixels.height) * 420 / 480)) {
                    image = UIImage(cgImage: crop, scale: original.scale, orientation: original.imageOrientation)
                }
            } else {
                let origin = source.convert(CGPoint.zero, to: view)
                let x = source.convert(CGPoint(x: source.bounds.width, y: 0), to: view)
                let y = source.convert(CGPoint(x: 0, y: source.bounds.height), to: view)
                size = CGSize(width: hypot(x.x-origin.x, x.y-origin.y), height: hypot(y.x-origin.x, y.y-origin.y))
                angle = atan2(x.y-origin.y, x.x-origin.x)
            }
            let preview = UIImageView(image: image)
            preview.contentMode = .scaleAspectFit
            preview.bounds.size = size
            preview.transform = CGAffineTransform(rotationAngle: angle)
            if card.isTapped.value {
                let arrow = UIImageView(image: UIImage.resource(named: "tap")?.withRenderingMode(.alwaysTemplate))
                arrow.tintColor = .white; arrow.alpha = 0.65; arrow.contentMode = .scaleAspectFit
                arrow.frame = preview.bounds.insetBy(dx: size.width * 0.27, dy: size.height * 0.27)
                preview.addSubview(arrow)
            }
            preview.alpha = 0.9; preview.isUserInteractionEnabled = false
            view.addSubview(preview); phoneDragPreview = preview
            cardView(for: card)?.alpha = 0
        }
        phoneDragPreview?.center = point
        if let preview = phoneDragPreview { view.bringSubviewToFront(preview) }
    }
    // MARK: Pile top-card drags

    /// The top card lifts off the pile at the pile's size and grows to hand size, then behaves
    /// like a card dragged from the hand: battlefield, attach/target hovers, piles, or the hand.
    @objc private func phonePilePanned(_ pan: PhonePilePanGesture) {
        guard let session = phoneMode, let bar = pan.bar else { return }
        let point = pan.location(in: view)
        switch pan.state {
        case .began:
            let owner = bar.player.identifier
            let pile = session.game.state[player: owner][pan.zone]
            // Your own library only; graveyards and exile are public.
            guard session.canAct, pan.zone != .library || owner == session.player,
                  let card = pile.cards.value.last, let pileView = pan.view as? HUDCardPileView else {
                pan.isEnabled = false; pan.isEnabled = true
                return
            }
            let source: UIView = pileView.topCardImageView.isHidden ? pileView : pileView.topCardImageView
            let sourceFrame = source.convert(source.bounds, to: nil)
            let height = min(220, max(110, view.bounds.height * 0.42))
            let size = CGSize(width: height * 63 / 88, height: height)
            let start = PhoneHandCardGeometry(center: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY), size: size, angle: 0)
            let faceDown = pan.zone == .library && !pile.isTopCardRevealed.value
            beginPhoneHandCardDrag(card, start: start, at: point, sourcePile: pan.zone, faceDown: faceDown,
                                   startScale: max(0.1, sourceFrame.height / height))
            _ = movePhoneHandCardPreview(card, to: point)
        case .changed:
            guard let card = phoneHandDrag?.card, phoneHandDrag?.sourcePile != nil else { return }
            _ = movePhoneHandCardPreview(card, to: point)
        case .ended:
            guard let card = phoneHandDrag?.card, phoneHandDrag?.sourcePile != nil else { return }
            finishPhoneHandCardDrag(card, at: point, handIndex: nil, slot: nil)
        default:
            if phoneHandDrag?.sourcePile != nil, phoneHandDrag?.landing == false { returnPhoneHandPreview() }
        }
    }

    // MARK: Arena-style hand drag

    private struct PhoneHandDragState {
        let card: CardInstance
        /// Where it was picked up (view coordinates) and its height in the fan.
        let startCenter: CGPoint
        let startHeight: CGFloat
        /// Current scale relative to the hand size (0 until the first move straightens it).
        var scale: CGFloat = 0
        /// Whether the finger was over the hand at the last move, and until when the card is still
        /// easing between floating above the finger (over the hand) and centered on it.
        var overHand: Bool?
        var settleUntil: CFTimeInterval = 0
        /// Released and animating to where it went.
        var landing = false
        /// Picked up off the top of a graveyard, exile or library rather than out of the hand.
        var sourcePile: Pile.Location? = nil
        /// Dragged showing its back (a hidden library top card).
        var faceDown = false
    }

    private func handlePhoneHandDrag(_ card: CardInstance, phase: PhoneHandDragPhase, windowPoint: CGPoint) -> Bool {
        let point = view.convert(windowPoint, from: view.window)
        switch phase {
        case .began(let start):
            beginPhoneHandCardDrag(card, start: start, at: point)
            return true
        case .changed:
            return movePhoneHandCardPreview(card, to: point)
        case .ended(let index, let slot):
            finishPhoneHandCardDrag(card, at: point, handIndex: index, slot: slot)
            return false
        case .cancelled:
            if phoneHandDrag?.card.uuid == card.uuid, phoneHandDrag?.landing == false { returnPhoneHandPreview() }
            return false
        }
    }

    /// Height of a card on the battlefield right now (cards are aspect-fit in square views).
    private var phoneBattlefieldCardHeight: CGFloat { max(44, phoneFieldCardExtent) }

    /// Where a held hand card counts as "over the hand": the collapsed hand and the HUD, plus a
    /// margin above, so a card just picked up from the expanded fan doesn't count as played.
    private func phoneHandDragRegionContains(_ point: CGPoint) -> Bool {
        guard let container = localPhoneBar?.handContainerView, container.superview === view else { return false }
        let compactTop = container.frame.minY + container.bounds.height * 0.48
        return phoneHandDropRegionContains(point) || point.y >= compactTop - container.bounds.height * 0.25
    }

    /// Shown beside the hand but actually in the graveyard or exile.
    private func isPhoneCastableOutsideHand(_ card: CardInstance) -> Bool {
        guard let session = phoneMode else { return false }
        let mine = session.game.state[player: session.player]
        return !mine.hand.cards.value.contains(card) && !mine.commandZone.cards.value.contains(card)
    }

    /// Still over the spot the card was picked up from (dropping it there changes nothing).
    private func isNearPhoneHandDragOrigin(_ point: CGPoint, _ drag: PhoneHandDragState) -> Bool {
        abs(point.x - drag.startCenter.x) < drag.startHeight * 63 / 88 * 0.6 && abs(point.y - drag.startCenter.y) < drag.startHeight * 0.6
    }

    /// The card lifts out of the fan exactly where it was drawn (same size, rotation and cost),
    /// and the rest of the hand collapses.
    private func beginPhoneHandCardDrag(_ card: CardInstance, start: PhoneHandCardGeometry, at point: CGPoint,
                                        sourcePile: Pile.Location? = nil, faceDown: Bool = false, startScale: CGFloat = 1) {
        let presentation = localPhoneBar?.handViewController?.phonePresentation
        guard phoneMode?.canAct == true else { presentation?.endDrag(); return }
        if phoneHandDrag != nil { finishPhoneHandLanding() }
        clearPhoneDragPreview() // also forgets the last zone, so this drag's first zone ticks
        let center = view.convert(start.center, from: view.window)
        let inCommandZone = phoneMode.map { $0.game.state[player: $0.player].commandZone.cards.value.contains(card) } ?? false
        // Arena's blue glow, shown while release would play (drawn in the card face, under its ability tiles).
        let playGlow = PhoneHandPlayGlow()
        let host = UIHostingController(rootView: PhoneHandCardFace(card: card, height: start.size.height, inCommandZone: inCommandZone,
                                                                   faceDown: faceDown, playGlow: playGlow))
        if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.accessibilityIdentifier = "phone-hand-drag-preview"
        host.view.bounds = CGRect(origin: .zero, size: start.size)
        host.view.center = center
        host.view.transform = CGAffineTransform(rotationAngle: start.angle).scaledBy(x: startScale, y: startScale)
        phoneHandPlayGlow = playGlow
        host.view.layer.shadowColor = UIColor.black.cgColor
        host.view.layer.shadowOpacity = 0.55
        host.view.layer.shadowRadius = 10
        host.view.layer.shadowOffset = CGSize(width: 0, height: 6)
        view.addSubview(host.view)
        phoneHandPreviewHost = host
        phoneDragPreview = host.view
        phoneDraggedCard = card
        phoneHandDrag = PhoneHandDragState(card: card, startCenter: center, startHeight: start.size.height, sourcePile: sourcePile, faceDown: faceDown)
        PhoneHaptics.pickUp()
        // A hand card leaves the hand open (to reorder in it) until it's dragged out of the hand.
        if sourcePile != nil { collapsePhoneHand() }
    }

    /// Follows the finger: full hand size over the hand, battlefield size over the battlefield,
    /// growing and shrinking (and straightening) as it crosses between them.
    private func movePhoneHandCardPreview(_ card: CardInstance, to point: CGPoint) -> Bool {
        guard var drag = phoneHandDrag, drag.card.uuid == card.uuid, !drag.landing,
              let preview = phoneDragPreview else { return phoneHandDragRegionContains(point) }
        let overHand = phoneHandDragRegionContains(point)
        if !overHand, localPhoneBar?.handViewController?.phonePresentation.isExpanded == true { collapsePhoneHand() }
        // Only cards out of the hand grow and shrink; one off a pile keeps a single size. Over an
        // open browser's fan, it matches the browser's cards.
        let browserHeight = !overHand && phoneBrowserDropZone != nil && phoneBrowser?.isOverFan(point) == true
            ? phoneBrowser?.fanCardHeight : nil
        let scale = browserHeight.map { $0 / drag.startHeight }
            ?? (drag.sourcePile != nil ? min(1, phoneBattlefieldCardHeight / drag.startHeight)
                : overHand ? 1 : min(1, phoneBattlefieldCardHeight / drag.startHeight))
        // Over the hand the card floats with its bottom just above the finger, so it can be read;
        // over the battlefield the finger holds its center. Crossing between them eases over.
        let target = overHand ? CGPoint(x: point.x, y: point.y - drag.startHeight * scale / 2 - 14) : point
        let now = CACurrentMediaTime()
        if drag.overHand != overHand {
            drag.overHand = overHand
            drag.settleUntil = now + 0.2
            phoneHandDrag = drag
        }
        let remaining = drag.settleUntil - now
        if remaining > 0.01 {
            UIView.animate(withDuration: remaining, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                preview.center = target
            }
        } else {
            preview.center = target
        }
        if drag.scale != scale {
            drag.scale = scale
            phoneHandDrag = drag
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                preview.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
        view.bringSubviewToFront(preview)
        if overHand { clearPhoneAttachHover() } else { updatePhoneAttachHover(at: point, excluding: [card.uuid], dragged: card.uuid) }
        // Piles (and, for a card off a pile or castable from another zone, the hand) show where it would go.
        updatePhoneZoneHover(at: point, includesHand: drag.sourcePile != nil
                             || (isPhoneCastableOutsideHand(card) && !isNearPhoneHandDragOrigin(point, drag)))
        // Glows blue while letting go would play it (not over the hand or a pile).
        // Over an open browser it only glows on its Battlefield zone (elsewhere the card goes into
        // the browser or back).
        let overBrowser = phoneBrowser.map { $0.covers(point) && !$0.isOverBattlefieldZone(point) } ?? false
        let willPlay = !overHand && !overBrowser && phonePileZone(at: point) == nil
        // Near the right edge, the "Move to Stack" area appears (it takes over the hovers when lit).
        updatePhoneStackCastZone(at: overHand || phoneBrowser != nil ? nil : point)
        if phoneStackCastArmed { clearPhoneAttachHover() }
        if let glow = phoneHandPlayGlow, glow.isVisible != willPlay { glow.isVisible = willPlay }
        return overHand
    }

    private func finishPhoneHandCardDrag(_ card: CardInstance, at point: CGPoint, handIndex: Int?, slot: PhoneHandCardGeometry?) {
        guard let drag = phoneHandDrag, drag.card.uuid == card.uuid, !drag.landing else {
            localPhoneBar?.handViewController?.phonePresentation.endDrag()
            return
        }
        let attachTarget = handIndex == nil ? armedPhoneAttachTarget(at: point, excluding: [card.uuid]) : nil
        let spellTarget = handIndex == nil ? armedPhoneSpellTarget(at: point, excluding: [card.uuid]) : nil
        let castToStack = handIndex == nil && phoneStackCastArmed && phoneBrowser == nil
        updatePhoneStackCastZone(at: nil)
        clearPhoneAttachHover()
        guard let session = phoneMode, session.canAct else { cancelPhoneSpringLoad(); returnPhoneHandPreview(); return }
        let browserCardHeight = phoneBrowser?.fanCardHeight
        if finishPhoneSpringLoad(card, at: point, faceUp: !drag.faceDown) {
            hidePhoneDragHover()
            collapsePhoneHand()
            // It fades where it was let go, at the browser's card size.
            landPhoneHandPreview(center: point, height: browserCardHeight ?? drag.startHeight * 0.6, angle: 0, fade: true)
            return
        }
        if handIndex == nil, phoneDropBlockedByBrowser(at: point) { hidePhoneDragHover(); returnPhoneHandPreview(); return }
        if castToStack {
            // Dropped on the "Move to Stack" area at the right edge: onto the stack, untargeted.
            hidePhoneDragHover()
            session.send(.castTargeting(card.uuid, nil))
            PhoneHaptics.drop()
            collapsePhoneHand()
            flyPhoneHandPreviewToBoard(card)
            return
        }
        if let pile = phonePileZone(at: point), phonePile(pile.location, of: pile.player, holds: card) {
            // Dropped back on the pile it came off: it stays where it was.
            hidePhoneDragHover()
            returnPhoneHandPreview()
            return
        }
        if let pile = phonePileZone(at: point) {
            if pile.location == .library { promptPhoneLibraryDrop(card, session: session) }
            else { session.send(.moveToPlayer(card.uuid, pile.location, pile.player, bottom: false)) }
            PhoneHaptics.drop()
            collapsePhoneHand() // the card left the hand
            let frame = view.convert(pile.view.bounds, from: pile.view)
            landPhoneHandPreview(center: CGPoint(x: frame.midX, y: frame.midY), height: frame.height * 0.8, angle: 0, fade: true)
            return
        }
        if drag.sourcePile != nil, handIndex == nil, phoneHandDropRegionContains(point) {
            // Off a pile into the hand (drawing the top card, returning one from the graveyard…).
            session.send(.moveToPlayer(card.uuid, .hand, session.player, bottom: false))
            PhoneHaptics.drop()
            landPhoneHandPreview(center: point, height: drag.startHeight * 0.7, angle: 0, fade: true)
            return
        }
        if let handIndex {
            var ids = session.game.state[player: session.player].hand.cards.value.map(\.uuid)
            if let from = ids.firstIndex(of: card.uuid) {
                ids.remove(at: from)
                ids.insert(card.uuid, at: min(max(0, handIndex), ids.count))
                if ids != session.game.state[player: session.player].hand.cards.value.map(\.uuid) { session.send(.reorderHand(ids)) }
            } else if session.game.state[player: session.player].commandZone.cards.value.contains(card) {
                // A commander dropped on the hand goes to the hand.
                session.send(.moveToPlayer(card.uuid, .hand, session.player, bottom: false))
            } else if !isNearPhoneHandDragOrigin(point, drag) {
                // A card castable from the graveyard or exile, dropped among the hand cards, moves
                // into the hand; dropped back where it came from, it stays put.
                session.send(.moveToPlayer(card.uuid, .hand, session.player, bottom: false))
                PhoneHaptics.drop()
            }
            if let slot {
                landPhoneHandPreview(center: view.convert(slot.center, from: view.window), height: slot.size.height, angle: slot.angle)
            } else {
                finishPhoneHandLanding()
            }
            return
        }
        if let spellTarget {
            session.send(.castTargeting(card.uuid, .card(spellTarget.uuid)))
            PhoneHaptics.drop()
            flyPhoneHandPreviewToBoard(card)
            return
        }
        if card.isPhoneTargetingSpell, (card.representation.typeLine ?? "").contains("Aura") {
            // Auras go onto the stack too; one cast without a target is just put there.
            session.send(.castTargeting(card.uuid, nil))
            PhoneHaptics.drop()
            flyPhoneHandPreviewToBoard(card)
            return
        }
        if let attachTarget {
            session.send(.attachDroppedCard(card.uuid, attachTarget.uuid))
            PhoneHaptics.drop()
            flyPhoneHandPreviewToBoard(card)
            return
        }
        playPhoneCard(card, session: session) { [weak self] played in
            if played { PhoneHaptics.drop(); self?.flyPhoneHandPreviewToBoard(card) } else { self?.returnPhoneHandPreview() }
        }
    }

    /// Zooms the dropped card from where it was released onto the spot it was added at, once the
    /// battlefield (or land row, or stack) shows it.
    private func flyPhoneHandPreviewToBoard(_ card: CardInstance, attempt: Int = 0) {
        guard let drag = phoneHandDrag, drag.card.uuid == card.uuid, phoneDragPreview != nil else { return }
        phoneHandDrag?.landing = true
        view.layoutIfNeeded()
        // Adding a permanent can regroup the row. Capture its final slot even when the
        // model's card-view subscription ran before the next UIKit layout callback.
        layoutPhoneBattlefield()
        if let target = cardView(for: card), target.window != nil, !target.isHidden, target.superview != nil {
            let origin = target.convert(CGPoint.zero, to: view)
            let xEdge = target.convert(CGPoint(x: target.bounds.width, y: 0), to: view)
            let center = target.convert(CGPoint(x: target.bounds.midX, y: target.bounds.midY), to: view)
            let side = hypot(xEdge.x - origin.x, xEdge.y - origin.y)
            landPhoneHandPreview(center: center, height: side, angle: atan2(xEdge.y - origin.y, xEdge.x - origin.x), crossfade: true, hiding: target)
            return
        }
        if let frame = landOrganizer?.landFrame(for: card.uuid) {
            let rect = view.convert(frame, from: nil)
            let host = UIHostingController(rootView: SwiftUICardView(card: card, isRotationEnabled: false))
            if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
            host.view.backgroundColor = .clear
            host.view.bounds = CGRect(origin: .zero, size: rect.size)
            phoneHandMiniHost = host
            landOrganizer?.concealCard(card.uuid, true)
            landPhoneHandPreview(center: CGPoint(x: rect.midX, y: rect.midY), height: rect.height,
                                angle: card.isTapped.value ? .pi / 15 : 0, crossfade: true, morph: host.view)
            return
        }
        if phoneMode?.game.stack.contains(where: { $0.card?.uuid == card.uuid }) == true {
            if let stackView = phoneStackCards?.view, !stackView.isHidden {
                let width = min(stackView.bounds.width / 1.62, stackView.bounds.height * 0.88 * 63 / 88)
                let center = CGPoint(x: stackView.frame.maxX - width / 2 - 5, y: stackView.frame.midY)
                landPhoneHandPreview(center: center, height: width * 88 / 63, angle: 0, crossfade: true)
                return
            } else if let button = phoneStackButton, !button.isHidden {
                landPhoneHandPreview(center: CGPoint(x: button.frame.midX, y: button.frame.midY), height: button.frame.height, angle: 0, fade: true)
                return
            }
        }
        guard attempt < 45 else {
            // Never showed up where we could see it: fade out where it was dropped.
            if let preview = phoneDragPreview {
                landPhoneHandPreview(center: preview.center, height: phoneBattlefieldCardHeight, angle: 0, fade: true)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 30) { [weak self] in
            self?.flyPhoneHandPreviewToBoard(card, attempt: attempt + 1)
        }
    }

    /// - Parameters:
    ///   - fade: fades the card out over the whole flight (into a pile or the stack).
    ///   - crossfade: morphs the travelling full card into a travelling mini-card snapshot.
    private func landPhoneHandPreview(center: CGPoint, height: CGFloat, angle: CGFloat, fade: Bool = false,
                                      crossfade: Bool = false, hiding target: UIView? = nil, morph: UIView? = nil) {
        guard let preview = phoneDragPreview, let drag = phoneHandDrag else { finishPhoneHandLanding(); return }
        phoneHandDrag?.landing = true
        let reduced = UIAccessibility.isReduceMotionEnabled
        let mini = crossfade && !reduced ? (morph ?? target?.snapshotView(afterScreenUpdates: true)) : nil
        if let mini {
            if let target { mini.bounds = target.bounds }
            mini.center = preview.center
            let currentHeight = preview.bounds.height * hypot(preview.transform.a, preview.transform.b)
            mini.transform = CGAffineTransform(rotationAngle: atan2(preview.transform.b, preview.transform.a))
                .scaledBy(x: currentHeight / mini.bounds.height, y: currentHeight / mini.bounds.height)
            mini.alpha = 0; mini.isUserInteractionEnabled = false
            view.insertSubview(mini, aboveSubview: preview)
            phoneHandMiniPreview = mini
        }
        target?.alpha = 0
        phoneHandPlayGlow?.isVisible = false
        let scale = height / drag.startHeight
        let duration = reduced ? 0.12 : 0.32
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
            if !reduced {
                preview.center = center
                preview.transform = CGAffineTransform(rotationAngle: angle).scaledBy(x: scale, y: scale)
                if let mini {
                    mini.center = center
                    mini.transform = CGAffineTransform(rotationAngle: angle)
                        .scaledBy(x: height / mini.bounds.height, y: height / mini.bounds.height)
                    mini.alpha = 1
                }
            }
            preview.layer.shadowOpacity = 0
            if fade || crossfade { preview.alpha = 0 }
            if crossfade && mini == nil { target?.alpha = 1 }
        } completion: { [weak self] _ in
            target?.alpha = 1
            guard self?.phoneHandDrag?.card.uuid == drag.card.uuid else { return }
            self?.finishPhoneHandLanding()
        }
    }

    /// Not played (cancelled, or the touch was taken away): the card goes back to its hand slot.
    private func returnPhoneHandPreview() {
        guard let drag = phoneHandDrag else { return }
        let presentation = localPhoneBar?.handViewController?.phonePresentation
        let index = phoneMode.map { $0.game.state[player: $0.player].hand.cards.value.map(\.uuid) }?.firstIndex(of: drag.card.uuid)
        presentation?.heldIndex = index
        landPhoneHandPreview(center: drag.startCenter, height: drag.startHeight * 0.7, angle: 0, fade: true)
    }

    /// Ends a hand drag immediately (size changes, app switches).
    private func abandonPhoneHandDrag() {
        guard phoneHandDrag != nil else { return }
        finishPhoneHandLanding()
    }

    private func finishPhoneHandLanding() {
        cancelPhoneSpringLoad()
        updatePhoneStackCastZone(at: nil)
        phoneHandDrag = nil
        phoneHandPreviewHost = nil
        phoneHandPlayGlow = nil
        clearPhoneDragPreview()
        localPhoneBar?.handViewController?.phonePresentation.endDrag()
    }

    private func finishPhoneCardDrag(_ card: CardInstance, at point: CGPoint) {
        guard let session = phoneMode else { clearPhoneDragPreview(); return }
        let settle = performPhoneCardDrop(card, at: point, session: session)
        clearPhoneAttachHover()
        settlePhoneDragPreview(card, settle)
    }

    private enum PhoneDragSettle { case back, fade, into(CGRect) }

    /// What a battlefield card dropped here does, and how its drag preview should settle.
    private func performPhoneCardDrop(_ card: CardInstance, at point: CGPoint, session: PhoneGameSession) -> PhoneDragSettle {
        if finishPhoneSpringLoad(card, at: point, faceUp: !card.representation.isFaceDown) { hidePhoneDragHover(); return .fade }
        if phoneDropBlockedByBrowser(at: point) { hidePhoneDragHover(); return .back }
        if performPhoneCombatDrop(at: point, ids: [card.uuid]) { return .back }
        if let pile = phonePileZone(at: point) {
            if pile.location == .library { promptPhoneLibraryDrop(card, session: session) }
            else { session.send(.moveToPlayer(card.uuid, pile.location, pile.player, bottom: false)) }
            phoneZoneDropFeedback()
            return .into(view.convert(pile.view.bounds, from: pile.view))
        }
        if phoneHandDropRegionContains(point) {
            session.send(.moveToPlayer(card.uuid, .hand, session.player, bottom: false))
            phoneZoneDropFeedback()
            return .fade
        }
        if let target = armedPhoneAttachTarget(at: point, excluding: [card.uuid]) {
            session.send(.attachDroppedCard(card.uuid, target.uuid))
            PhoneHaptics.drop()
            return .fade
        } else if phoneUnattachArmed {
            session.send(.attach(card.uuid, nil))
            return .fade
        }
        return .back
    }

    /// A released battlefield card doesn't snap: it glides back to its place, shrinks into the
    /// pile it was dropped on, or fades where it went (the hand, an attachment).
    private func settlePhoneDragPreview(_ card: CardInstance, _ settle: PhoneDragSettle) {
        guard let preview = phoneDragPreview, !UIAccessibility.isReduceMotionEnabled else { clearPhoneDragPreview(); return }
        phoneDragPreview = nil
        phoneDraggedCard = nil
        let source = cardView(for: card)
        let organizer = [landOrganizer, opponentLandOrganizer].compactMap { $0 }.first { $0.landFrame(for: card.uuid) != nil }
        let landFrame = organizer?.landFrame(for: card.uuid).map { view.convert($0, from: nil) }
        // Keep the land's slot empty until its preview arrives back.
        if case .back = settle { organizer?.concealCard(card.uuid, true) }
        let finish = { [weak self, weak source, weak organizer] in
            preview.removeFromSuperview()
            source?.alpha = 1
            organizer?.concealCard(card.uuid, false)
            self?.landOrganizer?.concealCard(card.uuid, false)
        }
        UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.beginFromCurrentState]) { [weak self] in
            guard let self else { return }
            switch settle {
            case .back:
                if let source, source.superview != nil, !source.isHidden {
                    preview.center = source.convert(CGPoint(x: source.bounds.midX, y: source.bounds.midY), to: self.view)
                    let x = source.convert(CGPoint(x: source.bounds.width, y: 0), to: self.view)
                    let origin = source.convert(CGPoint.zero, to: self.view)
                    preview.transform = CGAffineTransform(rotationAngle: atan2(x.y - origin.y, x.x - origin.x))
                } else if let frame = landFrame {
                    // An organized land glides back to its slot in the land row.
                    preview.center = CGPoint(x: frame.midX, y: frame.midY)
                    preview.transform = CGAffineTransform(rotationAngle: card.isTapped.value ? .pi / 15 : 0)
                } else { preview.alpha = 0 }
            case .fade:
                preview.alpha = 0
                preview.transform = preview.transform.scaledBy(x: 0.85, y: 0.85)
            case .into(let rect):
                preview.center = CGPoint(x: rect.midX, y: rect.midY)
                let scale = rect.height / max(1, preview.bounds.height)
                preview.transform = CGAffineTransform(scaleX: scale, y: scale)
                preview.alpha = 0
            }
        } completion: { _ in finish() }
    }

    /// A firm tap when a dropped card lands in a different zone.
    private func phoneZoneDropFeedback() { PhoneHaptics.drop() }

    private func handlePhoneCardPan(_ gesture: UIPanGestureRecognizer) {
        guard let cardView = gesture.view as? MiniCardView, let card = cardView.cardInstance else { return }
        let point = gesture.location(in: view)
        switch gesture.state {
        case .began, .changed: movePhoneCardPreview(card, to: point)
        case .ended: finishPhoneCardDrag(card, at: point)
        case .cancelled, .failed:
            clearPhoneDragPreview()
        default: break
        }
    }

    @objc private func collapsePhoneHand() {
        localPhoneBar?.handViewController?.phonePresentation.isExpanded = false
    }

    private func updatePhoneHandShield() {
        guard let shield = phoneHandShield else { return }
        shield.isHidden = localPhoneBar?.handViewController?.phonePresentation.isExpanded != true
        if !shield.isHidden { view.bringSubviewToFront(shield) }
    }

    private var localPhoneBar: BottomBarViewController? {
        [bottomBarA,bottomBarB].compactMap { $0 }.first { $0.player.identifier == phoneMode?.player }
    }

    private func presentPhonePacketChoices() {
        guard let session = phoneMode else { return }
        guard let selection = session.game.packetSelection,
              !selection.completed.contains(session.player.rawValue) else {
            phonePacketChooser?.dismiss(animated: true)
            phonePacketChooser = nil
            phonePacketSelectionID = nil
            return
        }
        guard phonePacketSelectionID != selection.id else { return }
        // With the board menu open (its Load Deck page started the draft), navigate forward in it.
        if let navigation = presentedViewController as? UINavigationController, !navigation.isBeingDismissed,
           navigation.presentedViewController == nil {
            phonePacketSelectionID = selection.id
            let chooser = UIHostingController(rootView: PhonePacketChoiceView(session: session, embedsNavigation: false))
            chooser.navigationItem.hidesBackButton = true
            phonePacketChooser = chooser
            navigation.isModalInPresentation = true
            navigation.pushViewController(chooser, animated: true)
            return
        }
        guard presentedViewController == nil else {
            dismiss(animated: true) { [weak self] in self?.presentPhonePacketChoices() }
            return
        }
        phonePacketSelectionID = selection.id
        let chooser = UIHostingController(rootView: PhonePacketChoiceView(session: session))
        chooser.view.accessibilityHint = PhoneSheet.providesCloseHint // a pending choice re-presents it; no close button
        chooser.modalPresentationStyle = .formSheet
        phonePacketChooser = chooser
        present(chooser, animated: true)
    }

    /// Load Deck, pushed inside the board menu's sheet.
    private func makePhoneDeckPicker() -> UIViewController {
        let player = phoneMode?.player ?? .a
        return UIHostingController(rootView: LoadDeckView(startPacketGame: { [weak self] kind, set in
            // The packet choices are pushed into this same sheet (presentPhonePacketChoices)
            // rather than closing it and presenting another.
            self?.phoneMode?.send(.startPackets(kind: kind, set: set))
        }, playerIdentifier: player, chooseListFile: { [weak self] in
            guard let self else { return }
            // Over the menu, which closes once a file is picked.
            self.loadDeckPlayerIdentifier = player
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText])
            picker.delegate = self
            self.phonePresenter.present(picker, animated: true)
        }, dismiss: { [weak self] in self?.dismiss(animated: true) }).navigationTitle("Load Deck"))
    }

    /// Abilities on the stack have no card to inspect or drag.
    private func showPhoneAbilityOptions() {
        guard let session = phoneMode, let item = session.game.stack.last(where: { $0.card == nil }) else { return }
        let alert = UIAlertController(title: item.text, message: nil, preferredStyle: .actionSheet)
        if session.game.stack.last?.id == item.id {
            alert.addAction(.init(title: "Resolve", style: .default) { _ in session.send(.resolve(item.id)) })
        }
        alert.addAction(.init(title: "Remove from Stack", style: .destructive) { _ in session.send(.counterStack(item.id)) })
        alert.addAction(.init(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = phoneStackCards?.view ?? view
        phonePresenter.present(alert, animated: true)
    }

    private func leavePhoneGame(showingStart: Bool = false) {
        phoneMode?.leave()
        AppDelegate.shared.phoneSession = nil
        phoneSubscriptions.removeAll()
        for (constraint, value) in savedPhoneConstraints { constraint.constant = value }
        savedPhoneConstraints.removeAll()
        if showingStart { AppRouter.showStart(); return }
        // Reinstantiate the unchanged storyboard to restore its normal gestures and bars.
        (view.window?.windowScene?.delegate as? SceneDelegate)?.window?.rootViewController = storyboard?.instantiateInitialViewController()
    }

    private var phonePresenter: UIViewController {
        var current: UIViewController = self
        while let next = current.presentedViewController, !next.isBeingDismissed { current = next }
        return current
    }

    private func showExistingCompanion(exitsToStart: Bool = false) {
        let originalState = try? JSONEncoder().encode(GameState.current)
        let app = AppDelegate.shared
        app.role = .player1
        app.transceiver.receive(GameState.self) { state, _ in
            DispatchQueue.main.async {
                guard !AppDelegate.shared.role.isBoard else { return }
                GameState.current.update(withValuesFrom: state)
            }
        }
        app.transceiver.peerConnected = { _ in app.sendCommand(.rebroadcast) }
        guard let playerSelect = UIStoryboard(name: "PlayerConnect", bundle: nil).instantiateInitialViewController() else { return }
        let controller = UINavigationController(rootViewController: playerSelect)
        do {
            playerSelect.navigationItem.leftBarButtonItem = UIBarButtonItem(title: exitsToStart ? "Exit" : "Battlefield", primaryAction: UIAction { [weak self] _ in
                if let originalState, let restored = try? JSONDecoder().decode(GameState.self, from: originalState) {
                    GameState.current.update(withValuesFrom: restored)
                }
                app.role = .board
                if exitsToStart { AppRouter.showStart() } else { self?.dismiss(animated: true) }
            })
        }
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
        app.sendCommand(.rebroadcast)
    }
}


/// The board's content view: a card laid out past its edges still receives touches (Phone Play's
/// field can be wider than the zoomed board, and UIKit only hit-tests subviews inside a view's bounds).
/// Where one of the opponent's cards is, for animating its moves. Hidden zones are a single spot.
enum PhoneOpponentZone: Equatable {
    case battlefield, stack, pile(Pile.Location)
    var isHidden: Bool {
        if case .pile(let location) = self { return location == .hand || location == .library || location == .sideboard }
        return false
    }
}

/// A card's drawn position: center, size and rotation in the board view's coordinates.
struct PhoneFlightGeometry {
    var center: CGPoint
    var size: CGSize
    var angle: CGFloat
    init(center: CGPoint, size: CGSize, angle: CGFloat) { self.center = center; self.size = size; self.angle = angle }
    init(rect: CGRect) { self.init(center: CGPoint(x: rect.midX, y: rect.midY), size: rect.size, angle: 0) }
}

struct PhoneOpponentMove {
    var card: CardInstance
    var from: PhoneOpponentZone
    var to: PhoneOpponentZone
    var start: PhoneFlightGeometry
}

final class PhoneBoardContentView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        return subviews.contains { !$0.isHidden && $0.alpha > 0.01 && $0.isUserInteractionEnabled && $0.frame.contains(point) }
    }
}

/// A label with room around its text, for the Rules-mode toast.
private final class PaddedToastLabel: UILabel {
    private let insets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let rect = super.textRect(forBounds: bounds.inset(by: insets), limitedToNumberOfLines: numberOfLines)
        return rect.inset(by: UIEdgeInsets(top: -insets.top, left: -insets.left, bottom: -insets.bottom, right: -insets.right))
    }
}
