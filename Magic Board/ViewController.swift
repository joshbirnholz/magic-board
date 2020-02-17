//
//  ViewController.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/12/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import Swiftfall
import RxSwift

class ViewController: UIViewController {
	
	@IBOutlet weak var scrollView: UIScrollView!
	@IBOutlet weak var board: UIView!
	@IBOutlet weak var boardWidthConstraint: NSLayoutConstraint!
	
	var cards: [MiniCardView: CardInstance] = [:]
	
	private let bag = DisposeBag()
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		splitViewController?.preferredDisplayMode = .primaryHidden
		splitViewController?.view.backgroundColor = .clear
		view.window?.backgroundColor = .black
		
		boardWidthConstraint.constant = UIScreen.main.bounds.width * 10
		
		let tap = UITapGestureRecognizer(target: self, action: #selector(tapRecognized(gestureRecognizer:)))
		board.addGestureRecognizer(tap)
		
		let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressRecognized(gestureRecognizer:)))
		board.addGestureRecognizer(longPress)
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		
		scrollView.zoomScale = 0.3
		centerScrollView()
	}
	
	fileprivate func addCardAtPoint(_ card: Swiftfall.Card, _ gestureRecognizer: UIGestureRecognizer) {
		let loc = gestureRecognizer.location(in: board)
		let cardView = MiniCardView(frame: CGRect(x: loc.x, y: loc.y, width: 500, height: 500))
		let cardInstance = CardInstance(card: card)
		cardView.cardInstance = cardInstance
		cardView.isOracleBoxHidden = shouldHideOracleBoxes()
		cardView.isCostLabelHidden = shouldHideOracleBoxes()
		cardView.isTypeLabelHidden = shouldHideOracleBoxes()
		
		let panGesture = UIPanGestureRecognizer(target: self, action: #selector(panRecognized(gestureRecognizer:)))
		panGesture.maximumNumberOfTouches = 1
		cardView.addGestureRecognizer(panGesture)
		
		let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(longPressOnCardRecognized(gestureRecognizer:)))
		cardView.addGestureRecognizer(longPressGesture)
		
		cards[cardView] = cardInstance
		
		cardInstance.remove
			.subscribe(onNext: { [weak self] (_) in
				guard let self = self else { return }
				self.cards[cardView] = nil
				cardView.removeFromSuperview()
			}).disposed(by: bag)
		
		board.addSubview(cardView)
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
		toggleSidebar()
	}
	
	@objc func longPressOnCardRecognized(gestureRecognizer: UITapGestureRecognizer) {
		(splitViewController?.viewControllers.first as? SideTableViewController)?.card = (gestureRecognizer.view as? MiniCardView)?.cardInstance
		
		if splitViewController?.displayMode == .primaryHidden {
			toggleSidebar()
		}
	}
	
	func toggleSidebar() {
		guard let splitViewController = splitViewController else { return }
		
		let target = splitViewController.displayModeButtonItem.target
		let action = splitViewController.displayModeButtonItem.action
		_ = target?.perform(action)
	}
	
	@objc func panRecognized(gestureRecognizer: UIPanGestureRecognizer) {
		guard gestureRecognizer.state != . cancelled && gestureRecognizer.state != .failed else { return }
		guard let cardView = gestureRecognizer.view as? MiniCardView else { return }
		
		cardView.superview?.bringSubviewToFront(cardView)
		let translation = gestureRecognizer.translation(in: board)
		cardView.center = CGPoint(x: cardView.center.x + translation.x, y: cardView.center.y + translation.y)
		gestureRecognizer.setTranslation(.zero, in: board)
		
		// recognize groups
		
		let tolerance: CGFloat = 300
		for (otherCardView, otherCardInstance) in cards where otherCardView != cardView && otherCardView.card.name == cardView.card.name {
			let rect = CGRect(origin: otherCardView.center.applying(CGAffineTransform(translationX: -tolerance/2, y: -tolerance/2)), size: CGSize(width: tolerance, height: tolerance))
			if rect.contains(cardView.center) {
				
			} else {
				
			}
		}
	}
	
	@objc func longPressRecognized(gestureRecognizer: UIGestureRecognizer) {
		let alert = UIAlertController(title: "Enter a card name", message: nil, preferredStyle: .alert)
		alert.addTextField(configurationHandler: nil)
		
		let action = UIAlertAction(title: "Add", style: .default) { (_) in
			do {
				guard let name = alert.textFields?.first?.text else { return }
				let card = try Swiftfall.getCard(fuzzy: name)
				self.addCardAtPoint(card, gestureRecognizer)
			} catch {
				let alert = UIAlertController(title: "Error", message: String(describing: error), preferredStyle: .alert)
				let okAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
				alert.addAction(okAction)
				self.present(alert, animated: true, completion: nil)
			}
		}
		alert.addAction(action)
		
		let randomAction = UIAlertAction(title: "Random", style: .default) { (_) in
			do {
				let card = try Swiftfall.getRandomCard()
				self.addCardAtPoint(card, gestureRecognizer)
			} catch {
				let alert = UIAlertController(title: "Error", message: String(describing: error), preferredStyle: .alert)
				let okAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
				alert.addAction(okAction)
				self.present(alert, animated: true, completion: nil)
			}
		}
		alert.addAction(randomAction)
		
		let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
		alert.addAction(cancel)
		
		present(alert, animated: true, completion: nil)
		
	}


}

extension ViewController: UIScrollViewDelegate {
	func viewForZooming(in scrollView: UIScrollView) -> UIView? {
		return board
	}
	
	func shouldHideOracleBoxes() -> Bool {
		scrollView.zoomScale / scrollView.maximumZoomScale < 0.6
	}
	
	func scrollViewDidZoom(_ scrollView: UIScrollView) {
		let shouldHideOracleBoxes = self.shouldHideOracleBoxes()
		DispatchQueue.main.async {
			UIView.animate(withDuration: 0.2) {
				for cardView in self.cards.keys {
					cardView.isOracleBoxHidden = shouldHideOracleBoxes
					cardView.isCostLabelHidden = shouldHideOracleBoxes
					cardView.isTypeLabelHidden = shouldHideOracleBoxes
				}
			}
		}
	}
	
	func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
		
	}
}
