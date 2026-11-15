//
//  CardImageViewController.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/5/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import UIKit
import CardService
import RxSwift

class CardImageViewController: UIViewController {
	
	private let bag = DisposeBag()
    private let cardCornerMask = CAShapeLayer()
	
	var temporaryImage: UIImage?
	
	@IBOutlet private weak var cardImageView: UIImageView!
	
	@IBOutlet weak var nameLabel: UILabel?
	@IBOutlet weak var typeLabel: UILabel?
	@IBOutlet weak var oracleLabel: UILabel?
	@IBOutlet weak var powerToughnessLabel: UILabel?
	
	
	var cardInstance: CardInstance? {
		didSet {
			if isViewLoaded {
				updateCardImage()
			}
			navigationItem.title = cardInstance?.representation.name
			
			cardInstance?.representedCardDidChange
			.subscribe(onNext: { [weak self] _ in
				guard let self = self, self.isViewLoaded else { return }
				self.updateCardImage()
			}).disposed(by: bag)
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		let interaction = UIDragInteraction(delegate: self)
		cardImageView.addInteraction(interaction)
		cardImageView.isUserInteractionEnabled = true
		
		if AppDelegate.shared.role.isBoard && !AppDelegate.shared.usesPhoneSession {
			let gesture = UITapGestureRecognizer(target: self, action: #selector(cardImageDoubleTapped(sender:)))
//			gesture.numberOfTapsRequired = 2
			cardImageView.addGestureRecognizer(gesture)
		}
		
		cardImageView.layer.masksToBounds = true
		cardImageView.layer.mask = cardCornerMask
		
		updateCardImage()
		
//		let rotateGestureRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(rotated(_:)))
//		cardImageView.addGestureRecognizer(rotateGestureRecognizer)
	}
	
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCardCorners()
    }

    private func updateCardCorners() {
        guard let image = cardImageView.image, image.size.width > 0, image.size.height > 0 else { return }
        // Aspect-fit images can be narrower than their UIImageView. Round the
        // visible card itself, rather than the surrounding letterbox bounds.
        let bounds = cardImageView.bounds
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                          width: size.width, height: size.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardCornerMask.frame = bounds
        cardCornerMask.path = UIBezierPath(roundedRect: rect, cornerRadius: size.width * 0.045).cgPath
        CATransaction.commit()
    }

	@objc private func rotated(_ gestureRecognizer: UIRotationGestureRecognizer) {
		// user's two fingers. This creates a more natural looking rotation.
		guard let view = gestureRecognizer.view else { return }
		
		let transform = view.transform.rotated(by: gestureRecognizer.rotation)
		view.transform = transform
		gestureRecognizer.rotation = 0
		
//		print(gestureRecognizer.rotation / .pi)
//		if gestureRecognizer.state == .began || gestureRecognizer.state == .changed {
//			if gestureRecognizer.rotation >= .pi / 4 {
//				rotateClockwise()
//				gestureRecognizer.rotation = 0
//			} else if gestureRecognizer.rotation <= .pi / -4 {
//				rotateClockwise()
//				gestureRecognizer.rotation = 0
//			}
//		}
	}
		
	@objc private func cardImageDoubleTapped(sender: Any) {
        guard !AppDelegate.shared.usesPhoneSession else { return }
			rotateClockwise()
	}
	
	private func rotateClockwise() {
		UIView.animate(withDuration: 0.2) { [weak self] in
			guard let imageView = self?.cardImageView else { return }
			imageView.transform = imageView.transform.rotated(by: .pi)
		}
		
	}
	
	private func rotateCounterClockwise() {
		UIView.animate(withDuration: 0.2) { [weak self] in
			guard let imageView = self?.cardImageView else { return }
			imageView.transform = imageView.transform.rotated(by: -.pi)
		}
	}
	
	private func updateCardImage() {
		guard let card = cardInstance?.representation else {
			cardImageView.image = #imageLiteral(resourceName: "mtg-card-back-png-1")
            updateCardCorners()
			return
		}
		
		if case .faceDown(_) = card {
			cardImageView.image = #imageLiteral(resourceName: "mtg-card-back-png-1")
            updateCardCorners()
			return
		}
		
		cardImageView.image = temporaryImage

		DispatchQueue.global(qos: .userInteractive).async {
			let image = card.image(type: .large)
			DispatchQueue.main.async { [weak self] in
				guard let self = self else { return }
				UIView.transition(with: self.cardImageView,
				duration: 0.2,
				options: .transitionCrossDissolve,
				animations: {
					self.cardImageView.image = image
                    self.updateCardCorners()
				},
				completion: nil)
			}
		}
		
        view.setNeedsLayout()
		updateCardText()
	}
	
	private func updateCardText() {
		guard let card = cardInstance?.representation else {
			nameLabel?.isHidden = true
			typeLabel?.isHidden = true
			oracleLabel?.isHidden = true
			powerToughnessLabel?.isHidden = true
			return
		}
		
		if case .faceDown(_) = card {
			nameLabel?.isHidden = true
			typeLabel?.isHidden = true
			oracleLabel?.isHidden = true
			powerToughnessLabel?.isHidden = true
			return
		}
		
    nameLabel?.text = card.card.printedName ?? card.name
    typeLabel?.text = card.card.printedTypeLine ?? card.typeLine
    oracleLabel?.text = card.card.printedText ?? card.oracleText
		powerToughnessLabel?.text = [card.power, card.toughness, card.loyalty].compactMap { $0 }.joined(separator: "/")
	}
	
}

extension CardImageViewController: UIDragInteractionDelegate {
	var dragItem: UIDragItem? {
		guard let cardInstance = cardInstance else { return nil }
		let item = NSItemProvider(card: cardInstance)
		let dragItem = UIDragItem(itemProvider: item)
		dragItem.localObject = cardInstance
		dragItem.previewProvider = { [weak self] in
			let imageView = UIImageView(image: self?.cardImageView.image ?? #imageLiteral(resourceName: "mtg-card-back-png-1"))
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
	
	func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
		guard let dragItem = dragItem else { return [] }
		return [dragItem]
	}
	
	func dragInteraction(_ interaction: UIDragInteraction, itemsForAddingTo session: UIDragSession, withTouchAt point: CGPoint) -> [UIDragItem] {
		guard let cardInstance = cardInstance else { return [] }
		let cardInstances = session.items.compactMap { $0.cardInstance }
		guard !cardInstances.contains(cardInstance) else { return [] }
		guard let dragItem = dragItem else { return [] }
		return [dragItem]
	}
}
