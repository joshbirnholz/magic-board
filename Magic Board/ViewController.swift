//
//  ViewController.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/12/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import Swiftfall



class ViewController: UIViewController {
	
	@IBOutlet weak var scrollView: UIScrollView!
	@IBOutlet weak var board: UIView!
	@IBOutlet weak var boardWidthConstraint: NSLayoutConstraint!
	
	var cardViews: [MiniCardView] = []
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		boardWidthConstraint.constant = UIScreen.main.bounds.width * 10
		
		let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(gestureRecognized(gestureRecognizer:)))
		board.addGestureRecognizer(gestureRecognizer)
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		
		centerScrollView()
		scrollView.zoomScale = 0.5
	}
	
	fileprivate func addCardAtPoint(_ card: Swiftfall.Card, _ gestureRecognizer: UITapGestureRecognizer) {
		let loc = gestureRecognizer.location(in: board)
		let cardView = MiniCardView(frame: CGRect(x: loc.x, y: loc.y, width: 500, height: 500))
		cardView.card = card
		cardView.isOracleBoxHidden = shouldHideOracleBoxes()
		cardView.isCostLabelHidden = shouldHideOracleBoxes()
		cardView.isTypeLabelHidden = shouldHideOracleBoxes()
		
		cardViews.append(cardView)
		
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
	
	@objc func gestureRecognized(gestureRecognizer: UITapGestureRecognizer) {
		do {
			let card = try Swiftfall.getRandomCard()
//			let card = try Swiftfall.getCard(fuzzy: "Rhythm of the wild")
			addCardAtPoint(card, gestureRecognizer)

			
		} catch {
			print(error)
		}
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
				for cardView in self.cardViews {
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
