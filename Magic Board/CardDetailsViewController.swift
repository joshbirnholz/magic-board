//
//  CardDetailsViewController.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/15/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import CardService

class CardDetailsViewController: UITableViewController {
	
	private let bag = DisposeBag()
	
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
	
	@IBOutlet weak var titleCell: UIView!
	@IBOutlet weak var typeCell: UIView!
	@IBOutlet weak var textCell: UIView!
	@IBOutlet weak var bottomCell: UIView!
	
	@IBOutlet weak var watermarkImageView: UIImageView!
	@IBOutlet weak var nameLabel: UILabel!
	@IBOutlet weak var costLabel: UILabel!
	@IBOutlet weak var artImageView: UIImageView!
	@IBOutlet weak var typeLabel: UILabel!
	@IBOutlet weak var oracleTextLabel: UILabel!
	@IBOutlet weak var powerToughnessLoyaltyLabel: UILabel!
	@IBOutlet weak var artistLabel: UILabel!
	
	private lazy var bgView: UIView = {
		let v = UIView(frame: tableView.frame)
		tableView.insertSubview(v, at: 0)
		return v
	}()
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		tableView.contentInset.top -= 26
//		tableView.alwaysBounceVertical = false
		tableView.isScrollEnabled = false
		
		let interaction = UIDragInteraction(delegate: self)
		tableView.addInteraction(interaction)
		tableView.isUserInteractionEnabled = true
		
		if AppDelegate.shared.role.isBoard {
			let gesture = UITapGestureRecognizer(target: self, action: #selector(cardImageDoubleTapped(sender:)))
			//			gesture.numberOfTapsRequired = 2
			tableView.addGestureRecognizer(gesture)
		}
		
		updateCardImage()
	}
	
	@objc private func cardImageDoubleTapped(sender: Any) {
		UIView.animate(withDuration: 0.2) { [weak self] in
			guard let tableView = self?.tableView else { return }
			if tableView.transform == .identity {
				let transform = tableView.transform.rotated(by: .pi)
				tableView.transform = transform
			} else {
				tableView.transform = .identity
			}
		}
	}
	
	private func updateCardImage() {
		artImageView.image = nil
		
		guard let card = cardInstance?.representation else {
			return
		}
		
		if case .faceDown(_) = card {
			return
		}

		DispatchQueue.global(qos: .userInteractive).async {
			let image = card.image(type: .art)
			DispatchQueue.main.async { [weak self] in
				guard let self = self else { return }
				UIView.transition(with: self.artImageView,
				duration: 0.2,
				options: .transitionCrossDissolve,
				animations: {
					self.artImageView.image = image
				},
				completion: nil)
			}
		}
		
		nameLabel.text = card.name
		
		var text: [NSMutableAttributedString] = []
		let textFontSize: CGFloat = 17
		let textFont = UIFont(name: "MPlantin", size: textFontSize)!
		let italicFont = UIFont(name: "MPlantin-Italic", size: textFontSize)!
		if var oracleText = card.oracleText, !oracleText.isEmpty, !card.isBasicLand {
			oracleText = oracleText
				.replacingOccurrences(of: "\n", with: "\n\n")
				.replacingOccurrences(of: "−", with: "-")
				.replacingOccurrences(of: "}{", with: "} {")
			
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
		
		let boxText = text.reduce(into: NSMutableAttributedString(), { (string, current) in
			string.append(current)
		})
		
		if let artist = card.artist {
			artistLabel.text = "Illus. \(artist)"
		} else {
			artistLabel.text = nil
		}
		
//		let paragraphStyle = NSMutableParagraphStyle()
//		paragraphStyle.paragraphSpacing = 8
//		boxText.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: boxText.length))
		
		oracleTextLabel.attributedText = boxText
		
		if let cost = card.manaCost {
			let cost = cost//.replacingOccurrences(of: "}{", with: "} {")
			let attributedString = NSMutableAttributedString(string: cost, attributes: [.font: textFont])
			
			for symbol in MTGSymbolName.allCases {
				let attachment = NSTextAttachment()
				attachment.image = symbol.image
				attachment.setImageHeight(height: 16)
				let attachmentString = NSAttributedString(attachment: attachment)
				
				while let range = attributedString.string.range(of: symbol.rawValue) {
					attributedString.replaceCharacters(in: NSRange(range, in: attributedString.string), with: attachmentString)
				}
			}
			
			costLabel.attributedText = attributedString
		} else {
			costLabel.text = nil
		}
		
		costLabel.layer.shadowColor = UIColor.black.cgColor
		costLabel.layer.shadowRadius = 0.0
		costLabel.layer.shadowOpacity = 1.0
		costLabel.layer.shadowOffset = CGSize(width: -0.3, height: 1.4)
		
		typeLabel.text = card.typeLine
		powerToughnessLoyaltyLabel.text = [card.power, card.toughness, card.loyalty].compactMap { $0 }.joined(separator: "/")
		
//		tableView.backgroundColor = #colorLiteral(red: 0.1773691475, green: 0.5996922851, blue: 0.8219305277, alpha: 1).darkened(by: 0.2)
		addColors()
		
		if card.isBasicLand, let typeLine = card.typeLine, let landName = typeLine.components(separatedBy: " ").last, let color = MTGColor(landName: landName) {
			watermarkImageView.image = UIImage(named: landName) ?? #imageLiteral(resourceName: "Wastes")
			
			watermarkImageView.isHidden = false
		}
	}
	
	func addColors() {
		guard let card = cardInstance?.representation else { return }
		
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
		
				addGradient(to: textCell, colors: colors, opacity: 1, type: \.textBackgroundColor)
				
				if colors.count >= 3 && card.manaCost?.contains("/") == false && !card.isToken {
					colors = [.multicolor]
				}
		
		
				
				var didSetBoxes = false
				
				func setBoxes(colors: [MTGColor]) {
					if card.isToken {
						titleCell.backgroundColor = .black
						nameLabel.textColor = #colorLiteral(red: 0.9784926772, green: 0.8576988578, blue: 0.3988588452, alpha: 1)
						nameLabel.font = UIFont(name: "Beleren Small Caps", size: nameLabel.font.pointSize)
						nameLabel.textAlignment = .center
					} else if card.isEmblem {
						titleCell.backgroundColor = .black
						nameLabel.textColor = .white
						nameLabel.font = UIFont(name: "Beleren Small Caps", size: nameLabel.font.pointSize)
						nameLabel.textAlignment = .center
					} else {
						nameLabel.textColor = .black
						nameLabel.font = UIFont(name: "Beleren2016-Bold", size: nameLabel.font.pointSize)
						nameLabel.textAlignment = .natural
						addGradient(to: titleCell, colors: colors, opacity: 1, type: \.boxBackgroundColor)
					}
					
					addGradient(to: typeCell, colors: colors, opacity: 1, type: \.boxBackgroundColor)
					addGradient(to: bottomCell, colors: colors, opacity: 1, type: \.boxBackgroundColor)
					
//					addGradient(to: powerToughnessBox, colors: colors, opacity: 1, type: \.textBackgroundColor)
					didSetBoxes = true
				}
				
				if typeLine.contains("land") {
					setBoxes(colors: colors)
				}
				
//				addGradient(to: borderView, colors: colors, opacity: 1, type: \.borderColor)
				
				if colors != [.artifact] && (originalColors.isEmpty || originalColors == [.colorless]) {
					colors = [.colorless]
				} else if colors.count == 2 && card.manaCost?.contains("/") == false && !card.isToken {
					colors = [.multicolor]
				}
				
				if !didSetBoxes {
					setBoxes(colors: colors)
				}
				
				if typeLine.contains("artifact") {
					addGradient(to: bgView, colors: [.artifact], opacity: 1, type: \.cardEdgeColor)
//					edgeView.image = MTGColor.artifact.cardEdgeImage
				} else if typeLine.contains("land") {
//					edgeView.image = #imageLiteral(resourceName: "bg-land")
				} else {
//					edgeView.image = colors.first?.cardEdgeImage
					addGradient(to: bgView, colors: colors, opacity: 1, type: \.cardEdgeColor)
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
	
}

extension CardDetailsViewController: UIDragInteractionDelegate {
	var dragItem: UIDragItem? {
		guard let cardInstance = cardInstance else { return nil }
		let item = NSItemProvider(object: cardInstance)
		let dragItem = UIDragItem(itemProvider: item)
		dragItem.localObject = cardInstance
		dragItem.previewProvider = { [weak self] in
			let imageView = UIImageView(image: cardInstance.representation.image(type: .small) ?? #imageLiteral(resourceName: "mtg-card-back-png-1"))
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
		let cardInstances = session.items.compactMap { $0.localObject as? CardInstance }
		guard !cardInstances.contains(cardInstance) else { return [] }
		guard let dragItem = dragItem else { return [] }
		return [dragItem]
	}
}
