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
import SwiftUI
import Combine
import CardView

class ObservableBridge<Input: Equatable>: ObservableObject {
	typealias Failure = Never
	
	@Published var value: Input {
		didSet {
			guard observable.value != value else { return }
			observable.accept(value)
		}
	}
	private let observable: BehaviorRelay<Input>
	
	private let bag = DisposeBag()
	
//	init(_ observable: Observable<Input>, initialValue: Input) {
//		self.value = initialValue
//		self.observable = observable
//
//		observable
//			.observeOn(MainScheduler.instance)
//			.subscribe(onNext: { [weak self] value in
//			self?.value = value
//		}).disposed(by: bag)
//	}
	
	init(_ behaviorRelay: BehaviorRelay<Input>) {
		self.value = behaviorRelay.value
		self.observable = behaviorRelay//.asObservable()
		
		behaviorRelay
			.observeOn(MainScheduler.instance)
			.subscribe(onNext: { [weak self] value in
				guard let self = self else { return }
				guard self.value != value else { return }
				self.value = value
		}).disposed(by: bag)
	}
  
  convenience init(_ observable: Observable<Input>, initialValue: Input) {
    let relay = BehaviorRelay(value: initialValue)
    
    self.init(relay)
    
    observable
      .bind(to: relay)
      .disposed(by: bag)
  }
}

struct HandCardView: View {
	@State var isVisible: Bool
	@State var card: MTGCard
	@State var face: MTGCard.Face?
	
	private static let back = Image("mtg-card-back-png-1").resizable()
  
  private var type: ImageType {
    if UIApplication.shared.keyWindow?.safeAreaInsets.bottom == 0 && UIDevice.current.userInterfaceIdiom == .phone {
      .small
    } else {
      .normal
    }
  }
	
  var body: some View {
    if isVisible {
      if let image = card.imageIfLoaded(type: type) {
        Image(uiImage: image).resizable()
      } else {
        AsyncImage(
          card: card,
          type: type,
          placeholder: Self.back.opacity(0.5),
          configuration: { $0.resizable() }
        )
      }
      
    } else {
      Self.back
    }
  }
}

struct AppliedView<Base: View, Result: View, ElseResult: View>: View {
	let condition: Bool
	let base: Base
	let applyIfTrue: (Base) -> Result
	let applyIfFalse: (Base) -> ElseResult
	
	var body: some View {
		Group {
			if condition {
				applyIfTrue(base)
			} else {
				applyIfFalse(base)
			}
		}
	}
}

extension View {
	func applyIf<ResultIfTrue: View, ResultIfFalse: View>(_ condition: Bool, ifTrue: @escaping (Self) -> ResultIfTrue, ifFalse: @escaping ((Self) -> ResultIfFalse)) -> some View {
		return AppliedView(condition: condition, base: self, applyIfTrue: ifTrue, applyIfFalse: ifFalse)
	}
	
	func applyIf<ResultIfTrue: View>(_ condition: Bool, ifTrue: @escaping (Self) -> ResultIfTrue) -> some View {
		return AppliedView(condition: condition, base: self, applyIfTrue: ifTrue, applyIfFalse: { $0 })
	}
}

struct HandView: View {

	@ObservedObject var hand: ObservableBridge<OrderedSet<CardInstance>>
  @ObservedObject var commandZone: ObservableBridge<OrderedSet<CardInstance>>
  
  @ObservedObject var debouncedHand = DebouncedValue(initialValue: [CardInstance](), delay: 0.7)
	
	let isLocalHand: Bool
	let isDragEnabled: Bool
	var isCardSelectionEnabled: Bool
	
	@ObservedObject var selectedCard: ObservableBridge<CardInstance?>
	
	let highlightColor = Color(#colorLiteral(red: 0.4745098054, green: 0.8392156959, blue: 0.9764705896, alpha: 1))
	
	var body: some View {
//			HStack {
//				ForEach(Array(self.cards.value.enumerated()), id: \.element.uuid) { (index, card) in
//					GeometryReader { gdeo in
//						HandCardView(isVisible: self.isLocalHand, card: card.representation.card)
//							.scaledToFit()
//							.cornerRadius(5)
//							.contextMenu(for: card)
//							.offset(y: self.cardIsSelected(card) ? -10 : 0)
//							.onTapGesture { self.select(card) }
//							.drag(card: self.isDragEnabled ? card : nil)
//							.gesture(DragGesture()
//								.onChanged { value in
//									print(card.representation.name, value)
//							})
//					}
//				}
//			}
    
    GeometryReader { proxy in
      FannedCardHandView(
        hand: self.hand.value.contents,
        commandZone: self.commandZone.value.contents,
        onTapGesture: select(_:),
        isVisible: isLocalHand,
        selectedCard: self.isCardSelectionEnabled ? selectedCard.value : nil,
        isDragEnabled: isDragEnabled,
        moveItemFromIndexToIndex: { sourceIndex, destinationIndex in
          guard isLocalHand else { return }
          
          let cardInstance = self.hand.value[sourceIndex]
          
          withAnimation {
            self.hand.value.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destinationIndex)
          }
          
          self.debouncedHand.liveValue = self.hand.value.contents
          
//          let command = Command.moveCards(Command.MoveCommandParameters(
//            cardInstanceIDs: [cardInstance.uuid],
//            destination: .init(
//              location: .hand,
//              playerIdentifier: cardInstance.owner
//            ),
//            insertionIndex: destinationIndex
//          ))
//          
//          AppDelegate.shared.transceiver.broadcast(command)
        }
      )
        .frame(height: proxy.size.height*2)
        .onChange(of: self.debouncedHand.debouncedValue) { newValue in
          guard isLocalHand, let playerIdentifier = AppDelegate.shared.role.playerIdentifier else { return }
          let command = Command.reorderHand(.init(cardInstanceIDs: newValue.map(\.uuid), playerIdentifier: playerIdentifier))
          AppDelegate.shared.transceiver.broadcast(command)
        }
      
        .gesture(DragGesture()
            .onChanged { value in
//              guard !isDragEnabled else { return }
              
              let allDisplayedCards = self.hand.value.contents + self.commandZone.value.contents
              let containsGap = !self.hand.value.isEmpty && !self.commandZone.value.isEmpty
              let allDisplayedCardsCount = containsGap ? allDisplayedCards.count+1 : allDisplayedCards.count
              
              guard value.location.y >= 0 else { return }
              
              let cardWidth = proxy.size.width / CGFloat(allDisplayedCardsCount)
              
              var index = (allDisplayedCardsCount)-1
              while cardWidth*CGFloat(index) >= value.location.x {
                index -= 1
              }
              
              if containsGap {
                if index == self.hand.value.count {
                  return
                } else if index > self.hand.value.count {
                  index -= 1
                }
              }
              
              // TODO: Take spacing into account in this calculation?
              
              guard allDisplayedCards.indices.contains(index) else { return }
              let cardInstance = allDisplayedCards[index]
              
              self.select(cardInstance)
          })
    }
	}
	
	private func overlayView(for card: CardInstance) -> some View {
		if cardIsSelected(card) {
			return AnyView(
				RoundedRectangle(cornerRadius: 5)
				.stroke(self.cardIsSelected(card) ? self.highlightColor : Color.clear, lineWidth: 1)
			)
		} else {
			return AnyView(EmptyView())
		}
	}
	
	private func cardIsSelected(_ card: CardInstance) -> Bool {
		return isCardSelectionEnabled && card.uuid == self.selectedCard.value?.uuid
	}
	
	private func select(_ cardInstance: CardInstance) {
    self.selectedCard.value = cardInstance
	}
  
  
	
}

extension View {
	
  @ViewBuilder
  func drag(card: CardInstance?, onDrag: (() -> Void)? = nil) -> some View {
		if let card = card {
      self
        .onDrag {
          onDrag?()
          return NSItemProvider(card: card)
        }
		} else {
			self
		}
	}
  
  @ViewBuilder
  func drag(card: CardInstance?, onDrag: (() -> Void)? = nil, preview: () -> some View) -> some View {
    if let card = card {
      self
        .onDrag({
          onDrag?()
          return NSItemProvider(card: card)
        }, preview: preview)
    } else {
      self
    }
  }
}

extension View {
	func contextMenu(for cardInstance: CardInstance) -> some View {
		return self
		
//		return contextMenu {
//				Button(action: {
//					// change country setting
//				}) {
//					Text("Choose Country")
//					Image(systemName: "globe")
//				}
//
//				Button(action: {
//					// enable geolocation
//				}) {
//					Text("Detect Location")
//					Image(systemName: "location.circle")
//				}
//		}
	}
}

class HandViewController: UIHostingController<HandView> {
	
	private let bag = DisposeBag()
	
	var player: Player! {
		didSet {
			bindHandCards()
		}
	}
	
	var isDragEnabled = false
	
	var hand: Pile {
		return player.hand
	}
  
  var commandZone: Pile {
    return player.commandZone
  }
	
	let selectedCard = BehaviorRelay<CardInstance?>(value: nil)
	
	var isCardSelectionEnabled: Bool = false {
		didSet {
			rootView.isCardSelectionEnabled = isCardSelectionEnabled
		}
	}
	
	private var isLocalHand: Bool {
		AppDelegate.shared.role.playerIdentifier == self.hand.playerIdentifier
	}
  
  let generator = UISelectionFeedbackGenerator()
	
	func bindHandCards() {
		rootView = HandView(
      hand: ObservableBridge(hand.cards),
      commandZone: ObservableBridge(commandZone.cards),
      isLocalHand: isLocalHand,
      isDragEnabled: isDragEnabled,
      isCardSelectionEnabled: isCardSelectionEnabled,
      selectedCard: ObservableBridge(selectedCard)
    )
		view.backgroundColor = .clear
		
//		let panGesturerecognizer = UIPanGestureRecognizer(target: self, action: #selector(gestureRecognized(sender:)))
//		view.addGestureRecognizer(panGesturerecognizer)
		
		let dropInteraction = UIDropInteraction(delegate: self)
		view.addInteraction(dropInteraction)
    
    selectedCard
      .subscribe(onNext: { [weak self] card in
        guard card != nil else { return }
        DispatchQueue.main.async {
          self?.generator.selectionChanged()
        }
      }).disposed(by: bag)
		
//		let dragInteraction = UIDragInteraction(delegate: self)
//		view.addInteraction(dragInteraction)
	}
		
//	@objc private func gestureRecognized(sender: UIGestureRecognizer) {
//		let location = sender.location(in: view)
//
//		guard let index = selectedIndex(for: location), hand.cards.value.indices.contains(index) else { return }
//
//		let cardInstance = hand.cards.value[index]
//		delegate?.handView(rootView, didSelect: cardInstance, at: index)
//	}
	
//	private func selectedIndex(for location: CGPoint) -> Int? {
//		guard location.y >= 0 else { return nil }
//
//		return (frames.sorted { $0.key < $1.key }.first { (arg) -> Bool in
//			let frame = arg.value
//
//			return frame.origin.x >= location.x
//			}?.key ?? hand.cards.value.count) - 1
//	}
	
	@objc required dynamic init?(coder aDecoder: NSCoder) {
    let handView = HandView(hand: ObservableBridge(BehaviorRelay(value: [])), commandZone: ObservableBridge(BehaviorRelay(value: [])), isLocalHand: false, isDragEnabled: false, isCardSelectionEnabled: false, selectedCard: ObservableBridge(BehaviorRelay(value: nil)))
		super.init(coder: aDecoder, rootView: handView)
	}
}

extension HandViewController: UIDropInteractionDelegate {
	
	func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
//		guard let context = session.localDragSession?.localContext as? HandViewController, context == self else { return false }
		return session.canLoadObjects(ofClass: CardInstance.self)
	}
	
	func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
		let cardInstances = session.items.compactMap { $0.cardInstance }
		let destinationPile = hand
		let allSourcesAndDestinationPilesAreEqual = cardInstances.allSatisfy({ (cardInstance) -> Bool in
			return cardInstance.pile == destinationPile
		})
		guard !allSourcesAndDestinationPilesAreEqual else {
			return UIDropProposal(operation: .cancel)
		}
		
		return UIDropProposal(operation: .move)
	}
	
	func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
		let destinationPile = hand

		let dropItems = session.items
			.sorted { (first, second) -> Bool in
				if let firstIndex = (first.cardInstance)?.indexInPile, let secondIndex = (second.cardInstance)?.indexInPile {
					return firstIndex > secondIndex
				}

				return false
		}
		
//		let destinationIndex = self.selectedIndex(for: session.location(in: view))
//		let destinationIndex: Int? = hand.cards.value.count

		for dropItem in dropItems {
			guard let cardInstance = dropItem.cardInstance else { continue }

			if cardInstance.pile == hand {
				print("Moving from same")
				
				hand.cards.mutate { cards in
					if let card = cards.remove(cardInstance) {
						cards.append(card)
					}
				}
				
				try? GameState.current.save()
			} else {
				GameState.current.move(cardInstances: [cardInstance], to: destinationPile)
			}
			
//			if cardInstance.pile == hand, let destinationIndex = destinationIndex {
//				print("Moving from same")
//
//				hand.cards.mutate { cards in
//					if let card = cards.remove(cardInstance) {
//						cards.insert(card, at: destinationIndex)
//					}
//				}
//
//				try? GameState.current.save()
//			} else {
//				GameState.current.move(cardInstances: [cardInstance], to: destinationPile)
//			}
		}
	}
	
}

//extension HandViewController: UIDragInteractionDelegate {
//	func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
//		session.localContext = self
//		liftedCards.mutate { $0.removeAll() }
//	}
//
////	func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: UIDragSession) {
////		session.localContext = self
////	}
//
//	func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, willEndWith operation: UIDropOperation) {
//		session.localContext = nil
//		print(#function)
//		liftedCards.mutate { $0.removeAll() }
//	}
//
////
////	func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
////		session.localContext = nil
////	}
//
//
////
//	func cardInstance(forTouchAt point: CGPoint) -> CardInstance? {
//		var point = point
//
//		point = view.convert(point, to: view.window)
//
//		guard let index = selectedIndex(for: point) else { return nil }
//		guard hand.cards.value.indices.contains(index) else { return nil }
//		return hand.cards.value[index]
//	}
//
////
//	func dragItem(for cardInstance: CardInstance, image: UIImage?) -> UIDragItem {
//		let item = NSItemProvider(card: cardInstance)
//		let dragItem = UIDragItem(itemProvider: item)
//		dragItem.localObject = cardInstance
//		dragItem.previewProvider = {
//			let imageView = UIImageView(image: image ?? #imageLiteral(resourceName: "mtg-card-back-png-1"))
//			imageView.contentMode = .scaleAspectFit
//
//			imageView.layer.masksToBounds = true
//			imageView.layer.cornerRadius = 5
//
//			imageView.frame.size = CGSize(width: 240/2.5, height: 335/2.5)
//
//			let parameters = UIDragPreviewParameters()
//			parameters.backgroundColor = .clear
//			return UIDragPreview(view: imageView, parameters: parameters)
//		}
//		return dragItem
//	}
//
//	func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
//		guard let cardInstance = self.cardInstance(forTouchAt: session.location(in: view)) else { return [] }
//		let dragItem = self.dragItem(for: cardInstance, image: #imageLiteral(resourceName: "mtg-card-back-png-1"))
//		print("Beginning with \(cardInstance.representation.name ?? "")")
//		liftedCards.mutate { $0.insert(cardInstance) }
//		return [dragItem]
//	}
//
//	func dragInteraction(_ interaction: UIDragInteraction, itemsForAddingTo session: UIDragSession, withTouchAt point: CGPoint) -> [UIDragItem] {
//		guard let cardInstance = self.cardInstance(forTouchAt: session.location(in: view)) else { return [] }
//		let cardInstances = session.items.compactMap { $0.cardInstance }
//		guard !cardInstances.contains(cardInstance) else { return [] }
//		let dragItem = self.dragItem(for: cardInstance, image: #imageLiteral(resourceName: "mtg-card-back-png-1"))
//		print("Adding \(cardInstance.representation.name ?? "")")
//		liftedCards.mutate { $0.insert(cardInstance) }
//		return [dragItem]
//	}
//}

/*
class HandCardCell: UICollectionViewCell {
	
	@IBOutlet weak var cardImageView: UIImageView!
	
}

class HandCollectionViewFlowLayout: UICollectionViewFlowLayout {
	var isVisualRotationEnabled = false
	
	override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
		guard isVisualRotationEnabled else { return nil }
		
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
	
	override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
		return true
	}
}

class HandViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
	
	var isVisualRotationEnabled: Bool {
		get {
			return (collectionViewLayout as! HandCollectionViewFlowLayout).isVisualRotationEnabled
		}
		set {
			_ = collectionView
			(collectionViewLayout as! HandCollectionViewFlowLayout).isVisualRotationEnabled = newValue
		}
	}
	
	var allowsReordering = false
	
	var isDragEnabled = false
	var selectedCard = BehaviorRelay<CardInstance?>(value: nil)
	var selectedCardInstance = BehaviorRelay<CardInstance?>(value: nil)
	var isCardSelectionEnabled: Bool = false
	
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
	
	var cardSpacing: CGFloat! {
		didSet {
			let layout = collectionView.collectionViewLayout as! HandCollectionViewFlowLayout
			layout.minimumLineSpacing = cardSpacing
			layout.invalidateLayout()
		}
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
		
		return cell
	}
	
    override func viewDidLoad() {
        super.viewDidLoad()
		
		collectionView.dropDelegate = self
		collectionView.dragDelegate = self
//		collectionView.dragInteractionEnabled = true
		
//		if cardSpacing == nil {
//			cardSpacing = -30
//		}
		
//		collectionView.contentInset = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
		
		_ = dataSource
		
		

        // Do any additional setup after loading the view.
    }
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		
		if !didInitialReload {
			bind()
			
			collectionView.collectionViewLayout.invalidateLayout()
			
			didInitialReload = true
		}
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
	
//	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
//		let collectionViewLayout = collectionViewLayout as! UICollectionViewFlowLayout
//		// Add inset to the collection view if there are not enough cells to fill the width.
//		let cellSpacing: CGFloat = collectionViewLayout.minimumLineSpacing
//		let cellWidth: CGFloat = collectionViewLayout.itemSize.width
//		let cellCount: Int = collectionView.numberOfItems(inSection: section)
//		var inset: CGFloat = collectionView.bounds.size.width
//		inset -= (CGFloat(cellCount) * cellWidth)
//		inset -= ((CGFloat(cellCount) - 1) * cellSpacing)
//		inset *= 0.5
//		inset = max(inset, 0.0)
//		return UIEdgeInsets(top: 0.0, left: inset, bottom: 0.0, right: 0.0)
//	}
	
	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
		let collectionViewLayout = collectionViewLayout as! UICollectionViewFlowLayout
		let numberOfItems = CGFloat(collectionView.numberOfItems(inSection: 0))
		
		var width: CGFloat = 98
		
		let totalWidth = collectionView.frame.width - collectionViewLayout.sectionInset.left - collectionViewLayout.sectionInset.right
		
		if (width * CGFloat(numberOfItems)) - (collectionViewLayout.minimumLineSpacing * numberOfItems-1) > totalWidth {
			width = (totalWidth - (collectionViewLayout.minimumLineSpacing * (numberOfItems-1))) / numberOfItems
		}
		
		let size = CGSize(width: width, height: collectionView.frame.height)
		
		print("Item size:", size)
		print("Collection view frame:", collectionView.frame.size)
		
		return size
		
//		if numberOfItems > 7 {
//			let extraCards = numberOfItems - 7
//			let scale: CGFloat = 0.88
//			for i in 0 ..< extraCards {
//				size.width *= scale
//				size.height *= scale
//			}
//		}
//
//		return size
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
		guard allowsReordering else { return false }
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
		guard isDragEnabled else { return [] }
		
		let cell = collectionView.cellForItem(at: indexPath) as? HandCardCell
		let cardInstance = self.cardInstance(forCardAt: indexPath)
		let dragItem = self.dragItem(for: cardInstance, image: cell?.cardImageView.image)
		return [dragItem]
	}
	
	func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
		guard isDragEnabled else { return [] }
		
		let cell = collectionView.cellForItem(at: indexPath) as? HandCardCell
		let cardInstance = self.cardInstance(forCardAt: indexPath)
		let cardInstances = session.items.compactMap { $0.localObject as? CardInstance }
		guard !cardInstances.contains(cardInstance) else { return [] }
		let dragItem = self.dragItem(for: cardInstance, image: cell?.cardImageView.image)
		return [dragItem]
	}
}*/
