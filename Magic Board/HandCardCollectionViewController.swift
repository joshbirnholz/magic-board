//
//  HandCardCollectionViewController.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/17/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import HFCardCollectionViewLayout
import RxSwift
import RxCocoa
import Shiny

fileprivate extension UIColor {
    convenience init(red: Int, green: Int, blue: Int) {
        self.init(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
    class var red: UIColor { return UIColor(red: 255, green: 59, blue: 48) }
    class var orange: UIColor { return UIColor(red: 255, green: 149, blue: 0) }
    class var yellow: UIColor { return UIColor(red: 255, green: 204, blue: 0) }
    class var green: UIColor { return UIColor(red: 76, green: 217, blue: 100) }
    class var tealBlue: UIColor { return UIColor(red: 90, green: 200, blue: 250) }
    class var blue: UIColor { return UIColor(red: 0, green: 122, blue: 255) }
    class var purple: UIColor { return UIColor(red: 88, green: 86, blue: 214) }
    class var pink: UIColor { return UIColor(red: 255, green: 45, blue: 85) }
    class var background: UIColor { return UIColor(red: 17, green: 17, blue: 17) }
    class var gray: UIColor { return UIColor(red: 34, green: 34, blue: 34) }
}

protocol HandCardCollectionViewCellDelegate: class {
	func handCardCollectionViewCellButtonPressed(_ cell: HandCardCollectionViewCell)
	func handCardCollectionViewCellSplitLeftButtonPressed(_ cell: HandCardCollectionViewCell)
	func handCardCollectionViewCellSplitRightButtonPressed(_ cell: HandCardCollectionViewCell)
}

class HandCardCollectionViewCell: HFCardCollectionViewCell {
	
	weak var delegate: HandCardCollectionViewCellDelegate?
	
	@IBOutlet weak var cardImageView: UIImageView!
	@IBOutlet weak var shinyView: ShinyView!
	@IBOutlet weak var shinyViewContainer: UIView!
	
	@IBOutlet weak var button: UIButton!
	@IBOutlet weak var splitButtonLeft: UIButton!
	@IBOutlet weak var splitButtonRight: UIButton!
	
//	@IBOutlet weak var buttonsStackView: UIStackView!
	
	override func awakeFromNib() {
		super.awakeFromNib()
		
		cardImageView.layer.cornerRadius = 18
		
		cardImageView.layer.masksToBounds = true
		
		shinyView.layer.masksToBounds = true
		shinyView.layer.cornerRadius = cardImageView.layer.cornerRadius
		shinyView.colors = [UIColor.white, UIColor.red, UIColor.orange, UIColor.green, UIColor.blue, UIColor.purple, UIColor.pink, UIColor.white].map { $0.withAlphaComponent(0.9) }
		//shinyView.axis = .horizontal
//		shinyView.startUpdates()
		shinyViewContainer.layer.compositingFilter = "multiplyBlendMode"
		shinyViewContainer.alpha = 0.315
//		shinyView.mask = cardImageView
		
		for button in [self.button!, splitButtonLeft!, splitButtonRight!] {
			button.isHidden = false
			button.alpha = 0
			button.layer.masksToBounds = true
			button.layer.cornerRadius = 9
		}
			
//		let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(buttonPressed(_:)))
//		button.addGestureRecognizer(tapGestureRecognizer)
	}
	
	var layout: CardTableViewCell.Layout = .default
	
	var displayedCardInstanceID: UUID?
	var splitFaceIndex = 0
	
	private func setSplitButtonsEnabled(_ split: Bool) {
		button.isHidden = !split
		splitButtonLeft.isHidden = split
		splitButtonRight.isHidden = split
	}
	
	private var buttonsForLayout: [UIButton] {
		switch layout {
		case .default: return [button!]
		case .split: return [splitButtonLeft!, splitButtonRight!]
		}
	}
	
	func cardRevealed(_ revealed: Bool) {
		UIView.animate(withDuration: 0.2, animations: {
			for button in self.buttonsForLayout {
				button.alpha = revealed ? 1 : 0
			}
		}, completion: { _ in
			for button in self.buttonsForLayout {
				button.isHidden = !revealed
			}
		})
	}
	
	override func prepareForReuse() {
		super.prepareForReuse()
		
		splitFaceIndex = 0
	}
	
	@IBAction func buttonPressed(_ sender: Any) {
		delegate?.handCardCollectionViewCellButtonPressed(self)
	}
	
	@IBAction func splitLeftButtonPressed(_ sender: Any) {
		delegate?.handCardCollectionViewCellSplitLeftButtonPressed(self)
	}
	
	@IBAction func splitRightButtonPressed(_ sender: Any) {
		delegate?.handCardCollectionViewCellSplitRightButtonPressed(self)
	}
	
}

fileprivate struct CardLayoutSetupOptions {
    var firstMovableIndex: Int = 0
    var cardHeadHeight: CGFloat = 65
    var cardShouldExpandHeadHeight: Bool = true
    var cardShouldStretchAtScrollTop: Bool = true
    var cardMaximumHeight: CGFloat = 0
    var bottomNumberOfStackedCards: Int = 0
    var bottomStackedCardsShouldScale: Bool = true
    var bottomCardLookoutMargin: CGFloat = 10
    var bottomStackedCardsMaximumScale: CGFloat = 1.0
    var bottomStackedCardsMinimumScale: CGFloat = 0.94
    var spaceAtTopForBackgroundView: CGFloat = 12
    var spaceAtTopShouldSnap: Bool = true
    var spaceAtBottom: CGFloat = 0
    var scrollAreaTop: CGFloat = 120
    var scrollAreaBottom: CGFloat = 120
    var scrollShouldSnapCardHead: Bool = false
    var scrollStopCardsAtTop: Bool = true
}

class HandCardCollectionViewController: UICollectionViewController, HFCardCollectionViewLayoutDelegate, PileDisplaying, HandCardCollectionViewCellDelegate {
	
	var contentType: DisplayedContent {
		return .pile(pile.location)
	}
	
	var pileLocation: Pile.Location? {
		return pile.location
	}
	
	var ownerIdentifier: Player.Identifier {
		return pile.playerIdentifier
	}
	
	func pushImageViewController(for cardInstance: CardInstance) {
		
	}
	
	var cardCollectionViewLayout: HFCardCollectionViewLayout?
	
	var pile: Pile!
	private let bag = DisposeBag()
	private let cardInstances = BehaviorRelay<OrderedSet<CardInstance>>(value: [])

	@IBOutlet var moreButton: UIBarButtonItem!
	@IBOutlet var flipButton: UIBarButtonItem!
	
	override func viewDidLoad() {
		setupExample()
		super.viewDidLoad()
		
		moreButton.tintColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 0.4487439572)
		flipButton.tintColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 0.4487439572)
		
		cardInstances
			.withPrevious(startWith: pile.cards.value)
			.subscribe(onNext: { [weak self] oldCards, newCards in
				guard let self = self else { return }
				guard self.cardCollectionViewLayout?.movingCardActive != true else { return }
				guard oldCards != newCards else { return }
				
				var deletedIndexPaths: [IndexPath] = []
				var insertedIndexPaths: [IndexPath] = []
				let diff = newCards.difference(from: oldCards)
				
				self.collectionView.performBatchUpdates({
					// Gather the the index paths to be deleted and inserted via the diff
					for change in diff {
					  switch change {
					  case let .remove(offset, _, _):
						deletedIndexPaths.append(IndexPath(row: offset, section: 0))
					  case let .insert(offset, _, _):
						insertedIndexPaths.append(IndexPath(row: offset, section: 0))
					  }
					}

					self.collectionView.performBatchUpdates({
					  self.collectionView.deleteItems(at: deletedIndexPaths)
					  self.collectionView.insertItems(at: insertedIndexPaths)
					}, completion: { completed in
					})
				}, completion: { _ in
					if newCards.count > 1 && diff.insertions.count == 1 ,case .insert(let offset, let element, _)? = diff.insertions.first, !oldCards.contains(element) {
						self.cardCollectionViewLayout?.revealCardAt(index: offset)
					}
					
					let cell = self.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? HandCardCollectionViewCell
					if self.cardCollectionViewLayout?.revealedIndex != 0 {
//						cell?.cardRevealed(newCards.count == 1)
					}
				})
				
//				self?.collectionView.reloadData()
			}).disposed(by: bag)
		
//		NotificationCenter.default.addObserver(forName: .minimizedViewControllerDidChange, object: containerViewController, queue: nil) { notification in
////			self.collectionView.reloadData()
//			self.collectionView.collectionViewLayout.invalidateLayout()
//		}
	}
	
	deinit {
		NotificationCenter.default.removeObserver(self)
	}
	
	func setPile(_ pile: Pile) {
		self.pile = pile
		pile.cards
			.bind(to: self.cardInstances)
			.disposed(by: bag)
	}
	
	// MARK: CollectionView
	
	override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return cardInstances.value.count
	}
	
	override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "HandCardCollectionViewCell", for: indexPath) as! HandCardCollectionViewCell
		let cardInstance = pile.cards.value[indexPath.row]
		let card = cardInstance.representation
		
		cell.delegate = self
		
		cell.displayedCardInstanceID = cardInstance.uuid
		
		cell.shinyView.isHidden = !card.isFoil
		if card.isFoil {
			cell.shinyView.startUpdates()
		} else {
//			cell.shinyView.stopUpdates()
		}
		
		cell.layout = card.card.cardFaces?.count == 2 && card.card.layout != "transform" ? .split : .default
		
		if let faces = card.card.cardFaces, !faces.isEmpty {
			var faces = faces.prefix(2)
			
			if card.card.layout == "adventure" {
				faces.reverse()
			}
			
			for (face, button) in zip(faces, [cell.splitButtonLeft, cell.splitButtonRight]) {
				button?.setTitle(face.name, for: .normal)
			}
		} else {
			let cardIsLand = card.typeLine?.lowercased().contains("land") == true
			cell.button.setTitle(cardIsLand ? "Play" : "Cast", for: .normal)
			cell.button.setImage(nil, for: .normal)
		}
		
		cell.cardImageView.image = nil
				DispatchQueue.global(qos: .userInteractive).async {
					let image = card.image(type: .large, alwaysUpright: true)
		//			if let cgImage = image?.cgImage, card.layout == "split" {
		//				image = UIImage(cgImage: cgImage, scale: 1, orientation: .right)
		//			}
					
					DispatchQueue.main.async { [weak self] in
						guard let self = self, self.collectionView.indexPath(for: cell) == indexPath else { return }
						cell.cardImageView.image = image
					}
				}
		//		cell.cornerRadius = 80
		//        cell.backgroundColor = self.cardArray[indexPath.item].color
		//        cell.imageIcon?.image = self.cardArray[indexPath.item].icon
		//		cell.cardImageView?.image = UIImage(named: "card\((0...7).randomElement()!)")
		return cell
	}
	
	override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
//		guard collectionView.numberOfItems(inSection: 0) > 1 else { return }
		
		self.cardCollectionViewLayout?.revealCardAt(index: indexPath.item)
	}
	
	func handCardCollectionViewCellButtonPressed(_ cell: HandCardCollectionViewCell) {
		guard let indexPath = collectionView.indexPath(for: cell) else { return }
		let cardInstance = cardInstances.value[indexPath.item]
		
		if cardInstance.representation.card.layout == "transform", let faces = cardInstance.representation.card.cardFaces, faces.count >= 1 {
//			castSplitFace(faceIndex: cell.splitFaceIndex, cardInstance: cardInstance) // cast currently viewed face of split face
			if cell.splitFaceIndex == 0 {
				castSplitFace(faceIndex: 0, cardInstance: cardInstance)
			} else {
				flipCell(cell, toFaceIndex: 0)
			}
		} else {
			castCard(cardInstance: cardInstance)
		}
	}
	
	func handCardCollectionViewCellSplitLeftButtonPressed(_ cell: HandCardCollectionViewCell) {
		guard let indexPath = collectionView.indexPath(for: cell) else { return }
		let cardInstance = cardInstances.value[indexPath.item]
		let index = cardInstance.representation.card.layout == "adventure" ? 1 : 0
		castSplitFace(faceIndex: index, cardInstance: cardInstance)
	}
	
	func handCardCollectionViewCellSplitRightButtonPressed(_ cell: HandCardCollectionViewCell) {
		guard let indexPath = collectionView.indexPath(for: cell) else { return }
		let cardInstance = cardInstances.value[indexPath.item]
		let index = cardInstance.representation.card.layout == "adventure" ? 0 : 1
		castSplitFace(faceIndex: index, cardInstance: cardInstance)
	}
	
	func castCard(cardInstance: CardInstance) {
		let command = Command.moveCardsToBattlefield([Command.PlayCardParameters(cardInstanceID: cardInstance.uuid, faceIndex: nil)])
		AppDelegate.shared.transceiver.broadcast(command)
	}
	
	func castSplitFace(faceIndex: Int, cardInstance: CardInstance) {
		guard let faces = cardInstance.representation.card.cardFaces, faces.count >= 1 else { return }
		let command = Command.moveCardsToBattlefield([Command.PlayCardParameters(cardInstanceID: cardInstance.uuid, faceIndex: faceIndex)])
		AppDelegate.shared.transceiver.broadcast(command)
	}
	
	@IBAction func moreButtonPressed(sender: UIBarButtonItem) {
		guard let index = cardCollectionViewLayout?.revealedIndex, index >= 0 else { return }
		let indexPath = IndexPath(item: index, section: 0)
		showPlayCardMenu(forRowAt: indexPath)
	}
	
	fileprivate func flipCell(_ cell: HandCardCollectionViewCell, toFaceIndex faceIndex: Int) {
		guard cardInstances.value.contains(where: { $0.uuid == cell.displayedCardInstanceID }) else { return }
		guard let indexPath = collectionView.indexPath(for: cell) else { return }
		let cardInstance = cardInstances.value[indexPath.item]
		guard let faces = cardInstance.representation.card.cardFaces, !faces.isEmpty else { return }
		
		let face = faces[faceIndex]
		cell.splitFaceIndex = faceIndex
		
		DispatchQueue.global(qos: .userInteractive).async {
			let image = cardInstance.representation.card.image(type: .large, for: face)
			DispatchQueue.main.async {
				UIView.transition(with: cell.cardImageView, duration: 0.5, options: faceIndex == 0 ? .transitionFlipFromLeft : .transitionFlipFromRight, animations: {
					cell.cardImageView.image = image
				}, completion: nil)
				
				UIView.transition(with: cell.button, duration: 0.5, options: .transitionCrossDissolve, animations: {
					if faceIndex == 0 {
						let faceIsLand = face.typeLine?.lowercased().contains("land") == true
						cell.button.setTitle(faceIsLand ? "Play" : "Cast", for: .normal)
						cell.button.setImage(nil, for: .normal)
					} else {
						cell.button.setTitle(nil, for: .normal)
						cell.button.setImage(UIImage(systemName: "arrow.2.circlepath")?.withTintColor(#colorLiteral(red: 1, green: 1, blue: 1, alpha: 0.4487439572)), for: .normal)
					}
				}, completion: nil)
			}
		}
		
	}
	
	@IBAction func flipButtonPressed(sender: UIBarButtonItem) {
		guard let index = cardCollectionViewLayout?.revealedIndex, index >= 0 else { return }
		let indexPath = IndexPath(item: index, section: 0)
		guard let cell = collectionView.cellForItem(at: indexPath) as? HandCardCollectionViewCell else { return }
		
		let faceIndex = cell.splitFaceIndex == 0 ? 1 : 0
		flipCell(cell, toFaceIndex: faceIndex)
	}
	
	private func showPlayCardMenu(forRowAt indexPath: IndexPath) {
		
		let cardInstance = cardInstances.value[indexPath.row]
		let card = cardInstance.representation.card
		let isSingleFaced = (card.cardFaces?.count ?? 0) == 0
		
		let alert = UIAlertController(title: isSingleFaced ? card.name : nil, message: nil, preferredStyle: .actionSheet)
		alert.title = nil
		
		for action in self.actions(for: cardInstance, includeFaceCasts: false, includeIndividualCast: !isSingleFaced) where action.title != "View Card" && action.title != "Reveal to Opponent" {
			let alertAction = UIAlertAction(title: action.title, style: action.style) {
				action.handler?($0)
				if action.style != .cancel {
					self.cardCollectionViewLayout?.revealCardAt(index: indexPath.item)
				}
			}
			alert.addAction(alertAction)
		}
		
		let cell = collectionView.cellForItem(at: indexPath)
		alert.popoverPresentationController?.sourceView = cell
		alert.popoverPresentationController?.sourceRect = cell?.frame ?? .zero
		alert.view.transform = (navigationController?.view ?? view).transform
		
		self.present(alert, animated: true)
	}
	
	override func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
		let cardInstance = pile.cards.value[sourceIndexPath.row]
		GameState.current.move(cardInstances: [cardInstance], to: pile, at: destinationIndexPath.row)
	}
	
	func cardCollectionViewLayout(_ collectionViewLayout: HFCardCollectionViewLayout, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
		let cardInstance = pile.cards.value[destinationIndexPath.row]
		let destinationPileIdentifier = Command.MoveCommandParameters.PileIdentifier(location: .hand, playerIdentifier: pile.playerIdentifier)
		let parameters = Command.MoveCommandParameters(cardInstanceIDs: [cardInstance.uuid], destination: destinationPileIdentifier, insertionIndex: destinationIndexPath.row)
		let command = Command.moveCards(parameters)
		AppDelegate.shared.transceiver.broadcast(command)
	}
	
	func cardCollectionViewLayout(_ collectionViewLayout: HFCardCollectionViewLayout, willRevealCardAtIndex index: Int) {
		guard let cell = collectionView.cellForItem(at: IndexPath(row: index, section: 0)) as? HandCardCollectionViewCell else {
			return
		}
		
		let cardInstance = self.cardInstances.value[index]
		
		cell.cardRevealed(true)
		let isDoubleFaced = cardInstance.representation.card.layout == "transform"
		navigationItem.setLeftBarButton(isDoubleFaced ? flipButton : nil, animated: true)
		navigationItem.setRightBarButton(moreButton, animated: true)
		
		navigationItem.title = nil
		
	}
	
	func cardCollectionViewLayout(_ collectionViewLayout: HFCardCollectionViewLayout, willUnrevealCardAtIndex index: Int) {
		guard let cell = collectionView.cellForItem(at: IndexPath(row: index, section: 0)) as? HandCardCollectionViewCell else {
			return
		}
		
		cell.cardRevealed(false)
		
		navigationItem.setLeftBarButton(nil, animated: true)
		navigationItem.setRightBarButton(nil, animated: false)
		navigationItem.title = "Hand"
		
		if cell.splitFaceIndex != 0 {
			flipCell(cell, toFaceIndex: 0)
		}
		
	}
	
	private func setupExample() {
		let cardLayoutOptions = CardLayoutSetupOptions()
		
		if let cardCollectionViewLayout = self.collectionView?.collectionViewLayout as? HFCardCollectionViewLayout {
            self.cardCollectionViewLayout = cardCollectionViewLayout
        }
		
		self.cardCollectionViewLayout?.firstMovableIndex = cardLayoutOptions.firstMovableIndex
		self.cardCollectionViewLayout?.cardHeadHeight = cardLayoutOptions.cardHeadHeight
		self.cardCollectionViewLayout?.cardShouldExpandHeadHeight = cardLayoutOptions.cardShouldExpandHeadHeight
		self.cardCollectionViewLayout?.cardShouldStretchAtScrollTop = cardLayoutOptions.cardShouldStretchAtScrollTop
		self.cardCollectionViewLayout?.cardMaximumHeight = cardLayoutOptions.cardMaximumHeight
		self.cardCollectionViewLayout?.bottomNumberOfStackedCards = cardLayoutOptions.bottomNumberOfStackedCards
		self.cardCollectionViewLayout?.bottomStackedCardsShouldScale = cardLayoutOptions.bottomStackedCardsShouldScale
		self.cardCollectionViewLayout?.bottomCardLookoutMargin = cardLayoutOptions.bottomCardLookoutMargin
		self.cardCollectionViewLayout?.spaceAtTopForBackgroundView = cardLayoutOptions.spaceAtTopForBackgroundView
		self.cardCollectionViewLayout?.spaceAtTopShouldSnap = cardLayoutOptions.spaceAtTopShouldSnap
		self.cardCollectionViewLayout?.spaceAtBottom = cardLayoutOptions.spaceAtBottom
		self.cardCollectionViewLayout?.scrollAreaTop = cardLayoutOptions.scrollAreaTop
		self.cardCollectionViewLayout?.scrollAreaBottom = cardLayoutOptions.scrollAreaBottom
		self.cardCollectionViewLayout?.scrollShouldSnapCardHead = cardLayoutOptions.scrollShouldSnapCardHead
		self.cardCollectionViewLayout?.scrollStopCardsAtTop = cardLayoutOptions.scrollStopCardsAtTop
		self.cardCollectionViewLayout?.bottomStackedCardsMinimumScale = cardLayoutOptions.bottomStackedCardsMinimumScale
		self.cardCollectionViewLayout?.bottomStackedCardsMaximumScale = cardLayoutOptions.bottomStackedCardsMaximumScale
		
        self.collectionView?.reloadData()
    }
	
	// MARK: Actions
	
//	@IBAction func goBackAction() {
//		_ = self.navigationController?.popViewController(animated: true)
//	}
//
//	@IBAction func addCardAction() {
//		let index = 0
//		let newItem = createCardInfo()
//		self.cardArray.insert(newItem, at: index)
//		self.collectionView?.insertItems(at: [IndexPath(item: index, section: 0)])
//
//		if(self.cardArray.count == 1) {
//			self.cardCollectionViewLayout?.revealCardAt(index: index)
//		}
//	}
//
//	@IBAction func deleteCardAtIndex0orSelected() {
//		var index = 0
//		if(self.cardCollectionViewLayout!.revealedIndex >= 0) {
//			index = self.cardCollectionViewLayout!.revealedIndex
//		}
//		self.cardCollectionViewLayout?.flipRevealedCardBack(completion: {
//			self.cardArray.remove(at: index)
//			self.collectionView?.deleteItems(at: [IndexPath(item: index, section: 0)])
//		})
//	}
	
}
