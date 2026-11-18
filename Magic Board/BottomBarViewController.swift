//
//  BottomBarViewController.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/24/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import CardView
import UIKit
import RxSwift
import RxCocoa
import CardService
import SwiftUI

class LifeTrackerViewController: UIHostingController<LifeTracker> {
  
  var value: ObservableBridge<Int>! {
    didSet {
      bindValue()
    }
  }
  
  @objc required dynamic init?(coder aDecoder: NSCoder) {
    let tracker = LifeTracker(life: ObservableBridge(BehaviorRelay(value: 0)))
    
    super.init(coder: aDecoder, rootView: tracker)
  }
  
  /// Whether the − / + marks show (Phone Play hides them on the opponent's tracker).
  var showsMarks = true {
    didSet { if showsMarks != oldValue, value != nil { bindValue() } }
  }
  
  /// Whether life changes flash and float their amount (Rules games, as on Arena).
  var showsChanges = false {
    didSet { if showsChanges != oldValue, value != nil { bindValue() } }
  }

  private func bindValue() {
    rootView = LifeTracker(life: value, showsMarks: showsMarks, showsChanges: showsChanges)
    view.backgroundColor = .clear
    if #available(iOS 16.4, *), AppDelegate.shared.usesPhoneSession {
      safeAreaRegions = []
    }
  }
  
}

protocol PileViewProtocol: UIView {
	
}

extension HUDCardPileView: PileViewProtocol {
	
}

class HandViewControllerContainerView: UIView, PileViewProtocol, UIDropInteractionDelegate {
    var phoneContentFrame: CGRect?
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if let phoneContentFrame { return phoneContentFrame.contains(point) }
        return super.point(inside: point, with: event)
    }
	
	
}

protocol BottomBarViewControllerDelegate: AnyObject {
	func bottomBarViewController(_ bottomBarViewController: BottomBarViewController, passthroughViewsFor navigationController: UINavigationController) -> [UIView]?
}
extension BottomBarViewControllerDelegate {
	func bottomBarViewController(_ bottomBarViewController: BottomBarViewController, passthroughViewsFor navigationController: UINavigationController) -> [UIView]? {
		return nil
	}
}

class BottomBarViewController: UIViewController {

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        addPhoneCloseButtonIfNeeded(to: viewControllerToPresent)
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }
    private var phoneHUDConstraints: [NSLayoutConstraint] = []
    private var phoneHUDHeights: [NSLayoutConstraint] = []
    private var phoneHUDBottoms: [NSLayoutConstraint] = []

    private var phoneLifeWidth: NSLayoutConstraint?
    private var phonePileWidths: [NSLayoutConstraint] = []
    /// Horizontal HUD placement: piles left and life right for the local bar, mirrored for the opponent's.
    private var phoneLocalSideConstraints: [NSLayoutConstraint] = []
    private var phoneOpponentSideConstraints: [NSLayoutConstraint] = []
	
	private let bag = DisposeBag()
	
	var player: Player!
	
	@IBOutlet weak var libraryPileView: HUDCardPileView!
	@IBOutlet weak var graveyardPileView: HUDCardPileView!
	@IBOutlet weak var exilePileView: HUDCardPileView!
	// Strong: neither is ever in the view hierarchy (see viewDidLoad).
	@IBOutlet var lifeLabel: UILabel!
	@IBOutlet var lifeStepper: UIStepper!
	@IBOutlet weak var handContainerView: HandViewControllerContainerView!
	
  @IBOutlet weak var untapButton: UIButton!
  /// Rules mode: the main button's Arena pill width and gradient (see configureRulesMainButton).
  private var rulesMainWidth: NSLayoutConstraint?
  private var rulesMainGradient: CAGradientLayer?
  /// The storyboard's untap symbol, restored after combat.
  var phoneUntapImage: UIImage?
  
  weak var handViewController: HandViewController!
	
	weak var delegate: BottomBarViewControllerDelegate?
  
  var focusOn: ((CardInstance?) -> Void)?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		// The old life label and stepper (replaced by the life tracker) stay out of the bar. This
		// isn't done with a storyboard size-class variation ("installed" unchecked) because any
		// variation makes UIKit re-install every storyboard constraint and subview of the bar on a
		// size-class change, such as the snapshot iOS takes of the app in the background. That
		// undid Phone Play's HUD layout: the opponent's life tracker stretched across the bar,
		// over their piles.
		lifeLabel.removeFromSuperview()
		lifeStepper.removeFromSuperview()
		
		setupPile(GameState.current.effectivePile(.library, player: player.identifier), view: libraryPileView)
		setupPile(GameState.current.effectivePile(.graveyard, player: player.identifier), view: graveyardPileView)
		setupPile(player.exile, view: exilePileView)
		
		lifeStepper.transform = .init(rotationAngleDegrees: -90)
		lifeStepper.value = Double(player.life.value)
		
		bind()
	}
	
	private func bind() {    
    player.life
      .subscribe(onNext: { [weak self] value in
        try? GameState.current.save()
        self?.lifeLabel.text = "\(value)"
      }).disposed(by: bag)
	}
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "EmbedHandViewController", let destination = segue.destination as? HandViewController {
			self.handViewController = destination
			destination.isDragEnabled = true
			destination.player = player
      
      destination.selectedCard
        .subscribe { [weak self] cardInstance in
          guard let cardInstance else {
            self?.focusOn?(nil)
            return
          }
          if AppDelegate.shared.usesPhoneSession && self?.player.identifier == AppDelegate.shared.role.playerIdentifier || cardInstance.revealedPlayers.value.contains(cardInstance.ownerIdentifier == .a ? .b : .a) || cardInstance.pile?.location == .command {
            self?.focusOn?(cardInstance)
          }
        }.disposed(by: bag)

      
//			setupPile(player.hand, view: handContainerView)
    } else if segue.identifier == "EmbedLifeTracker", let destination = segue.destination as? LifeTrackerViewController {
      destination.value = ObservableBridge(player.life)
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
        if let draw = GameState.sessionDraw { draw(player.identifier, 1, false); return }
		guard let last: CardInstance = GameState.current.effectivePile(.library, player: player.identifier).cards.value.last else { return }
		GameState.current.move(cardInstances: [last], to: player.hand)
	}
	
	fileprivate func drawOpeningHand() {
        if let draw = GameState.sessionDraw { draw(player.identifier, 7, true); return }
    if !player.hand.cards.value.contents.isEmpty {
      GameState.current.move(cardInstances: player.hand.cards.value.contents, to: GameState.current.effectivePile(.library, player: player.identifier))
      GameState.current.effectivePile(.library, player: player.identifier).cards.mutate {
        $0 = OrderedSet($0.contents.shuffled())
      }
    }
    let newHand = Array(GameState.current.effectivePile(.library, player: player.identifier).cards.value.suffix(7))
		
		GameState.current.move(cardInstances: newHand, to: player.hand)
    
    let shouldOrderLandsFirst = false
    
    if shouldOrderLandsFirst {
      player.hand.cards.mutate {
        $0 = OrderedSet($0.sorted { first, second in
          let firstValue = first.representation.isLand ? 0 : 1
          let secondValue = second.representation.isLand ? 0 : 1
          return firstValue < secondValue
        })
      }
      
      try? GameState.current.save()
    }
	}
	
	fileprivate func untapAll() {
		for cardInstance in GameState.current.battlefield.value where cardInstance.controllerIdentifier.value == player.identifier {
      if !cardInstance.doesNotUntapNextTurn.value && !cardInstance.doesNotUntapAutomatically.value && !cardInstance.counters.value.contains(.stun) {
				cardInstance.isTapped.accept(false)
			}
      if let index = cardInstance.counters.value.firstIndex(of: .stun) {
        var counters = cardInstance.counters.value
        counters.remove(at: index)
        cardInstance.counters.accept(counters)
      }
			cardInstance.doesNotUntapNextTurn.accept(false)
			cardInstance.isSummoningSick.accept(false)
		}
		try? GameState.current.save()
	}
	
	fileprivate var openingHandIsAvailable: Bool {
		return GameState.current.battlefield.value.isEmpty && GameState.current.effectivePile(.graveyard, player: player.identifier).cards.value.isEmpty && player.exile.cards.value.isEmpty
	}
	
	@IBAction func untapButtonPressed(_ sender: Any) {
        if let session = AppDelegate.shared.phoneSession, player.identifier == session.player {
            if session.mode == .rules { session.send(.endTurn); return }
            // Nothing happens while the opening hands are still being kept or mulliganed.
            if session.game.opening?.deciding.isEmpty == false { return }
            // The phase button: Start Game → Untap + Draw → Move to Combat → End Combat → End Turn.
            switch session.game.phaseButton(for: session.player) {
            // Both players get a new seven to keep or mulligan.
            case .startGame: session.send(.startGame)
            case .untapAndDraw: session.send(.untapAndDraw(draw: PhoneGame.untapDraws))
            case .moveToCombat: session.send(.beginCombat)
            // Clears every attacker and blocker.
            case .endCombat: session.send(.endCombat)
            case .endTurn: session.send(.endTurn)
            case .opponentsCombat, .opponentsTurn: break
            }
            return
        }
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
			return UIAction(title: title, attributes: style == .destructive ? [.destructive] : [], handler: { _ in self.handler?() })
		}
	}
	
	private func actions(for pileView: PileViewProtocol) -> [Action] {
		var actions: [Action] = []
		
		let pile = self.pile(for: pileView)
		
		if pile.location == .library {
			let shuffleAction = Action(title: "Shuffle", style: .default) {
				GameState.current.effectivePile(.library, player: self.player.identifier).cards.mutate { $0 = OrderedSet($0.contents.shuffled()) }
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
		
		if pile.playerIdentifier == .b && !AppDelegate.shared.usesPhoneSession {
			alert.view.transform = CGAffineTransform(rotationAngle: .pi)
		}
		
		self.present(alert, animated: true, completion: nil)
	}
	
	func viewPile(from pileView: PileViewProtocol) {
		let pile = self.pile(for: pileView)
		guard !pile.cards.value.isEmpty else { return }
		// Phone Play opens graveyards, exile and libraries in the board's card browser.
		if AppDelegate.shared.usesPhoneSession, [.graveyard, .exile, .library].contains(pile.location),
		   let board = AppDelegate.shared.boardController {
			board.showPhoneZoneBrowser(.pile(pile.location, pile.playerIdentifier))
			return
		}
		presentPileSheet(from: pileView)
	}

	/// The list view of a pile (search, reveal, context menus…), still reachable from the browser.
	func presentPileSheet(from pileView: PileViewProtocol) {
		let pile = self.pile(for: pileView)
		guard !pile.cards.value.isEmpty else { return }
		guard let pileViewController = self.storyboard?.instantiateViewController(identifier: "PileViewController") as? PileViewController else { return }
		pileViewController.setPile(pile)
		
		// Compact-width phones get a full-screen sheet; wide displays (e.g. iPhone Duo's inner display) keep the popover.
		let phoneSheet = AppDelegate.shared.usesPhoneSession && traitCollection.userInterfaceIdiom == .phone && traitCollection.horizontalSizeClass == .compact
		let navigationController = phoneSheet ? PhonePortraitNavigationController(rootViewController: pileViewController) : UINavigationController(rootViewController: pileViewController)
		navigationController.modalPresentationStyle = phoneSheet ? .fullScreen : .popover
		navigationController.popoverPresentationController?.permittedArrowDirections = [.up, .down]
		navigationController.popoverPresentationController?.sourceView = pileView
		navigationController.popoverPresentationController?.passthroughViews = delegate?.bottomBarViewController(self, passthroughViewsFor: navigationController)
		
		if pile.playerIdentifier == .b && !AppDelegate.shared.usesPhoneSession {
			navigationController.view.transform = CGAffineTransform(rotationAngle: .pi)
		}
		
		self.present(navigationController, animated: true, completion: nil)
		// The opponent's phone outlines the pile while this sheet is open.
		if let session = AppDelegate.shared.phoneSession, [.graveyard, .exile, .library].contains(pile.location) {
			session.trackInspection(.pile(pile.playerIdentifier, pile.location), while: navigationController)
		}
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
			let item = NSItemProvider(card: cardInstance)
			let dragItem = UIDragItem(itemProvider: item)
			dragItem.localObject = cardInstance
			dragItem.previewProvider = { [weak self] in
				let imageView = UIImageView(image: image ?? UIImage.resource(named: "mtg-card-back-png-1")!)
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
		let cardItems = session.items.compactMap { $0.cardInstance }
		
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
			let cardInstances = (session.localDragSession?.items.compactMap { ($0.cardInstance) } ?? [])
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

extension BottomBarViewController {
    /// Height the local hand rises above the bottom HUD row.
    static func phoneHandLift(expanded: Bool, sceneHeight: CGFloat) -> CGFloat {
        expanded ? min(310, max(116, sceneHeight * 0.32)) : max(12, min(35, sceneHeight * 0.035))
    }

    /// Compact the same pile/hand/life controls instead of introducing another HUD.
    func refreshForPhoneSession() {
        guard AppDelegate.shared.usesPhoneSession, isViewLoaded else { return }
        libraryPileView.pile = GameState.current.effectivePile(.library, player: player.identifier)
        graveyardPileView.pile = GameState.current.effectivePile(.graveyard, player: player.identifier)
        let isLocal = player.identifier == AppDelegate.shared.role.playerIdentifier
        libraryPileView.isAccessibilityElement = true
        libraryPileView.accessibilityIdentifier = "phone-library-" + player.identifier.rawValue
        libraryPileView.accessibilityLabel = "Library"
        libraryPileView.accessibilityValue = String(libraryPileView.pile.cards.value.count)
        libraryPileView.accessibilityTraits = .button
        graveyardPileView.isAccessibilityElement = true
        graveyardPileView.accessibilityIdentifier = "phone-graveyard-" + player.identifier.rawValue
        graveyardPileView.accessibilityLabel = "Graveyard"
        graveyardPileView.accessibilityValue = String(graveyardPileView.pile.cards.value.count)
        graveyardPileView.accessibilityTraits = .button
        let sceneSize = parent?.view.bounds.size ?? view.window?.bounds.size ?? CGSize(width: 667, height: 375)
        let shortSide = min(sceneSize.width, sceneSize.height)
        let uiScale = min(2.4, max(1, shortSide / 375))
        handContainerView.transform = isLocal ? .identity : CGAffineTransform(rotationAngle: .pi)
        let hudHeight = min(124, max(52, shortSide * 0.12))
        let bottomSafe = isLocal ? (parent?.view.safeAreaInsets.bottom ?? 0) : 0
        lifeLabel.isHidden = true
        lifeStepper.isHidden = true
        for constraint in view.constraints where constraint.firstItem as? UIView === lifeLabel || constraint.secondItem as? UIView === lifeLabel || constraint.firstItem as? UIView === lifeStepper || constraint.secondItem as? UIView === lifeStepper { constraint.isActive = false }
        let titleFont = UIFont.systemFont(ofSize: 8 * uiScale)
        let piles = [libraryPileView,graveyardPileView,exilePileView].compactMap { $0 }
        func width(for pile: HUDCardPileView) -> CGFloat {
            max(28 * uiScale,ceil(((pile.titleLabel.text ?? "") as NSString).size(withAttributes:[.font:titleFont]).width)+10*uiScale)
        }
        let pileBand = piles.reduce(CGFloat(16)) { $0 + width(for:$1) }
        if phonePileWidths.isEmpty {
            for pile in [libraryPileView,graveyardPileView,exilePileView].compactMap({ $0 }) {
                for constraint in pile.constraints where constraint.firstAttribute == .width && constraint.secondAttribute == .height { constraint.isActive = false }
                let width = pile.widthAnchor.constraint(equalToConstant:width(for:pile))
                width.isActive = true;phonePileWidths.append(width)
            }
        }
        for (constraint,pile) in zip(phonePileWidths,piles) { constraint.constant = width(for:pile) }
        let lifeContainer = children.first(where: { $0 is LifeTrackerViewController })?.view.superview
        lifeContainer?.accessibilityIdentifier = isLocal ? "phone-life-local" : "phone-life-opponent"
        if phoneHUDConstraints.isEmpty, let lifeContainer {
            let fixedViews: [UIView] = piles + [lifeContainer, untapButton]
            // Each HUD control fits inside the fixed bar with equal vertical padding.
            for constraint in view.constraints {
                let first = constraint.firstItem as? UIView
                let second = constraint.secondItem as? UIView
                let vertical: [NSLayoutConstraint.Attribute] = [.top, .topMargin, .bottom, .bottomMargin, .centerY]
                if (fixedViews.contains(where: { $0 === first }) && vertical.contains(constraint.firstAttribute)) ||
                   (fixedViews.contains(where: { $0 === second }) && vertical.contains(constraint.secondAttribute)) ||
                   (first === untapButton && constraint.firstAttribute == .leading) ||
                   (first === lifeContainer && constraint.firstAttribute == .trailing) ||
                   (second === lifeContainer && constraint.secondAttribute == .trailing) {
                    constraint.isActive = false
                }
            }
            for item in fixedViews {
                let bottom = item.bottomAnchor.constraint(equalTo: view.bottomAnchor)
                let height = item.heightAnchor.constraint(equalToConstant: hudHeight)
                phoneHUDBottoms.append(bottom); phoneHUDHeights.append(height)
            }
            phoneHUDConstraints = phoneHUDBottoms + phoneHUDHeights + [
                // The board already keeps the bar clear of the camera (reserved regions); the
                // bar's own safe area would push the life total in by the whole side inset again.
                lifeContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
                untapButton.trailingAnchor.constraint(equalTo: lifeContainer.leadingAnchor, constant: -8)
            ]
            NSLayoutConstraint.activate(phoneHUDConstraints)
            // The storyboard's left-to-right pile row (graveyard, library, exile) and the life total
            // pinned right. The opponent's bar mirrors it: life at the top left, and from the top
            // right graveyard, library, exile, then the hand.
            phoneLocalSideConstraints = view.constraints.filter { constraint in
                let first = constraint.firstItem as? UIView
                return piles.contains(where: { $0 === first }) && constraint.firstAttribute == .leading
            } + phoneHUDConstraints.filter { $0.firstItem as? UIView === lifeContainer && $0.firstAttribute == .trailing }
            if let graveyardPileView, let libraryPileView, let exilePileView {
                phoneOpponentSideConstraints = [
                    graveyardPileView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    libraryPileView.trailingAnchor.constraint(equalTo: graveyardPileView.leadingAnchor, constant: -8),
                    exilePileView.trailingAnchor.constraint(equalTo: libraryPileView.leadingAnchor, constant: -8),
                    lifeContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4)
                ]
            }
        }
        if isLocal {
            NSLayoutConstraint.deactivate(phoneOpponentSideConstraints)
            NSLayoutConstraint.activate(phoneLocalSideConstraints)
        } else {
            NSLayoutConstraint.deactivate(phoneLocalSideConstraints)
            NSLayoutConstraint.activate(phoneOpponentSideConstraints)
        }
        // One metric for both bars: every control gets the same height and the same top/bottom padding.
        let rowHeight = hudHeight
        let hudPadding = (5 * uiScale).rounded()
        let controlHeight = rowHeight - 2 * hudPadding
        for constraint in phoneHUDHeights { constraint.constant = controlHeight }
        for constraint in phoneHUDBottoms { constraint.constant = -hudPadding }
        untapButton.contentHorizontalAlignment = .fill
        untapButton.contentVerticalAlignment = .fill
        untapButton.imageView?.contentMode = .scaleAspectFit
        for pile in [libraryPileView, graveyardPileView, exilePileView].compactMap({ $0 }) {
            // Phone Play drags the top card with the board's own pan (like hand cards), not a system drag.
            for drag in pile.interactions.compactMap({ $0 as? UIDragInteraction }) { drag.isEnabled = false }
            pile.numberLabel.font = .systemFont(ofSize: 12 * uiScale)
            pile.titleLabel.font = titleFont
            pile.titleLabel.adjustsFontSizeToFitWidth = false
            let previewHeight = max(14, min(28 * uiScale, controlHeight - titleFont.lineHeight - 2 * uiScale))
            pile.configurePhoneLayout(previewHeight: previewHeight, scale: uiScale)

        }
        untapButton.isHidden = !isLocal
        let phase = AppDelegate.shared.phoneSession?.game.phaseButton(for: player.identifier) ?? .untapAndDraw
        let label: String
        switch phase {
        case .startGame: label = "Start\nGame"
        case .untapAndDraw: label = PhoneGame.untapDraws ? "Untap\n+ Draw" : "Untap"
        case .moveToCombat: label = "Move to\nCombat"
        case .endCombat: label = "End\nCombat"
        case .endTurn: label = "End\nTurn"
        case .opponentsCombat: label = "Opponent\nAttacking"
        case .opponentsTurn: label = "Opponent's\nTurn"
        }
        let status = phase == .opponentsCombat || phase == .opponentsTurn
        let rulesSession = AppDelegate.shared.phoneSession.flatMap { $0.mode == .rules ? $0 : nil }
        if let rulesSession, isLocal {
            configureRulesMainButton(rulesSession.rulesPrimaryLabel, enabled: rulesSession.rulesPrimaryEnabled, height: controlHeight)
        } else {
            configureUntapButton(label: rulesSession?.rulesPrimaryLabel ?? label, height: controlHeight,
                                 status: rulesSession == nil ? status : rulesSession?.rulesPrimaryEnabled != true)
        }
        untapButton.isEnabled = isLocal && (rulesSession.map { $0.connected && $0.rulesPrimaryEnabled } ?? !status)
        untapButton.accessibilityIdentifier = isLocal ? "phone-untap-local" : "phone-untap-opponent"
        #if !BOARD_CONNECT
        // Rules mode: hold the main button for Arena's pass shortcuts (XMage's own skip-ahead stops).
        // Built once per game: replacing the menu on every board refresh could swap it out
        // while it's open and drop the tapped action.
        if isLocal, let session = rulesSession, let engine = session.rulesAdapter?.engine, untapButton.menu == nil {
            func pass(_ title: String, _ image: String, _ action: RulesPriorityAction) -> UIAction {
                UIAction(title: title, image: UIImage(systemName: image)) { _ in Task { await engine.controlPriority(action) } }
            }
            untapButton.menu = UIMenu(title: "Pass Until…", children: [
                pass("Stack Resolves", "square.stack.3d.up", .resolveStack),
                pass("Next Main Phase", "arrow.right.to.line", .nextMain),
                pass("End Step", "forward.end", .endStep),
                pass("My Next Turn", "forward.end.alt", .yourTurn)
            ])
            untapButton.showsMenuAsPrimaryAction = false
        } else if rulesSession == nil, untapButton.menu != nil {
            untapButton.menu = nil
        }
        #endif
        let expanded = isLocal && handViewController?.phonePresentation.isExpanded == true
        // The local hand always draws above the static HUD controls; it never pushes them around.
        if isLocal, handContainerView.superview === view {
            view.bringSubviewToFront(handContainerView)
        } else if !isLocal, let lifeContainer, lifeContainer.superview === view, handContainerView.superview === view {
            // Only reorder within this bar: insertSubview would also pull a hand the board has
            // adopted back into the bar.
            view.insertSubview(handContainerView, belowSubview: lifeContainer)
        }
        handContainerView.accessibilityIdentifier = isLocal ? "phone-local-hand" : "phone-opponent-hand"
        handContainerView.accessibilityValue = expanded ? "Expanded" : "Compact"
        if phoneLifeWidth == nil, let lifeView = children.first(where: { $0 is LifeTrackerViewController })?.view {
            for constraint in view.constraints where constraint.firstItem as? UIView === untapButton && constraint.secondItem as? UIView === handContainerView { constraint.isActive = false }
            phoneLifeWidth = lifeView.superview?.widthAnchor.constraint(equalToConstant: 85)
            phoneLifeWidth?.isActive = true
        }
        phoneLifeWidth?.constant = min(170, max(70, shortSide * 0.19))
        lifeStepper?.isEnabled = isLocal && rulesSession == nil
        for child in children where child is LifeTrackerViewController {
            child.view.isUserInteractionEnabled = isLocal && rulesSession == nil
            if #available(iOS 16.4, *), let tracker = child as? LifeTrackerViewController { tracker.safeAreaRegions = [] }
            (child as? LifeTrackerViewController)?.showsMarks = isLocal && rulesSession == nil
            (child as? LifeTrackerViewController)?.showsChanges = rulesSession?.rulesAdapter?.hasProjected == true
        }
        guard handContainerView.superview === view else { return }
        // Reduce the original fixed side allowance as the existing piles shrink.
        for constraint in view.constraints where constraint.firstItem as? UIView === handContainerView && constraint.firstAttribute == .width {
            let rightBand = (phoneLifeWidth?.constant ?? 70) + max(20,hudHeight-20) + 12
            // Leave room for the outer cards' rotation and rounded screen corners.
            let safe = parent?.view.safeAreaInsets ?? .zero
            let handMargin = max(36 * uiScale, max(safe.left, safe.right) + 12)
            constraint.constant = isLocal ? (expanded ? sceneSize.width - 2 * handMargin - view.bounds.width : -max(220,pileBand+rightBand+30)) : -max(310, shortSide * 0.85)
        }
        for constraint in view.constraints where constraint.firstItem as? UIView === handContainerView && constraint.firstAttribute == .centerX {
            let safe = parent?.view.safeAreaInsets ?? .zero
            constraint.constant = isLocal ? -(safe.left-safe.right)/2 : 0
        }
        for constraint in handContainerView.constraints where constraint.firstAttribute == .height && constraint.secondItem == nil {
            let screenHeight = shortSide
            constraint.constant = isLocal ? (expanded ? min(360, max(150, screenHeight * 0.40)) + bottomSafe : min(270, max(105, screenHeight * 0.28))) : min(125, max(60, screenHeight * 0.16))
        }
        for constraint in view.constraints where constraint.firstItem as? UIView === handContainerView && constraint.firstAttribute == .top {
            let overflow = BottomBarViewController.phoneHandLift(expanded: true, sceneHeight: sceneSize.height)
                - BottomBarViewController.phoneHandLift(expanded: false, sceneHeight: sceneSize.height)
            constraint.constant = isLocal ? (expanded ? -overflow : 0) : -min(48, shortSide * 0.06)
        }
        for constraint in view.constraints where constraint.firstItem as? UIView === untapButton && constraint.firstAttribute == .leading {
            constraint.constant = 10
        }
    }
}

/// Forward touches for the opponent hand where it extends beyond its bar.
class PlayerBarHitAreaView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        guard AppDelegate.shared.usesPhoneSession, !isHidden, alpha > 0.01 else { return false }
        for child in subviews where child is PlayerBarHitAreaView || child is HandViewControllerContainerView {
            if !child.isHidden, child.point(inside: convert(point, to: child), with: event) { return true }
        }
        return false
    }
}


extension BottomBarViewController {
    /// During the local player's combat, the untap button turns orange and reads "End Combat"
    /// in Beleren (Arena), and before the game it reads "Start Game"; otherwise it shows its
    /// untap symbol. `label` is the text to show (lines split by "\n"), nil for the symbol.
    /// A `status` (the opponent's turn or combat) is gray and not tappable.
    /// Rules mode: Arena's main button. A wide pill with a Beleren title and, on a second line, a
    /// small caption ("Next / To Combat"). Orange to act, blue for "No Attacks/Blocks", red to
    /// confirm attackers or blockers; "Opponent's Turn" is plain text with no button behind it.
    func configureRulesMainButton(_ label: String, enabled: Bool, height: CGFloat) {
        untapButton.setImage(nil, for: .normal)
        let lines = label.components(separatedBy: "\n")
        let title = lines.first ?? label
        let caption = lines.count > 1 ? lines[1] : nil
        let waiting = !enabled
        let titleSize = max(10, height * 0.34)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineHeightMultiple = 0.85
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: UIFont(name: "Beleren2016-Bold", size: titleSize) ?? .boldSystemFont(ofSize: titleSize),
            .foregroundColor: UIColor.white, .paragraphStyle: paragraph,
            .shadow: { let s = NSShadow(); s.shadowColor = UIColor.black.withAlphaComponent(0.75); s.shadowOffset = CGSize(width: 0, height: 1.5); s.shadowBlurRadius = 2.5; return s }()
        ])
        if let caption {
            text.append(NSAttributedString(string: "\n" + caption, attributes: [
                .font: UIFont.systemFont(ofSize: max(8, height * 0.19), weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85), .paragraphStyle: paragraph
            ]))
        }
        // Arena shows an hourglass on the button while it waits on the other player or the engine,
        // instead of status text.
        let hourglass = waiting && ["Waiting", "Opponent's Turn", "Sending…"].contains(title)
        if hourglass {
            let symbol = UIImage(systemName: "hourglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: max(10, height * 0.36), weight: .bold))
            untapButton.setImage(symbol, for: .normal)
            untapButton.setImage(symbol, for: .disabled)
            untapButton.tintColor = UIColor.white.withAlphaComponent(0.85)
            text.setAttributedString(NSAttributedString(string: ""))
        } else {
            untapButton.setImage(nil, for: .disabled)
        }
        untapButton.setAttributedTitle(text, for: .normal)
        untapButton.setAttributedTitle(text, for: .disabled)
        untapButton.titleLabel?.numberOfLines = 2
        untapButton.titleLabel?.adjustsFontSizeToFitWidth = true
        untapButton.titleLabel?.minimumScaleFactor = 0.5
        untapButton.titleLabel?.textAlignment = .center
        untapButton.accessibilityLabel = label.replacingOccurrences(of: "\n", with: " ")
        untapButton.accessibilityValue = nil
        // Wider than Phone Play's square button, as Arena's pill.
        if rulesMainWidth == nil {
            // Replace the storyboard's width/aspect constraints (deactivated, not re-prioritised:
            // changing an installed required constraint's priority raises an exception).
            let owners: [UIView] = [untapButton as UIView] + [untapButton.superview].compactMap { $0 }
            for owner in owners {
                for constraint in owner.constraints where (constraint.firstItem as? UIView) === untapButton && constraint.firstAttribute == .width {
                    constraint.isActive = false
                }
            }
            let width = untapButton.widthAnchor.constraint(equalTo: untapButton.heightAnchor, multiplier: 2.6)
            width.isActive = true
            rulesMainWidth = width
        }
        let colors: [UIColor]
        if waiting {
            colors = []
        } else if title.hasPrefix("No ") {
            colors = RulesArenaPalette.blue
        } else if title.hasSuffix("Attacker") || title.hasSuffix("Attackers") || title.hasSuffix("Blocker") || title.hasSuffix("Blockers") {
            colors = RulesArenaPalette.red
        } else {
            colors = RulesArenaPalette.orange
        }
        untapButton.backgroundColor = .clear
        let gradient = rulesMainGradient ?? {
            let layer = CAGradientLayer()
            untapButton.layer.insertSublayer(layer, at: 0)
            rulesMainGradient = layer
            return layer
        }()
        // Arena's pill: deeper at the top, brightening toward the bottom, with a bright rim and glow.
        gradient.colors = colors.map(\.cgColor)
        gradient.isHidden = colors.isEmpty
        gradient.frame = untapButton.bounds
        gradient.cornerRadius = untapButton.bounds.height / 2
        gradient.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        gradient.borderWidth = colors.isEmpty ? 0 : 1.5
        untapButton.layer.cornerRadius = untapButton.bounds.height / 2
        untapButton.layer.shadowColor = (colors.first ?? .clear).cgColor
        untapButton.layer.shadowRadius = 10
        untapButton.layer.shadowOpacity = colors.isEmpty ? 0 : 0.85
        untapButton.layer.shadowOffset = .zero
        // Keep the gradient matched to the pill after layout.
        DispatchQueue.main.async { [weak self] in
            guard let self, let gradient = self.rulesMainGradient else { return }
            gradient.frame = self.untapButton.bounds
            gradient.cornerRadius = self.untapButton.bounds.height / 2
            self.untapButton.layer.cornerRadius = self.untapButton.bounds.height / 2
        }
    }

    func configureUntapButton(label: String?, height: CGFloat, status: Bool = false) {
        if phoneUntapImage == nil { phoneUntapImage = untapButton.image(for: .normal) }
        let combat = label == "End\nCombat"
        untapButton.accessibilityValue = combat ? "Combat" : nil
        guard let label else {
            untapButton.setAttributedTitle(nil, for: .normal)
            untapButton.setImage(phoneUntapImage, for: .normal)
            untapButton.backgroundColor = .clear
            untapButton.layer.shadowOpacity = 0
            untapButton.accessibilityLabel = "Untap"
            return
        }
        untapButton.setImage(nil, for: .normal)
        let size = max(8, height * 0.24)
        let font = UIFont(name: "Beleren2016-Bold", size: size) ?? .boldSystemFont(ofSize: size)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineHeightMultiple = 0.9
        let title = NSAttributedString(string: label, attributes: [
            .font: font, .foregroundColor: status ? UIColor.white.withAlphaComponent(0.75) : UIColor.white, .paragraphStyle: paragraph
        ])
        untapButton.setAttributedTitle(title, for: .normal)
        untapButton.setAttributedTitle(title, for: .disabled)
        untapButton.titleLabel?.numberOfLines = 2
        untapButton.titleLabel?.adjustsFontSizeToFitWidth = true
        untapButton.titleLabel?.minimumScaleFactor = 0.5
        untapButton.titleLabel?.textAlignment = .center
        untapButton.backgroundColor = status ? .systemGray : .systemOrange
        untapButton.layer.cornerRadius = height * 0.2
        untapButton.layer.shadowColor = UIColor.systemOrange.cgColor
        untapButton.layer.shadowRadius = 6
        untapButton.layer.shadowOpacity = status ? 0 : 0.8
        untapButton.layer.shadowOffset = .zero
        untapButton.accessibilityLabel = label.replacingOccurrences(of: "\n", with: " ")
    }

    /// The HUD controls the collapsed hand must stay clear of: the piles on the left,
    /// the untap button and life total on the right.
    var phoneHUDSideControls: (left: [UIView], right: [UIView]) {
        let piles: [UIView] = [graveyardPileView, libraryPileView, exilePileView].compactMap { $0 }
        let life = children.first(where: { $0 is LifeTrackerViewController })?.view.superview
        let right: [UIView] = [untapButton, life].compactMap { $0 }.filter { !$0.isHidden }
        return (piles.filter { !$0.isHidden }, right)
    }
}

/// Arena's button colors, top (deeper) to bottom (lighter): shared by the main button and the
/// SwiftUI buttons beside it.
enum RulesArenaPalette {
    static let orange = [UIColor(red: 0.91, green: 0.42, blue: 0.16, alpha: 1), UIColor(red: 0.98, green: 0.6, blue: 0.33, alpha: 1), UIColor(red: 1, green: 0.8, blue: 0.58, alpha: 1)]
    static let blue = [UIColor(red: 0.24, green: 0.29, blue: 0.82, alpha: 1), UIColor(red: 0.42, green: 0.5, blue: 0.95, alpha: 1), UIColor(red: 0.68, green: 0.74, blue: 1, alpha: 1)]
    static let red = [UIColor(red: 0.84, green: 0.25, blue: 0.27, alpha: 1), UIColor(red: 0.96, green: 0.45, blue: 0.43, alpha: 1), UIColor(red: 1, green: 0.7, blue: 0.66, alpha: 1)]
}
