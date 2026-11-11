//
//  CardTableViewCell.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/13/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import UIKit
import RxSwift
import CardService

class CardTableViewCell: UITableViewCell {
	@IBOutlet weak var cardImageView: UIImageView! {
		didSet {
			cardImageView.layer.masksToBounds = true
			cardImageView.layer.cornerRadius = 4
		}
	}
	
	struct Content {
		var title: String?
		var cost: String?
		var type: String?
		var oracleText: String?
		var flavorText: String?
	}
	
	enum Face {
		case front
		case split
		case back
	}
	
	@IBOutlet weak var titleLabel: UILabel!
	@IBOutlet weak var costLabel: UILabel!
	@IBOutlet weak var typeLabel: UILabel!
	@IBOutlet weak var oracleLabel: UILabel!
	
	@IBOutlet weak var splitFaceTitleLabel: UILabel!
	@IBOutlet weak var splitFaceCostLabel: UILabel!
	@IBOutlet weak var splitFaceTypeLabel: UILabel!
	@IBOutlet weak var splitFaceOracleLabel: UILabel!
	
	@IBOutlet weak var fuseStackView: UIStackView!
	@IBOutlet weak var fuseLabel: UILabel!
	
	@IBOutlet weak var separator: UIView!
	@IBOutlet weak var splitFaceStackView: UIStackView!
	
	enum Layout {
		case `default`
		case split
	}
	
	var layout: Layout = .split {
		didSet {
			switch layout {
			case .default:
				separator.isHidden = true
				splitFaceStackView.isHidden = true
//				oracleLabel.font = UIFont(descriptor: oracleLabel.font.fontDescriptor, size: 14)
				setFuseLabelText(nil)
			case .split:
				separator.isHidden = false
				splitFaceStackView.isHidden = false
//				oracleLabel.font = UIFont(descriptor: oracleLabel.font.fontDescriptor, size: 13)
			}
		}
	}
	
	private func label(for keyPath: KeyPath<Content, String?>, face: Face) -> UILabel? {
		switch keyPath {
		case \.title:
			switch face {
			case .front: return titleLabel
			case .split: return splitFaceTitleLabel
			case .back: return nil
			}
		case \.cost:
			switch face {
			case .front: return costLabel
			case .split: return splitFaceCostLabel
			case .back: return nil
			}
		case \.type:
			switch face {
			case .front: return typeLabel
			case .split: return splitFaceTypeLabel
			case .back: return nil
			}
		case \.oracleText:
			switch face {
			case .front: return oracleLabel
			case .split: return splitFaceOracleLabel
			case .back: return nil
			}
		default:
			fatalError("This shouldn't happen!")
		}
	}
	
	func set(content: Content, for face: Face) {
		let titleLabel = label(for: \.title, face: face)
		titleLabel?.text = content.title
		
		if let cost = content.cost {
			let costLabel = label(for: \.cost, face: face)
			costLabel?.isHidden = false
			costLabel?.attributedText = attributedManaCost(cost)
		} else {
			let costLabel = label(for: \.cost, face: face)
			costLabel?.text = nil
			costLabel?.isHidden = true
		}
		
		var text: [NSMutableAttributedString] = []
		if let oracleText = content.oracleText {
			text.append(attributedOracleText(oracleText))
		}
		if let flavorText = content.flavorText {
			text.append(attributedFlavorText(flavorText))
		}
		
		for string in text.dropLast() {
			string.append(NSAttributedString(string: "\n\n"))
		}
		
		let bodyText = text.reduce(into: NSMutableAttributedString(), { (string, current) in
			string.append(current)
		})
		bodyText.addAttribute(.foregroundColor, value: detailColor, range: NSRange(location: 0, length: bodyText.string.count))
		let oracleLabel = label(for: \.oracleText, face: face)
		oracleLabel?.attributedText = bodyText
		
		if let type = content.type {
			let typeLabel = label(for: \.type, face: face)
			typeLabel?.isHidden = false
			typeLabel?.text = type
		} else {
			let typeLabel = label(for: \.type, face: face)
			typeLabel?.text = nil
			typeLabel?.isHidden = true
		}
	}
	
	func setFuseLabelText(_ text: String?) {
		if let text = text {
			fuseLabel.attributedText = attributedOracleText(text)
			fuseStackView.isHidden = false
		} else {
			fuseLabel.text = nil
			fuseStackView.isHidden = true
		}
	}
	
	private func attributedManaCost(_ cost: String) -> NSAttributedString {
		let cost = cost.replacingOccurrences(of: "}{", with: "} {")
		let attributedString = NSMutableAttributedString(string: cost)
		
		for symbol in MTGSymbolName.allCases {
			while let range = attributedString.string.range(of: symbol.rawValue) {
				let attachment = NSTextAttachment()
				attachment.image = symbol.image
				attachment.setImageHeight(height: 15)
				let attachmentString = NSAttributedString(attachment: attachment)
				attributedString.replaceCharacters(in: NSRange(range, in: attributedString.string), with: attachmentString)
			}
		}
		
		return attributedString
	}
	
	private let detailColor: UIColor = UIColor { (traits) -> UIColor in
		traits.userInterfaceStyle == .dark ? .secondaryLabel : .label
	}
	
	private func attributedOracleText(_ oracleText: String) -> NSMutableAttributedString {
		let oracleText = oracleText
			.replacingOccurrences(of: "\n", with: "\n\n")
			.replacingOccurrences(of: "−", with: "-")
			.replacingOccurrences(of: "}{", with: "} {")
		
		let defaultFont = UIFont.systemFont(ofSize: 14)
		let italicFont = UIFont(name: "MPlantin-Italic", size: 15)!
		
		let attributedString = NSMutableAttributedString(string: oracleText, attributes: [.foregroundColor: detailColor, .font: defaultFont])
		
		let matches = oracleText.matches(forRegex: #"(?:\((.*?)\)|^(.+) — )"#, options: .dotMatchesLineSeparators)
		for match in matches {
			let range = NSRange(match.fullMatch.range, in: oracleText)
			attributedString.addAttribute(.font, value: italicFont, range: range)
		}
		
		for symbol in MTGSymbolName.allCases {
			let attachment = NSTextAttachment()
			attachment.image = symbol.image
			attachment.setImageHeight(height: oracleLabel.font!.pointSize * 0.8)
			let attachmentString = NSAttributedString(attachment: attachment)
			
			while let range = attributedString.string.range(of: symbol.rawValue) {
				attributedString.replaceCharacters(in: NSRange(range, in: attributedString.string), with: attachmentString)
			}
		}
		
		return attributedString
	}
	
	func attributedFlavorText(_ flavorText: String) -> NSMutableAttributedString {
		let textFont = UIFont(name: "MPlantin", size: oracleLabel.font.pointSize+1)!
		let italicFont = UIFont(name: "MPlantin-Italic", size: oracleLabel.font.pointSize+1)!
		
		let attributedString = NSMutableAttributedString(string: flavorText, attributes: [.foregroundColor: detailColor, .font: italicFont])
		
		let matches = flavorText.matches(forRegex: "\\*([^*]+)\\*")
		for (fullMatch, groups) in matches {
			guard let group = groups.first else { continue }
			let range = NSRange(fullMatch.range, in: attributedString.string)
			attributedString.addAttribute(.font, value: textFont, range: range)
			// TODO: Remove the asterisks -- repalce the range of the full match in the attributed string with just the text of the capture group.
		}
		
		return attributedString
	}
	
	override func prepareForReuse() {
		super.prepareForReuse()
		
		cardImageView.image = nil
		titleLabel.text = nil
		costLabel.text = nil
		typeLabel.text = nil
		costLabel.isHidden = false
		oracleLabel.text = nil
	}
}
