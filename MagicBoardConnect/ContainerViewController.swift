//
//  ContainerViewController.swift
//  MagicBoardConnect
//
//  Created by Josh Birnholz on 3/11/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import CardService

extension Notification.Name {
	static let minimizedViewControllerDidChange = Notification.Name(rawValue: "minimizedViewControllerDidChange")
}

extension UIViewController {
	var containerViewController: ContainerViewController? {
		var viewController: UIViewController? = parent
		while let parent = viewController {
			if let container = viewController as? ContainerViewController {
				return container
			}
			viewController = parent.parent
		}
		return nil
	}
	
	@objc func presentAndSave(_ viewControllerToPresent: UIViewController, animated flag: Bool, minimizedTitle: String? = nil, completion: (() -> Void)? = nil) {
		if let container = containerViewController {
			container.presentAndSave(viewControllerToPresent, animated: flag, minimizedTitle: minimizedTitle, completion: completion)
		} else {
			present(viewControllerToPresent, animated: flag, completion: completion)
		}
	}
	
	var dismissSavedViewControllerButtonItem: UIBarButtonItem {
		let container = self.containerViewController
		return UIBarButtonItem(barButtonSystemItem: .done, target: container, action: #selector(ContainerViewController.dismissMinimizedViewController))
	}
}

class MinimizedBarView: UIView, UISpringLoadedInteractionSupporting {
	var isSpringLoaded: Bool = true
}

protocol ContainerViewControllerDelegate: class {
	func containerViewController(_ containerViewController: ContainerViewController, didDismiss minimizedViewController: UIViewController)
}

func waitUntil(_ condition: @escaping @autoclosure () -> Bool, thenOnMainThread completion: @escaping () -> ()) {
	if condition() {
		if Thread.isMainThread {
			completion()
		} else {
			DispatchQueue.main.sync {
				completion()
			}
		}
		return
	}
	
	DispatchQueue.global(qos: .background).async {
		while !condition() {
			
		}
		DispatchQueue.main.sync {
			completion()
		}
	}
	
}



class ContainerViewController: UIViewController {
	
	var containedTabBarController: UITabBarController!
	
	private let cornerRoundingRadius: CGFloat = 10
	
	private let bag = DisposeBag()
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		AppDelegate.shared.transceiver.broadcast(Command.rebroadcast)
		
		let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(presentMinimizedViewController(_:)))
		minimizedBarView.addGestureRecognizer(gestureRecognizer)
		minimizedBarView.backgroundColor = .secondarySystemFill
		
		self.roundCorners(corners: [.layerMinXMinYCorner, .layerMaxXMinYCorner], radius: cornerRoundingRadius, of: self.minimizedBarView)
//		minimizedBarView.isHidden = true
		
		let interaction = UISpringLoadedInteraction { (interaction, _) in
			self.presentMinimizedViewController(interaction)
		}
		minimizedBarView.addInteraction(interaction)
		
		minimizedViewController
			.withPrevious(startWith: nil)
			.observeOn(MainScheduler.instance)
			.do(onNext: { [weak self] (oldValue, minimizedViewController) in
				guard let self = self else { return }
				
				self.savedTitleLabel.text = self.minimizedTitle ?? (minimizedViewController as? UINavigationController)?.navigationBar.topItem?.title ?? minimizedViewController?.navigationItem.title ?? minimizedViewController?.title
				if minimizedViewController != nil {
					self.roundCorners(corners: [.layerMinXMaxYCorner, .layerMaxXMaxYCorner], radius: self.cornerRoundingRadius, of: self.containerView)
				} else {
					self.containerView.layer.cornerRadius = 0
				}
				
				if oldValue != minimizedViewController {
					NotificationCenter.default.post(name: .minimizedViewControllerDidChange, object: self)
				}
			}).map { $1 == nil }
			.bind(to: self.minimizedBarView.rx.isHidden)
			.disposed(by: bag)
	}
	
	private func makeRevealedCardsViewController(for player: Player) -> UIViewController! {
		guard let pileViewController = self.storyboard?.instantiateViewController(identifier: "PileViewController") as? PileViewController else { return nil }
//		pileViewController.setCardItems(player.revealedCards.asObservable(), owner: player.identifier, contentType: .revealedCards)
		pileViewController.setCardInstances(player.revealedCards, owner: player.identifier, contentType: .revealedCards)
		
		let navigationController = UINavigationController(rootViewController: pileViewController)
		pileViewController.navigationItem.leftBarButtonItem = self.dismissSavedViewControllerButtonItem
		self.delegate = pileViewController
		
		return navigationController
	}
	
	private var isTabBarControllerInitialized = false
	
	@IBOutlet weak var containerView: UIView!
	
	private let minimizedViewController = BehaviorRelay<UIViewController?>(value: nil)
	
	var minimizedTitle: String?
	
	@IBOutlet weak var constraint: NSLayoutConstraint!
	@IBOutlet weak var minimizedBarView: UIView!
	@IBOutlet weak var savedTitleLabel: UILabel!
	
	weak var delegate: ContainerViewControllerDelegate?
	
	override func presentAndSave(_ viewControllerToPresent: UIViewController, animated flag: Bool, minimizedTitle: String? = nil, completion: (() -> Void)? = nil) {
		guard presentedViewController == nil else {
			print("Error: Attempting to present view controller when there is already a presented view controller")
			return
		}
		
		guard Thread.isMainThread else {
			DispatchQueue.main.sync {
				self.presentAndSave(viewControllerToPresent, animated: flag, minimizedTitle: minimizedTitle, completion: completion)
			}
			return
		}
		
		super.present(viewControllerToPresent, animated: flag, completion: {
			self.minimizedTitle = minimizedTitle
			self.minimizedViewController.accept(viewControllerToPresent)
			completion?()
		})
	}
	
	@objc func dismissMinimizedViewController() {
		if let minimizedViewController = minimizedViewController.value {
			minimizedViewController.dismiss(animated: true) {
				self.delegate?.containerViewController(self, didDismiss: minimizedViewController)
			}
		}
		
		self.minimizedViewController.accept(nil)
	}
	
	@objc private func presentMinimizedViewController(_ sender: Any) {
		guard let savedViewController = minimizedViewController.value else { return }
		self.presentAndSave(savedViewController, animated: true, completion: nil)
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		
		initializeTabBarController()
	}
	
//	override func overrideTraitCollection(forChild childViewController: UIViewController) -> UITraitCollection? {
//		UITraitCollection(userInterfaceLevel: .elevated)
//		return nil
//	}
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "EmbedTabBarController", let destination = segue.destination as? UITabBarController {
			containedTabBarController = destination
		}
	}
	
	private func roundCorners(corners: CACornerMask, radius: CGFloat, of view: UIView) {
		view.layer.cornerRadius = radius
		view.layer.maskedCorners = corners
		view.layer.masksToBounds = true
    }
	
	@objc func presentSideboardPileViewController(sender: UIBarButtonItem) {
		let sceneDelegate = view.window?.windowScene?.delegate as? ConnectSceneDelegate
		guard let player = sceneDelegate?.player else { return }
		if let viewController = self.pileViewController(for: player.sideboard, withExtraButton: false, withDoneButton: true) {
			self.present(viewController, animated: true, completion: nil)
		}
	}
	
	@objc func presentOpponentExilePileViewController(sender: UIBarButtonItem) {
		let sceneDelegate = view.window?.windowScene?.delegate as? ConnectSceneDelegate
		guard let player = sceneDelegate?.player else { return }
		let pile = GameState.current[player: (player.identifier == .a ? .b : .a)].exile
		if let viewController = self.pileViewController(for: pile, withExtraButton: false, withDoneButton: true) {
			self.present(viewController, animated: true, completion: nil)
		}
	}
	
	@objc func presentOpponentGraveyardPileViewController(sender: UIBarButtonItem) {
		let sceneDelegate = view.window?.windowScene?.delegate as? ConnectSceneDelegate
		guard let player = sceneDelegate?.player else { return }
		let pile = GameState.current[player: (player.identifier == .a ? .b : .a)].graveyard
		if let viewController = self.pileViewController(for: pile, withExtraButton: false, withDoneButton: true) {
			self.present(viewController, animated: true, completion: nil)
		}
	}
	
	@objc private func dismissPresentedVC(sender: UIBarButtonItem) {
		dismiss(animated: true, completion: nil)
	}
	
	private func pileViewController(for pile: Pile, withExtraButton: Bool, withDoneButton: Bool) -> UIViewController? {
		let viewController: UIViewController? = {
			if pile.location == .hand {
				return storyboard?.instantiateViewController(identifier: "HandCardCollectionViewController")
			}
			return storyboard?.instantiateViewController(identifier: "PileViewController") as? PileViewController
		}()
		guard let pileViewController = viewController as? PileDisplaying else { return nil }
		pileViewController.setPile(pile)
		
		let navigationController = UINavigationController(rootViewController: pileViewController)
		navigationController.tabBarItem = UITabBarItem(title: String(describing: pile.location).capitalized, image: nil, selectedImage: nil)
		
		let doneButton: UIBarButtonItem? = {
			guard withDoneButton else { return nil }
			return UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissPresentedVC(sender:)))
		}()
		
		if let doneButton = doneButton {
			pileViewController.navigationItem.leftBarButtonItem = doneButton
		}
		
		if withExtraButton {
			if pile.location == .library {
				let sideboardItem = UIBarButtonItem(title: "Sideboard", style: .plain, target: self, action: #selector(presentSideboardPileViewController(sender:)))
				pileViewController.navigationItem.rightBarButtonItem = sideboardItem
			}
			if pile.location == .exile {
				let sideboardItem = UIBarButtonItem(title: "Opponent", style: .plain, target: self, action: #selector(presentOpponentExilePileViewController(sender:)))
				pileViewController.navigationItem.rightBarButtonItem = sideboardItem
			}
			if pile.location == .graveyard {
				let sideboardItem = UIBarButtonItem(title: "Opponent", style: .plain, target: self, action: #selector(presentOpponentGraveyardPileViewController(sender:)))
				pileViewController.navigationItem.rightBarButtonItem = sideboardItem
			}
		}
		
		return navigationController
	}
	
	private func makeBattlefieldViewController() -> UIViewController? {
		guard let pileViewController = storyboard?.instantiateViewController(identifier: "PileViewController") as? PileViewController else { return nil }
		let sceneDelegate = view.window?.windowScene?.delegate as? ConnectSceneDelegate
		guard let player = sceneDelegate?.player else { return nil }
		
		// A list of card items for cards on the battlefield
		// Each card should only appear once. If there is more than one copy of
		// the same card on the battlefield, the most recently played copy should
		// be the one that's included.
		// TODO: Make face-down cards show up, and include them every time they show up, not just the most recently played copy.
		// TODO: make face-down cards played by the current player marked as such (transparent?) in the tableview, and show a face down blank card for face-down cards played by the opponent
		let battlefieldCardInstances = GameState.current.battlefield
			.map { (cardInstances) -> OrderedSet<CardInstance> in
				cardInstances.reduce(into: OrderedSet<CardInstance>()) { (set, cardInstance) in
					if case .faceDown(_) = cardInstance.representation {
						return
					}
					
					let card = cardInstance.representation.card
					while let item = set.first(where: { $0.representation.card == card || $0.representation.name == card.name }) {
						set.remove(item)
					}
					set.append(cardInstance)
				}
		}
		
		pileViewController.setCardInstances(battlefieldCardInstances, owner: player.identifier, contentType: .battlefield)
		
		let navigationController = UINavigationController(rootViewController: pileViewController)
		navigationController.tabBarItem = UITabBarItem(title: "Battlefield", image: nil, selectedImage: nil)
		
		return navigationController
	}
	
	private func initializeTabBarController() {
		guard !isTabBarControllerInitialized else { return }
		
		constraint.constant += view.safeAreaInsets.bottom
		
		let sceneDelegate = view.window?.windowScene?.delegate as? ConnectSceneDelegate
		guard let player = sceneDelegate?.player else { return }
		
		var viewControllers: [UIViewController] = [player.hand, player.graveyard, player.exile, player.library].compactMap { pile in
			pileViewController(for: pile, withExtraButton: true, withDoneButton: false)
		}
		
		if let battlefieldViewController = self.makeBattlefieldViewController() {
			viewControllers.append(battlefieldViewController)
		}
		
		containedTabBarController.setViewControllers(viewControllers, animated: false)
		
		player.revealedCards
			.observeOn(MainScheduler.instance)
//			.skip(1)
			.subscribe(onNext: { [weak self] cardItems in
				guard let self = self else { return }
				
				if cardItems.isEmpty {
					self.dismissMinimizedViewController()
				} else if self.presentedViewController == nil && self.minimizedViewController.value == nil {
					guard let viewController = self.makeRevealedCardsViewController(for: player) else { return }
					self.presentAndSave(viewController, animated: true)
				}
				
			}).disposed(by: bag)
		
		isTabBarControllerInitialized = true
	}
	
}
