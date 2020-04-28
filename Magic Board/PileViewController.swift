//
//  PileViewController.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/25/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import CardService

struct Action {
	var title: String?
	var style: UIAlertAction.Style
	var handler: ((Any) -> ())?
}

//enum Content {
//	case pile(Pile)
//	case cardItems(cards: BehaviorRelay<[UUID]>, owner: Player.Identifier)
//}

enum DisplayedContent: Equatable {
	case pile(Pile.Location)
	case revealedCards
	case battlefield
	
	var title: String {
		switch self {
		case .pile(let location): return location.rawValue
		case .revealedCards: return "Revealed Cards"
		case .battlefield: return "Battlefield"
		}
	}
}

protocol PileDisplaying: UIViewController {
	func setPile(_ pile: Pile)
	func actions(for cardInstance: CardInstance, includeFaceCasts: Bool, includeIndividualCast: Bool) -> [Action]
	var contentType: DisplayedContent { get }
	var pileLocation: Pile.Location? { get }
	var ownerIdentifier: Player.Identifier { get }
	func pushImageViewController(for cardInstance: CardInstance)
}

extension PileDisplaying {
	func actions(for cardInstance: CardInstance, includeFaceCasts: Bool = true, includeIndividualCast: Bool = true) -> [Action] {
		var actions: [Action] = []
		
		let card = cardInstance.representation.card
		
		let isSingleFaced = (card.cardFaces?.count ?? 0) == 0
//		let isSplitWithFuse = (card.cardFaces?.)
		// TODO: Make the "Play" text say "Cast (Fuse)" for split cards with fuse
		
		let play = "Play"
		let cast = "Cast"
		
		if includeFaceCasts {
			if let faces = card.cardFaces, !faces.isEmpty {
				for (faceIndex, face) in faces.enumerated() {
					let faceIsLand = face.typeLine?.lowercased().contains("land") == true
					let playAction = Action(title: "\(faceIsLand ? play : cast) \(face.name ?? "Face \(faceIndex+1)")", style: .default) { [weak self] (_) in
						guard let self = self else { return }
						//					let cardItem = CardItem(sourcePileLocation: self.pile.location, playerIdentifier: self.pile.playerIdentifier, sourceIndex: index)
						let command = Command.moveCardsToBattlefield([Command.PlayCardParameters(cardInstanceID: cardInstance.uuid, faceIndex: faceIndex)])
						AppDelegate.shared.transceiver.broadcast(command)
					}
					actions.append(playAction)
				}
			}
		}
		
		if includeIndividualCast {
			let playAction = Action(title: card.isLand || !isSingleFaced ? play : cast, style: .default) { [weak self] (_) in
				guard let self = self else { return }
				//			let cardItem = CardItem(sourcePileLocation: self.pile.location, playerIdentifier: self.pile.playerIdentifier, sourceIndex: index)
				let command = Command.moveCardsToBattlefield([Command.PlayCardParameters(cardInstanceID: cardInstance.uuid, faceIndex: nil)])
				AppDelegate.shared.transceiver.broadcast(command)
			}
			actions.append(playAction)
		}
		
		let playFaceDownAction = Action(title: "\(play) Face-down", style: .default) { [weak self] (_) in
			guard let self = self else { return }
			//			let cardItem = CardItem(sourcePileLocation: self.pile.location, playerIdentifier: self.pile.playerIdentifier, sourceIndex: index)
			let command = Command.moveCardsToBattlefield([Command.PlayCardParameters(cardInstanceID: cardInstance.uuid, faceIndex: -1)])
			AppDelegate.shared.transceiver.broadcast(command)
		}
		actions.append(playFaceDownAction)
		
		if case .pile(_) = contentType, pileLocation != .library {
			let revealAction = Action(title: "Reveal to Opponent", style: .default) { [weak self] _ in
				guard let self = self else { return }
				
				let parameters = Command.RevealCardsToPlayerParameters(cardInstanceIDs: [cardInstance.uuid], playerIdentifier: self.ownerIdentifier == .a ? .b : .a)
				let command = Command.revealCardsToPlayer(parameters)
				AppDelegate.shared.transceiver.broadcast(command)
			}
			actions.append(revealAction)
		}
		
		if pileLocation != .hand && cardInstance.ownerIdentifier == ownerIdentifier && cardInstance.revealedPlayers.value.contains(ownerIdentifier) {
			let discardAction = Action(title: "Move to Hand", style: .default) { [weak self] _ in
				guard let self = self else { return }
				let parameters = Command.MoveCommandParameters(cardInstanceIDs: [cardInstance.uuid], destination: Command.MoveCommandParameters.PileIdentifier(location: .hand, playerIdentifier: self.ownerIdentifier))
				let command = Command.moveCards(parameters)
				AppDelegate.shared.transceiver.broadcast(command)
			}
			actions.append(discardAction)
		}
		
		if pileLocation == .hand || pileLocation == .library || contentType == .revealedCards {
			let moveToTopAction = Action(title: "Move to Top of Library", style: .default) { [weak self] _ in
				guard let self = self else { return }
				let parameters = Command.MoveCommandParameters(cardInstanceIDs: [cardInstance.uuid], destination: Command.MoveCommandParameters.PileIdentifier(location: .library, playerIdentifier: self.ownerIdentifier)) // TODO: Figure out why 0 isn't working here.
				let command = Command.moveCards(parameters)
				AppDelegate.shared.transceiver.broadcast(command)
			}
			actions.append(moveToTopAction)
			
			let moveToBottomAction = Action(title: "Move to Bottom of Library", style: .default) { [weak self] _ in
				guard let self = self else { return }
				let parameters = Command.MoveCommandParameters(cardInstanceIDs: [cardInstance.uuid], destination: Command.MoveCommandParameters.PileIdentifier(location: .library, playerIdentifier: self.ownerIdentifier), insertionIndex: -1) // TODO: Figure out why 0 isn't working here.
				let command = Command.moveCards(parameters)
				AppDelegate.shared.transceiver.broadcast(command)
			}
			actions.append(moveToBottomAction)
		}
		
		if pileLocation == .hand {
			let discardAction = Action(title: "Discard", style: .destructive) { [weak self] _ in
				guard let self = self else { return }
				let parameters = Command.MoveCommandParameters(cardInstanceIDs: [cardInstance.uuid], destination: Command.MoveCommandParameters.PileIdentifier(location: .graveyard, playerIdentifier: self.ownerIdentifier))
				let command = Command.moveCards(parameters)
				AppDelegate.shared.transceiver.broadcast(command)
			}
			actions.append(discardAction)
			
			let exileAction = Action(title: "Exile", style: .destructive) { [weak self] _ in
				guard let self = self else { return }
				let parameters = Command.MoveCommandParameters(cardInstanceIDs: [cardInstance.uuid], destination: Command.MoveCommandParameters.PileIdentifier(location: .exile, playerIdentifier: self.ownerIdentifier))
				let command = Command.moveCards(parameters)
				AppDelegate.shared.transceiver.broadcast(command)
			}
			actions.append(exileAction)
		}
		
		
		let viewAction = Action(title: "View Card", style: .default) { [weak self] _ in
			self?.pushImageViewController(for: cardInstance)
		}
		actions.append(viewAction)
		
		let cancelAction = Action(title: "Cancel", style: .cancel, handler: nil)
		actions.append(cancelAction)
		
		return actions
	}
}

class PileViewController: UITableViewController, PileDisplaying {
	
	private func alphabetize<S: Sequence>(_ cardInstances: S) -> [CardInstance] where S.Element == CardInstance {
		return cardInstances.sorted(by: { (first, second) -> Bool in
			if case .faceDown(_) = first.representation {
				return false
			}
			
			if case .faceDown(_) = second.representation {
				return true
			}
			
			if let firstName = first.representation.name, let secondName = second.representation.name {
				return firstName < secondName
			}
			
			if first.representation.name != nil {
				return true
			}
			
			return false
		})
	}
	
	private func filter<S: Sequence>(_ cardInstances: S, showOnlyCardsBelongingTo playerIdentifier: Player.Identifier) -> [CardInstance] where S.Element == CardInstance {
		return cardInstances.filter {
			if let pile = $0.pile {
				return pile.playerIdentifier == playerIdentifier
			} else {
				return GameState.current.battlefield.value.contains(where: { ($0.controllerIdentifier.value == playerIdentifier || $0.ownerIdentifier == playerIdentifier) && $0.representation.card == $0.representation.card })
			}
		}
	}
	
	private func filter<S: Sequence>(_ cardInstances: S, searchText: String?, includeFlavorText: Bool = false) -> [CardInstance] where S.Element == CardInstance {
		guard let searchText = searchText?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !searchText.isEmpty else { return Array(cardInstances) }
		
		return cardInstances.filter {
			if case .faceDown(_) = $0.representation {
				return false
			}
			
			// TODO: Match symbol names in oracle text
			
			if $0.representation.name?.lowercased().contains(searchText) == true {
				return true
			}
			if $0.representation.typeLine?.lowercased().contains(searchText) == true {
				return true
			}
			if $0.representation.oracleText?.lowercased().contains(searchText) == true {
				return true
			}
			if includeFlavorText && $0.representation.flavorText?.lowercased().contains(searchText) == true {
				return true
			}
			if $0.representation.power == searchText {
				return true
			}
			if $0.representation.toughness == searchText {
				return true
			}
			if $0.representation.loyalty == searchText {
				return true
			}
			if $0.representation.convertedManaCost.flatMap(Int.init).map(String.init) == searchText {
				return true
			}
			if let power = $0.representation.power, let toughness = $0.representation.toughness, "\(power)/\(toughness)" == searchText {
				return true
			}
			
			for face in $0.representation.card.cardFaces ?? [] {
				if face.name?.lowercased().contains(searchText) == true {
					return true
				}
				if face.typeLine?.lowercased().contains(searchText) == true {
					return true
				}
				if face.oracleText?.lowercased().contains(searchText) == true {
					return true
				}
				if includeFlavorText && face.flavorText?.lowercased().contains(searchText) == true {
					return true
				}
				if face.power == searchText {
					return true
				}
				if face.toughness == searchText {
					return true
				}
				if face.loyalty == searchText {
					return true
				}
				if let power = face.power, let toughness = face.toughness, "\(power)/\(toughness)" == searchText {
					return true
				}
			}
			
			return false
		}
	}
	
	private func sortByManaCost<S: Sequence>(_ cardInstances: S) -> [CardInstance] where S.Element == CardInstance {
		return cardInstances.sorted(by: { (first, second) -> Bool in
			var firstCost = first.representation.convertedManaCost ?? 0
			var secondCost = second.representation.convertedManaCost ?? 0
			if case .faceDown(_) = first.representation {
				firstCost = 0
			}
			
			if case .faceDown(_) = second.representation {
				secondCost = 0
			}
			
			return firstCost > secondCost
		})
	}
	
	func setPile(_ pile: Pile) {
		ownerIdentifier = pile.playerIdentifier
		
		contentType = .pile(pile.location)
		
		if isPrivate && isOwned && pile.location != .library {
			cardsAreVisible = true
		} else {
			cardsAreVisible = !pile.isHidden
		}
		
		if cardsAreVisible {
			navigationItem.searchController = searchController
		}
			
		bindCardInstances(pile.cards.asObservable())
	}
	
	func setCardInstances(_ cardInstances: Observable<OrderedSet<CardInstance>>, owner: Player.Identifier, contentType: DisplayedContent, cardsAreVisible: Bool = true) {
		ownerIdentifier = owner
		
		self.cardsAreVisible = cardsAreVisible
		
		self.contentType = contentType
		
		if cardsAreVisible {
			navigationItem.searchController = searchController
		}
		
		bindCardInstances(cardInstances)
	}
	
	private let filteredPlayerIdentifier: BehaviorRelay<Player.Identifier?> = BehaviorRelay(value: nil)
	
	private func bindCardInstances(_ cardInstances: Observable<OrderedSet<CardInstance>>) {
		bag = DisposeBag()
		
		Observable.combineLatest(cardInstances, displayOrder, shouldReverseOrder, filteredPlayerIdentifier, searchController.searchBar.rx.text)
			.map { [weak self] cardInstances, displayOrder, shouldReverseOrder, filteredPlayerIdentifier, searchText in
				guard let self = self else { return [] }
				var cardItems: [CardInstance] = {
					if let filter = filteredPlayerIdentifier {
						return self.filter(cardInstances, showOnlyCardsBelongingTo: filter)
					} else {
						return cardInstances.contents
					}
				}()
				
				// TODO: When pressing 'done' during a search, the search bar's text is not cleared out!
				cardItems = self.filter(cardItems, searchText: searchText)
				
				
			switch displayOrder {
			case .actual:
				return OrderedSet(cardItems)
			case .alphabetical:
				var sorted = self.alphabetize(cardItems)
				if shouldReverseOrder {
					sorted.reverse()
				}
				return OrderedSet(sorted)
			case .convertedManaCost:
				var sorted = self.sortByManaCost(cardItems)
				if shouldReverseOrder {
					sorted.reverse()
				}
				return OrderedSet(sorted)
			}
		}.bind(to: self.cardInstances)
		.disposed(by: bag)
		
		updateTableHeaderView()
	}
	
	enum DisplayOrder: Int, Equatable, CaseIterable {
		typealias AllCases = [DisplayOrder]
		
		case actual
		case alphabetical
		case convertedManaCost
		
		static var allCases: [DisplayOrder] {
			return [.actual, .alphabetical, .convertedManaCost]
		}
		
		func name(for contentType: DisplayedContent) -> String {
			switch self {
			case .actual:
				return contentType == .battlefield ? "Recent" : "Actual"
			case .alphabetical:
				return "Name"
			case .convertedManaCost:
				return "CMC"
			}
		}
	}
	
	private(set) var contentType: DisplayedContent = .revealedCards
	
	let displayOrder: BehaviorRelay<DisplayOrder> = BehaviorRelay(value: .actual)
	
	/// If the value of `pileLocation` is `nil`, then we're not looking at a pile; we're looking at revealed cards.
	var pileLocation: Pile.Location? {
		switch contentType {
		case .pile(let location):
			return location
		default:
			return nil
		}
	}
	var ownerIdentifier: Player.Identifier = .a
	let cardInstances = BehaviorRelay<OrderedSet<CardInstance>>(value: [])
	
	private var bag = DisposeBag()
	
	private lazy var emptyTableViewDropDelegate = EmptyTableViewDropDelegate(pileViewController: self, canHandleSession: { [weak self] _ in
		guard let self = self else { return false }
		return self.tableView.numberOfRows(inSection: 0) == 0
		}, dropIndexProvider: { IndexPath(row: 0, section: 0) })
	
	private lazy var dropAtBottomDropDelegate = EmptyTableViewDropDelegate(pileViewController: self, canHandleSession: { [weak self] session in
	guard let self = self else { return false }
		return self.tableView(self.tableView, canHandle: session)
	}, dropIndexProvider: { [weak self] in
		guard let self = self else { return IndexPath(row: 0, section: 0) }
		return IndexPath(row: self.cardInstances.value.count, section: 0) }
	)
	
	private lazy var dragAllDelegate = DragAllDelegate(pileViewController: self)
	
	var cardsAreVisible: Bool = false {
		didSet {
			if isViewLoaded {
//				tableView.reloadSections(IndexSet(integer: 0), with: .fade)
				tableView.reloadData()
				navigationItem.rightBarButtonItem?.isEnabled = !cardsAreVisible
			}
		}
	}
	
	private lazy var revealButtonItem: UIBarButtonItem = {
//		UIBarButtonItem(title: "Reveal", style: .plain, target: self, action: #selector(reveal))
//		let item = self.editButtonItem
//		item.title = "Reveal"
//		return item
		
		return UIBarButtonItem(title: "Reveal", style: .plain, target: self, action: #selector(enableReveal))
	}()
	
	private lazy var confirmRevealButtonItem: UIBarButtonItem = {
		return UIBarButtonItem(title: "Reveal", style: .done, target: self, action: #selector(confirmReveal))
	}()
	
	private lazy var cancelRevealButtonItem: UIBarButtonItem = {
		return UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelReveal))
	}()
	
	@objc private func cancelReveal() {
		setEditing(false, animated: true)
		
		updateButtonItems(animated: true)
	}
	
	@objc private func confirmReveal(sender: UIBarButtonItem) {
		let selectedCount = tableView.indexPathsForSelectedRows?.count ?? 0
		guard selectedCount > 0 else {
			setEditing(false, animated: true)
			updateButtonItems(animated: true)
			return
		}
		let alert = UIAlertController(title: "Reveal \(selectedCount) Card\(selectedCount == 1 ? "" : "s") to…", message: nil, preferredStyle: .actionSheet)
		
		for player in GameState.current.allPlayers {
			let revealAction = UIAlertAction(title: player.name.value, style: .default) { [weak self] _ in
				self?.revealCardsForSelectedRows(to: player)
				self?.setEditing(false, animated: true)
				self?.updateButtonItems(animated: true)
			}
			alert.addAction(revealAction)
		}
		
		let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
		alert.addAction(cancelAction)
		
		alert.popoverPresentationController?.barButtonItem = sender
		self.present(alert, animated: true, completion: nil)
	}
	
	private func updateButtonItems(animated: Bool) {
		if case .revealedCards = contentType, isLocalPhone {
			navigationItem.setLeftBarButton(dismissSavedViewControllerButtonItem, animated: animated)
			navigationItem.setRightBarButton(nil, animated: animated)
		} else if isEditing {
			navigationItem.setRightBarButton(confirmRevealButtonItem, animated: animated)
			navigationItem.setLeftBarButton(cancelRevealButtonItem, animated: animated)
		} else {
			if AppDelegate.shared.role.isBoard {
				let rotateButton = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(rotateView))
				navigationItem.setLeftBarButton(rotateButton, animated: animated)
			}
			
			if !cardsAreVisible && !isLocalPhone {
				navigationItem.setRightBarButton(revealButtonItem, animated: animated)
			}
			
			if pileLocation == .library && AppDelegate.shared.role.isBoard {
				navigationItem.setLeftBarButton(shuffleButtonItem, animated: animated)
			}
			
			if pileLocation == .library && isLocalPhone {
				navigationItem.setLeftBarButton(loadDeckButtonItem, animated: animated)
			}
		}
	}
	
	private var editingSetFromReveal = false
	
	@objc private func enableReveal() {
		editingSetFromReveal = true
		setEditing(true, animated: true)
		updateButtonItems(animated: true)
	}
	
	private lazy var shuffleButtonItem: UIBarButtonItem = {
		UIBarButtonItem(title: "Shuffle", style: .plain, target: self, action: #selector(shuffle))
	}()

	private lazy var loadDeckButtonItem: UIBarButtonItem = {
		UIBarButtonItem(title: "Load", style: .plain, target: self, action: #selector(presentLoadDeckDocumentPicker))
	}()
	
	private var isLocalPhone: Bool {
		return isPrivate && !AppDelegate.shared.role.isBoard
	}
	
	private var isPrivate: Bool {
		return AppDelegate.shared.role.playerIdentifier != nil
	}
	
	private var isOwned: Bool {
		return AppDelegate.shared.role.playerIdentifier == ownerIdentifier
	}
	
	let isReorderingAllowed = true
	
	@IBOutlet weak var dragAllLabel: UILabel?
	@IBOutlet weak var dropToBottomLabel: UILabel?
	@IBOutlet weak var dragDropStackView: UIView?
	@IBOutlet weak var revealAllButton: UIButton?
	@IBOutlet var sortStackView: UIView!
	@IBOutlet weak var sortModeSegmentedControl: UISegmentedControl!
	@IBOutlet weak var filterSegmentedControl: UISegmentedControl!
	
	private let searchController: UISearchController = {
		let controller = UISearchController(searchResultsController: nil)
		controller.obscuresBackgroundDuringPresentation = false
		return controller
	}()
	
	fileprivate func updateTableHeaderView() {
		if contentType == .battlefield {
			tableView.tableHeaderView = sortStackView
			tableView.contentOffset = CGPoint(x: 0, y: sortStackView.frame.height)
		} else if pileLocation != .library {
			tableView.tableHeaderView = nil
		}
	}
	
	override func viewDidLoad() {
        super.viewDidLoad()
		
		tableView.dragInteractionEnabled = true
		tableView.dragDelegate = self
		tableView.dropDelegate = self
		
		tabBarController?.tabBar.items?.forEach({ (item) in
			item.isSpringLoaded = true
		})
		
		let dropInteraction = UIDropInteraction(delegate: emptyTableViewDropDelegate)
		tableView.addInteraction(dropInteraction)
		
		updateTitle()
		
		let dragAllInteraction = UIDragInteraction(delegate: dragAllDelegate)
		dragAllLabel?.isUserInteractionEnabled = true
		dragAllLabel?.addInteraction(dragAllInteraction)
		
		let dropAtBottomInteraction = UIDropInteraction(delegate: dropAtBottomDropDelegate)
		dropToBottomLabel?.isUserInteractionEnabled = true
		dropToBottomLabel?.addInteraction(dropAtBottomInteraction)
		
		dropToBottomLabel?.layer.cornerRadius = 8
		dropToBottomLabel?.layer.masksToBounds = true
		dragAllLabel?.layer.cornerRadius = 8
		dragAllLabel?.layer.masksToBounds = true
		
		sortModeSegmentedControl.removeAllSegments()
		for mode in DisplayOrder.allCases {
			sortModeSegmentedControl.insertSegment(withTitle: mode.name(for: contentType), at: sortModeSegmentedControl.numberOfSegments, animated: false)
		}
		
		sortModeSegmentedControl.selectedSegmentIndex = displayOrder.value.rawValue
		
		sortModeSegmentedControl.rx.selectedSegmentIndex
			.compactMap(DisplayOrder.init(rawValue:))
			.bind(to: displayOrder)
			.disposed(by: bag)
		
		filterSegmentedControl.removeAllSegments()
		let oppositeID: Player.Identifier = ownerIdentifier == .a ? .b : .a
		let titles = ["Mine", "All", "Opponent's"]
		let ids: [Player.Identifier?] = [ownerIdentifier, nil, oppositeID]
		updateTableHeaderView()
		for title in titles {
			filterSegmentedControl.insertSegment(withTitle: title, at: filterSegmentedControl.numberOfSegments, animated: false)
		}
		
		filterSegmentedControl.selectedSegmentIndex = 1
		
		filterSegmentedControl.rx.selectedSegmentIndex
			.map { ids[$0] }
			.bind(to: filteredPlayerIdentifier)
			.disposed(by: bag)
		
//		displayOrder
//		.compactMap { $0.rawValue }
//		.bind(to: sortModeSegmentedControl.rx.selectedSegmentIndex)
//		.disposed(by: bag)
		
		updateButtonItems(animated: false)

		cardInstances
			.withPrevious(startWith: cardInstances.value)
			.subscribe(onNext: { [weak self] (oldValue, cardInstances) in
			guard oldValue != cardInstances else { return }
			self?.tableView.reloadData()
//			self?.tableView.reloadSections(IndexSet(integer: 0), with: .fade)
			if AppDelegate.shared.role.isBoard {
				self?.updateTitle()
			}
		}).disposed(by: bag)
		
		// TODO: Make it so if you're looking at your library and more cards are revealed, the cells reload.
		
//		searchController.searchBar.delegate = self
    }
	
	@IBAction func revealAllButtonPressed(_ sender: Any) {
		let numberOfRows = tableView.numberOfRows(inSection: 0)
		guard numberOfRows > 0 else { return }
		for index in 0 ..< numberOfRows {
			let indexPath = IndexPath(row: index, section: 0)
			tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
		}
	}
	
	@objc private func presentLoadDeckDocumentPicker() {
		let picker = UIDocumentPickerViewController(documentTypes: ["public.plain-text"], in: .import)
		picker.allowsMultipleSelection = false
		picker.delegate = self
		present(picker, animated: true)
	}
	
	private func updateTitle() {
		if isLocalPhone {
			let opponents = pileLocation != nil && !isOwned ? "Opponent's " : ""
			navigationItem.title = opponents + contentType.title
		} else {
			let cardCount = cardInstances.value.count
			self.navigationItem.title = "\(cardCount) Card\(cardCount == 1 ? "" : "s")"
		}
	}
	
	@objc private func reveal() {
		cardsAreVisible = true
//		let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
//		let revealAction = UIAlertAction(title: "Reveal", style: .default) { [weak self] (_) in
//			self?.cardsAreVisible = true
//		}
//		alert.addAction(revealAction)
//
//		let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
//		alert.addAction(cancelAction)
//
//		alert.popoverPresentationController?.barButtonItem = revealButtonItem
//		alert.view.transform = (navigationController?.view ?? view).transform
//
//		present(alert, animated: true, completion: nil)
	}
	
	/// Shuffles the pile, if we're looking at a pile. If we're not, this method does nothing.
	@objc private func shuffle() {
		if let location = pileLocation {
			let pile = GameState.current[player: ownerIdentifier][location]
			pile.cards.mutate {
				$0 = OrderedSet($0.shuffled())
			}
			try? GameState.current.save()
		}
		
	}
	
	@objc private func rotateView() {
		guard let view = navigationController?.view ?? view else { return }
		view.transform = view.transform.rotated(by: .pi)
	}
	
	private var expandedCardInstances: Set<CardInstance> = []
	
	private let shouldReverseOrder = BehaviorRelay<Bool>(value: true)
	
	func cardInstance(for indexPath: IndexPath) -> CardInstance {
		var cardInstances = self.cardInstances.value.contents
		if shouldReverseOrder.value {
			cardInstances.reverse()
		}
		return cardInstances[indexPath.row]
	}
	
	func card(forRowAt indexPath: IndexPath) -> MTGCard {
		return cardInstance(for: indexPath).representation.card
	}
	
	private func indexOfCard(forRowAt indexPath: IndexPath) -> Int {
		if shouldReverseOrder.value {
			return cardInstances.value.count - indexPath.row - 1
		} else {
			return indexPath.row
		}
	}
    
	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return cardInstances.value.count
	}
	
	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}
	
	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		
		guard let cell = tableView.dequeueReusableCell(withIdentifier: "CardListCell", for: indexPath) as? CardTableViewCell else { return UITableViewCell() }
		
		let instance = self.cardInstance(for: indexPath)
		let card = instance.representation.card
		
		guard cardsAreVisible || (isOwned && isLocalPhone && cardIsRevealed(forRowAt: indexPath)) else {
			cell.cardImageView.image = #imageLiteral(resourceName: "mtg-card-back-png-1")
			
			cell.layout = .default
			cell.set(content: CardTableViewCell.Content(title: nil, cost: nil, type: nil, oracleText: nil), for: .front)
			
			return cell
		}
		
		cell.cardImageView.image = nil
		DispatchQueue.global(qos: .userInteractive).async {
			let image = card.image(type: .small)
//			if let cgImage = image?.cgImage, card.layout == "split" {
//				image = UIImage(cgImage: cgImage, scale: 1, orientation: .right)
//			}
			
			DispatchQueue.main.async { [weak self] in
				guard let self = self, self.tableView.indexPath(for: cell) == indexPath else { return }
				cell.cardImageView.image = image
			}
		}
		
		cell.layout = card.cardFaces?.count == 2 ? .split : .default
		
		func typeLineWithPowerToughness(typeLine: String?, power: String?, toughness: String?, loyalty: String?) -> String? {
			if let power = power, let toughness = toughness {
				var text = power.replacingOccurrences(of: "*", with: "★")
				text += "/"
				text += toughness.replacingOccurrences(of: "*", with: "★")
				if let typeLine = typeLine {
					return "\(text) \(typeLine)"
				} else {
					return text
				}
			} else if let text = loyalty {
				if let typeLine = typeLine {
					return "\(typeLine) <\(text)>"
				} else {
					return text
				}
			} else {
				return typeLine
			}
		}
		
		switch card.layout {
		case _ where card.cardFaces?.count == 2:
			cell.layout = .split
			
			let cardFaces = card.cardFaces?.prefix(upTo: 2) ?? []
			
			let layoutFaces: [CardTableViewCell.Face] = [.front, .split]
			for (cardFace, layoutFace) in zip(cardFaces, layoutFaces) {
				
				let typeLine = typeLineWithPowerToughness(typeLine: cardFace.typeLine, power: cardFace.power, toughness: cardFace.toughness, loyalty: cardFace.loyalty)
				
				var oracleText = cardFace.oracleText
				if var lines = oracleText?.split(separator: "\n"),
					let fuseLineIndex = lines.lastIndex(where: { $0.hasPrefix("Fuse") }) {
					let fuseText = String(lines[fuseLineIndex])
					cell.setFuseLabelText(fuseText)
					lines.remove(at: fuseLineIndex)
					oracleText = lines.joined(separator: "\n")
				} else {
					cell.setFuseLabelText(nil)
				}
				
				let hasAdventure = card.typeLine?.lowercased().contains("adventure") == true
				let shouldShowFlavorText = hasAdventure ? cardFace.typeLine?.lowercased().contains("adventure") == false : cardFace == cardFaces.last
				
				let content = CardTableViewCell.Content(
					title: cardFace.name,
					cost: cardFace.manaCost,
					type: typeLine,
					oracleText: oracleText,
					flavorText: shouldShowFlavorText && card.language == .english ? card.flavorText : nil)
				cell.set(content: content, for: layoutFace)
			}
		default:
			cell.layout = .default
			
			let typeLine = typeLineWithPowerToughness(typeLine: card.typeLine, power: card.power, toughness: card.toughness, loyalty: card.loyalty)
			
			let multifaceOracleText: String? = {
				if let faces = card.cardFaces, !faces.isEmpty {
					return faces.map { $0.oracleText ?? "" }.joined(separator: "\n//\n")
				}
				return nil
			}()
			
			var oracleText = multifaceOracleText ?? card.oracleText
			if card.isBasicLand {
				oracleText = nil
			}
			
			let content = CardTableViewCell.Content(
				title: card.name,
				cost: card.manaCost,
				type: typeLine,
				oracleText: oracleText,
				flavorText: card.language == .english ? card.flavorText : nil)
			
			cell.set(content: content, for: .front)
			
			cell.setFuseLabelText(nil)
		}
		
		let oracleLines = isLocalPhone || self.expandedCardInstances.contains(instance) ? 0 : 4
		cell.oracleLabel.numberOfLines = oracleLines
		cell.splitFaceOracleLabel.numberOfLines = oracleLines
		
		return cell
	}
	
	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if isEditing {
			return
		}
		
		defer {
			tableView.deselectRow(at: indexPath, animated: true)
		}
		
		if isLocalPhone {
			if localPhoneAllowsPlayingCards || cardIsRevealed(forRowAt: indexPath) {
				showPlayCardMenu(forRowAt: indexPath)
			} else if cardsAreVisible {
				pushImageViewController(forRowAt: indexPath)
			}
		} else {
			toggleExpandedState(forRowAt: indexPath)
		}
	}
	
	override func setEditing(_ editing: Bool, animated: Bool) {
		super.setEditing(editing, animated: animated)
		
		if isEditing {
			if editingSetFromReveal {
				if let stackView = dragDropStackView {
					UIView.transition(with: stackView, duration: 0.2, options: .transitionCrossDissolve, animations: { [weak self] in
						self?.revealAllButton?.isHidden = false
						self?.dropToBottomLabel?.isHidden = true
						}, completion: nil)
				}
			}
			
//			for revealedCardItem in GameState.current[player: ownerIdentifier].revealedCards.value {
//				if let index = self.cardItems.value.map({ $0.source }).firstIndex(of: revealedCardItem.source) {
//					let indexPath = IndexPath(row: index, section: 0)
////					self.tableView(tableView, didSelectRowAt: indexPath)
////					tableView.selectRow(at: indexPath, animated: animated, scrollPosition: .none)
//
//				}
//			}
		} else {
			editingSetFromReveal = false
			if let stackView = dragDropStackView {
				UIView.transition(with: stackView, duration: 0.2, options: .transitionCrossDissolve, animations: { [weak self] in
					self?.revealAllButton?.isHidden = true
					self?.dropToBottomLabel?.isHidden = false
				}, completion: nil)
			}
		}
		
		tableView.beginUpdates()
		tableView.endUpdates()
	}
	
	override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		if editingSetFromReveal {
			return 70
		} else {
			return UITableView.automaticDimension
		}
	}
	
	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		if editingSetFromReveal && !cell.isSelected {
			let shouldSelect = cardIsRevealed(forRowAt: indexPath)
			cell.setSelected(shouldSelect, animated: false)
		}
	}
	
	override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		guard AppDelegate.shared.role.isBoard else { return nil }
		
		var actions: [UIContextualAction] = []
		
		let cardInstance = self.cardInstance(for: indexPath)
		
		switch pileLocation {
		case .library?:
//			let discardAction = UIContextualAction(style: .destructive, title: "Discard") { [weak self] (action, view, completion) in
//							guard let self = self else { return }
//							let destinationPile = GameState.current[player: self.ownerIdentifier].graveyard
//			//				self.revealCards([cardItem], to: GameState.current.player2)
//							switch cardItem.source {
//							case .pile(let identifier):
//								guard let pile = identifier.pile else { break }
//								GameState.current.move(cardsAt: IndexSet(integer: identifier.index), from: pile, to: destinationPile)
//							case .cardInstance(let identifier):
//								guard let cardInstance = identifier.cardInstance else { break }
//								GameState.current.move(cardInstances: [cardInstance], to: destinationPile)
//							}
//							try? GameState.current.save()
//
//							completion(true)
//						}
//						actions.append(discardAction)
			
			let revealActionP2 = UIContextualAction(style: .normal, title: "Reveal to Player 2") { (action, view, completion) in
				self.revealCards([cardInstance], to: GameState.current.player2)
				completion(true)
			}
			revealActionP2.backgroundColor = #colorLiteral(red: 0.9960784314, green: 0.2509803922, blue: 0.1803921569, alpha: 1)
			actions.append(revealActionP2)
			
			let revealActionP1 = UIContextualAction(style: .normal, title: "Reveal to Player 1") { (action, view, completion) in
				self.revealCards([cardInstance], to: GameState.current.player1)
				completion(true)
			}
			revealActionP1.backgroundColor = #colorLiteral(red: 0.8401651771, green: 0.2069964211, blue: 0.1529994599, alpha: 1)
			actions.append(revealActionP1)
			
		case .hand? where isLocalPhone:
			// TODO: Add actions that send commands.
			return nil
		default:
			return nil
		}
		
		guard !actions.isEmpty else { return nil }
		
		let config = UISwipeActionsConfiguration(actions: actions)
		config.performsFirstActionWithFullSwipe = false
		
		return config
	}
	
	private func cardIsRevealed(forRowAt indexPath: IndexPath) -> Bool {
		return cardInstance(for: indexPath).revealedPlayers.value.contains(ownerIdentifier)
//		GameState.current[player: ownerIdentifier].revealedCards.value.map { $0.source }.contains(self.cardItem(for: indexPath).source)
	}
	
	private func revealCards(_ cardInstances: [CardInstance], to player: Player) {
		for cardInstance in cardInstances {
			cardInstance.revealedPlayers.mutate {
				$0.insert(ownerIdentifier)
			}
		}
		
		try? GameState.current.save()
	}
	
	private func revealCardsForSelectedRows(to player: Player) {
		let cardItems = tableView.indexPathsForSelectedRows?.map { self.cardInstance(for: $0) } ?? []
		
		revealCards(cardItems, to: player)
	}
	
	private var localPhoneAllowsPlayingCards: Bool {
		return !(contentType == .revealedCards && !isOwned) && (pileLocation != .library) && contentType != .battlefield
	}
	
	private func showPlayCardMenu(forRowAt indexPath: IndexPath) {
		guard localPhoneAllowsPlayingCards || (isLocalPhone && cardIsRevealed(forRowAt: indexPath)) else { return }
		let cardInstance = self.cardInstance(for: indexPath)
		
		let card = cardInstance.representation.card
		let isSingleFaced = (card.cardFaces?.count ?? 0) == 0
		
		var actions = self.actions(for: cardInstance)
		let moveActions = actions.filter { $0.title?.hasPrefix("Move to") == true }
		actions.removeAll(where: { $0.title?.hasPrefix("Move to") == true })
		
		let alert = UIAlertController(title: isSingleFaced ? card.name : nil, message: nil, preferredStyle: .actionSheet)
		let cell = tableView.cellForRow(at: indexPath)
		
		for action in actions {
			let alertAction = UIAlertAction(title: action.title, style: action.style) {
				action.handler?($0)
			}
			alert.addAction(alertAction)
		}
		
		if !moveActions.isEmpty {
			let moveAction = UIAlertAction(title: "Move to…", style: .default) { [weak self] _ in
				guard let self = self else { return }
				let moveAlert = UIAlertController(title: "Move to…", message: nil, preferredStyle: .actionSheet)
				
				for action in moveActions {
					let title = action.title?.replacingOccurrences(of: "Move to ", with: "")
					let alertAction = UIAlertAction(title: title ?? "", style: action.style) {
						action.handler?($0)
					}
					moveAlert.addAction(alertAction)
				}
				
				let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
				moveAlert.addAction(cancelAction)
				
				moveAlert.popoverPresentationController?.sourceView = cell
				moveAlert.popoverPresentationController?.sourceRect = cell?.frame ?? .zero
				moveAlert.view.transform = (self.navigationController?.view ?? self.view).transform
				self.present(moveAlert, animated: true)
			}
			alert.addAction(moveAction)
		}
//
//		var elements: [UIMenuElement] = actions.compactMap { action in
//			guard action.title != "View Card" else { return nil }
//			guard action.style != .cancel else { return nil }
//			return UIAction(title: action.title ?? "", attributes: action.style == .destructive ? .destructive : []) {
//				action.handler?($0)
//			}
//		}
//
//		if !moveActions.isEmpty {
//			let moveElements: [UIMenuElement] = moveActions.compactMap { action in
//				guard action.style != .cancel else { return nil }
//				let title = action.title?.replacingOccurrences(of: "Move to ", with: "")
//				return UIAction(title: title ?? "", attributes: action.style == .destructive ? .destructive : []) {
//					action.handler?($0)
//				}
//			}
//			let moveMenu = UIMenu(title: "Move to…", image: nil, identifier: nil, options: [], children: moveElements)
//			elements.append(moveMenu)
//		}
		
		alert.popoverPresentationController?.sourceView = cell
		alert.popoverPresentationController?.sourceRect = cell?.frame ?? .zero
		alert.view.transform = (navigationController?.view ?? view).transform
		
		self.present(alert, animated: true)
	}
	
	private func toggleExpandedState(forRowAt indexPath: IndexPath) {
		guard let cell = tableView.cellForRow(at: indexPath) as? CardTableViewCell else { return }
		
		let cardInstance = self.cardInstance(for: indexPath)
		self.expandedCardInstances.formSymmetricDifference([cardInstance])
		
		cell.oracleLabel.numberOfLines = self.expandedCardInstances.contains(cardInstance) ? 0 : 4
		cell.splitFaceOracleLabel.numberOfLines = self.expandedCardInstances.contains(cardInstance) ? 0 : 4
		
		tableView.beginUpdates()
		tableView.endUpdates()
	}
	
	private func imageViewController(for cardInstance: CardInstance, temporaryImage: UIImage?) -> CardImageViewController {
		let cardImageVC = storyboard?.instantiateViewController(identifier: "CardImageViewController") as! CardImageViewController
		cardImageVC.cardInstance = cardInstance
		// TODO: This doesn't work
//		cardImageVC.temporaryImage = temporaryImage
		return cardImageVC
	}
	
	private func pushImageViewController(forRowAt indexPath: IndexPath) {
		let cardInstance = self.cardInstance(for: indexPath)
		pushImageViewController(for: cardInstance)
	}
	
	func pushImageViewController(for cardInstance: CardInstance) {
		let tempImage = cardInstance.representation.image(type: .small)
		let cardImageVC = imageViewController(for: cardInstance, temporaryImage: tempImage)
		
		navigationController?.pushViewController(cardImageVC, animated: true)
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		guard contentType != .battlefield else { return nil }
		guard !isLocalPhone else { return "\(cardInstances.value.count) Card\(cardInstances.value.count == 1 ? "" : "s")" }
		return "TOP"
	}
	
	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		guard !isLocalPhone else { return nil }
		return "BOTTOM"
	}
	
	override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
		return true
	}
	
	override func tableView(_ tableView: UITableView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
		guard let indexPath = configuration.identifier as? IndexPath else { return }
		pushImageViewController(forRowAt: indexPath)
	}
	
	override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
		guard isLocalPhone && (pileLocation != .library || cardIsRevealed(forRowAt: indexPath)) else { return nil }
		let config = UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: { [weak self] () -> UIViewController? in
//			return nil
			guard let self = self else { return nil }
			let cardInstance = self.cardInstance(for: indexPath)
//			let tempImage = (tableView.cellForRow(at: indexPath) as? CardTableViewCell)?.imageView?.image
			let viewController = UIViewController()
			
			let imageView = UIImageView(image: nil)
			imageView.backgroundColor = .black
			imageView.contentMode = .scaleAspectFill
			viewController.view = imageView
			// TODO: Make this load async
			let scale: CGFloat = 45
			viewController.preferredContentSize = CGSize(width: 63*scale, height: 88*scale)
			
			DispatchQueue.global(qos: .userInteractive).async { [weak viewController] in
				guard viewController != nil else { return }
				let image = cardInstance.representation.image(type: .large)
				DispatchQueue.main.async { [weak imageView] in
					imageView?.image = image
				}
			}
			
			return viewController
		}, actionProvider: { [weak self] suggestedActions in
			guard let self = self else { return nil }
			guard self.localPhoneAllowsPlayingCards || self.cardIsRevealed(forRowAt: indexPath) else { return nil }
			
			let cardInstance = self.cardInstance(for: indexPath)
			var actions = self.actions(for: cardInstance)
			
			let moveActions = actions.filter { $0.title?.hasPrefix("Move to") == true }
			actions.removeAll(where: { $0.title?.hasPrefix("Move to") == true })
			
			var elements: [UIMenuElement] = actions.compactMap { action in
				guard action.title != "View Card" else { return nil }
				guard action.style != .cancel else { return nil }
				return UIAction(title: action.title ?? "", attributes: action.style == .destructive ? .destructive : []) {
					action.handler?($0)
				}
			}
			
			if !moveActions.isEmpty {
				let moveElements: [UIMenuElement] = moveActions.compactMap { action in
					guard action.style != .cancel else { return nil }
					let title = action.title?.replacingOccurrences(of: "Move to ", with: "")
					return UIAction(title: title ?? "", attributes: action.style == .destructive ? .destructive : []) {
						action.handler?($0)
					}
				}
				let moveMenu = UIMenu(title: "Move to…", image: nil, identifier: nil, options: [], children: moveElements)
				elements.append(moveMenu)
			}
			
			guard !elements.isEmpty else { return nil }
			
			return UIMenu(title: "", children: elements)
		})
		return config
	}
}

// MARK: UITableViewDragDelegate

extension PileViewController: UITableViewDragDelegate {
	
	func dragItems(forCardsAt indices: IndexSet, image: UIImage?) -> [UIDragItem] {
		return indices.map { index in
			let cardInstance = self.cardInstances.value[index]
			let item = NSItemProvider(object: cardInstance)
			let dragItem = UIDragItem(itemProvider: item)
			dragItem.localObject = cardInstance
			dragItem.previewProvider = {
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
	
	func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		guard !isEditing else { return [] }
		// Don't allow players to move or change the order of cards in piles belonging to other players.
		if isPrivate && !isOwned {
			return []
		}
		if isLocalPhone && pileLocation == .library && !cardIsRevealed(forRowAt: indexPath) {
			return []
		}
		let card = self.card(forRowAt: indexPath)
		let image = cardsAreVisible ? card.image(type: .small) : #imageLiteral(resourceName: "mtg-card-back-png-1")
		return dragItems(forCardsAt: IndexSet(integer: self.indexOfCard(forRowAt: indexPath)), image: image)
	}
	
	func tableView(_ tableView: UITableView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
		guard !isEditing else { return [] }
		// Don't allow players to move or change the order of cards in piles belonging to other players.
		if isPrivate && !isOwned {
			return []
		}
		if isLocalPhone && pileLocation == .library && !cardIsRevealed(forRowAt: indexPath) {
			return []
		}
		let card = self.card(forRowAt: indexPath)
		let image = cardsAreVisible ? card.image(type: .small) : #imageLiteral(resourceName: "mtg-card-back-png-1")
		return dragItems(forCardsAt: IndexSet(integer: self.indexOfCard(forRowAt: indexPath)), image: image)
	}
	
}

// MARK: UITableViewDropDelegate

class EmptyTableViewDropDelegate: NSObject, UIDropInteractionDelegate {
	
	weak var pileViewController: PileViewController?
	weak var view: UIView?
	private let provideDropIndex: () -> IndexPath
	private let canHandleSession: (UIDropSession) -> Bool
	
	var tableView: UITableView? {
		return pileViewController?.tableView
	}
	
	init(pileViewController: PileViewController, associatedView: UIView? = nil, canHandleSession: @escaping (UIDropSession) -> Bool, dropIndexProvider: @escaping () -> IndexPath) {
		self.pileViewController = pileViewController
		self.provideDropIndex = dropIndexProvider
		self.canHandleSession = canHandleSession
		self.view = associatedView
		super.init()
	}
	
	func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
		return self.canHandleSession(session) && session.canLoadObjects(ofClass: CardInstance.self)
	}
	
	func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
		guard let tableView = tableView, let dropDelegate = tableView.dropDelegate else { return .init(operation: .cancel) }
		
		return dropDelegate.tableView?(tableView, dropSessionDidUpdate: session, withDestinationIndexPath: IndexPath(row: 0, section: 0)) ?? UIDropProposal(operation: .cancel)
	}
	
	func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
		let indexPath = provideDropIndex()
		pileViewController?.performDrop(with: session, at: indexPath)
	}
	
}


extension PileViewController: UITableViewDropDelegate {
	func tableView(_ tableView: UITableView, canHandle session: UIDropSession) -> Bool {
		return !isEditing && tableView.numberOfRows(inSection: 0) > 0 && session.canLoadObjects(ofClass: CardInstance.self)
	}
	
	func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
		guard let pileLocation = pileLocation else { return .init(operation: .forbidden) } // Can only drop into a pile
		let pile = GameState.current[player: ownerIdentifier][pileLocation]
		
		let cardInstances = session.items.compactMap { $0.localObject as? CardInstance }
		
		// Don't allow players to move or change the order of cards in piles belonging to other players.
		if isPrivate && !isOwned {
			return UITableViewDropProposal(operation: .forbidden)
		}
		
		// Disable moving cards between sources from the phone. This should be done on the iPad. Cards can only be reordered within the same pile on the phone.
		// EXCEPT if they've all been revealed
		let allDraggedCardItemsAreRevealedToOwnerOfThisPile = cardInstances.allSatisfy { $0.revealedPlayers.value.contains(ownerIdentifier) }
		let allDraggedCardItemsAreFromPileOwnersHand = cardInstances.allSatisfy { $0.pile?.location == .hand && $0.pile?.playerIdentifier == ownerIdentifier }
		if !allDraggedCardItemsAreRevealedToOwnerOfThisPile {
			let atLeastOneCardIsFromAnotherSource = cardInstances.contains { (cardInstance) -> Bool in
				cardInstance.pile != pile
			}
			if isPrivate && allDraggedCardItemsAreFromPileOwnersHand {
				return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
			}
			if isPrivate && (atLeastOneCardIsFromAnotherSource) {
				return UITableViewDropProposal(operation: .forbidden)
			}
		}

		// Prevent tokens and emblems from leaving the battlefield.
		let allCardsCannotLeaveBattlefield = cardInstances.allSatisfy { cardInstance -> Bool in
			var card = cardInstance.representation
			
			if case .faceDown(let faceDownCard) = cardInstance.representation {
				card = faceDownCard
			}
			
			return card.isToken == true || card.isEmblem == true
		}
		if allCardsCannotLeaveBattlefield {
			return UITableViewDropProposal(operation: .forbidden)
		}
		
		// TODO: Prevent cards from being moved to opponent's zones
		// Maybe: Move them to those zones but belonging to their owner
		
		return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
	}
	
	func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
		guard let destinationIndexPath = coordinator.destinationIndexPath else { return }
		
		
		performDrop(with: coordinator.session, at: destinationIndexPath)
	}
	
	func performDrop(with session: UIDropSession, at destinationIndexPath: IndexPath) {
		guard let pileLocation = pileLocation else { return }
		let pile = GameState.current[player: ownerIdentifier][pileLocation]
		
		let insertionIndex = self.indexOfCard(forRowAt: destinationIndexPath)
		
		let cardInstances = (session.localDragSession?.items.compactMap { ($0.localObject as? CardInstance) } ?? [])
		
		for cardInstance in cardInstances {
			cardInstance.revealedPlayers.mutate {
				$0.remove(ownerIdentifier)
			}
		}
		
		// move the cards, even on the phone, so the hand updates. Then send the command. When the phone receives the updated board state, the cards won't have changed, and it will look good.
		GameState.current.move(cardInstances: cardInstances, to: pile, at: insertionIndex)
		
		if !AppDelegate.shared.role.isBoard {
			let destinationPileIdentifier = Command.MoveCommandParameters.PileIdentifier(location: pile.location, playerIdentifier: pile.playerIdentifier)
			let parameters = Command.MoveCommandParameters(cardInstanceIDs: cardInstances.map { $0.uuid }, destination: destinationPileIdentifier, insertionIndex: insertionIndex)
			let command = Command.moveCards(parameters)
			AppDelegate.shared.transceiver.broadcast(command)
		}
		
	}
}

extension PileViewController: UIDocumentPickerDelegate {
	fileprivate func loadDeck(from url: URL, for playerIdentifier: Player.Identifier) {
		DispatchQueue.global(qos: .userInteractive).async {
			do {
				let data = try Data(contentsOf: url)
				DispatchQueue.main.async {
					guard let string = String(data: data, encoding: .utf8) else {
						return
					}
					let command = Command.loadDeck(Command.LoadDeckParameters(playerIdentifier: playerIdentifier, deckList: string))
					AppDelegate.shared.transceiver.broadcast(command)
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
		guard isLocalPhone, let playerIdentifier = AppDelegate.shared.role.playerIdentifier else { return }
		guard urls.count == 1, let url = urls.first else { return }
		
		loadDeck(from: url, for: playerIdentifier)
	}
}

extension PileViewController: ContainerViewControllerDelegate {
	func containerViewController(_ containerViewController: ContainerViewController, didDismiss minimizedViewController: UIViewController) {
		if case .revealedCards = contentType {
			for cardInstance in GameState.current.allCards.values {
				cardInstance.revealedPlayers.mutate {
					$0.remove(ownerIdentifier)
				}
			}
			let command = Command.removeAllRevealedCards(ownerIdentifier)
			AppDelegate.shared.transceiver.broadcast(command)
		}
	}
}

fileprivate class DragAllDelegate: NSObject, UIDragInteractionDelegate {
	weak var pileViewController: PileViewController?
	
	init(pileViewController: PileViewController) {
		self.pileViewController = pileViewController
	}
	
	func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
		guard let pileViewController = pileViewController else { return [] }
		
		let indices = IndexSet(integersIn: 0 ..< pileViewController.cardInstances.value.count)
		return pileViewController.dragItems(forCardsAt: indices, image: nil)
	}
}

extension PileViewController: UISearchBarDelegate {
	func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
		searchBar.text = nil
	}
}
