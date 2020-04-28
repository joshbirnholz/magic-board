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

class BoardViewController: UIViewController {
	
	@IBOutlet weak var scrollView: UIScrollView!
	@IBOutlet weak var board: UIView!
	@IBOutlet weak var boardWidthConstraint: NSLayoutConstraint!
	
	@IBOutlet weak var player1BarContainerView: UIView!
	@IBOutlet weak var player2BarContainerView: UIView!
	
	weak var focusViewController: UIViewController?
	
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
		longPress.delegate = self
		board.addGestureRecognizer(longPress)
		
		let dropInteraction = UIDropInteraction(delegate: self)
		board.addInteraction(dropInteraction)
		
		//		for card in cards.values {
		//			card.remove.onNext(())
		//		}
		
		for card in GameState.current.battlefield.value {
			addCardViewToBattlefield(for: card)
		}
		
		GameState.current.player2.name
			.subscribe(onNext: { (name) in
				if GameState.current.player1.name.value == name {
					GameState.current.player1.name.accept("\(name) (2)")
				}
			}).disposed(by: bag)
		
		UIView.setAnimationsEnabled(true)
		
		AppDelegate.shared.transceiver.receive(Command.self) { [weak self] command in
			guard let self = self else { return }
			switch command {
			case .rebroadcast:
				AppDelegate.shared.transceiver.broadcast(GameState.current)
			case .moveCardsToBattlefield(let parameters):
				let cardInstances = GameState.current.cardInstances(with: parameters.map { $0.cardInstanceID })
				
				for param in parameters {
					guard let cardInstance = cardInstances[param.cardInstanceID] else { continue }
					cardInstance.revealedPlayers.mutate {
						$0.remove(cardInstance.ownerIdentifier)
					}
					switch param.faceIndex {
					case (0...)?:
						guard let index = param.faceIndex, let face = cardInstance.representation.card.cardFaces?[index] else { fallthrough }
						cardInstance.representation = .alternateFace(cardInstance.representation.card, face)
					case (..<0)?:
						cardInstance.representation = .faceDown(cardInstance.representation)
					default:
						break
					}
				}
				
				self.moveCardItemsToBattlefield(cardInstances.values, at: self.visibleBoardCenter)
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
				self.loadDeck(from: parameters.deckList, playerIdentifier: parameters.playerIdentifier)
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
			}
		}
		
//		GameState.current.accept(self.displayedGameState())
	}
	
	var visibleBoardCenter: CGPoint {
		let visibleRect = scrollView.convert(scrollView.bounds, to: board!)
		return CGPoint(x: visibleRect.midX, y: visibleRect.midY)
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		
		scrollView.zoomScale = 0.3
		centerScrollView()
	}
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "EmbedPlayer2Bar" {
			let bottomBar = segue.destination as? BottomBarViewController
			bottomBar?.player = GameState.current.player2
			bottomBar?.delegate = self
			segue.destination.view.transform = CGAffineTransform(rotationAngle: .pi)
		} else if segue.identifier == "EmbedPlayer1Bar" {
			let bottomBar = segue.destination as? BottomBarViewController
			bottomBar?.player = GameState.current.player1
			bottomBar?.delegate = self
		}
	}
	
	func cardView(for cardInstance: CardInstance) -> MiniCardView? {
		board.subviews.first { (view) -> Bool in
			guard let cardView = view as? MiniCardView else { return false }
			return cardView.cardInstance == cardInstance
		} as? MiniCardView
	}
	
	private var cardInstanceDisposeBags: [UUID: DisposeBag] = [:]
	
	fileprivate func addCardViewToBattlefield(for cardInstance: CardInstance) {
		guard let point = cardInstance.center.value else { return }
		let cardView = MiniCardView(frame: CGRect(x: point.x, y: point.y, width: 500, height: 500))
		
		cardView.cardInstance = cardInstance
		let shouldHide = self.shouldHideOracleBoxes()
		cardView.isOracleBoxHidden = shouldHide
		cardView.isCostLabelHidden = shouldHide
		cardView.isTypeLabelHidden = shouldHide
		
		let panGesture = UIPanGestureRecognizer(target: self, action: #selector(panRecognized(gestureRecognizer:)))
		panGesture.delegate = self
		panGesture.maximumNumberOfTouches = 1
		cardView.addGestureRecognizer(panGesture)
		
		let focusGesture = UILongPressGestureRecognizer(target: self, action: #selector(longPressOnCardRecognized(gestureRecognizer:)))
		cardView.addGestureRecognizer(focusGesture)
		
		board.addSubview(cardView)
		cardView.center = point
		
		if cardInstanceDisposeBags[cardInstance.uuid] == nil {
			let cardBag = DisposeBag()
			
			cardInstance.remove
				.subscribe(onNext: { [weak self] (_) in
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
	}
	
	@objc func longPressOnCardRecognized(gestureRecognizer: UIGestureRecognizer) {
		guard let cardView = (gestureRecognizer.view as? MiniCardView) else { return }
		guard gestureRecognizer.state == .began else { return }
		
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
		var viewControllers: [UIViewController] = SideTableViewController.SectionModel.viewControllerCombinations.compactMap { sections in
			guard let viewController = storyboard?.instantiateViewController(identifier: "SideTableViewController") as? SideTableViewController else { return nil }
			
			viewController.card = cardView.cardInstance
			viewController.sectionModel = sections
			
			let navigationController = UINavigationController(rootViewController: viewController)
			navigationController.tabBarItem = UITabBarItem(title: sections.last?.title, image: sections.last?.tabBarImage, selectedImage: nil)
			return navigationController
		}
		
		if let countersViewController = storyboard?.instantiateViewController(identifier: "CountersViewController") as? CountersViewController {
			
			countersViewController.cardInstance = cardView.cardInstance
			
			let navigationController = UINavigationController(rootViewController: countersViewController)
			navigationController.tabBarItem = UITabBarItem(title: "Counters", image: nil, selectedImage: nil)
			viewControllers.append(navigationController)
		}
		
		var shouldShowRealCard = cardView.cardInstance.representation.card.language == .english
		if case .faceDown(_) = cardView.cardInstance.representation {
			shouldShowRealCard = true
		}
		
		if let cardImageViewController = storyboard?.instantiateViewController(identifier: "CardImageViewController") as? CardImageViewController, shouldShowRealCard {
			cardImageViewController.cardInstance = cardView.cardInstance

//			let navigationController = UINavigationController(rootViewController: cardImageViewController)

			cardImageViewController.tabBarItem = UITabBarItem(title: "Card", image: nil, selectedImage: nil)
			viewControllers.insert(cardImageViewController, at: 0)
		} else if let cardDetailsViewController = storyboard?.instantiateViewController(identifier: "CardDetail") as? CardDetailsViewController {
			cardDetailsViewController.cardInstance = cardView.cardInstance
			
//			let navigationController = UINavigationController(rootViewController: cardDetailsViewController)
			
			cardDetailsViewController.tabBarItem = UITabBarItem(title: "Card", image: nil, selectedImage: nil)
			viewControllers.insert(cardDetailsViewController, at: 0)
		}
		
		tabBarController.setViewControllers(viewControllers, animated: false)
		
		tabBarController.modalPresentationStyle = .popover
		tabBarController.popoverPresentationController?.sourceView = cardView
		tabBarController.popoverPresentationController?.sourceRect = cardView.bounds
		tabBarController.popoverPresentationController?.permittedArrowDirections = [.left, .right]
		tabBarController.popoverPresentationController?.passthroughViews = [self.view]
		
		let scale: CGFloat = 1.08
		tabBarController.preferredContentSize = CGSize(width: 320*scale, height: 490*scale)
		
		if cardView.cardInstance.controllerIdentifier.value == .b {
			tabBarController.view.transform = .init(rotationAngle: .pi)
		}
		
		tabBarController.selectedIndex = cardView.cardInstance.previouslyViewedFocusIndex
		
//		setDetailViewHidden(false, for: cardView)
		
		tabBarController.cardInstance = cardView.cardInstance
		focusViewController = tabBarController
		
		present(tabBarController, animated: true, completion: nil)
		
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
		
		cardView.superview?.bringSubviewToFront(cardView)
		let translation = gestureRecognizer.translation(in: board)
		cardView.center = CGPoint(x: cardView.center.x + translation.x, y: cardView.center.y + translation.y)
		cardView.cardInstance.center.accept(CGPoint(x: cardView.center.x + translation.x, y: cardView.center.y + translation.y))
		gestureRecognizer.setTranslation(.zero, in: board)
		
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
					guard let bottomBar = containerView?.subviews.first else { continue }
					
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
				return nil
			}()
				
			if let destinationPile = endedPile {
				func continuation(insertionIndex: Int? = nil) {
					GameState.current.move(cardInstances: [cardView.cardInstance], to: destinationPile, at: insertionIndex)
				}
				
//				continuation()
				
				if destinationPile.location == .library && !destinationPile.cards.value.isEmpty && !cardView.cardInstance.representation.isToken && !cardView.cardInstance.representation.isEmblem {
					let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

					let topAction = UIAlertAction(title: "Top", style: .default) { (_) in
						continuation(insertionIndex: nil)
					}
					alert.addAction(topAction)
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
				} else {
					continuation()
				}
				
			} else {
				try? GameState.current.save()
			}
			
			print(cardView.center)
			print(visibleBoardCenter)
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
	
	fileprivate func loadDeck(from decklist: String, playerIdentifier: Player.Identifier) {
		let player = playerIdentifier == .a ? GameState.current.player1 : GameState.current.player2
		
		DispatchQueue.global(qos: .userInitiated).async {
			player.allPiles.forEach {
				$0.cards.mutate {
					$0.removeAll()
				}
			}
			
			let groups = DeckParser.parse(deckList: decklist)
			
			for group in groups {
				let identifiers = group.cardCounts.map { $0.identifier }
				
				do {
					let list = try CardService.shared.getCollection(identifiers: identifiers)
					
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
					
					var cards: [MTGCard] = []
					
					for (card, count) in zip(list.cards, group.cardCounts.map { $0.count }) {
						for _ in 0 ..< count {
							cards.append(card)
						}
					}
					
					DispatchQueue.main.async {
						if pile.location == .library {
							cards.shuffle()
						}
						
						let instances = OrderedSet(cards.map { CardInstance(card: $0, center: nil, ownerIdentifier: playerIdentifier) })
						pile.cards.accept(instances)
					}
					
					for card in cards {
						CardService.shared.cacheImagesIfNeeded(for: card, types: [.art, .small, .large])
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
				try? GameState.current.save()
			}
			
		}
	}
	
	@objc func longPressRecognized(gestureRecognizer: UIGestureRecognizer) {
		guard presentedViewController == nil else { return }
		
		let alert = UIAlertController(title: "Add a Card", message: nil, preferredStyle: .alert)
		alert.addTextField(configurationHandler: nil)
		
		let action = UIAlertAction(title: "Add by Name", style: .default) { (_) in
			guard let name = alert.textFields?.first?.text else { return }
			self.createCards(at: self.visibleBoardCenter) {
				return [(.a, .card(try CardService.shared.getCard(name: name)))]
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
				return [(.a, .card(try CardService.shared.getRandomCard()))]
			}
		}
		alert.addAction(randomAction)
		
		let loadDeckActionA = UIAlertAction(title: "Load Deck (\(GameState.current.player1.name.value))", style: .default) { (_) in
			let picker = UIDocumentPickerViewController(documentTypes: ["public.plain-text"], in: .import)
			picker.allowsMultipleSelection = false
			picker.delegate = self
			self.loadDeckPlayerIdentifier = .a
			self.present(picker, animated: true, completion: nil)
		}
		alert.addAction(loadDeckActionA)
		
		let loadDeckActionB = UIAlertAction(title: "Load Deck (\(GameState.current.player2.name.value))", style: .default) { (_) in
			let picker = UIDocumentPickerViewController(documentTypes: ["public.plain-text"], in: .import)
			picker.allowsMultipleSelection = false
			picker.delegate = self
			self.loadDeckPlayerIdentifier = .b
			self.present(picker, animated: true, completion: nil)
		}
		alert.addAction(loadDeckActionB)
		
		let setPlayer1NameAction = UIAlertAction(title: "Set Player 1 Name", style: .default) { _ in
			guard let text = alert.textFields?.first?.text else { return }
			GameState.current.player1.name.accept(text)
		}
		alert.addAction(setPlayer1NameAction)
		
		let setPlayer2NameAction = UIAlertAction(title: "Set Player 2 Name", style: .default) { _ in
			guard let text = alert.textFields?.first?.text else { return }
			GameState.current.player2.name.accept(text)
		}
		alert.addAction(setPlayer2NameAction)
		
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
}

extension BoardViewController: UIScrollViewDelegate {
	func viewForZooming(in scrollView: UIScrollView) -> UIView? {
		return board
	}
	
	func shouldHideOracleBoxes() -> Bool {
		return true
//		scrollView.zoomScale < 0.5
	}
	
	func scrollViewDidZoom(_ scrollView: UIScrollView) {
		let shouldHideOracleBoxes = self.shouldHideOracleBoxes()
		DispatchQueue.main.async {
			for case let cardView? in self.board.subviews.map({ $0 as? MiniCardView }) {
				self.setDetailViewHidden(shouldHideOracleBoxes, for: cardView, animated: true)
			}
		}
	}
	
	func setDetailViewHidden(_ hidden: Bool, for cardView: MiniCardView, animated: Bool = true) {
		UIView.animate(withDuration: animated ? 0.2 : 0) {
			cardView.isOracleBoxHidden = hidden
			cardView.isCostLabelHidden = hidden
			cardView.isTypeLabelHidden = hidden
			cardView.chainsImageView.alpha = hidden ? 1.0 : 0.5
		}
	}
	
	func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
		print("zoomed to scale: \(scale)")
		print("Offset: \(scrollView.contentOffset)")
		print("Visible size: \(scrollView.visibleSize)")
	}
}

extension BoardViewController: UIGestureRecognizerDelegate {
	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		if gestureRecognizer is UIPanGestureRecognizer {
			return shouldHideOracleBoxes()
		}
		
//		if gestureRecognizer is UILongPressGestureRecognizer {
//			let location = gestureRecognizer.location(in: view)
//			if player1BarContainerView.hitTest(location, with: nil) != nil {
//				return false
//			} else if player2BarContainerView.hitTest(location, with: nil) != nil {
//				return false
//			}
//		}
		
		return true
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
					self.loadDeck(from: string, playerIdentifier: playerIdentifier)
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
		
		let cardInstances = (session.localDragSession?.items.compactMap { ($0.localObject as? CardInstance) } ?? [])
		moveCardItemsToBattlefield(cardInstances, at: location)
	}
	
	func moveCardItemsToBattlefield<S: Sequence>(_ cardInstances: S, at location: CGPoint) where S.Element == CardInstance {
		for cardInstance in cardInstances {
			if let pile = cardInstance.pile {
				pile.cards.mutate {
					$0.remove(cardInstance)
				}
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
		let item = NSItemProvider(object: cardInstance)
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
