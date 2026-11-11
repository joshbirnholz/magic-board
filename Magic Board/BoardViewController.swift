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
	
	@IBOutlet weak var scrollView: UIScrollView!
	@IBOutlet weak var board: UIView!
	@IBOutlet weak var boardWidthConstraint: NSLayoutConstraint!
	
	@IBOutlet weak var player1BarContainerView: UIView!
	@IBOutlet weak var player2BarContainerView: UIView!
  @IBOutlet weak var landOrganizerContainerView: UIView!
	
	weak var focusViewController: UIViewController?
  
  private var isSelectionEnabled: Bool = true
  
  
  var dropFaceUp: Bool = true
  
  @AppStorage("showLandOrganizer") var showLandOrganizer: Bool = true
	
	var loadDeckPlayerIdentifier: Player.Identifier?
	
	//	var cards: [MiniCardView: CardInstance] = [:]
	
	private let bag = DisposeBag()
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
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
  
  private var bottomBarA: BottomBarViewController?
  private var bottomBarB: BottomBarViewController?
  private var landOrganizer: LandOrganizerViewController?
  
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
    
    cardInstance.isTapped.toggle()
    try? GameState.current.save()
  }
  
  private func tapUnTap() {
    
  }
	
  fileprivate func addCardViewToBattlefield(for cardInstance: CardInstance) {
    guard let point = cardInstance.center.value else { return }
    
    if let cardView = self.cardView(for: cardInstance) {
      cardView.center = point
      return
    }
		
		let cardView = MiniCardView(frame: CGRect(x: point.x, y: point.y, width: 500, height: 500))
		
		cardView.cardInstance = cardInstance
    
    // This is buggy!
    if !dropFaceUp {
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
					guard var center = cardInstance.center.value else { return }
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
		
		focusViewController?.dismiss(animated: true, completion: nil)
		
		class CustomTabBarController: UITabBarController {
			weak var cardInstance: CardInstance?
			
			override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
				if let cardInstance = cardInstance, let index = tabBar.items?.firstIndex(of: item) {
					cardInstance.previouslyViewedFocusIndex = index
				}
			}
		}
		
		let tabBarController = CustomTabBarController()
		var viewControllers: [UIViewController] = []
    
    viewControllers.append(contentsOf: SideTableViewController.SectionModel.viewControllerCombinations.compactMap { sections in
			guard let viewController = storyboard?.instantiateViewController(identifier: "SideTableViewController") as? SideTableViewController else { return nil }
			
			viewController.card = cardInstance
			viewController.sectionModel = sections
      
      return viewController
			
//			let navigationController = UINavigationController(rootViewController: viewController)
//			navigationController.tabBarItem = UITabBarItem(title: sections.last?.title, image: sections.last?.tabBarImage, selectedImage: nil)
//			return navigationController
		})
		
		if let countersViewController = storyboard?.instantiateViewController(identifier: "CountersViewController") as? CountersViewController {
			
			countersViewController.cardInstance = cardInstance
      viewControllers.append(countersViewController)
			
//			let navigationController = UINavigationController(rootViewController: countersViewController)
//			navigationController.tabBarItem = UITabBarItem(title: "Counters", image: nil, selectedImage: nil)
//			viewControllers.append(navigationController)
		}
		
		struct RulingsListView: View {
			@State var rulings: [MTGRuling]
			
			var body: some View {
        Text("Rulings")
          .font(.headline)
          .multilineTextAlignment(.center)
          .padding()
				List {
					ForEach(rulings, id: \.self) { ruling in
						VStack(alignment: .leading) {
							Text(ruling.comment).font(.system(Font.TextStyle.subheadline))
							Text(ruling.publishedAt).italic().foregroundColor(Color.secondary)
						}.padding([.top, .bottom], 4)
					}
				}.listStyle(InsetGroupedListStyle())
				.environment(\.horizontalSizeClass, .regular)
			}
		}
		
		let rulings: [MTGRuling] = {
			guard let id = cardInstance.representation.card.oracleID else { return [] }
			if case .faceDown(_) = cardInstance.representation {
				return []
			}
			if case .morph(_) = cardInstance.representation {
				return []
			}
			if case .foretold(_) = cardInstance.representation {
				return []
			}
			
			return CardService.shared.getRulings(oracleID: id)
		}()
    
    if !rulings.isEmpty {
      let rulingsViewController = UIHostingController(rootView: RulingsListView(rulings: rulings))
      viewControllers.append(rulingsViewController)
    }
		
		var shouldShowRealCard = cardInstance.representation.card.language == .english
		if case .faceDown(_) = cardInstance.representation {
			shouldShowRealCard = true
		}
		
    let cardImageViewController = storyboard?.instantiateViewController(identifier: "CardImageViewController") as? CardImageViewController
		if shouldShowRealCard {
			cardImageViewController?.cardInstance = cardInstance

//			let navigationController = UINavigationController(rootViewController: cardImageViewController)

			cardImageViewController?.tabBarItem = UITabBarItem(title: "Card", image: nil, selectedImage: nil)
//			viewControllers.insert(cardImageViewController, at: 0)
		}
    
    var dismissVC: () -> () = { }
		
		let cardControlView = CardControlView(card: cardInstance, dismiss: {
      dismissVC()
		})
		let hostingController = UIHostingController(rootView: cardControlView)
		hostingController.tabBarItem = UITabBarItem(title: "Control", image: nil, selectedImage: nil)
		viewControllers.insert(hostingController, at: 0)
		
		tabBarController.setViewControllers(viewControllers, animated: false)
		
//		tabBarController.modalPresentationStyle = .popover
    tabBarController.modalPresentationStyle = .formSheet
    if let cardView {
      tabBarController.popoverPresentationController?.sourceView = cardView
      tabBarController.popoverPresentationController?.sourceRect = cardView.bounds
    }
		tabBarController.popoverPresentationController?.permittedArrowDirections = [.left, .right]
		tabBarController.popoverPresentationController?.passthroughViews = [self.view]
		
		let scale: CGFloat = 1.08
//		tabBarController.preferredContentSize = CGSize(width: 320*scale, height: 490*scale)
		
		if cardInstance.controllerIdentifier.value == .b {
			tabBarController.view.transform = .init(rotationAngle: .pi)
		}
		
		tabBarController.selectedIndex = cardInstance.previouslyViewedFocusIndex
		
//		setDetailViewHidden(false, for: cardView)
		
		tabBarController.cardInstance = cardInstance
		focusViewController = tabBarController
    
    struct ViewControllerView: UIViewControllerRepresentable {
      let viewController: UIViewController
      
      init(viewController: UIViewController) {
        self.viewController = viewController
      }
      
      func makeUIViewController(context: Context) -> some UIViewController {
        return viewController
      }
      
      func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
      }
    }
    
    struct ControlView: View {
      let card: CardInstance
      let cardImageViewController: UIViewController?
      let tabs: [UIViewController]
      
      @State var index: Int
      
      var body: some View {
        HStack {
          if let cardImageViewController {
            ViewControllerView(viewController: cardImageViewController)
          }
          
          TabView(selection: $index) {
            ForEach(0..<tabs.count, id: \.self) { index in
              ViewControllerView(viewController: tabs[index])
            }
          }.tabViewStyle(.page)
        }.onChange(of: index) { newValue in
          card.previouslyViewedFocusIndex = newValue
        }
      }
    }
    
    let v = ControlView(card: cardInstance, cardImageViewController: cardImageViewController, tabs: viewControllers, index: cardInstance.previouslyViewedFocusIndex)
    let host = UIHostingController(rootView: v)
    host.modalPresentationStyle = .pageSheet
    host.modalTransitionStyle = .crossDissolve
    focusViewController = host
    
    if cardInstance.controllerIdentifier.value == .b {
      host.view.transform = .init(rotationAngle: .pi)
    }
    
    dismissVC = {
      host.dismiss(animated: true)
    }
		
		present(host, animated: true, completion: nil)
		
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
						let instance = CardInstance(card: card, center: center, ownerIdentifier: owner)
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
		
		let alert = UIAlertController(title: "Add a Card", message: nil, preferredStyle: .alert)
		alert.addTextField(configurationHandler: nil)
		
		let action = UIAlertAction(title: "Add by Name", style: .default) { (_) in
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
		
		let addCodeAction = UIAlertAction(title: "Add by Set and Number", style: .default) { (_) in
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
		
		let randomAction = UIAlertAction(title: "Add Random", style: .default) { (_) in
			self.createCards(at: self.visibleBoardCenter) {
				return [(.a, .card(try CardService.shared.getRandomCard(query: alert.textFields?.first?.text)))]
			}
		}
		alert.addAction(randomAction)
		
//		let boosterPackAction = UIAlertAction(title: "Booster Pack", style: .default) { _ in
//			guard let setCode = alert.textFields?.first?.text else { return }
//			self.createCards(at: self.visibleBoardCenter) { () -> [(Player.Identifier, CardRepresentation)] in
//				let pack = try CardService.shared.generateBoosterPack(setCode: setCode, includeExtendedArt: true, specialOptions: [])
//
//				return pack.map { (.a, .card($0)) }
//			}
//		}
//		alert.addAction(boosterPackAction)
		
//		let loadDeckActionA = UIAlertAction(title: "Load Deck (\(GameState.current.player1.name.value))", style: .default) { (_) in
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
//		let loadDeckActionB = UIAlertAction(title: "Load Deck (\(GameState.current.player2.name.value))", style: .default) { (_) in
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
		
//		let jumpstartAction = UIAlertAction(title: "Jumpstart", style: .default) { _ in
//			self.loadJumpstart()
//		}
//		alert.addAction(jumpstartAction)
		
//		let setPlayer1NameAction = UIAlertAction(title: "Set Player 1 Name", style: .default) { _ in
//			guard let text = alert.textFields?.first?.text else { return }
//			GameState.current.player1.name.accept(text)
//		}
//		alert.addAction(setPlayer1NameAction)
//
//		let setPlayer2NameAction = UIAlertAction(title: "Set Player 2 Name", style: .default) { _ in
//			guard let text = alert.textFields?.first?.text else { return }
//			GameState.current.player2.name.accept(text)
//		}
//		alert.addAction(setPlayer2NameAction)
    
    let dandanAction = UIAlertAction(title: "Load Dandân", style: .default) { _ in
      self.loadDandan()
    }
    alert.addAction(dandanAction)
		
		let togglePlayer2Action = UIAlertAction(title: "Show/Hide Player 2", style: .default) { _ in
			GameState.current.player2.isHidden.toggle()
			self.updatePlayersHidden()
		}
		alert.addAction(togglePlayer2Action)
    
    let toggleLandOrganizerAction = UIAlertAction(title: "Show/Hide Land Organizer", style: .default) { _ in
      self.showLandOrganizer.toggle()
      
      self.updateLandOrganizerLands()
    }
    alert.addAction(toggleLandOrganizerAction)
    
    let dropModeAction = UIAlertAction(title: "Drop Cards \(self.dropFaceUp ? "Face-Down" : "Face-Up")", style: .default) { _ in
      self.dropFaceUp.toggle()
    }
    alert.addAction(dropModeAction)
    
    let toggleSelectionAction = UIAlertAction(title: "\(isSelectionEnabled ? "Disable" : "Enable") Selection", style: .default) { _ in
      self.isSelectionEnabled.toggle()
      self.updateSelection()
    }
    alert.addAction(toggleSelectionAction)
    
    let player1TopCardAction = UIAlertAction(title: "Reveal Player 1 Library Top Card", style: .default) { _ in
      GameState.current.player1.library.isTopCardRevealed.mutate {
        $0.toggle()
      }
      try? GameState.current.save()
    }
    alert.addAction(player1TopCardAction)
    
    if !GameState.current.player2.isHidden {
      let player2TopCardAction = UIAlertAction(title: "Reveal Player 2 Library Top Card", style: .default) { _ in
        GameState.current.player2.library.isTopCardRevealed.mutate {
          $0.toggle()
        }
        try? GameState.current.save()
      }
      alert.addAction(player2TopCardAction)
    }
		
		let updateAction = UIAlertAction(title: "Update Card Database", style: .default) { _ in
			CardService.shared.updateDatabase()
		}
		alert.addAction(updateAction)
		
//		let loadDeckFromURLA = UIAlertAction(title: "Load Deck From URL (Player 1)", style: .default) { [weak self] (_) in
//			guard let text = alert.textFields?.first?.text else { return }
//			guard let url = URL(string: text) else { return }
//			self?.loadDeck(from: url, for: .a)
//		}
//		alert.addAction(loadDeckFromURLA)
//
//		let loadDeckFromURLB = UIAlertAction(title: "Load Deck From URL (Player 2)", style: .default) { [weak self] (_) in
//			guard let text = alert.textFields?.first?.text else { return }
//			guard let url = URL(string: text) else { return }
//			self?.loadDeck(from: url, for: .b)
//		}
//		alert.addAction(loadDeckFromURLB)
		if let url = URL(string: "https://testflight.apple.com/join/VbVcGZw1") {
			let shareLinkAction = UIAlertAction(title: "Share Connect App", style: .default) { [weak self] _ in
				guard let self = self else { return }
				let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
				activityViewController.popoverPresentationController?.sourceView = self.player1BarContainerView
				activityViewController.popoverPresentationController?.sourceRect = self.player1BarContainerView.bounds
				
				self.present(activityViewController, animated: true, completion: nil)
			}
			alert.addAction(shareLinkAction)
		}
		
		let removeAction = UIAlertAction(title: "Reset Game", style: .destructive) { [weak self] (_) in
			for card in GameState.current.battlefield.value {
				card.remove.onNext(())
			}
			
			GameState.current = GameState()
      
      GameState.current.player2.isHidden.toggle()
      self?.updatePlayersHidden()
      
			(self?.view.window?.windowScene?.delegate as? SceneDelegate)?.window?.rootViewController = self?.storyboard?.instantiateInitialViewController()
		}
		alert.addAction(removeAction)
		
		let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
		alert.addAction(cancel)
		
		present(alert, animated: true, completion: nil)
		
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
    self.scrollView.isScrollEnabled = !isSelectionEnabled
    selectionGestureRecognizer.isEnabled = isSelectionEnabled
    
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
					let groups = DeckParser.parse(deckList: string, autofix: true)
					self.loadDeck(groups, playerIdentifier: playerIdentifier)
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
		return UIDropProposal(operation: .move)
	}
	
	func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
		let location = session.location(in: board)
		
		let cardInstances = (session.localDragSession?.items.compactMap { ($0.cardInstance) } ?? [])
		moveCardItemsToBattlefield(cardInstances, at: location)
	}
	
	func moveCardItemsToBattlefield<S: Sequence>(_ cardInstances: S, at location: CGPoint) where S.Element == CardInstance {
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
		guard let cardView = interaction.view?.superview?.superview as? MiniCardView, let cardInstance = cardView.cardInstance else { return [] }
		
		return [dragItem(for: cardInstance)]
	}
	
	func dragInteraction(_ interaction: UIDragInteraction, itemsForAddingTo session: UIDragSession, withTouchAt point: CGPoint) -> [UIDragItem] {
		guard let cardView = interaction.view?.superview?.superview as? MiniCardView, let cardInstance = cardView.cardInstance else { return [] }
		
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
