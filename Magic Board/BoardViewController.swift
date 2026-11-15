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
  private var phoneStackButton: UIButton?
  private var phoneStackCards: UIHostingController<PhoneStackCardsView>?
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
      
      self.moveCardItemsToBattlefield(cardInstances.values, at: self.visibleBoardCenter)
      
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
    // During your combat, tapping one of your creatures marks or unmarks it as an attacker
    // (tapping or untapping it unless it has vigilance). The card menu can still just tap it.
    if let session = phoneMode, session.game.attackingPlayer == session.player,
       cardInstance.controllerIdentifier.value == session.player, cardInstance.isPhoneCreature,
       session.game.attachments[cardInstance.uuid] == nil, session.game.state.battlefield.value.contains(cardInstance) {
        session.send(.attack(cardInstance.uuid, tap: !cardInstance.hasVigilance))
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
        if let session = phoneMode, session.game.state[player: session.player].hand.cards.value.contains(cardInstance) {
            let controller = PhoneHandCardController(session: session, card: cardInstance)
            let navigation = UINavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .pageSheet
            present(navigation, animated: true)
            return
        }
        focusViewController?.dismiss(animated: true, completion: nil)

        struct InspectorPage {
            let card: CardInstance
            let image: UIViewController?
            let controls: [UIViewController]
        }
        var dismissInspector: () -> Void = {}
        func makePage(for cardInstance: CardInstance) -> InspectorPage {
            var controllers = SideTableViewController.SectionModel.viewControllerCombinations.compactMap { sections -> UIViewController? in
                guard let controller = storyboard?.instantiateViewController(identifier: "SideTableViewController") as? SideTableViewController else { return nil }
                controller.card = cardInstance
                controller.sectionModel = sections
                return controller
            }
            if let counters = storyboard?.instantiateViewController(identifier: "CountersViewController") as? CountersViewController {
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
                case .faceDown, .morph, .foretold: return []
                default: return CardService.shared.getRulings(oracleID: id)
                }
            }()
            if !rulings.isEmpty { controllers.append(UIHostingController(rootView: RulingsListView(rulings: rulings))) }
            let image = storyboard?.instantiateViewController(identifier: "CardImageViewController") as? CardImageViewController
            var showCard = cardInstance.representation.card.language == .english
            if case .faceDown = cardInstance.representation { showCard = true }
            if showCard { image?.cardInstance = cardInstance }
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
        present(host, animated: true)
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
		guard presentedViewController == nil else { return }
    
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
    if phoneMode != nil {
      alert.addAction(BoardMenuAction(title: "Connection…", style: .default) { [weak self] _ in self?.showConnectionOptions() })
    }
    alert.addAction(BoardMenuAction(title: "Load Deck / JumpStart / Jump In", style: .default) { [weak self] _ in self?.showPhoneDeckPicker() })
    alert.addAction(BoardMenuAction(title: "Preloaded Games & Artwork", style: .default) { [weak self] _ in
      let games = UIHostingController(rootView: NavigationStack { OfflineGamesView(close: { [weak self] in self?.dismiss(animated: true) }) })
      games.view.accessibilityHint = PhoneSheet.providesCloseHint // has its own Done
      self?.present(games, animated: true)
    })
		
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
    
    let dropModeAction = BoardMenuAction(title: "Drop Cards \(self.dropFaceUp ? "Face-Down" : "Face-Up")", style: .default) { _ in
      self.dropFaceUp.toggle()
    }
    alert.addAction(dropModeAction)
    
    let toggleSelectionAction = BoardMenuAction(title: "\(isSelectionEnabled ? "Disable" : "Enable") Selection", style: .default) { _ in
      self.isSelectionEnabled.toggle()
      self.updateSelection()
    }
    alert.addAction(toggleSelectionAction)
    
    let player1TopCardAction = BoardMenuAction(title: "Reveal Player 1 Library Top Card", style: .default) { _ in
      GameState.current.effectivePile(.library, player: .a).isTopCardRevealed.mutate {
        $0.toggle()
      }
      try? GameState.current.save()
    }
    alert.addAction(player1TopCardAction)
    
    if !GameState.current.player2.isHidden {
      let player2TopCardAction = BoardMenuAction(title: "Reveal Player 2 Library Top Card", style: .default) { _ in
        GameState.current.effectivePile(.library, player: .b).isTopCardRevealed.mutate {
          $0.toggle()
        }
        try? GameState.current.save()
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
    private enum PhoneDropIntent: Equatable { case attach(UUID), unattach, block(UUID), unblock }

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
        if blocker != nil, let target, phoneMode?.game.combat?.attackers.contains(target.uuid) == true {
            // Your creature over one of the opponent's attackers: block it.
            intent = target.uuid == blocking ? nil : .block(target.uuid)
        } else if blocking != nil, !phoneHandDropRegionContains(point) {
            intent = .unblock
        } else if let target {
            intent = target.uuid == parent ? nil : .attach(target.uuid)
        } else if parent != nil, !phoneHandDropRegionContains(point) {
            intent = .unattach
        } else {
            intent = nil
        }
        if let intent, intent == phoneAttachHover?.intent {
            if phoneAttachHover?.armed == true { showPhoneDropIntent(intent, at: point) } // follow the finger/relayouts
            return
        }
        clearPhoneAttachHover()
        guard let intent else { return }
        phoneAttachGeneration += 1
        let generation = phoneAttachGeneration
        phoneAttachHover = (intent, false, generation)
        // GCD's main queue also runs while UIKit tracks a drag (unlike a default-mode Timer).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, let hover = self.phoneAttachHover, hover.generation == generation else { return }
            self.phoneAttachHover?.armed = true
            UISelectionFeedbackGenerator().selectionChanged()
            self.showPhoneDropIntent(intent, at: self.phoneLastDragPoint ?? point)
        }
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
        if let target = armedPhoneBlockTarget(at: point, excluding: ids) {
            clearPhoneAttachHover()
            session.send(.block(id, target.uuid))
            return true
        }
        if phoneAttachHover?.armed == true, phoneAttachHover?.intent == .unblock, session.game.combat?.blockers[id] != nil {
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
        phoneAttachHover = nil
        phoneAttachIndicator?.removeFromSuperview()
        phoneAttachIndicator = nil
        phoneAttachLabel?.removeFromSuperview()
        phoneAttachLabel = nil
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
        label.font = .systemFont(ofSize: 13, weight: .semibold)
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
        case .attach(let id), .block(let id):
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
                view.addSubview(indicator)
                phoneAttachIndicator = indicator
            }
            indicator.layer.borderColor = color.cgColor
            indicator.layer.shadowColor = color.cgColor
            indicator.backgroundColor = color.withAlphaComponent(0.15)
            indicator.transform = .identity
            indicator.bounds.size = CGSize(width: geometry.size.width + 4, height: geometry.size.height + 4)
            indicator.center = geometry.center
            indicator.layer.cornerRadius = min(10, geometry.size.width * 0.05)
            indicator.transform = CGAffineTransform(rotationAngle: geometry.angle)
            // Under the card being dragged; the label floats above the target, over everything.
            if let preview = phoneDragPreview, preview.superview === view { view.insertSubview(indicator, belowSubview: preview) }
            else { view.bringSubviewToFront(indicator) }
            let label = phoneDropLabel(isBlock ? "Block" : "Attach")
            label.backgroundColor = color
            label.center = CGPoint(x: geometry.center.x, y: indicator.frame.minY - label.bounds.height / 2 - 6)
            view.bringSubviewToFront(label)
        case .unattach, .unblock:
            phoneAttachIndicator?.removeFromSuperview()
            phoneAttachIndicator = nil
            let label = phoneDropLabel(intent == .unblock ? "Stop Blocking" : "Unattach")
            label.backgroundColor = .systemBlue
            let top = phoneDragPreview.map { $0.frame.minY } ?? point.y - 50
            label.center = CGPoint(x: phoneDragPreview?.center.x ?? point.x, y: top - label.bounds.height / 2 - 6)
            view.bringSubviewToFront(label)
        }
    }

    /// Drops on the hand's visible area or the empty part of the local HUD band go to the hand.
    /// (The piles in the band have their own drop interactions and are hit first.)
    private func phoneHandDropRegionContains(_ point: CGPoint) -> Bool {
        guard phoneMode != nil, let container = localPhoneBar?.handContainerView,
              container.superview === view, !container.isHidden else { return false }
        let visibleTop = container.frame.minY + (container.phoneContentFrame?.minY ?? 0)
        let hudTop = phoneBarBackgrounds.count > 1 ? phoneBarBackgrounds[1].frame.minY : visibleTop
        return point.y >= min(visibleTop, hudTop) && point.y <= view.bounds.maxY
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
//			let imageView = UIImageView(image: image ?? #imageLiteral(resourceName: "mtg-card-back-png-1"))
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
    private func showConnectionOptions() {
        guard let session = phoneMode else { return }
        let alert = UIAlertController(title: "Connection", message: session.status, preferredStyle: .alert)
        if session.mode == .join { alert.addAction(.init(title: "Reconnect", style: .default) { _ in session.reconnect() }) }
        alert.addAction(.init(title: "View Stack (\(session.game.stack.count))", style: .default) { [weak self] _ in self?.showPhoneStack() })
        alert.addAction(.init(title: "Cancel", style: .cancel))
        present(alert, animated: true)
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
        session.onUpdate = { [weak self] in self?.refreshPhoneBoard() }
        session.$error.compactMap { $0 }.sink { [weak self, weak session] message in
            guard let self else { return }
            let alert = UIAlertController(title: session?.connected == false && message.localizedCaseInsensitiveContains("disconnected") ? "Disconnected" : "Game", message: message, preferredStyle: .alert)
            alert.addAction(.init(title: "OK", style: .default) { _ in session?.error = nil })
            self.phonePresenter.present(alert, animated: true)
        }.store(in: &phoneSubscriptions)
        for child in [bottomBarA, bottomBarB].compactMap({ $0 }) {
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
        }.store(in: &phoneSubscriptions)
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
        DispatchQueue.main.async { [weak self] in self?.presentPhonePacketChoices() }
        let cards = Array(session.game.cards.values)
        let fieldIDs = Set(session.game.state.battlefield.value.map(\.uuid) + session.game.stack.compactMap { $0.card?.uuid })
        let handIDs = Set(session.game.state[player: session.player].hand.cards.value.map(\.uuid))
        if let previousPhoneHandIDs, !previousPhoneHandIDs.subtracting(handIDs).isDisjoint(with: fieldIDs) {
            collapsePhoneHand()
        }
        previousPhoneHandIDs = handIDs
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
        phoneStackCards?.rootView = PhoneStackCardsView(items: session.game.stack, inspect: { [weak self] card in self?.focus(on: card, view: nil) })
        view.setNeedsLayout()
    }

    private func layoutPhoneBattlefield() {
        guard let session = phoneMode, view.bounds.width > 0 else { return }
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
        let barHeight: CGFloat = min(124, max(52, view.bounds.height * 0.12))
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
        let landHeight: CGFloat = showLandOrganizer ? min(120, max(54, view.bounds.height * 0.14)) : 0
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
        landOrganizerContainerView.accessibilityIdentifier = "phone-local-lands"
        landOrganizerContainerView.backgroundColor = .clear
        landOrganizer?.hideOrganizerBackground()
        opponentLandOrganizer?.hideOrganizerBackground()
        for child in [bottomBarA, bottomBarB].compactMap({ $0 }) { child.view.backgroundColor = .clear }
        for constraint in view.constraints {
            let first = constraint.firstItem as? UIView
            let second = constraint.secondItem as? UIView
            if (first === player1BarContainerView || first === player2BarContainerView) && constraint.firstAttribute == .leading {
                rememberPhoneConstraint(constraint); constraint.constant = safe.left - (constraint.secondItem is UILayoutGuide ? view.safeAreaInsets.left : 0)
            }
            if (second === player1BarContainerView || second === player2BarContainerView) && constraint.firstAttribute == .trailing {
                rememberPhoneConstraint(constraint); constraint.constant = safe.right - (constraint.firstItem is UILayoutGuide ? view.safeAreaInsets.right : 0)
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
        translate(landOrganizerContainerView, x: safe.left + 8 - landBase.minX, y: bottomHUDTop - landGap - landHeight - landBase.minY)
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
        let opponentLandHeight = min(124, max(52, view.bounds.height * 0.14))
        let landRowTop = top.frame.maxY + landGap
        (phoneOpponentLandContainer ?? opponentLandOrganizer?.view)?.frame = CGRect(x: safe.left + 8, y: landRowTop, width: view.bounds.width - safe.left - safe.right - 100, height: opponentLandHeight)
        let topY = landRowTop + opponentLandHeight
        let bottomY = bottomHUDTop - landHeight - landGap
        let rowVisible = CGRect(x: safe.left + 8, y: topY + 4, width: max(100, view.bounds.width - safe.left - safe.right - 16), height: max(90, bottomY - topY - 8))
        // Column layout: land rows only occupy the left of their rows. When their lands are narrow,
        // the battlefield can use the full height between the bars beside them (much larger cards on
        // short screens). It stays clear of the compact hand's top edge in the middle.
        let measuredLandMaxX = currentPhoneLandMaxX() ?? (safe.left + 8)
        phoneLandContentMaxX = measuredLandMaxX
        // Tapping a land splits its stack (wider row). Reserve one stack of slack and never shrink
        // within a game, so land taps don't move the battlefield.
        let landStackWidth = max(landHeight, opponentLandHeight) * 480 / 420 * 1.5 + 14 // a tapped (rotated) stack is wider than a card
        if phoneLandReservation?.gameID != session.game.id { phoneLandReservation = nil }
        if measuredLandMaxX > (phoneLandReservation?.maxX ?? -.infinity) {
            phoneLandReservation = (session.game.id, measuredLandMaxX + landStackWidth)
        }
        let landMaxX = phoneLandReservation?.maxX ?? measuredLandMaxX
        let handHeight = min(360, max(150, min(view.bounds.width, view.bounds.height) * 0.40))
        let columnTop = top.frame.maxY + landGap
        let columnBottom = min(bottomHUDTop - landGap, view.bounds.height - handHeight * 0.44 - 4)
        let columnX = landMaxX + 12
        // Symmetric about the screen center, so the column layout's cards stay centered like the row layout's.
        let columnInset = max(columnX, safe.right + 8)
        let columnVisible = CGRect(x: columnInset, y: columnTop, width: max(100, view.bounds.width - 2 * columnInset), height: max(90, columnBottom - columnTop))
        var descriptors: [(Player.Identifier, PhoneBattlefieldLayout.Row)] = [(session.opponent, .support), (session.opponent, .creatures), (session.player, .creatures)]
        let ownSupport = PhoneBattlefieldLayout.groups(in: session.game, player: session.player, row: .support).filter {
            !(showLandOrganizer && landOrganizer?.shouldIncludeCard($0.top) == true)
        }
        if !ownSupport.isEmpty { descriptors.append((session.player, .support)) }
        // Identical non-land permanents are laid out one by one when that fits without shrinking
        // the cards or paging a row; otherwise (or for 5+ copies) they stack. Lands keep their stacking.
        var splitDuplicates = false
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
        struct FieldPlan { var leftSpill: CGFloat; var bottomSpill: CGFloat; var useColumn: Bool; var visible: CGRect; var extent: CGFloat }
        func plan() -> FieldPlan {
            let largestRow = descriptors.map { groups(for: $0.0, row: $0.1, ignoringTapped: true).count }.max() ?? 0
            // A row includes its fanned duplicates and attachments. Keep that entire
            // footprint inside its player's half, clear of both land organizers.
            let attachmentCount = descriptors.flatMap { groups(for: $0.0, row: $0.1) }
                .map { session.game.attachedCards(to: $0.top.uuid).count }.max() ?? 0
            // Fanned duplicates (up to 3 layers at 22/18 per layer) and attachments only reserve space when present.
            let maxLayers = min(3, descriptors.flatMap { groups(for: $0.0, row: $0.1) }.map(\.cards.count).max() ?? 1)
            let bottomSpill: CGFloat = max(CGFloat(maxLayers - 1) * 18, attachmentCount > 0 ? 70 + CGFloat(attachmentCount - 1) * 25 : 0) + rotationSpill
            let leftSpill: CGFloat = max(CGFloat(maxLayers - 1) * 22, attachmentCount > 0 ? 85 + CGFloat(attachmentCount - 1) * 30 : 0) + rotationSpill
            func extent(in rect: CGRect) -> CGFloat {
                let heightFit = max(24, (rect.height / 2 - 4) / (1 + (topSpill + bottomSpill) / 500))
                return min(heightFit, PhoneBattlefieldLayout.cardExtent(screenWidth: rect.width, screenHeight: view.bounds.height, groups: largestRow))
            }
            // The column must fit its largest row without paging (cards shrink within it if needed);
            // otherwise the row layout (which pages dense rows) is used.
            let cellUnits = 520 + leftSpill + rotationSpill
            func fittedColumnExtent() -> CGFloat {
                var fitted = extent(in: columnVisible)
                let needed = CGFloat(max(1, largestRow)) * cellUnits - 20
                for _ in 0..<2 {
                    let stackInset = session.game.stack.isEmpty ? 0 : max(86, fitted * 1.12)
                    let available = columnVisible.width - 2 * stackInset
                    if needed * fitted / 500 > available { fitted = max(24, available * 500 / needed) }
                }
                return fitted
            }
            let useColumn = fittedColumnExtent() > extent(in: rowVisible) * 1.05
            return FieldPlan(leftSpill: leftSpill, bottomSpill: bottomSpill, useColumn: useColumn,
                             visible: useColumn ? columnVisible : rowVisible,
                             extent: useColumn ? fittedColumnExtent() : extent(in: rowVisible))
        }
        /// Mirrors the row/lane sizing below: true when no row of this plan would page.
        func fitsWithoutPaging(_ plan: FieldPlan) -> Bool {
            let zoom = plan.extent / 500
            let stackInset = session.game.stack.isEmpty ? 0 : max(86, plan.extent * 1.12) / zoom
            let fieldWidth = max(500, plan.visible.width / zoom - 2 * stackInset)
            let cellWidth = 520 + plan.leftSpill + rotationSpill
            return descriptors.allSatisfy { player, row in
                let count = groups(for: player, row: row).count
                let supportCount = groups(for: player, row: .support).count
                let hasCreatures = !groups(for: player, row: .creatures).isEmpty
                let supportWidth = supportCount > 0 && hasCreatures
                    ? min(max(cellWidth, min(fieldWidth * 0.35, CGFloat(supportCount) * cellWidth)), fieldWidth - cellWidth) : 0
                let rowWidth = supportWidth > 0 && row == .support ? supportWidth : fieldWidth - supportWidth
                return count <= max(1, Int((rowWidth + 20) / cellWidth))
            }
        }
        let stackedPlan = plan()
        splitDuplicates = true
        let splitPlan = plan()
        splitDuplicates = splitPlan.extent >= stackedPlan.extent - 0.5 && fitsWithoutPaging(splitPlan)
        let fieldPlan = splitDuplicates ? splitPlan : stackedPlan
        let leftSpill = fieldPlan.leftSpill
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
        let stackScreenWidth = max(86, extent * 1.12)
        let stackWidth = stackScreenWidth / scrollView.zoomScale
        let fieldInset = session.game.stack.isEmpty ? CGFloat.zero : stackWidth
        let field = CGRect(x: world.minX + fieldInset, y: world.minY, width: max(500, world.width - 2 * fieldInset), height: world.height)
        for button in phoneGroupButtons { button.removeFromSuperview() }
        phoneGroupButtons.removeAll()
        for cardView in board.subviews.compactMap({ $0 as? MiniCardView }) {
            cardView.isHidden = true
            for gesture in cardView.gestureRecognizers ?? [] where gesture is UIPanGestureRecognizer { gesture.isEnabled = true }
            for interaction in cardView.interactions.compactMap({ $0 as? UIDragInteraction }) { interaction.isEnabled = true }
            // Holding opens the inspector only after 0.65 s without moving; any drag wins first.
            for interaction in cardView.interactions.compactMap({ $0 as? UIContextMenuInteraction }) { cardView.removeInteraction(interaction) }
            if !(cardView.gestureRecognizers ?? []).contains(where: { $0.name == "phone-hold" }) {
                let hold = UILongPressGestureRecognizer(target: self, action: #selector(phoneCardHeld(_:)))
                hold.name = "phone-hold"
                hold.minimumPressDuration = 0.65
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
            cardView.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Inspect", actionHandler: { [weak self, weak cardView] _ in
                guard let self, let cardView else { return false }
                self.focus(on: cardView.cardInstance, view: cardView)
                return true
            })]
        }
        for descriptor in descriptors {
            let allGroups = groups(for: descriptor.0, row: descriptor.1)
            let key = descriptor.0.rawValue + (descriptor.1 == .creatures ? "creatures" : "support")
            let supportCount = groups(for: descriptor.0, row: .support).count
            let hasCreatures = !groups(for: descriptor.0, row: .creatures).isEmpty
            let cellWidth = 520 + leftSpill + rotationSpill // 20-unit gap; less padding between cards
            // Support permanents and creatures use separate horizontal lanes in
            // the same player band. Four fractional rows could overlap vertically.
            let supportWidth = supportCount > 0 && hasCreatures
                ? min(max(cellWidth, min(field.width * 0.35, CGFloat(supportCount) * cellWidth)), field.width - cellWidth)
                : 0
            let rowX = descriptor.1 == .creatures ? field.minX + supportWidth : field.minX
            let rowWidth = supportWidth > 0 && descriptor.1 == .support ? supportWidth : field.width - supportWidth
            // A paging row reserves room at its end for the page button, so it never covers a card.
            let pageReserve = 76 / max(0.01, scrollView.zoomScale)
            let pages = allGroups.count > max(1, Int((rowWidth + 20) / cellWidth))
            let layoutWidth = pages ? max(cellWidth, rowWidth - pageReserve) : rowWidth
            let capacity = max(1, Int((layoutWidth + 20) / cellWidth))
            let startIndex = min(phoneRowOffsets[key] ?? 0, max(0, allGroups.count - 1))
            let pageGroups = Array(allGroups.dropFirst(startIndex).prefix(capacity))
            let fraction: CGFloat = descriptor.0 == session.player ? 0.75 : 0.25
            let centerY = field.minY + field.height * fraction - (bottomSpill - topSpill) / 2
            let row = CGRect(x: rowX, y: centerY - 250, width: layoutWidth, height: 500)
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
            let spacing = cellWidth
            let width = CGFloat(pageGroups.count) * cellWidth - 20
            // Creature rows center on the screen (not on the lane beside the lands), sliding
            // toward the lane only as far as needed to stay clear of the lands.
            var start = row.minX
            if descriptor.1 == .creatures {
                let screenMidX = board.convert(CGPoint(x: view.bounds.midX, y: 0), from: view).x
                let centered = screenMidX - leftSpill - 250 - CGFloat(max(0, pageGroups.count - 1)) * spacing / 2
                start = min(max(centered, row.minX), max(row.minX, row.minX + layoutWidth - width))
            }
            for (column, group) in pageGroups.enumerated() {
                let point = CGPoint(x: start + leftSpill + 250 + CGFloat(column) * spacing, y: row.midY)
                for (layer, card) in group.cards.prefix(3).enumerated().reversed() {
                    if let cardView = cardView(for: card) {
                        cardView.isHidden = false
                        cardView.center = CGPoint(x: point.x - CGFloat(layer) * 22, y: point.y + CGFloat(layer) * 18)
                        board.bringSubviewToFront(cardView)
                    }
                }
                if group.cards.count > 1 { addPhoneBadge("x\(group.cards.count)", at: CGPoint(x: point.x + 160, y: point.y - 190), cards: group.cards) }
                let attached = session.game.attachedCards(to: group.top.uuid)
                for (layer, attachment) in attached.enumerated() {
                    if let cardView = cardView(for: attachment) {
                        cardView.isHidden = false
                        cardView.center = CGPoint(x: point.x - 85 - CGFloat(layer) * 30, y: point.y + 70 + CGFloat(layer) * 25)
                        if let parent = self.cardView(for: group.top) { board.insertSubview(cardView, belowSubview: parent) }
                    }
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
        }
        if phoneStackCards == nil {
            let host = UIHostingController(rootView: PhoneStackCardsView(items: session.game.stack, inspect: { [weak self] card in self?.focus(on: card, view: nil) }))
            host.view.backgroundColor = .clear
            addChild(host); view.addSubview(host.view); host.didMove(toParent: self)
            phoneStackCards = host
        }
        phoneStackCards?.view.frame = CGRect(x: visible.maxX - stackScreenWidth, y: visible.minY + 38, width: stackScreenWidth, height: max(80, visible.height - 38))
        phoneStackCards?.view.isHidden = session.game.stack.isEmpty
        if phoneStackButton == nil {
            let button = UIButton(type: .system)
            button.addAction(UIAction { [weak self] _ in self?.showPhoneStack() }, for: .touchUpInside)
            view.addSubview(button); phoneStackButton = button
        }
        phoneStackButton?.isHidden = session.game.stack.isEmpty
        phoneStackButton?.setTitle("Stack · \(session.game.stack.count)", for: .normal)
        phoneStackButton?.titleLabel?.font = .systemFont(ofSize: max(14, min(28, view.bounds.height * 0.037)))
        phoneStackButton?.frame = CGRect(x: visible.maxX - stackScreenWidth, y: visible.minY, width: stackScreenWidth, height: 36)
        phoneStackButton?.accessibilityIdentifier = "phone-stack"
        updatePhoneAttackIndicators()
        view.bringSubviewToFront(bottom)
        for badge in phoneGroupButtons where badge.superview === board { board.bringSubviewToFront(badge) }
        layoutPhoneHandOverlay()
        if let shield = phoneHandShield, !shield.isHidden { view.bringSubviewToFront(shield) }
    }

    private func updatePhoneAttackIndicators() {
        guard let session = phoneMode else { return }
        updatePhoneCombatGlows(session)
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
            indicator.bounds.size = CGSize(width: min(72, max(28, frame.width * 0.6)), height: 20)
            indicator.center = CGPoint(x: frame.midX, y: local ? frame.minY - 13 : frame.maxY + 13)
            indicator.transform = local ? .identity : CGAffineTransform(rotationAngle: .pi)
            view.bringSubviewToFront(indicator)
        }
    }

    private func updatePhoneCombatGlows(_ session: PhoneGameSession) {
        let combat = session.game.combat
        var wanted: [UUID: UIColor] = [:]
        for id in combat?.attackers ?? [] { wanted[id] = .systemOrange }
        for id in combat?.blockers.keys.map({ $0 }) ?? [] { wanted[id] = .systemBlue }
        for (id, glow) in phoneCombatGlows where wanted[id] == nil {
            glow.removeFromSuperview()
            phoneCombatGlows[id] = nil
        }
        for (id, color) in wanted {
            guard let card = session.game.cards[id], let geometry = phoneCardGeometry(card) else {
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
            glow.accessibilityValue = color == .systemOrange ? "Attacking" : "Blocking"
            // Just above the battlefield: under the HUD, the hand and any dragged card.
            if glow.superview !== view || view.subviews.firstIndex(of: glow) != (view.subviews.firstIndex(of: scrollView) ?? -1) + 1 {
                view.insertSubview(glow, aboveSubview: scrollView)
            }
            glow.transform = .identity
            glow.bounds.size = CGSize(width: geometry.size.width + 3, height: geometry.size.height + 3)
            glow.center = geometry.center
            glow.layer.cornerRadius = min(10, geometry.size.width * 0.05)
            glow.transform = CGAffineTransform(rotationAngle: geometry.angle)
        }
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

    private func layoutPhoneHandOverlay() {
        adoptPhoneHandContainer()
        guard let bar = localPhoneBar, let hand = bar.handViewController,
              let container = bar.handContainerView, container.superview === view else { return }
        let shortSide = min(view.bounds.width, view.bounds.height)
        let scale = min(2.4, max(1, shortSide / 375))
        let margin = max(36 * scale, max(view.safeAreaInsets.left, view.safeAreaInsets.right) + 12)
        let height = min(360, max(150, shortSide * 0.40))
        let width = max(0, view.bounds.width - 2 * margin)
        // Always derived from the current bounds; the bottom 8% intentionally sits below the screen edge.
        let frame = CGRect(x: margin, y: view.bounds.maxY - height * 0.92, width: width, height: height)
        if container.transform != .identity { container.transform = .identity }
        defer {
            // A card being dragged (and its Attach glow) always draws above the hand.
            if let indicator = phoneAttachIndicator { view.bringSubviewToFront(indicator) }
            if let preview = phoneDragPreview { view.bringSubviewToFront(preview) }
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
    private func addPhoneBadge(_ text: String, at point: CGPoint, cards: [CardInstance]) {
        let button = UIButton(type: .system)
        button.setTitle(text, for: .normal)
        let scale = max(0.04, scrollView.zoomScale)
        let uiScale = min(2.4, max(1, min(view.bounds.width, view.bounds.height) / 375))
        let font = UIFont(name: "Beleren2016-Bold", size: 14 * uiScale / scale) ?? .boldSystemFont(ofSize: 14 * uiScale / scale)
        button.titleLabel?.font = font
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        button.layer.cornerRadius = 4 * uiScale / scale
        let measured = (text as NSString).size(withAttributes: [.font: font])
        let size = CGSize(width: ceil(measured.width) + 16 * uiScale / scale, height: ceil(measured.height) + 8 * uiScale / scale)
        button.frame = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
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
        let options = Command.PlayCardParameters.options(for: card)
        if options.count == 1 { session.send(.playCard(options[0].parameters)); completion?(true); return }
        let chooser = UIAlertController(title: "Play", message: card.representation.name, preferredStyle: .actionSheet)
        for option in options {
            chooser.addAction(.init(title: option.title, style: .default) { _ in session.send(.playCard(option.parameters)); completion?(true) })
        }
        chooser.addAction(.init(title: "Cancel", style: .cancel) { _ in completion?(false) })
        chooser.popoverPresentationController?.sourceView = view
        chooser.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(chooser, animated: true)
    }

    private func clearPhoneDragPreview() {
        if let card = phoneDraggedCard { cardView(for: card)?.alpha = 1 }
        phoneDragPreview?.removeFromSuperview()
        phoneDragPreview = nil
        phoneDraggedCard = nil
        clearPhoneAttachHover()
    }

    private func movePhoneCardPreview(_ card: CardInstance, to point: CGPoint, sourceSize: CGSize? = nil) {
        guard phoneMode?.canAct == true else { return }
        defer { updatePhoneAttachHover(at: point, excluding: [card.uuid]) }
        if phoneDraggedCard?.uuid != card.uuid {
            clearPhoneDragPreview()
            phoneDraggedCard = card
            guard let source = cardView(for: card) else { return }
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
                let arrow = UIImageView(image: UIImage(named: "tap")?.withRenderingMode(.alwaysTemplate))
                arrow.tintColor = .white; arrow.alpha = 0.65; arrow.contentMode = .scaleAspectFit
                arrow.frame = preview.bounds.insetBy(dx: size.width * 0.27, dy: size.height * 0.27)
                preview.addSubview(arrow)
            }
            preview.alpha = 0.9; preview.isUserInteractionEnabled = false
            view.addSubview(preview); phoneDragPreview = preview
            cardView(for: card)?.alpha = 0
        }
        phoneDragPreview?.center = point
    }
    // MARK: Arena-style hand drag

    private struct PhoneHandDragState {
        let card: CardInstance
        /// Where it was picked up (view coordinates) and its height in the fan.
        let startCenter: CGPoint
        let startHeight: CGFloat
        /// From the finger to the card's center when it was picked up.
        let grab: CGVector
        /// Current scale relative to the hand size (0 until the first move straightens it).
        var scale: CGFloat = 0
        /// Released and animating to where it went.
        var landing = false
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

    /// The card lifts out of the fan exactly where it was drawn (same size, rotation and cost),
    /// and the rest of the hand collapses.
    private func beginPhoneHandCardDrag(_ card: CardInstance, start: PhoneHandCardGeometry, at point: CGPoint) {
        let presentation = localPhoneBar?.handViewController?.phonePresentation
        guard phoneMode?.canAct == true else { presentation?.endDrag(); return }
        if phoneHandDrag != nil { finishPhoneHandLanding() }
        clearPhoneDragPreview()
        let center = view.convert(start.center, from: view.window)
        let host = UIHostingController(rootView: PhoneHandCardFace(card: card, height: start.size.height))
        if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.accessibilityIdentifier = "phone-hand-drag-preview"
        host.view.bounds = CGRect(origin: .zero, size: start.size)
        host.view.center = center
        host.view.transform = CGAffineTransform(rotationAngle: start.angle)
        host.view.layer.shadowColor = UIColor.black.cgColor
        host.view.layer.shadowOpacity = 0.55
        host.view.layer.shadowRadius = 10
        host.view.layer.shadowOffset = CGSize(width: 0, height: 6)
        view.addSubview(host.view)
        phoneHandPreviewHost = host
        phoneDragPreview = host.view
        phoneDraggedCard = card
        phoneHandDrag = PhoneHandDragState(card: card, startCenter: center, startHeight: start.size.height,
                                           grab: CGVector(dx: center.x - point.x, dy: center.y - point.y))
        collapsePhoneHand()
    }

    /// Follows the finger: full hand size over the hand, battlefield size over the battlefield,
    /// growing and shrinking (and straightening) as it crosses between them.
    private func movePhoneHandCardPreview(_ card: CardInstance, to point: CGPoint) -> Bool {
        guard var drag = phoneHandDrag, drag.card.uuid == card.uuid, !drag.landing,
              let preview = phoneDragPreview else { return phoneHandDragRegionContains(point) }
        let overHand = phoneHandDragRegionContains(point)
        let scale = overHand ? 1 : min(1, phoneBattlefieldCardHeight / drag.startHeight)
        // The point that was grabbed stays under the finger, at the card's current scale.
        preview.center = CGPoint(x: point.x + drag.grab.dx * scale, y: point.y + drag.grab.dy * scale)
        if drag.scale != scale {
            drag.scale = scale
            phoneHandDrag = drag
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                preview.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
        view.bringSubviewToFront(preview)
        if overHand { clearPhoneAttachHover() } else { updatePhoneAttachHover(at: point, excluding: [card.uuid]) }
        return overHand
    }

    private func finishPhoneHandCardDrag(_ card: CardInstance, at point: CGPoint, handIndex: Int?, slot: PhoneHandCardGeometry?) {
        guard let drag = phoneHandDrag, drag.card.uuid == card.uuid, !drag.landing else {
            localPhoneBar?.handViewController?.phonePresentation.endDrag()
            return
        }
        let attachTarget = handIndex == nil ? armedPhoneAttachTarget(at: point, excluding: [card.uuid]) : nil
        clearPhoneAttachHover()
        guard let session = phoneMode, session.canAct else { returnPhoneHandPreview(); return }
        for bar in [bottomBarA, bottomBarB].compactMap({ $0 }) {
            let targets: [(UIView?, Pile.Location)] = [(bar.graveyardPileView, .graveyard), (bar.exilePileView, .exile), (bar.libraryPileView, .library)]
            for (target, location) in targets {
                guard let target, !target.isHidden,
                      target.point(inside: target.convert(point, from: view), with: nil) else { continue }
                session.send(.moveToPlayer(card.uuid, location, bar.player.identifier, bottom: false))
                let frame = view.convert(target.bounds, from: target)
                landPhoneHandPreview(center: CGPoint(x: frame.midX, y: frame.midY), height: frame.height * 0.8, angle: 0, fade: true)
                return
            }
        }
        if let handIndex {
            var ids = session.game.state[player: session.player].hand.cards.value.map(\.uuid)
            if let from = ids.firstIndex(of: card.uuid) {
                ids.remove(at: from)
                ids.insert(card.uuid, at: min(max(0, handIndex), ids.count))
                if ids != session.game.state[player: session.player].hand.cards.value.map(\.uuid) { session.send(.reorderHand(ids)) }
            } else {
                // A commander dropped on the hand goes to the hand.
                session.send(.moveToPlayer(card.uuid, .hand, session.player, bottom: false))
            }
            if let slot {
                landPhoneHandPreview(center: view.convert(slot.center, from: view.window), height: slot.size.height, angle: slot.angle)
            } else {
                finishPhoneHandLanding()
            }
            return
        }
        if let attachTarget {
            session.send(.attachDroppedCard(card.uuid, attachTarget.uuid))
            flyPhoneHandPreviewToBoard(card)
            return
        }
        playPhoneCard(card, session: session) { [weak self] played in
            if played { self?.flyPhoneHandPreviewToBoard(card) } else { self?.returnPhoneHandPreview() }
        }
    }

    /// Zooms the dropped card from where it was released onto the spot it was added at, once the
    /// battlefield (or land row, or stack) shows it.
    private func flyPhoneHandPreviewToBoard(_ card: CardInstance, attempt: Int = 0) {
        guard let drag = phoneHandDrag, drag.card.uuid == card.uuid, phoneDragPreview != nil else { return }
        phoneHandDrag?.landing = true
        view.layoutIfNeeded()
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
            landPhoneHandPreview(center: CGPoint(x: rect.midX, y: rect.midY), height: rect.height, angle: 0, crossfade: true)
            return
        }
        if phoneMode?.game.stack.contains(where: { $0.card?.uuid == card.uuid }) == true, let button = phoneStackButton, !button.isHidden {
            landPhoneHandPreview(center: CGPoint(x: button.frame.midX, y: button.frame.midY), height: button.frame.height, angle: 0, fade: true)
            return
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
    ///   - crossfade: dissolves the card into what it lands on during the second half of the flight
    ///     (`target`, faded in from transparent, or a land already drawn underneath).
    private func landPhoneHandPreview(center: CGPoint, height: CGFloat, angle: CGFloat, fade: Bool = false,
                                      crossfade: Bool = false, hiding target: UIView? = nil) {
        guard let preview = phoneDragPreview, let drag = phoneHandDrag else { finishPhoneHandLanding(); return }
        phoneHandDrag?.landing = true
        target?.alpha = 0
        let scale = height / drag.startHeight
        let duration = 0.32
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
            preview.center = center
            preview.transform = CGAffineTransform(rotationAngle: angle).scaledBy(x: scale, y: scale)
            preview.layer.shadowOpacity = 0
            if fade { preview.alpha = 0 }
        } completion: { [weak self] _ in
            target?.alpha = 1
            guard self?.phoneHandDrag?.card.uuid == drag.card.uuid else { return }
            self?.finishPhoneHandLanding()
        }
        if crossfade {
            UIView.animate(withDuration: duration * 0.55, delay: duration * 0.4, options: [.curveEaseInOut, .beginFromCurrentState]) {
                preview.alpha = 0
                target?.alpha = 1
            }
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
        phoneHandDrag = nil
        phoneHandPreviewHost = nil
        clearPhoneDragPreview()
        localPhoneBar?.handViewController?.phonePresentation.endDrag()
    }

    private func finishPhoneCardDrag(_ card: CardInstance, at point: CGPoint) {
        defer { clearPhoneDragPreview() }
        guard let session = phoneMode else { return }
        if performPhoneCombatDrop(at: point, ids: [card.uuid]) { return }
        for bar in [bottomBarA, bottomBarB].compactMap({ $0 }) {
            let targets: [(UIView?, Pile.Location)] = [(bar.graveyardPileView, .graveyard), (bar.exilePileView, .exile), (bar.libraryPileView, .library), (bar.handContainerView, .hand)]
            for (target, location) in targets {
                guard let target, !target.isHidden,
                      target.point(inside: target.convert(point, from: view), with: nil) else { continue }
                session.send(.moveToPlayer(card.uuid, location, bar.player.identifier, bottom: false))
                return
            }
        }
        if phoneHandDropRegionContains(point) {
            session.send(.moveToPlayer(card.uuid, .hand, session.player, bottom: false))
            return
        }
        if let target = armedPhoneAttachTarget(at: point, excluding: [card.uuid]) {
            session.send(.attachDroppedCard(card.uuid, target.uuid))
        } else if phoneUnattachArmed {
            session.send(.attach(card.uuid, nil))
        }
    }
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

    private func showPhoneDeckPicker() {
        let player = phoneMode?.player ?? .a
        let host = UIHostingController(rootView: NavigationStack {
            LoadDeckView(startPacketGame: { [weak self] kind, set in
                self?.dismiss(animated: true) { [weak self] in self?.phoneMode?.send(.startPackets(kind: kind, set: set)) }
            }, playerIdentifier: player, chooseListFile: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.loadDeckPlayerIdentifier = player
                    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText])
                    picker.delegate = self
                    self?.present(picker, animated: true)
                }
            }, dismiss: { [weak self] in self?.dismiss(animated: true) }).navigationTitle("Load Deck")
        })
        host.modalPresentationStyle = .formSheet
        present(host, animated: true)
    }

    private func showPhoneStack() {
        guard let phoneMode else { return }
        let controller = PhoneStackController(session: phoneMode)
        controller.inspect = { [weak self, weak controller] card in
            controller?.dismiss(animated: true) { [weak self] in self?.focus(on: card, view: nil) }
        }
        present(UINavigationController(rootViewController: controller), animated: true)
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
