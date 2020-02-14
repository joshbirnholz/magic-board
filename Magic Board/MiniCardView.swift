//
//  MiniCardView.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/12/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import Swiftfall

extension NSTextAttachment {
    func setImageHeight(height: CGFloat) {
        guard let image = image else { return }
        let ratio = image.size.width / image.size.height
        
		bounds = CGRect(x: bounds.origin.x, y: bounds.origin.y, width: ratio * height, height: height)
    }
}

extension Swiftfall {
	
	enum Color: String {
		case white = "W"
		case blue = "U"
		case black = "B"
		case red = "R"
		case green = "G"
		case multicolor
		case artifact
		case colorless
		
		var name: String {
			switch self {
			case .white:
				return "white"
			case .blue:
				return "blue"
			case .black:
				return "black"
			case .red:
				return "red"
			case .green:
				return "green"
			case .multicolor:
				return "multicolor"
			case .artifact:
				return "artifact"
			case .colorless:
				return "colorless"
			}
		}
		
		var land: String? {
			switch self {
			case .white:
				return "plains"
			case .blue:
				return "island"
			case .black:
				return "swamp"
			case .red:
				return "mountain"
			case .green:
				return "forest"
			case .multicolor:
				return nil
			case .artifact:
				return nil
			case .colorless:
				return "wastes"
			}
		}
		
		var symbolColor: UIColor {
			return UIColor(named: "\(name) mana")!
		}
		
		var borderColor: UIColor {
			return UIColor(named: "\(name) border")!
		}
		
		var textBackgroundColor: UIColor {
			return UIColor(named: "\(name) background")!
		}
		
		var boxBackgroundColor: UIColor {
			return UIColor(named: "\(name) box background")!
		}
	}
	
	enum SymbolName: String, CaseIterable {
		case symbol_T = "{T}"
		case symbol_Q = "{Q}"
		case symbol_E = "{E}"
		case symbol_PW = "{PW}"
		case symbol_CHAOS = "{CHAOS}"
		case symbol_X = "{X}"
		case symbol_Y = "{Y}"
		case symbol_Z = "{Z}"
		case symbol_0 = "{0}"
		case symbol_½ = "{½}"
		case symbol_1 = "{1}"
		case symbol_2 = "{2}"
		case symbol_3 = "{3}"
		case symbol_4 = "{4}"
		case symbol_5 = "{5}"
		case symbol_6 = "{6}"
		case symbol_7 = "{7}"
		case symbol_8 = "{8}"
		case symbol_9 = "{9}"
		case symbol_10 = "{10}"
		case symbol_11 = "{11}"
		case symbol_12 = "{12}"
		case symbol_13 = "{13}"
		case symbol_14 = "{14}"
		case symbol_15 = "{15}"
		case symbol_16 = "{16}"
		case symbol_17 = "{17}"
		case symbol_18 = "{18}"
		case symbol_19 = "{19}"
		case symbol_20 = "{20}"
		case symbol_100 = "{100}"
		case symbol_1000000 = "{1000000}"
		case symbol_INFINITE = "{∞}"
		case symbol_W_U = "{W/U}"
		case symbol_W_B = "{W/B}"
		case symbol_B_R = "{B/R}"
		case symbol_B_G = "{B/G}"
		case symbol_U_B = "{U/B}"
		case symbol_U_R = "{U/R}"
		case symbol_R_G = "{R/G}"
		case symbol_R_W = "{R/W}"
		case symbol_G_W = "{G/W}"
		case symbol_G_U = "{G/U}"
		case symbol_2_W = "{2/W}"
		case symbol_2_U = "{2/U}"
		case symbol_2_B = "{2/B}"
		case symbol_2_R = "{2/R}"
		case symbol_2_G = "{2/G}"
		case symbol_P = "{P}"
		case symbol_W_P = "{W/P}"
		case symbol_U_P = "{U/P}"
		case symbol_B_P = "{B/P}"
		case symbol_R_P = "{R/P}"
		case symbol_G_P = "{G/P}"
		case symbol_HW = "{HW}"
		case symbol_HR = "{HR}"
		case symbol_W = "{W}"
		case symbol_U = "{U}"
		case symbol_B = "{B}"
		case symbol_R = "{R}"
		case symbol_G = "{G}"
		case symbol_C = "{C}"
		case symbol_S = "{S}"

		var image: UIImage {
			return UIImage(named: rawValue.replacingOccurrences(of: "/", with: "-"))!.withRenderingMode(.alwaysOriginal)
		}
	}
}

class MiniCardView: UIView {

	@IBOutlet var contentView: UIView!
	@IBOutlet var cardView: UIView!
	@IBOutlet weak var titleLabel: UILabel!
	@IBOutlet weak var powerToughnessLabel: UILabel!
	@IBOutlet weak var powerToughnessBox: UIView!
	@IBOutlet weak var artImageView: UIImageView!
	@IBOutlet weak var titleBox: UIView!
	@IBOutlet weak var bottomBox: UIView!
	@IBOutlet weak var cardTextLabel: UILabel!
	@IBOutlet weak var cardTextBox: UIView!
	@IBOutlet weak var oracleBox: UIView!
	@IBOutlet weak var tappedDarkeningView: UIView!
	@IBOutlet weak var costLabel: UILabel!
	@IBOutlet weak var typeLabel: UILabel!
	
	var card: Swiftfall.Card! {
		didSet {
			
			titleLabel.text = card.name
			
			updatePowerToughness()
			
			let colors = (card.colors ?? []).compactMap { Swiftfall.Color(rawValue: $0) }
			
			addGradient(to: titleBox, colors: colors, opacity: 1, type: \.boxBackgroundColor)
			addGradient(to: bottomBox, colors: colors, opacity: 1, type: \.boxBackgroundColor)
			addGradient(to: oracleBox, colors: colors, opacity: 0.75, type: \.textBackgroundColor)
			addGradient(to: cardView, colors: colors, opacity: 1, type: \.borderColor)
			addGradient(to: powerToughnessBox, colors: colors, opacity: 0.75, type: \.textBackgroundColor)
			
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
			
			if var oracleText = card.oracleText {
				oracleText = oracleText.replacingOccurrences(of: "\n", with: "\n\n")
				
				let attributedString = NSMutableAttributedString(string: oracleText, attributes: [.font: UIFont(name: "MPlantin", size: 24)])
				
				for symbol in Swiftfall.SymbolName.allCases {
					let attachment = NSTextAttachment()
					attachment.image = symbol.image
					attachment.setImageHeight(height: 20)
					let attachmentString = NSAttributedString(attachment: attachment)
					
					while let range = attributedString.string.range(of: symbol.rawValue) {
						attributedString.replaceCharacters(in: NSRange(range, in: attributedString.string), with: attachmentString)
					}
				}
				
				cardTextLabel.attributedText = attributedString
			}
			
			if let cost = card.manaCost {
				let cost = cost.replacingOccurrences(of: "}{", with: "} {")
				let attributedString = NSMutableAttributedString(string: cost, attributes: [.font: UIFont(name: "MPlantin", size: 24)])
				
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
			
		}
	}
	
	private func addGradient(to view: UIView, colors: [Swiftfall.Color], opacity: Float, type: KeyPath<Swiftfall.Color, UIColor>) {
		let backgroundColors: [UIColor] = {
			var colors = colors.map { $0[keyPath: type] }
			
			if colors.isEmpty {
				colors.insert(#colorLiteral(red: 1, green: 1, blue: 1, alpha: 1), at: 0)
			}
			
			return colors
		}()
		
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
			guard card.oracleText != nil else {
				oracleBox.alpha = 0
				return
			}
			
			oracleBox.alpha = newValue ? 0 : 1
		}
		get {
			oracleBox.alpha > 1
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
			costLabel.alpha > 1
		}
	}
	
	var isTypeLabelHidden: Bool {
		set {
			guard card.typeLine != nil else {
				typeLabel.alpha = 0
				return
			}
			
			typeLabel.alpha = newValue ? 0 : 1
		}
		get {
			typeLabel.alpha > 1
		}
	}
	
	var powerMod: Int = 0 {
		didSet {
			updatePowerToughness()
		}
	}
	
	var toughnessMod: Int = 0 {
		didSet {
			updatePowerToughness()
		}
	}
	
	private func updatePowerToughness() {
		if let power = card.power, let toughness = card.toughness {
			let numPower = (Int(power) ?? 0) + powerMod
			let numToughness = (Int(toughness) ?? 0) + toughnessMod
			
			let attributedString = NSMutableAttributedString()
			
			let powerString = NSAttributedString(string: "\(numPower)", attributes: [.foregroundColor: (powerMod == 0 ? UIColor.black : UIColor.blue).cgColor])
			attributedString.append(powerString)
			
			attributedString.append(NSAttributedString(string: "/"))
			
			let toughnessString = NSAttributedString(string: "\(numToughness)", attributes: [.foregroundColor: (toughnessMod == 0 ? UIColor.black : UIColor.blue).cgColor])
			attributedString.append(toughnessString)
			
			attributedString.addAttribute(.font, value: UIFont(name: "Matrix-Bold", size: 36.0), range: NSRange(location: 0, length: attributedString.length))
			
			powerToughnessLabel.attributedText = attributedString
		} else {
			powerToughnessLabel.isHidden = true
			powerToughnessBox.isHidden = true
		}
	}
	
	var isTapped: Bool = false {
		didSet {
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
	
	func reverse() {
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
		
		cardView.layer.cornerRadius = 8
		cardView.layer.masksToBounds = true
		
		powerToughnessBox.layer.cornerRadius = 6
		powerToughnessBox.layer.borderColor = UIColor.black.cgColor
		powerToughnessBox.layer.borderWidth = 4
		powerToughnessBox.layer.shadowOpacity = 0.3
		
		let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapUnTap))
		cardView.addGestureRecognizer(gestureRecognizer)
		
		let interaction = UIContextMenuInteraction(delegate: self)
		cardView.addInteraction(interaction)
		
	}
	
	@objc private func tapUnTap() {
		isTapped.toggle()
	}
	
	override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
		return cardView.hitTest(point, with: event)
	}

}

extension MiniCardView: UIContextMenuInteractionDelegate {
	func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
		return UIContextMenuConfiguration(identifier: nil, previewProvider: { () -> UIViewController? in
			
			guard let image = self.card.image(type: .normal) else { return nil }
			
			let vc = UIViewController()
			vc.view = UIImageView(image: image)
			vc.view.backgroundColor = .black
			vc.preferredContentSize = image.size
			return vc
		}, actionProvider: { _ in
			return UIMenu(title: "", children: self.actions())
		})
	}
	
	func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
		print("will end")
	}
	
	func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
		tapUnTap()
	}
	
	func actions() -> [UIMenuElement] {
		var actions: [UIMenuElement] = []
		
		let tapUntap = UIAction(title: isTapped ? "Untap" : "Tap") { [weak self] _ in
			self?.tapUnTap()
		}
		actions.append(tapUntap)
		
		let reverse = UIAction(title: "Reverse") { [weak self] _ in
			self?.reverse()
		}
		actions.append(reverse)
		
//		if card.power != nil {
//			var items: [UIMenuElement] = []
//
//			for (mod) in [+1, +2, -1, -2] {
//				var first = String(mod)
//				if !first.hasPrefix("-") {
//					first = "+" + first
//				}
//				let action = UIAction(title: "\(first)") { _ in
//					self.powerMod += mod
//				}
//				items.append(action)
//			}
//
//			let action = UIAction(title: "Restore") { _ in
//				self.powerMod = 0
//			}
//			items.append(action)
//
//			let menu = UIMenu(title: "Power", options: .displayInline, children: items)
//			actions.append(menu)
//		}
//
//		if card.toughness != nil {
//			var items: [UIMenuElement] = []
//
//			for (mod) in [+1, +2, -1, -2] {
//				var first = String(mod)
//				if !first.hasPrefix("-") {
//					first = "+" + first
//				}
//				let action = UIAction(title: "\(first)") { _ in
//					self.toughnessMod += mod
//				}
//				items.append(action)
//			}
//
//			let action = UIAction(title: "Restore") { _ in
//				self.toughnessMod = 0
//			}
//			items.append(action)
//
//			let menu = UIMenu(title: "Toughness", options: .displayInline, children: items)
//			actions.append(menu)
//		}
//
//		if card.power != nil && card.toughness != nil {
//			var items: [UIMenuElement] = []
//
//			for (mod) in [+1, +2, -1, -2] {
//				var first = String(mod)
//				if !first.hasPrefix("-") {
//					first = "+" + first
//				}
//				let action = UIAction(title: "\(first)/\(first)") { _ in
//					self.powerMod += mod
//					self.toughnessMod += mod
//				}
//				items.append(action)
//			}
//
//			let action = UIAction(title: "Restore") { _ in
//				self.powerMod = 0
//				self.toughnessMod = 0
//			}
//			items.append(action)
//
//			let menu = UIMenu(title: "Power/Toughness", options: .displayInline, children: items)
//			actions.append(menu)
//		}
		
		return actions
	}
	
	
}
