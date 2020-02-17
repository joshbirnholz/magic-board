//
//  MiniCardView.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/12/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import Swiftfall
import RxSwift
import RxCocoa

class MiniCardView: UIView {
	
	private let bag = DisposeBag()

	@IBOutlet var contentView: UIView!
	@IBOutlet var cardView: UIView!
	@IBOutlet weak var titleLabel: UILabel!
	@IBOutlet weak var powerToughnessLabel: UILabel!
	@IBOutlet weak var powerToughnessBox: UIView!
	@IBOutlet weak var artImageView: UIImageView!
	@IBOutlet weak var titleBox: UIView!
	@IBOutlet weak var bottomBox: UIView!
	@IBOutlet weak var cardTextLabel: UILabel!
	@IBOutlet weak var oracleBox: UIView!
	@IBOutlet weak var tappedDarkeningView: UIView!
	@IBOutlet weak var costLabel: UILabel!
	@IBOutlet weak var typeLabel: UILabel!
	@IBOutlet weak var borderView: UIView!
	@IBOutlet weak var loyaltyBox: UIView!
	@IBOutlet weak var loyaltyLabel: InsetLabel!
	@IBOutlet weak var typeBox: UIView!
	@IBOutlet weak var edgeView: UIView!
	@IBOutlet weak var landView: UIView!
	@IBOutlet weak var landManaSymbolImageView: UIImageView!
	
	var card: Swiftfall.Card {
		return cardInstance.card
	}
	
	var cardInstance: CardInstance! {
		didSet {
			
			titleLabel.text = card.name
			
			if let borderColor = Swiftfall.BorderColor(rawValue: card.borderColor) {
				cardView.backgroundColor = borderColor.uiColor
			}
			
			addColors()
			
			DispatchQueue.global(qos: .userInteractive).async { [weak self] in
				let image = self?.card.image(type: .art)
				DispatchQueue.main.async { [weak self] in
					guard let self = self, let image = image else { return }
					UIView.transition(with: self.artImageView,
					duration: 0.2,
					options: .transitionCrossDissolve,
					animations: { self.artImageView.image = image },
					completion: nil)
				}
			}
			
			let isBasicLand = card.typeLine?.lowercased().contains("basic land") == true
			let isLand = card.typeLine?.lowercased().contains("land") == true
			landView.isHidden = !isLand
			landManaSymbolImageView.isHidden = !isBasicLand
			
			if isBasicLand, let name = card.name, let image = UIImage(named: name) {
				landManaSymbolImageView.image = image
			}
			
			var text: [NSMutableAttributedString] = []
			let textFontSize: CGFloat = 24
			let textFont = UIFont(name: "MPlantin", size: textFontSize)!
			let italicFont = UIFont(name: "MPlantin-Italic", size: textFontSize)!
			if var oracleText = card.oracleText, !oracleText.isEmpty, !(card.typeLine?.contains("Basic Land") ?? false) {
				oracleText = oracleText
					.replacingOccurrences(of: "\n", with: "\n\n")
					.replacingOccurrences(of: "−", with: "-")
				
				let attributedString = NSMutableAttributedString(string: oracleText, attributes: [.font: textFont])
				
				let matches = oracleText.matches(forRegex: "\\((.*?)\\)")
				for match in matches {
					let range = NSRange(match.fullMatch.range, in: oracleText)
					attributedString.addAttribute(.font, value: italicFont, range: range)
				}
				
				for symbol in Swiftfall.SymbolName.allCases {
					let attachment = NSTextAttachment()
					attachment.image = symbol.image
					attachment.setImageHeight(height: 20)
					let attachmentString = NSAttributedString(attachment: attachment)
					
					while let range = attributedString.string.range(of: symbol.rawValue) {
						attributedString.replaceCharacters(in: NSRange(range, in: attributedString.string), with: attachmentString)
					}
				}
				
				text.append(attributedString)
			}
			
			if let flavorText = card.flavorText {
				let attributedString = NSMutableAttributedString(string: flavorText, attributes: [.font: italicFont])
				
				text.append(attributedString)
			}
			
			for string in text.dropLast() {
				string.append(NSAttributedString(string: "\n\n"))
			}
			
			cardTextLabel.attributedText = text.reduce(into: NSMutableAttributedString(), { (string, current) in
				string.append(current)
			})
			
			if let cost = card.manaCost {
				let cost = cost.replacingOccurrences(of: "}{", with: "} {")
				let attributedString = NSMutableAttributedString(string: cost, attributes: [.font: textFont])
				
				for symbol in Swiftfall.SymbolName.allCases {
					let attachment = NSTextAttachment()
					attachment.image = symbol.image
					attachment.setImageHeight(height: 30)
					let attachmentString = NSAttributedString(attachment: attachment)
					
					while let range = attributedString.string.range(of: symbol.rawValue) {
						attributedString.replaceCharacters(in: NSRange(range, in: attributedString.string), with: attachmentString)
					}
				}
				
				costLabel.attributedText = attributedString
			} else {
				costLabel.text = nil
			}
			
			typeLabel.text = card.typeLine
			
			bind()
		}
	}
	
	private func addColors() {
		let originalColors = (card.colors ?? [Swiftfall.Color.colorless.rawValue]).compactMap { Swiftfall.Color(rawValue: $0) }
		var colors = originalColors
		
		let typeLine = card.typeLine?.lowercased() ?? ""
		
		if colors.isEmpty {
			if typeLine.contains("basic land") {
				for color in Swiftfall.Color.allCases {
					guard let land = color.land, typeLine.contains(land) else { continue }
					colors.append(color)
				}
			} else if typeLine.contains("land"), let oracleText = card.oracleText?.lowercased() {
				let lines = oracleText.split(separator: "\n")
				for line in lines {
					let split = line.split(separator: ":")
					guard split.count == 2 else { continue }
					let abilityText = split[1]
					
					for color in Swiftfall.Color.allCases {
						guard abilityText.contains("{\(color.rawValue.lowercased())}") else { continue }
						colors.append(color)
					}
				}
			} else if typeLine.contains("artifact") {
				colors = [.artifact]
			}
			
			if colors.isEmpty {
				colors = [.colorless]
			}
		}
		
		let regex = "\\{(.*?)\\}"
		let costColors = (card.manaCost ?? "").matches(forRegex: regex).compactMap { $0.groups.compactMap { Swiftfall.Color(rawValue: $0.value) } }.joined()
		if Set(costColors) == Set(colors) {
			colors = Array(costColors).uniques
		}
		
		if colors.count >= 3 && card.manaCost?.contains("/") == false {
			colors = [.multicolor]
		}
		
		func setBoxes(colors: [Swiftfall.Color]) {
			addGradient(to: titleBox, colors: colors, opacity: 1, type: \.boxBackgroundColor)
			addGradient(to: bottomBox, colors: colors, opacity: 1, type: \.boxBackgroundColor)
			addGradient(to: oracleBox, colors: colors, opacity: 0.75, type: \.textBackgroundColor)
			addGradient(to: powerToughnessBox, colors: colors, opacity: 1, type: \.textBackgroundColor)
		}
		
		if typeLine.contains("land") {
			setBoxes(colors: colors)
		}
		
		addGradient(to: borderView, colors: colors, opacity: 1, type: \.borderColor)
		
		if colors != [.artifact] && (originalColors.isEmpty || originalColors == [.colorless]) {
			colors = [.colorless]
		} else if colors.count == 2 && card.manaCost?.contains("/") == false {
			colors = [.multicolor]
		}
		
		if !typeLine.contains("land") {
			setBoxes(colors: colors)
		}
		
		addGradient(to: edgeView, colors: colors, opacity: 1, type: \.cardEdgeColor)
		
	}
	
	private func addGradient(to view: UIView, colors: [Swiftfall.Color], opacity: Float, type: KeyPath<Swiftfall.Color, UIColor>) {
		let backgroundColors: [UIColor] = colors.map { $0[keyPath: type] }
		
		if backgroundColors.count == 1, let backgroundColor = backgroundColors.first {
			view.backgroundColor = backgroundColor.withAlphaComponent(CGFloat(opacity))
		} else {
			let gradient = CAGradientLayer()
			gradient.frame = view.bounds
			gradient.colors = backgroundColors.map { $0.cgColor }
			
			gradient.startPoint = CGPoint(x: 0.0, y: 0.5)
			gradient.endPoint = CGPoint(x: 1.0, y: 0.5)
			gradient.locations = [0.38, 0.62]
			gradient.opacity = opacity
			
			view.layer.insertSublayer(gradient, at: 0)
		}
	}
	
	var isOracleBoxHidden: Bool {
		set {
			oracleBox.alpha = newValue ? 0 : 1
		}
		get {
			oracleBox.alpha == 0
		}
	}
	
	var isCostLabelHidden: Bool {
		set {
			guard card.manaCost != nil else {
				costLabel.alpha = 0
				return
			}
			
			costLabel.alpha = newValue ? 0 : 1
		}
		get {
			costLabel.alpha == 0
		}
	}
	
	var isTypeLabelHidden: Bool {
		set {
			guard card.typeLine != nil else {
				typeBox.alpha = 0
				typeLabel.alpha = 0
				return
			}
			
			typeBox.alpha = newValue ? 0 : 0.6
			typeLabel.alpha = newValue ? 0 : 1
		}
		get {
			typeBox.alpha == 0
		}
	}
	
	private func bind() {
		guard let cardInstance = cardInstance else { return }
		
		cardInstance.power
			.map { [weak self] power in
				guard let self  = self else { return NSAttributedString() }
				return self.powerToughnessLabelText(power: power, toughness: self.cardInstance.toughness.value)
			}
			.bind(to: powerToughnessLabel.rx.attributedText)
			.disposed(by: bag)
		
		cardInstance.toughness
			.map { [weak self] toughness in
				guard let self  = self else { return NSAttributedString() }
				return self.powerToughnessLabelText(power: self.cardInstance.power.value, toughness: toughness)
			}
			.bind(to: powerToughnessLabel.rx.attributedText)
			.disposed(by: bag)
		
//		Observable.combineLatest(cardInstance.power, cardInstance.toughness)
//			.map { [weak self] arg in
//				let (power, toughness) = arg
//				guard let self = self else { return NSAttributedString() }
//				return self.powerToughnessLabelText(power: power, toughness: toughness)
//				}
//			.bind(to: powerToughnessLabel.rx.attributedText)
//			.disposed(by: bag)
		
		cardInstance.isPowerToughnessVisible
			.map { !$0 }
			.bind(to: powerToughnessLabel.rx.isHidden)
			.disposed(by: bag)
		
		cardInstance.isPowerToughnessVisible
			.map { !$0 }
			.bind(to: powerToughnessBox.rx.isHidden)
			.disposed(by: bag)
		
		cardInstance.isFlying
			.subscribe (onNext: { [weak self] isFlying in
				guard let self = self else { return }
				
				if isFlying {
					self.cardView.startWiggle(durationModifier: 12, varianceModifier: 1.2, angleModifier: 2, bounceModifier: 1)
					self.cardView.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
					self.layer.shadowOpacity = 0.75
					self.layer.shadowRadius = 50
					//			self.layer.allowsEdgeAntialiasing = true
					//			self.layer.shadowOffset = CGSize(width: 0, height: 50)
					self.layer.zPosition = 10
				} else {
					self.cardView.stopWiggle()
					self.cardView.transform = CGAffineTransform.identity
					self.layer.shadowOpacity = 0
					self.layer.zPosition = 0
					//				self.layer.allowsEdgeAntialiasing = false
					return
				}
			}).disposed(by: bag)
		
		cardInstance.loyalty
			.map { $0 == nil }
			.bind(to: loyaltyBox.rx.isHidden)
			.disposed(by: bag)
		
		cardInstance.loyalty
			.compactMap { $0 }
			.map(String.init)
			.bind(to: loyaltyLabel.rx.text)
			.disposed(by: bag)
		
		cardInstance.flip
			.subscribe(onNext: { [weak self] _ in
				self?.flip()
			}).disposed(by: bag)
	}
	
	private func powerToughnessLabelText(power: String, toughness: String) -> NSAttributedString {
		let attributedString = NSMutableAttributedString()
		let modifiedColor = #colorLiteral(red: 0.2145935893, green: 0.5758153796, blue: 0.8829388022, alpha: 1)

		let powerString = NSAttributedString(string: power, attributes: [.foregroundColor: (power == self.cardInstance.card.power ? UIColor.black : modifiedColor)])
		attributedString.append(powerString)

		attributedString.append(NSAttributedString(string: "/"))

		let toughnessString = NSAttributedString(string: toughness, attributes: [.foregroundColor: (toughness == self.cardInstance.card.toughness ? UIColor.black : modifiedColor)])
		attributedString.append(toughnessString)

		attributedString.addAttribute(.font, value: UIFont(name: "Beleren2016-Bold", size: 40)!, range: NSRange(location: 0, length: attributedString.length))

		return attributedString
	}
	
	var isTapped: Bool = false {
		didSet {
			guard isTapped != oldValue else { return }
			
			UIView.animate(withDuration: 0.3) {
				var amount: CGFloat = .pi/15
				if !self.isTapped {
					amount *= -1
				}
				
				self.transform = self.transform.rotated(by: amount)
				self.tappedDarkeningView.alpha = self.isTapped ? 0.5 : 0
			}
		}
	}
	
	func flip() {
		UIView.animate(withDuration: 0.3) {
			self.transform = self.transform.rotated(by: .pi)
		}
	}
	
	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}
	
	private func commonInit() {
		Bundle.main.loadNibNamed("MiniCardView", owner: self, options: nil)
		addSubview(contentView)
		contentView.frame = self.bounds
		contentView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
		
		cardView.layer.cornerRadius = 16
		cardView.layer.masksToBounds = true
		
		edgeView.roundCorners(topLeft: 10, topRight: 10, bottomLeft: 50, bottomRight: 50)
		
		borderView.layer.cornerRadius = 8
		borderView.layer.masksToBounds = true
		borderView.layer.borderWidth = 1
		borderView.layer.borderColor = UIColor.black.cgColor
		
		for box in [titleBox, bottomBox, artImageView, oracleBox] {
			box?.layer.borderWidth = 1
			box?.layer.borderColor = UIColor.black.cgColor
		}
		
		titleBox.layer.cornerRadius = 6
		titleBox.layer.masksToBounds = true
		
		bottomBox.layer.cornerRadius = 6
		bottomBox.layer.masksToBounds = true
		
		powerToughnessBox.layer.borderWidth = 1
		powerToughnessBox.layer.borderColor = UIColor.black.cgColor
		
		powerToughnessBox.layer.cornerRadius = 6
		powerToughnessBox.layer.masksToBounds = true
		powerToughnessBox.layer.borderColor = UIColor.black.cgColor
		powerToughnessBox.layer.borderWidth = 4
		powerToughnessBox.layer.shadowOpacity = 0.3
		
		typeBox.layer.cornerRadius = 16
		typeBox.layer.masksToBounds = true
		
		landView.layer.cornerRadius = landView.frame.width / 2
		landView.layer.masksToBounds = true
		
		let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapUnTap))
		cardView.addGestureRecognizer(gestureRecognizer)
		
//		let rotateGestureRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(rotated(_:)))
//		cardView.addGestureRecognizer(rotateGestureRecognizer)
	}
	
	@objc private func rotated(_ gestureRecognizer: UIRotationGestureRecognizer) {
		// user's two fingers. This creates a more natural looking rotation.
		guard gestureRecognizer.view != nil else { return }
		
		print(gestureRecognizer.rotation / .pi)
		if gestureRecognizer.state == .began || gestureRecognizer.state == .changed {
			if gestureRecognizer.rotation >= .pi / 4 {
				isTapped = true
				gestureRecognizer.rotation = 0
			} else if gestureRecognizer.rotation <= .pi / -4 {
				isTapped = false
				gestureRecognizer.rotation = 0
			}
		}
	}
	
	@objc private func tapUnTap() {
		isTapped.toggle()
	}
	
	override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
		return cardView.hitTest(point, with: event)
	}

}
