//
//  HandViewController.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/7/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import CardService

class HandCardCell: UICollectionViewCell {
	
	@IBOutlet weak var cardImageView: UIImageView!
	
}

class HandCollectionViewFlowLayout: UICollectionViewFlowLayout {
	override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
		let layoutAttributes = super.layoutAttributesForElements(in: rect)
		
		if let layoutAttributes = layoutAttributes, layoutAttributes.count > 1 {
			let totalRotationAmount: CGFloat = CGFloat(layoutAttributes.count * 7)
			let step = totalRotationAmount / CGFloat(layoutAttributes.count-1)
			let distance = totalRotationAmount/2
			
			let steps = stride(from: -distance, through: distance, by: step)
			print(Array(steps))
			
			for (rotationAngle, attributes) in zip(steps, layoutAttributes) {
				attributes.transform = CGAffineTransform(rotationAngleDegrees: rotationAngle)
			}
		}
		
		return layoutAttributes
	}
}

class HandViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
	
	private let bag = DisposeBag()
	
	var player: Player!
	
	var hand: Pile {
		return player.hand
	}
	
	private enum Section {
		case hand
	}
	
	var isLocalHand: Bool {
		AppDelegate.shared.role.playerIdentifier == self.hand.playerIdentifier
	}
	
	private lazy var dataSource = UICollectionViewDiffableDataSource<Section, CardInstance>(collectionView: collectionView) { [weak self] collectionView, indexPath, cardItem -> UICollectionViewCell? in
		guard let self = self else { return  nil }
		guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "HandCardCell", for: indexPath) as? HandCardCell else { return UICollectionViewCell() }
		let card = cardItem.representation.card
		
//		cell.cardImageView.image = nil
		cell.cardImageView.image = #imageLiteral(resourceName: "mtg-card-back-png-1")
		
		if self.isLocalHand {
			DispatchQueue.global(qos: .userInteractive).async {
				let image = card.image(type: .small)
				DispatchQueue.main.async { [weak self, card] in
//					guard let self = self, card == self.hand.cards.value[indexPath.row] else { return }
					cell.cardImageView.image = image
				}
			}
		}
		
		cell.cardImageView.layer.cornerRadius = 7.5
		cell.cardImageView.layer.masksToBounds = true
		cell.cardImageView.backgroundColor = .black
		
		return cell	}
	
    override func viewDidLoad() {
        super.viewDidLoad()
		
		collectionView.dropDelegate = self
		collectionView.dragDelegate = self
//		collectionView.dragInteractionEnabled = true
		
		let layout = collectionView.collectionViewLayout as! HandCollectionViewFlowLayout
		layout.minimumLineSpacing = -30
		
		collectionView.contentInset = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
		
		_ = dataSource
		
		bind()
		
		collectionView.collectionViewLayout.invalidateLayout()

        // Do any additional setup after loading the view.
    }
	
	private var didInitialReload = false
	
	func bind() {
		hand.cards
		.observeOn(MainScheduler.instance)
//		.withPrevious(startWith: hand.cards.value)
		.subscribe(onNext: { [weak self] (cards) in
			guard let self = self else { return }
			var snapshot = NSDiffableDataSourceSnapshot<Section, CardInstance>()
			
			snapshot.appendSections([.hand])
			snapshot.appendItems(cards.contents)
			
			self.dataSource.apply(snapshot, animatingDifferences: true)
		}).disposed(by: bag)
	}
	
	var allHidden: Bool {
		return player.identifier != AppDelegate.shared.role.playerIdentifier
	}
	
	// MARK: UICollectionViewDelegateFlowLayout
	
	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
		let collectionViewLayout = collectionViewLayout as! UICollectionViewFlowLayout
		// Add inset to the collection view if there are not enough cells to fill the width.
		let cellSpacing: CGFloat = collectionViewLayout.minimumLineSpacing
		let cellWidth: CGFloat = collectionViewLayout.itemSize.width
		let cellCount: Int = collectionView.numberOfItems(inSection: section)
		var inset: CGFloat = collectionView.bounds.size.width
		inset -= (CGFloat(cellCount) * cellWidth)
		inset -= ((CGFloat(cellCount) - 1) * cellSpacing)
		inset *= 0.5
		inset = max(inset, 0.0)
		return UIEdgeInsets(top: 0.0, left: inset, bottom: 0.0, right: 0.0)
	}
	
	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
		let numberOfItems = collectionView.numberOfItems(inSection: 0)
		
		var size = CGSize(width: 98, height: 140)
		
		if numberOfItems > 7 {
			let extraCards = numberOfItems - 7
			let scale: CGFloat = 0.88
			for i in 0 ..< extraCards {
				size.width *= scale
				size.height *= scale
			}
		}
		
		return size
	}
	
//	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
//
//		let numberOfItems = collectionView.numberOfItems(inSection: 0)
//
////		let cardSize = CGSize(width: 72, height: 100)
////		return cardSize
//
//		let spacing = (collectionViewLayout as! UICollectionViewFlowLayout).minimumInteritemSpacing * CGFloat(numberOfItems-1)
//		let width = (self.collectionView.frame.width - spacing) / CGFloat(numberOfItems)
//		let height = self.collectionView.frame.height
//
//		print(width, height)
//		return CGSize(width: width, height: height)
//	}
	
//	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
//		return -10
//	}
	
//	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
//
//		let numberOfItems = collectionView.numberOfItems(inSection: 0)
//		let totalCellWidth: CGFloat = 70 * CGFloat(numberOfItems)
//		let totalSpacingWidth: CGFloat = self.collectionView(collectionView, layout: collectionViewLayout, minimumInteritemSpacingForSectionAt: section) * CGFloat(numberOfItems-1)
//
//		let leftInset = (collectionView.frame.width - CGFloat(totalCellWidth + totalSpacingWidth)) / 2
//		let rightInset = leftInset
//
//		return UIEdgeInsets(top: 0, left: leftInset, bottom: 0, right: rightInset)
//	}

}

extension HandViewController: UICollectionViewDropDelegate {
	
	func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
		return false
		// return true here to enable reordering 
		guard let context = session.localDragSession?.localContext as? HandViewController, context == self else { return false }
		return session.canLoadObjects(ofClass: CardInstance.self)
	}
	
	func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
		let cardInstances = session.items.compactMap { $0.localObject as? CardInstance }
		let destinationPile = hand
		let allSourcesAndDestinationPilesAreEqual = cardInstances.allSatisfy({ (cardInstance) -> Bool in
			return cardInstance.pile == destinationPile
		})
		guard !allSourcesAndDestinationPilesAreEqual else {
			return UICollectionViewDropProposal(operation: .cancel)
		}
		
		return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
	}
	
	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
		
		let destinationPile = hand
		
		let dropItems = coordinator.items
			.sorted { (first, second) -> Bool in
				if let firstIndex = (first.dragItem.localObject as? CardInstance)?.indexInPile, let secondIndex = (second.dragItem.localObject as? CardInstance)?.indexInPile {
					return firstIndex > secondIndex
				}
				
				return false
		}
		
		for dropItem in dropItems {
			guard let cardInstance = dropItem.dragItem.localObject as? CardInstance else { continue }
			
			if cardInstance.pile == hand, let destinationIndexPath = coordinator.destinationIndexPath {
				print("Moving from same")
				
				hand.cards.mutate { cards in
					if let card = cards.remove(cardInstance) {
						cards.insert(card, at: destinationIndexPath.item)
					}
				}
				coordinator.drop(dropItem.dragItem, toItemAt: destinationIndexPath)
				
				try? GameState.current.save()
			} else {
				GameState.current.move(cardInstances: [cardInstance], to: destinationPile)
			}
		}
	}
	
}

extension HandViewController: UICollectionViewDragDelegate {
	func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: UIDragSession) {
		session.localContext = self
	}
	
	func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
		session.localContext = nil
	}
	
	func cardInstance(forCardAt indexPath: IndexPath) -> CardInstance {
		return hand.cards.value[indexPath.row]
	}
	
	func dragItem(for cardInstance: CardInstance, image: UIImage?) -> UIDragItem {
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

	func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		let cell = collectionView.cellForItem(at: indexPath) as? HandCardCell
		let cardInstance = self.cardInstance(forCardAt: indexPath)
		let dragItem = self.dragItem(for: cardInstance, image: cell?.cardImageView.image)
		return [dragItem]
	}
	
	func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
		let cell = collectionView.cellForItem(at: indexPath) as? HandCardCell
		let cardInstance = self.cardInstance(forCardAt: indexPath)
		let cardInstances = session.items.compactMap { $0.localObject as? CardInstance }
		guard !cardInstances.contains(cardInstance) else { return [] }
		let dragItem = self.dragItem(for: cardInstance, image: cell?.cardImageView.image)
		return [dragItem]
	}
}
