//
//  RepresentedCard.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/14/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import CardService
import UIKit

indirect enum CardRepresentation: Codable, Equatable, Hashable {
	case card(MTGCard)
	case tokenCopy(CardRepresentation)
	case alternateFace(MTGCard, MTGCard.Face)
	case faceDown(CardRepresentation)
	//			case appearingAsCopy(original: RepresentedCard, copying: Represented)
	
	private struct AltFace: Codable {
		var card: MTGCard
		var face: MTGCard.Face
	}
	
	private enum CodingKeys: String, CodingKey {
		case card
		case tokenCopy
		case alternateFace
		case faceDown
	}
	
	var card: MTGCard {
		switch self {
		case .card(let card), .alternateFace(let card, _):
			return card
		case .tokenCopy(let card):
			return card.card
		case .faceDown(let card):
			return card.card
		}
	}
	
	// MARK: Codable
	
	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		
		switch self {
		case .card(let card):
			try container.encode(card, forKey: .card)
		case .tokenCopy(let card):
			try container.encode(card, forKey: .tokenCopy)
		case .alternateFace(let card, let face):
			try container.encode(AltFace(card: card, face: face), forKey: .alternateFace)
		case .faceDown(let card):
			try container.encode(card, forKey: .faceDown)
		}
	}
	
	init(from decoder: Decoder) throws {
		if let container = try? decoder.singleValueContainer(), let card = try? container.decode(MTGCard.self) {
			self = .card(card)
			return
		}
		
		let container = try decoder.container(keyedBy: CodingKeys.self)
		
		if let card = try container.decodeIfPresent(MTGCard.self, forKey: .card) {
			self = .card(card)
		} else if let card = try container.decodeIfPresent(CardRepresentation.self, forKey: .tokenCopy) {
			self = .tokenCopy(card)
		} else if let altFace = try container.decodeIfPresent(AltFace.self, forKey: .alternateFace) {
			self = .alternateFace(altFace.card, altFace.face)
		} else if let card = try container.decodeIfPresent(CardRepresentation.self, forKey: .faceDown) {
			self = .faceDown(card)
		} else {
			let context = DecodingError.Context(codingPath: [], debugDescription: "Could not decode a card representable object")
			throw DecodingError.dataCorrupted(context)
		}
	}
	
	// MARK: Card Properties
	
	var power: String? {
		switch self {
		case .alternateFace(_, let face):
			return face.power
		case .faceDown(_):
			return nil
		default:
			return card.power
		}
	}
	
	var toughness: String? {
		switch self {
		case .alternateFace(_, let face):
			return face.toughness
		case .faceDown(_):
			return nil
		default:
			return card.toughness
		}
	}
	
	var typeLine: String? {
		switch self {
		case .tokenCopy(let card):
			guard let typeLine = card.typeLine else { return "Token" }
			if typeLine.lowercased().contains("token") {
				return typeLine
			} else {
				return "Token \(typeLine)"
			}
		case .alternateFace(_, let face):
			return face.typeLine
		case .card(let card):
			return card.typeLine
		case .faceDown(_):
			return nil
		}
	}
	
	var oracleText: String? {
		switch self {
		case .alternateFace(_, let face):
			return face.oracleText
		case .card(let card):
			return card.oracleText
		case .tokenCopy(let card):
			return card.oracleText
		case .faceDown(_):
			return nil
		}
	}
	
	var loyalty: String? {
		switch self {
		case .alternateFace(_, let face):
			return face.loyalty
		case .card(let card):
			return card.loyalty
		case .tokenCopy(let card):
			return card.loyalty
		case .faceDown(_):
			return nil
		}
	}
	
	var name: String? {
		switch self {
		case .alternateFace(_, let face):
			return face.name
		case .card(let card):
			return card.name
		case .tokenCopy(let card):
			return card.name
		case .faceDown(_):
			return nil
		}
	}
	
	var borderColor: MTGCard.BorderColor {
		return self.card.borderColor ?? .black
	}
	
	var convertedManaCost: Double? {
		switch self {
		case .alternateFace(let card, _):
			return card.convertedManaCost
		case .card(let card):
			return card.convertedManaCost
		case .tokenCopy(let card):
			return card.convertedManaCost
		case .faceDown(_):
			return nil
		}
	}
	
	var artist: String? {
		switch self {
		case .alternateFace(let card, _):
			return card.artist
		case .card(let card):
			return card.artist
		case .tokenCopy(let card):
			return card.artist
		case .faceDown(_):
			return nil
		}
	}
	
	//		var imageUris: [String: String]? {
	//			switch self {
	//			case .alternateFace(_, let face):
	//				return face.imageUris ?? card?.imageUris
	//			case .card(let card):
	//				return card.imageUris
	//			case .tokenCopy(let card):
	//				return card.imageUris
	//			case .faceDown(_):
	//				return nil
	//			}
	//		}
	
	func image(type: ImageType, alwaysUpright: Bool = false) -> UIImage? {
		switch self {
		case .alternateFace(let card, let face):
			return card.image(type: type, for: face, alwaysUpright: alwaysUpright)
		case .card(let card):
			return card.image(type: type, alwaysUpright: alwaysUpright)
		case .tokenCopy(let card):
			return card.image(type: type, alwaysUpright: alwaysUpright)
		case .faceDown(_):
			return nil
		}
	}
	
	var fullArt: Bool {
		switch self {
		case .faceDown(_):
			return false
		default:
			return card.isFullArt
		}
	}
	
	var isLand: Bool {
		switch self {
		case .faceDown(_):
			return false
		case .alternateFace(_, let face):
			return face.typeLine?.lowercased().contains("land") == true
		default:
			return card.isLand
		}
	}
	
	var isBasicLand: Bool {
		switch self {
		case .faceDown(_):
			return false
		case .alternateFace(_, let face):
			return (face.typeLine?.lowercased().contains("basic land") == true) || (face.typeLine?.lowercased().contains("basic snow land") == true)
		default:
			return card.isBasicLand
		}
	}
	
	var flavorText: String? {
		switch self {
		case .alternateFace(_, let face):
			return face.flavorText
		case .faceDown(_):
			return nil
		default:
			return card.flavorText
		}
	}
	
	var manaCost: String? {
		switch self {
		case .faceDown(_):
			return nil
		case .alternateFace(_, let face):
			return face.manaCost
		default:
			return card.manaCost
		}
	}
	
	var colors: [MTGColor]? {
		switch self {
		case .faceDown(_):
			return nil
		case .alternateFace(_, let face):
			if let colors = face.colors {
				return colors.ordered
			} else if let cost = face.manaCost {
				//					let regex = "\\{(.*?)\\}"
				//					let costColors = Array(OrderedSet(Array(cost.matches(forRegex: regex).compactMap { $0.groups.compactMap { Swiftfall.Color(rawValue: $0.value) } }.joined())))
				let costColors = cost.compactMap { MTGColor(rawValue: String($0)) }
				return costColors.uniques.ordered
			} else {
				return nil
			}
		case .tokenCopy(let card):
			return card.colors
		default:
			return card.colors?.ordered
		}
	}
	
	var scryfallUri: URL? {
		switch self {
		case .faceDown(_):
			return nil
		default:
			return card.scryfallURL
		}
	}
	
	var isToken: Bool {
		switch self {
		case .faceDown(_):
			return false
		case .tokenCopy(_):
			return true
		case _ where card.typeLine?.lowercased().contains("token") == true:
			return true
		default:
			return false
		}
	}
	
	var isEmblem: Bool {
		switch self {
		case .faceDown(_):
			return false
		case _ where card.layout == "emblem":
			return true
		default:
			return false
		}
	}
	
	var isFoil: Bool {
		switch self {
		case .faceDown(_):
			return false
		default:
			return !card.isNonFoilAvailable
		}
	}
}
