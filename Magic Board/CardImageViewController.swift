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

	/// Card menus: a round arrows button under the card shows its other side (transform, modal
	/// DFC, flip…) just here — the card on the battlefield doesn't change and the opponent isn't told.
	var showsOtherSideButton = false {
		didSet { if isViewLoaded { updateOtherSideButton() } }
	}
	/// Showing the side that isn't the card's current one.
	private var isShowingOtherSide = false
	private let otherSideButton = UIButton(type: .system)
	private var imageBottomConstraint: NSLayoutConstraint?
	
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
			
			isShowingOtherSide = false
			cardInstance?.representedCardDidChange
			.subscribe(onNext: { [weak self] _ in
				guard let self = self, self.isViewLoaded else { return }
				self.isShowingOtherSide = false
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

		imageBottomConstraint = view.constraints.first { constraint in
			(constraint.firstItem === cardImageView || constraint.secondItem === cardImageView)
				&& constraint.firstAttribute == .bottom && constraint.secondAttribute == .bottom
		}
		var config = UIButton.Configuration.plain()
		config.image = UIImage(systemName: "arrow.2.circlepath")
		config.preferredSymbolConfigurationForImage = .init(pointSize: 17, weight: .semibold)
		config.baseForegroundColor = .label
		config.background.backgroundColor = .tertiarySystemFill
		config.cornerStyle = .capsule
		otherSideButton.configuration = config
		otherSideButton.accessibilityIdentifier = "card-other-side"
		otherSideButton.addTarget(self, action: #selector(toggleOtherSide), for: .touchUpInside)
		otherSideButton.isHidden = true
		view.addSubview(otherSideButton)

		updateCardImage()
		
//		let rotateGestureRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(rotated(_:)))
//		cardImageView.addGestureRecognizer(rotateGestureRecognizer)
	}
	
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCardCorners()
        // Centered just under the card itself (aspect fit leaves letterbox space around it).
        let card = visibleCardRect
        let size: CGFloat = 40
        otherSideButton.frame = CGRect(x: card.midX - size / 2, y: card.maxY + 6, width: size, height: size)
    }

    /// The drawn card, in this view's coordinates.
    private var visibleCardRect: CGRect {
        let bounds = cardImageView.bounds
        guard let image = cardImageView.image, image.size.width > 0, image.size.height > 0 else { return cardImageView.frame }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let center = CGPoint(x: cardImageView.frame.midX, y: cardImageView.frame.midY)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    // MARK: Other side

    /// Layouts whose other side is a different card image.
    private static let doubleFacedLayouts: Set<String> = ["transform", "modal_dfc", "double_faced_token", "reversible_card", "battle", "art_series"]

    private enum OtherSide { case none, turnOver, rotate }

    private var otherSideKind: OtherSide {
        guard let representation = cardInstance?.representation else { return .none }
        switch representation {
        case .card, .alternateFace, .tokenCopy, .prototyped: break
        default: return .none // face-down cards keep their secret
        }
        let card = representation.card
        guard let faces = card.cardFaces, faces.count >= 2 else { return .none }
        if card.layout == "flip" { return .rotate }
        return Self.doubleFacedLayouts.contains(card.layout) ? .turnOver : .none
    }

    /// The face the card currently shows (0 = front).
    private var currentFaceIndex: Int {
        guard let representation = cardInstance?.representation else { return 0 }
        let faces = representation.card.cardFaces ?? []
        switch representation {
        case .alternateFace(_, let face), .tokenCopy(.alternateFace(_, let face)):
            return faces.firstIndex(of: face) ?? 0
        default: return 0
        }
    }

    /// The face on screen: the current one, or the other one while previewing.
    private var shownFaceIndex: Int {
        isShowingOtherSide ? (currentFaceIndex == 0 ? 1 : 0) : currentFaceIndex
    }

    /// Upside down: a flip card's flipped half, and the back of a card printed upside down
    /// (Scryfall frame effect "upsidedowndfc", e.g. Hawkins National Laboratory // The Upside Down).
    private var shownFaceIsUpsideDown: Bool {
        guard let card = cardInstance?.representation.card, shownFaceIndex == 1 else { return false }
        return card.layout == "flip" || card.frameEffects?.contains("upsidedowndfc") == true
    }

    private func updateOtherSideButton() {
        let kind = otherSideKind
        let visible = showsOtherSideButton && kind != .none
        otherSideButton.isHidden = !visible
        otherSideButton.configuration?.image = UIImage(systemName: kind == .rotate ? "arrow.clockwise" : "arrow.2.circlepath")
        otherSideButton.accessibilityLabel = isShowingOtherSide ? "Show Current Side" : "Show Other Side"
        otherSideButton.isSelected = isShowingOtherSide
        // Room for the button under the card.
        imageBottomConstraint?.constant = visible ? 8 + 52 : 8
    }

    @objc private func toggleOtherSide() {
        let kind = otherSideKind
        guard kind != .none else { return }
        isShowingOtherSide.toggle()
        updateOtherSideButton()
        if kind == .rotate {
            // A flip card is one image: it just turns around.
            let reduce = UIAccessibility.isReduceMotionEnabled
            UIView.animate(withDuration: reduce ? 0 : 0.3, delay: 0, options: [.curveEaseInOut]) {
                self.cardImageView.transform = self.shownFaceIsUpsideDown ? CGAffineTransform(rotationAngle: .pi) : .identity
            }
        } else {
            updateCardImage(flip: true)
        }
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
	
	private func updateCardImage(flip: Bool = false) {
		if isViewLoaded { updateOtherSideButton() }
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
		
		if !flip { cardImageView.image = temporaryImage }

		let kind = otherSideKind
		let faceIndex = shownFaceIndex
		let upsideDown = shownFaceIsUpsideDown
		// A flip card's halves share one image (turned around); a double-faced card shows a face's image.
		cardImageView.transform = kind == .rotate && upsideDown ? CGAffineTransform(rotationAngle: .pi) : .identity
		let mtgCard = card.card
		DispatchQueue.global(qos: .userInteractive).async {
			var image: UIImage?
			if kind == .turnOver, let faces = mtgCard.cardFaces, faces.indices.contains(faceIndex) {
				image = mtgCard.image(type: .large, for: faces[faceIndex])
				if upsideDown, let cgImage = image?.cgImage {
					image = UIImage(cgImage: cgImage, scale: image?.scale ?? 1, orientation: .down)
				}
			} else {
				image = card.image(type: .large)
			}
			DispatchQueue.main.async { [weak self] in
				guard let self = self else { return }
				let reduce = UIAccessibility.isReduceMotionEnabled
				UIView.transition(with: self.cardImageView,
				duration: flip && !reduce ? 0.35 : 0.2,
				options: flip && !reduce ? (self.isShowingOtherSide ? .transitionFlipFromRight : .transitionFlipFromLeft) : .transitionCrossDissolve,
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
