//
//  MiniCardView.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/12/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import CardService
import RxSwift
import RxCocoa

class MiniCardView: UIView {
	
	private var bag = DisposeBag()

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
	@IBOutlet weak var edgeView: UIImageView!
	@IBOutlet weak var landView: UIView!
	@IBOutlet weak var watermarkImageView: UIImageView!
	@IBOutlet weak var landIconImageView: UIImageView!
	@IBOutlet weak var edgeViewBottomSpacingConstraint: NSLayoutConstraint!
	@IBOutlet weak var chainsImageView: UIImageView!
	@IBOutlet weak var countersStackView: UIStackView!
	@IBOutlet weak var triggeredAbilityImageView: UIImageView!
	@IBOutlet weak var tapAbilityImageView: UIImageView!
	
	var card: CardRepresentation {
		return cardInstance!.representation
	}
	
	var cardInstance: CardInstance! {
		didSet {
			updateCard()
		}
	}
	
	private func updateCard() {
		bag = DisposeBag()
		
		titleLabel.text = card.name
		
		let borderColor = card.borderColor
		cardView.backgroundColor = borderColor.uiColor
		
		addColors()
		
		if let view = self.card.fullArt ? self.edgeView : self.artImageView {
			view.image = nil
			DispatchQueue.global(qos: .userInteractive).async { [weak self, card] in
				let image = card.image(type: .art)
				DispatchQueue.main.async { [weak self] in
					guard let self = self, let image = image, card == self.card else { return }
					UIView.transition(with: view,
									  duration: 0.2,
									  options: .transitionCrossDissolve,
									  animations: { view.image = image },
									  completion: nil)
				}
			}
		}
		
		borderView.mask = nil
		if card.fullArt {
			borderView.mask(withRect: artImageView.frame.inset(by: UIEdgeInsets(top: artImageView.layer.borderWidth, left: artImageView.layer.borderWidth, bottom: artImageView.layer.borderWidth, right: artImageView.layer.borderWidth)), inverse: true)
			//				edgeViewBottomSpacingConstraint.constant = 0
			//				edgeView.roundCorners(topLeft: 10, topRight: 10, bottomLeft: 10, bottomRight: 10)
			
			//				titleBox.backgroundColor = titleBox.backgroundColor?.darkened(by: 0.6)
			bottomBox.backgroundColor = bottomBox.backgroundColor//?.darkened(by: 0.25)
			//				titleLabel.textColor = .white
			
			oracleBox.backgroundColor = UIColor.black.withAlphaComponent(0.55)
			cardTextLabel.textColor = .white
		}
		
		landView.isHidden = !card.isLand
		watermarkImageView.isHidden = !card.isBasicLand
		
		if card.isBasicLand, let typeLine = card.typeLine, let landName = typeLine.components(separatedBy: " ").last, let color = MTGColor(landName: landName) {
			watermarkImageView.image = UIImage(named: landName) ?? #imageLiteral(resourceName: "Wastes")
			
			landIconImageView.image = UIImage(named: "{\(color.rawValue)}")
		}
		
		var text: [NSMutableAttributedString] = []
		let textFontSize: CGFloat = 24
		let textFont = UIFont(name: "MPlantin", size: textFontSize)!
		let italicFont = UIFont(name: "MPlantin-Italic", size: textFontSize)!
		if var oracleText = card.oracleText, !oracleText.isEmpty, !card.isBasicLand {
			oracleText = oracleText
				.replacingOccurrences(of: "\n", with: "\n\n")
				.replacingOccurrences(of: "−", with: "-")
			
			let attributedString = NSMutableAttributedString(string: oracleText, attributes: [.font: textFont])
			
			let matches = oracleText.matches(forRegex: #"(?:\((.*?)\)|^(.+) — )"#, options: .dotMatchesLineSeparators)
			for match in matches {
				let range = NSRange(match.fullMatch.range, in: oracleText)
				attributedString.addAttribute(.font, value: italicFont, range: range)
			}
			
			for symbol in MTGSymbolName.allCases {
				let attachment = NSTextAttachment()
				attachment.image = symbol.image
				attachment.setImageHeight(height: textFontSize * 0.67)
				let attachmentString = NSAttributedString(attachment: attachment)
				
				while let range = attributedString.string.range(of: symbol.rawValue) {
					attributedString.replaceCharacters(in: NSRange(range, in: attributedString.string), with: attachmentString)
				}
			}
			
			text.append(attributedString)
		}
		
		if let flavorText = card.flavorText, card.card.language == .english {
			let attributedString = NSMutableAttributedString(string: flavorText, attributes: [.font: italicFont])
			
			let matches = flavorText.matches(forRegex: "\\*([^*]+)\\*")
			for (fullMatch, groups) in matches {
				guard let group = groups.first else { continue }
				let range = NSRange(fullMatch.range, in: attributedString.string)
				attributedString.addAttribute(.font, value: textFont, range: range)
				// TODO: Remove the asterisks -- repalce the range of the full match in the attributed string with just the text of the capture group.
			}
			
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
			
			for symbol in MTGSymbolName.allCases {
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
		
		updateTransform(controllerIdentifier: cardInstance.controllerIdentifier.value, isTapped: cardInstance.isTapped.value, animated: false)
		
		if let oracleText = card.oracleText, !oracleText.matches(forRegex: #"^((At )|(When )|(Whenever ))"#, options: .anchorsMatchLines).isEmpty {
			triggeredAbilityImageView.isHidden = false
			// TODO: Make this NOT match "enters the battlefield" effects
		} else {
			triggeredAbilityImageView.isHidden = true
		}
		
		if let oracleText = card.oracleText, !oracleText.matches(forRegex: #"^.*{T}.*:"#, options: .anchorsMatchLines).isEmpty {
			// TODO: Check why this isn't working!
			tapAbilityImageView.isHidden = false
		} else {
			tapAbilityImageView.isHidden = true
		}
		
		bind()
	}
	
	private func addColors() {
		let originalColors = card.colors ?? [.colorless]
		var colors = originalColors
		
		let typeLine = card.typeLine?.lowercased() ?? ""
		
		if colors.isEmpty {
			if typeLine.contains("basic land") {
				for color in MTGColor.allCases {
					guard let land = color.land, typeLine.contains(land) else { continue }
					colors.append(color)
				}
			} else if typeLine.contains("land"), let oracleText = card.oracleText?.lowercased() {
				let lines = oracleText.split(separator: "\n")
				
				var foundMulticolor = false
				
				for line in lines {
					let split = line.split(separator: ":")
					guard split.count == 2 else { continue }
					let abilityText = split[1]
					
					for color in MTGColor.allCases {
						guard abilityText.contains("{\(color.rawValue.lowercased())}") else { continue }
						colors.append(color)
					}
					
					if abilityText.contains("of any color") {
						foundMulticolor = true
					}
				}
				
				if colors.isEmpty && foundMulticolor {
					colors = [.multicolor]
				}
			} else if typeLine.contains("artifact") {
				colors = [.artifact]
			}
			
			if colors.isEmpty {
				colors = [.colorless]
			}
		}
		
		let regex = "\\{(.*?)\\}"
		let costColors = (card.manaCost ?? "").matches(forRegex: regex).compactMap { $0.groups.compactMap { MTGColor(rawValue: $0.value) } }.joined()
		if Set(costColors) == Set(colors) {
			colors = Array(costColors).uniques
		}
		
		if colors.count >= 3 && card.manaCost?.contains("/") == false && !card.isToken {
			colors = [.multicolor]
		}
		
		var didSetBoxes = false
		
		func setBoxes(colors: [MTGColor]) {
			if card.isToken {
				titleBox.backgroundColor = .black
				titleLabel.textColor = #colorLiteral(red: 0.9784926772, green: 0.8576988578, blue: 0.3988588452, alpha: 1)
				titleLabel.font = UIFont(name: "Beleren Small Caps", size: titleLabel.font.pointSize)
				titleLabel.textAlignment = .center
			} else if card.isEmblem {
				titleBox.backgroundColor = .black
				titleLabel.textColor = .white
				titleLabel.font = UIFont(name: "Beleren Small Caps", size: titleLabel.font.pointSize)
				titleLabel.textAlignment = .center
			} else {
				titleLabel.textColor = .black
				titleLabel.font = UIFont(name: "Beleren2016-Bold", size: titleLabel.font.pointSize)
				titleLabel.textAlignment = .natural
				addGradient(to: titleBox, colors: colors, opacity: 1, type: \.boxBackgroundColor)
			}
			
			addGradient(to: bottomBox, colors: colors, opacity: 1, type: \.boxBackgroundColor)
			addGradient(to: oracleBox, colors: colors, opacity: 0.75, type: \.textBackgroundColor)
			addGradient(to: powerToughnessBox, colors: colors, opacity: 1, type: \.textBackgroundColor)
			didSetBoxes = true
		}
		
		if typeLine.contains("land") {
			setBoxes(colors: colors)
		}
		
		addGradient(to: borderView, colors: colors, opacity: 1, type: \.borderColor)
		
		if colors != [.artifact] && (originalColors.isEmpty || originalColors == [.colorless]) {
			colors = [.colorless]
		} else if colors.count == 2 && card.manaCost?.contains("/") == false && !card.isToken {
			colors = [.multicolor]
		}
		
		if !didSetBoxes {
			setBoxes(colors: colors)
		}
		
		if typeLine.contains("artifact") {
//			addGradient(to: edgeView, colors: [.artifact], opacity: 1, type: \.cardEdgeColor)
			edgeView.image = MTGColor.artifact.cardEdgeImage
		} else if typeLine.contains("land") {
			edgeView.image = #imageLiteral(resourceName: "bg-land")
		} else {
			edgeView.image = colors.first?.cardEdgeImage
//			addGradient(to: edgeView, colors: colors, opacity: 1, type: \.cardEdgeColor)
		}
		
	}
	
	private func addGradient(to view: UIView, colors: [MTGColor], opacity: Float, type: KeyPath<MTGColor, UIColor>) {
		class CustomGradientLayer: CAGradientLayer { }
		view.layer.sublayers?.filter({ $0 is CustomGradientLayer }).forEach { $0.removeFromSuperlayer() }
		
		let backgroundColors: [UIColor] = colors.map { $0[keyPath: type] }
		
		if backgroundColors.count == 1, let backgroundColor = backgroundColors.first {
			view.backgroundColor = backgroundColor.withAlphaComponent(CGFloat(opacity))
		} else {
			let gradient = CustomGradientLayer()
			gradient.frame = view.bounds
			gradient.colors = backgroundColors.map { $0.cgColor }
			
			gradient.startPoint = CGPoint(x: 0.0, y: 0.5)
			gradient.endPoint = CGPoint(x: 1.0, y: 0.5)
			gradient.locations = [0.38, 0.62]
			gradient.opacity = opacity
			
			view.layer.insertSublayer(gradient, at: 0)
		}
	}
	
	private var shouldAlwaysHideTextBox: Bool {
		return card.isBasicLand || ((card.oracleText == nil || card.oracleText == "") && (card.flavorText == nil || card.flavorText == ""))
	}
	
	var isOracleBoxHidden: Bool {
		set {
			guard !shouldAlwaysHideTextBox else {
				oracleBox.alpha = 0
				return
			}
			
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
		
		cardInstance.representedCardDidChange
			.subscribe(onNext: { [weak self] _ in
				self?.updateCard()
			}).disposed(by: bag)
		
		Observable.combineLatest(cardInstance.power, cardInstance.toughness, cardInstance.counters)
			.map { [weak self] power, toughness, counters in
				guard let self = self else { return NSAttributedString() }
				return self.powerToughnessLabelText(power: power, toughness: toughness, counters: counters)
				}
			.bind(to: powerToughnessLabel.rx.attributedText)
			.disposed(by: bag)
		
		cardInstance.isPowerToughnessVisible
			.subscribe(onNext: { [weak self] isPowerToughnessVisible in
				self?.updateTransform(controllerIdentifier: cardInstance.controllerIdentifier.value, isTapped: cardInstance.isTapped.value, animated: true)
			}).disposed(by: bag)
		
		cardInstance.isPowerToughnessVisible
			.map { !$0 }
			.bind(to: powerToughnessLabel.rx.isHidden)
			.disposed(by: bag)
		
		cardInstance.isPowerToughnessVisible
			.map { !$0 }
			.bind(to: powerToughnessBox.rx.isHidden)
			.disposed(by: bag)
		
//		cardInstance.isSummoningSick
//			.subscribe(onNext: { [weak self] isSummoningSick in
//				if isSummoningSick {
//					self?.oracleBox.startGlowingWithColor(color: .black, fromIntensity: 0.1, toIntensity: 0.5, duration: 1.6, repeat: true)
//				} else {
//					self?.oracleBox.stopGlowing()
//				}
//			}).disposed(by: bag)
		
		cardInstance.isFlying
			.subscribe (onNext: { [weak self] isFlying in
				guard let self = self else { return }
				
				if isFlying {
					self.cardView.startWiggle(durationModifier: 24, varianceModifier: 1.2, angleModifier: 2, bounceModifier: 1)
					self.cardView.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
					self.layer.shadowOpacity = 0.75
					self.layer.shadowRadius = 50
					//			self.layer.allowsEdgeAntialiasing = true
					//			self.layer.shadowOffset = CGSize(width: 0, height: 50)
					self.layer.zPosition = 1
				} else {
					self.cardView.stopWiggle()
					self.cardView.transform = .identity
					self.layer.shadowOpacity = 0
					self.layer.zPosition = 0
					//				self.layer.allowsEdgeAntialiasing = false
					return
				}
			}).disposed(by: bag)
		
		cardInstance.counters
			.map { counters in
				counters.reduce(into: 0) { (result, counter) in
					if counter == .loyalty {
						result += 1
					}
				}
			}.map { [weak self] loyaltyCounterCount -> String? in
				guard let self = self else { return nil }
				if loyaltyCounterCount > 0 {
					return "\(loyaltyCounterCount)"
				} else if let loyalty = self.card.loyalty {
					let loyalty = loyalty.replacingOccurrences(of: "*", with: "★")
					if Int(loyalty) == nil {
						return loyalty
					} else if self.card.typeLine?.lowercased().contains("planeswalker") == true {
						return "0"
					}
				}
				return nil
			}
			.do(onNext: { [weak self] loyalty in
				self?.loyaltyBox.isHidden = loyalty == nil
			})
			.bind(to: loyaltyLabel.rx.text)
			.disposed(by: bag)
		
		cardInstance.counters
			.map { counters -> [Counter: Int] in
				let mappedItems = counters.compactMap { $0 == .loyalty ? nil : ($0, 1) }
				return Dictionary(mappedItems, uniquingKeysWith: +)
			}
			.subscribe(onNext: { [weak self] countersAndCounts in
				guard let self = self else { return }
				
				for subview in self.countersStackView.arrangedSubviews {
					subview.removeFromSuperview()
				}
				
				for (counter, count) in countersAndCounts {
//					let view = UIView()
					let image: UIImage? = {
						switch counter {
						case .plusOnePlusOne: return #imageLiteral(resourceName: "Plus")
						case .minusOneMinusOne: return #imageLiteral(resourceName: "Minus")
						case .loyalty: return #imageLiteral(resourceName: "Loyalty")
						default: return #imageLiteral(resourceName: "{0}").withRenderingMode(.alwaysTemplate)
						}
					}()
					let view = UIImageView(image: image)
					view.contentMode = .scaleAspectFit
					view.translatesAutoresizingMaskIntoConstraints = false
					let width: CGFloat = counter == .plusOnePlusOne || counter == .minusOneMinusOne || counter == .loyalty ? 80 : 60
					view.heightAnchor.constraint(equalToConstant: width).isActive = true
					view.widthAnchor.constraint(equalToConstant: width).isActive = true
					view.tintColor = counter.color
					
					view.layer.shadowColor = UIColor.black.cgColor
					view.layer.shadowRadius = 3.0
					view.layer.shadowOpacity = 0.8
					view.layer.shadowOffset = CGSize(width: 0, height: 3)
					view.layer.masksToBounds = false
					
					let label = UILabel()
					label.translatesAutoresizingMaskIntoConstraints = false
					view.addSubview(label)
					label.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
					label.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
					label.font = UIFont(name: "Beleren2016-Bold", size: 45)
					label.text = String(count)
					
					self.countersStackView.addArrangedSubview(view)
				}
			}).disposed(by: bag)
		
		Observable.combineLatest(cardInstance.controllerIdentifier, cardInstance.isTapped)
			.observeOn(MainScheduler.instance)
			.subscribe(onNext: { [weak self] controllerIdentifier, isTapped in
				self?.updateTransform(controllerIdentifier: controllerIdentifier, isTapped: isTapped, animated: true)
			}).disposed(by: bag)
		
		Observable.combineLatest(cardInstance.doesNotUntapNextTurn, cardInstance.doesNotUntapAutomatically)
			.do(onNext: { (doesNotUntapNextTurn, doesNotUntapAutomatically) in
				if doesNotUntapAutomatically {
					self.chainsImageView.image = #imageLiteral(resourceName: "chains")
				} else if doesNotUntapNextTurn {
					self.chainsImageView.image = #imageLiteral(resourceName: "bluechains")
				}
			})
			.map { !($0 || $1) }
			.bind(to: chainsImageView.rx.isHidden)
			.disposed(by: bag)
	}
	
	private func updateTransform(controllerIdentifier: Player.Identifier, isTapped: Bool, animated: Bool) {
		UIView.animate(withDuration: animated ? 0.3 : 0) { [weak self] in
			guard let self = self else { return }
			var transform: CGAffineTransform = .identity
			
			if controllerIdentifier == .b {
				transform = transform.rotated(by: .pi)
			}
			
			if isTapped {
				transform = transform.rotated(by: .pi/15)
				self.tappedDarkeningView.alpha = 0.5
			} else {
				self.tappedDarkeningView.alpha = 0
			}
			
			if let typeLine = self.card.typeLine?.lowercased(), !self.cardInstance.isPowerToughnessVisible.value && (typeLine.contains("artifact") || typeLine.contains("enchantment") || typeLine.contains("land") || typeLine.contains("emblem")) {
				let scale: CGFloat = 0.85
				transform = transform.scaledBy(x: scale, y: scale)
			}
			
			self.transform = transform
		}
	}
	
	private func powerToughnessLabelText(power: String, toughness: String, counters: [Counter]) -> NSAttributedString {
		let attributedString = NSMutableAttributedString()
		let normalColor: UIColor = .black
		let modifiedColor = #colorLiteral(red: 0.2145935893, green: 0.5758153796, blue: 0.8829388022, alpha: 1)
		
		func string(for power: String) -> String {
			var string = power.replacingOccurrences(of: "*", with: "★")
			
			if let value = Int(string) {
				let counterModifier: Int = counters.reduce(into: 0) { (result, counter) in
					if counter == .plusOnePlusOne {
						result += 1
					} else if counter == .minusOneMinusOne {
						result -= 1
					}
				}
				string = "\(value+counterModifier)"
			}
			
			return string
		}
		
		let powerString: String = string(for: power)
		let toughnessString = string(for: toughness)

		let powerAttributedString = NSAttributedString(string: powerString, attributes: [.foregroundColor: (powerString == self.cardInstance.representation.power?.replacingOccurrences(of: "*", with: "★") ? normalColor : modifiedColor)])
		attributedString.append(powerAttributedString)

		attributedString.append(NSAttributedString(string: "/"))

		let toughnessAttributedString = NSAttributedString(string: toughnessString, attributes: [.foregroundColor: (toughnessString == self.cardInstance.representation.toughness?.replacingOccurrences(of: "*", with: "★") ? normalColor : modifiedColor)])
		attributedString.append(toughnessAttributedString)

		attributedString.addAttribute(.font, value: UIFont(name: "Beleren2016-Bold", size: 40)!, range: NSRange(location: 0, length: attributedString.length))

		return attributedString
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
		
		let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapUnTapGestureRecognized))
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
				cardInstance.isTapped.accept(true)
				gestureRecognizer.rotation = 0
			} else if gestureRecognizer.rotation <= .pi / -4 {
				cardInstance.isTapped.accept(false)
				gestureRecognizer.rotation = 0
			}
		}
	}
	
	@objc private func tapUnTapGestureRecognized(_ gestureRecognizer: UIGestureRecognizer) {
		tapUnTap()
	}
	
	private func tapUnTap() {
		cardInstance.isTapped.toggle()
		try? GameState.current.save()
	}
	
	override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
		return cardView.hitTest(point, with: event)
	}

}

extension MiniCardView: UIGestureRecognizerDelegate {
//	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
//		if let otherGestureRecognizer = otherGestureRecognizer as? UITapGestureRecognizer, otherGestureRecognizer.numberOfTapsRequired == 2 {
//			return true
//		}
//		return false
//	}
}
