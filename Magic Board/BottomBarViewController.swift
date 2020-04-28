//
//  BottomBarViewController.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/24/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import UIKit
import RxSwift
import RxCocoa
import CardService

protocol PileViewProtocol: UIView {
	
}

extension HUDCardPileView: PileViewProtocol {
	
}

class HandViewControllerContainerView: UIView, PileViewProtocol, UIDropInteractionDelegate {
	
	
}

protocol BottomBarViewControllerDelegate: class {
	func bottomBarViewController(_ bottomBarViewController: BottomBarViewController, passthroughViewsFor navigationController: UINavigationController) -> [UIView]?
}
extension BottomBarViewControllerDelegate {
	func bottomBarViewController(_ bottomBarViewController: BottomBarViewController, passthroughViewsFor navigationController: UINavigationController) -> [UIView]? {
		return nil
	}
}

class BottomBarViewController: UIViewController {
	
	private let bag = DisposeBag()
	
	var player: Player!
	
	@IBOutlet weak var libraryPileView: HUDCardPileView!
	@IBOutlet weak var graveyardPileView: HUDCardPileView!
	@IBOutlet weak var exilePileView: HUDCardPileView!
	@IBOutlet weak var lifeLabel: UILabel!
	@IBOutlet weak var lifeStepper: UIStepper!
	@IBOutlet weak var handContainerView: HandViewControllerContainerView!
	
	weak var handViewController: HandViewController!
	
	weak var delegate: BottomBarViewControllerDelegate?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		setupPile(player.library, view: libraryPileView)
		setupPile(player.graveyard, view: graveyardPileView)
		setupPile(player.exile, view: exilePileView)
		
		lifeStepper.transform = .init(rotationAngleDegrees: -90)
		lifeStepper.value = Double(player.life.value)
		
		bind()
	}
	
	private func bind() {
		player.life
			.map(String.init)
			.bind(to: lifeLabel.rx.text)
			.disposed(by: bag)
		
		lifeStepper.rx.value
			.subscribe(onNext: { [weak self] value in
				self?.player.life.accept(Int(value))
				try? GameState.current.save()
			}).disposed(by: bag)
	}
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "EmbedHandViewController", let destination = segue.destination as? HandViewController {
			self.handViewController = destination
			destination.player = player
			setupPile(player.hand, view: handContainerView)
		}
	}
	
	func setupPile(_ pile: Pile, view: PileViewProtocol) {
		(view as? HUDCardPileView)?.pile = pile
		let dragInteraction = UIDragInteraction(delegate: self)
		view.addInteraction(dragInteraction)
		
		let dropInteraction = UIDropInteraction(delegate: self)
		view.addInteraction(dropInteraction)
		
		if pile.location != .hand {
			let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(viewPile(_:)))
			view.addGestureRecognizer(tapGestureRecognizer)
			
			let springLoadedInteraction = UISpringLoadedInteraction { [weak self] interaction, context in
				self?.viewPile(from: view)
			}
			view.addInteraction(springLoadedInteraction)
		}
		
//		if pile.location == .library {
////			let gestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(displayPileOptions(_:)))
////			view.addGestureRecognizer(gestureRecognizer)
//
////			let interaction = UIContextMenuInteraction(delegate: self)
////			view.addInteraction(interaction)
//
//			let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(viewPile(_:)))
//			view.addGestureRecognizer(tapGestureRecognizer)
//		} else if pile.location != .hand {
//			let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(viewPile(_:)))
//			view.addGestureRecognizer(tapGestureRecognizer)
//		}
		
		// Alternative, instead of the popover.
//		let contextMenuInteraction = UIContextMenuInteraction(delegate: self)
//		view.addInteraction(contextMenuInteraction)
		
	}
	
	@objc func drawCard(_ sender: UIGestureRecognizer) {
		guard let last: CardInstance = player.library.cards.value.last else { return }
		GameState.current.move(cardInstances: [last], to: player.hand)
	}
	
	fileprivate func drawOpeningHand() {
		GameState.current.move(cardInstances: player.hand.cards.value.contents, to: player.library)
		player.library.cards.mutate {
			$0 = OrderedSet($0.contents.shuffled())
		}
		let newHand = Array(player.library.cards.value.suffix(7))
		GameState.current.move(cardInstances: newHand, to: player.hand)
	}
	
	fileprivate func untapAll() {
		for cardInstance in GameState.current.battlefield.value where cardInstance.controllerIdentifier.value == player.identifier {
			if !cardInstance.doesNotUntapNextTurn.value && !cardInstance.doesNotUntapAutomatically.value {
				cardInstance.isTapped.accept(false)
			}
			cardInstance.doesNotUntapNextTurn.accept(false)
			cardInstance.isSummoningSick.accept(false)
		}
		try? GameState.current.save()
	}
	
	fileprivate var openingHandIsAvailable: Bool {
		return GameState.current.battlefield.value.isEmpty && player.graveyard.cards.value.isEmpty && player.exile.cards.value.isEmpty
	}
	
	@IBAction func untapButtonPressed(_ sender: Any) {
		if openingHandIsAvailable {
			drawOpeningHand()
		} else {
			untapAll()
		}
		
	}
	
	
	@objc func viewPile(_ sender: UIGestureRecognizer) {
		guard let pileView = sender.view as? PileViewProtocol else { return }
		
		viewPile(from: pileView)
	}
	
	private struct Action {
		var title: String
		var style: UIAlertAction.Style = .default
		var handler: (() -> ())?
		
		static let cancel = Action(title: "Cancel", style: .cancel, handler: nil)
		
		var alertAction: UIAlertAction {
			return UIAlertAction(title: title, style: style, handler: { _ in self.handler?() })
		}
		
		var uiAction: UIAction {
			return UIAction(title: title, handler: { _ in self.handler?() })
		}
	}
	
	private func actions(for pileView: PileViewProtocol) -> [Action] {
		var actions: [Action] = []
		
		let pile = self.pile(for: pileView)
		
		if pile.location == .library {
			let shuffleAction = Action(title: "Shuffle", style: .default) {
				self.player.library.cards.mutate { $0 = OrderedSet($0.contents.shuffled()) }
			}
			actions.append(shuffleAction)
		}
		
		let viewAction = Action(title: "Search", style: .default) {
			self.viewPile(from: pileView)
		}
		actions.append(viewAction)
		
		return actions
	}
	
	@objc func displayPileOptions(_ sender: UIGestureRecognizer) {
		let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
		guard let pileView = sender.view as? PileViewProtocol else { return }
		let pile = self.pile(for: pileView)
		
		let actions = self.actions(for: pileView)
		actions.forEach { alert.addAction($0.alertAction) }
		
		let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
		alert.addAction(cancelAction)
		
		alert.popoverPresentationController?.sourceView = sender.view
		alert.popoverPresentationController?.permittedArrowDirections = [.up, .down]
		
		if pile.playerIdentifier == .b {
			alert.view.transform = CGAffineTransform(rotationAngle: .pi)
		}
		
		self.present(alert, animated: true, completion: nil)
	}
	
	func viewPile(from pileView: PileViewProtocol) {
		let pile = self.pile(for: pileView)
		
		guard !pile.cards.value.isEmpty else { return }
		guard let pileViewController = self.storyboard?.instantiateViewController(identifier: "PileViewController") as? PileViewController else { return }
		pileViewController.setPile(pile)
		
		let navigationController = UINavigationController(rootViewController: pileViewController)
		navigationController.modalPresentationStyle = .popover
		navigationController.popoverPresentationController?.permittedArrowDirections = [.up, .down]
		navigationController.popoverPresentationController?.sourceView = pileView
		navigationController.popoverPresentationController?.passthroughViews = delegate?.bottomBarViewController(self, passthroughViewsFor: navigationController)
		
		if pile.playerIdentifier == .b {
			navigationController.view.transform = CGAffineTransform(rotationAngle: .pi)
		}
		
		self.present(navigationController, animated: true, completion: nil)
	}
	
	func pile(for pileView: PileViewProtocol) -> Pile {
		if let pileView = pileView as? HUDCardPileView {
			return pileView.pile
		} else {
			return player.hand
		}
	}

}

extension BottomBarViewController: UIDragInteractionDelegate {
	func dragItems(forCardsAt indices: IndexSet, in pile: Pile, image: UIImage?) -> [UIDragItem] {
		return indices.map { index in
			let cardInstance = pile.cards.value[index]
			let item = NSItemProvider(object: cardInstance)
			let dragItem = UIDragItem(itemProvider: item)
			dragItem.localObject = cardInstance
			dragItem.previewProvider = { [weak self] in
				let imageView = UIImageView(image: image ?? #imageLiteral(resourceName: "mtg-card-back-png-1"))
				imageView.contentMode = .scaleAspectFit
				
				imageView.layer.masksToBounds = true
				imageView.layer.cornerRadius = 5
				
				imageView.frame.size = CGSize(width: 240/2.5, height: 335/2.5)
				
				let parameters = UIDragPreviewParameters()
				parameters.backgroundColor = .clear
				return UIDragPreview(view: imageView, parameters: parameters)
			}
			return dragItem
		}
	}
	
	func dragItems(forPile pile: Pile, session: UIDragSession, image: UIImage?) -> [UIDragItem] {
		let indexToAdd = pile.cards.value.count-session.items.count-1
		guard pile.cards.value.indices.contains(indexToAdd) else { return [] }
		
		return dragItems(forCardsAt: IndexSet(integer: indexToAdd), in: pile, image: indexToAdd == pile.cards.value.indices.last ?? 0 ? image : nil)
	}
	
	func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
		guard let pileView = (interaction.view as? HUDCardPileView), let pile = pileView.pile else { return [] }
		return dragItems(forPile: pile, session: session, image: pileView.topCardImageView.image)
	}
	
	func dragInteraction(_ interaction: UIDragInteraction, itemsForAddingTo session: UIDragSession, withTouchAt point: CGPoint) -> [UIDragItem] {
		guard let pileView = (interaction.view as? HUDCardPileView), let pile = pileView.pile else { return [] }
		return dragItems(forPile: pile, session: session, image: pileView.topCardImageView.image)
	}
	
}

extension BottomBarViewController: UIDropInteractionDelegate {
	func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
		return session.canLoadObjects(ofClass: CardInstance.self)
	}
	
	func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
		let cardItems = session.items.compactMap { $0.localObject as? CardInstance }
		
		guard let pileView = interaction.view as? PileViewProtocol else { return UIDropProposal(operation: .cancel) }
		guard let destinationPile = (pileView as? HUDCardPileView)?.pile ?? (pileView is HandViewControllerContainerView ? player.hand : nil) else { return UIDropProposal(operation: .cancel) }
		
		let allSourcesAndDestinationPilesAreEqual = cardItems.allSatisfy({ (cardItem) -> Bool in
			cardItem.pile == destinationPile
		})
		guard !allSourcesAndDestinationPilesAreEqual else {
			return UICollectionViewDropProposal(operation: .cancel)
		}
		
		let allCardsCannotLeaveBattlefield = cardItems.allSatisfy { (cardItem) -> Bool in
			var card = cardItem.representation
			
			if case .faceDown(let faceDownCard) = cardItem.representation {
				card = faceDownCard
			}
			
			return card.isToken == true || card.isEmblem == true
		}
		if allCardsCannotLeaveBattlefield {
			return UIDropProposal(operation: .forbidden)
		}
		
		// TODO: Prevent cards from being moved to opponent's zones
		// Maybe: Move them to those zones but belonging to their owner
		
		return UIDropProposal(operation: .move)
	}
	
	func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
		guard let pileView = interaction.view as? PileViewProtocol else { return }
		let destinationPile = self.pile(for: pileView)
		
		func continuation(insertionIndex: Int? = nil) {
			let cardInstances = (session.localDragSession?.items.compactMap { ($0.localObject as? CardInstance) } ?? [])
				.sorted { (first, second) -> Bool in
					if let firstIndex = first.indexInPile, let secondIndex = second.indexInPile {
						return firstIndex > secondIndex
					}
					
					return false
			}
			
			GameState.current.move(cardInstances: cardInstances, to: destinationPile, at: insertionIndex)
		}
		
//		if destinationPile.location == .library {
//			let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
//
//			let topAction = UIAlertAction(title: "Top", style: .default) { (_) in
//				continuation(insertionIndex: nil)
//			}
//			alert.addAction(topAction)
//			let bottomAction = UIAlertAction(title: "Bottom", style: .default) { _ in
//				continuation(insertionIndex: 0)
//			}
//			alert.addAction(bottomAction)
//
//			let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
//			alert.addAction(cancelAction)
//
//			alert.popoverPresentationController?.sourceView = pileView
//			alert.popoverPresentationController?.permittedArrowDirections = [.up, .down]
//
//			if destinationPile.playerIdentifier == .b {
//				alert.view.transform = CGAffineTransform(rotationAngle: .pi)
//			}
//
//			self.present(alert, animated: true, completion: nil)
//		} else {
//			continuation()
//		}
		
		continuation()
	}
}

extension BottomBarViewController: UIContextMenuInteractionDelegate {
	func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
		guard let pileView = interaction.view as? HUDCardPileView else { return nil }
		
		return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { suggestedActions -> UIMenu? in
			var menuElements: [UIMenuElement] = []
			
			let actions = self.actions(for: pileView)
			actions.forEach { menuElements.append($0.uiAction) }
			
			return UIMenu(title: "", children: menuElements)
		}
	}
}
