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
	
	private static var morphCard: MTGCard = {
    return CardService.shared.getMorphCard()
	}()
	
	private static var manifestCard: MTGCard = {
    return CardService.shared.getManifestCard()
	}()
	
	private static var foretellCard: MTGCard = {
    return CardService.shared.getForetellCard()
	}()
	
	case card(MTGCard)
	case tokenCopy(CardRepresentation)
	case alternateFace(MTGCard, MTGCard.Face)
	case faceDown(CardRepresentation)
	case morph(MTGCard)
	case manifest(MTGCard)
	case foretold(MTGCard)
  case prototyped(MTGCard)
	//			case appearingAsCopy(original: RepresentedCard, copying: Represented)
	
	private struct AltFace: Codable {
		var card: MTGCard
		var face: MTGCard.Face
	}
  
  // Returns true if the card is any kind of face down (face down, morph, manifest, foretold)
  var isFaceDown: Bool {
    if case .faceDown(_) = self {
      return true
    } else if case .morph(_) = self {
      return true
    } else if case .manifest(_) = self {
      return true
    } else if case .foretold(_) = self {
      return true
    }
    return false
  }
  
  private struct Commander: Codable {
    var card: CardRepresentation
    var tax: Int
  }
	
	private enum CodingKeys: String, CodingKey {
		case card
		case tokenCopy
		case alternateFace
		case faceDown
		case morph
		case manifest
		case foretold
    case prototyped
    case commander
	}
	
	var card: MTGCard {
		switch self {
		case .card(let card), .alternateFace(let card, _):
			return card
		case .tokenCopy(let card):
			return card.card
		case .faceDown(let card):
			return card.card
		case .morph(let card), .manifest(let card), .foretold(let card):
			return card
    case .prototyped(let card):
      return card
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
		case .morph(let card):
			try container.encode(card, forKey: .morph)
		case .manifest(let card):
			try container.encode(card, forKey: .manifest)
		case .foretold(let card):
			try container.encode(card, forKey: .foretold)
    case .prototyped(let card):
      try container.encode(card, forKey: .prototyped)
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
		} else if let card = try container.decodeIfPresent(MTGCard.self, forKey: .morph) {
			self = .morph(card)
		} else if let card = try container.decodeIfPresent(MTGCard.self, forKey: .foretold) {
      self = .foretold(card)
    } else if let card = try container.decodeIfPresent(MTGCard.self, forKey: .prototyped) {
      self = .prototyped(card)
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
		case .faceDown(_), .foretold(_):
			return nil
		case .morph(_), .manifest(_):
			return "2"
    case .prototyped(let card):
      return card.prototype?.power ?? card.power
		default:
			return card.power
		}
	}
	
	var toughness: String? {
		switch self {
		case .alternateFace(_, let face):
			return face.toughness
		case .faceDown(_), .foretold(_):
			return nil
		case .morph(_), .manifest(_):
			return "2"
    case .prototyped(let card):
      return card.prototype?.toughness ?? card.toughness
		default:
			return card.toughness
		}
	}
	
	var typeLine: String? {
		switch self {
		case .tokenCopy(let card):
      guard let typeLine = card.card.printedTypeLine ?? card.typeLine else { return "Token" }
			if typeLine.lowercased().contains("token") {
				return typeLine
			} else {
				return "Token \(typeLine)"
			}
		case .alternateFace(_, let face):
      return face.printedTypeLine ?? face.typeLine
		case .card(let card):
      return card.printedTypeLine ?? card.typeLine
		case .faceDown(_):
			return nil
		case .morph(_):
			return CardRepresentation.morphCard.typeLine
		case .manifest(_):
			return CardRepresentation.manifestCard.typeLine
		case .foretold(_):
			return CardRepresentation.foretellCard.typeLine
    case .prototyped(let card):
      return card.printedTypeLine ?? card.typeLine
		}
	}
	
	var oracleText: String? {
		switch self {
		case .alternateFace(_, let face):
      return face.printedText ?? face.oracleText
		case .card(let card):
      return card.printedText ?? card.oracleText
		case .tokenCopy(let card):
      return card.card.printedText ?? card.oracleText
		case .faceDown(_):
			return nil
		case .morph(_):
			return CardRepresentation.morphCard.oracleText
		case .manifest(_):
			return CardRepresentation.manifestCard.oracleText
		case .foretold(_):
			return CardRepresentation.foretellCard.oracleText
    case .prototyped(let card):
      return card.printedText ?? card.oracleText
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
		case .morph(_):
			return nil
		case .manifest(_):
			return nil
		case .foretold(_):
			return nil
    case .prototyped(let card):
      return card.loyalty
		}
	}
	
	var name: String? {
		switch self {
		case .alternateFace(_, let face):
      return face.printedName ?? face.name
		case .card(let card):
      return card.printedName ?? card.name
		case .tokenCopy(let card):
      return card.card.printedName ?? card.name
		case .faceDown(_):
			return nil
		case .morph(_):
			return CardRepresentation.morphCard.name
		case .manifest(_):
			return CardRepresentation.manifestCard.name
		case .foretold(_):
			return CardRepresentation.foretellCard.name
    case .prototyped(let card):
      return card.printedName ?? card.name
		}
	}
	
	var id: UUID? {
		switch self {
		case .alternateFace(let card, _):
			return card.scryfallID
		case .card(let card):
			return card.scryfallID
		case .tokenCopy(let card):
			return card.card.scryfallID
		case .faceDown(_):
			return nil
		case .morph(_):
			return CardRepresentation.morphCard.scryfallID
		case .manifest(_):
			return CardRepresentation.manifestCard.scryfallID
		case .foretold(_):
			return CardRepresentation.foretellCard.scryfallID
    case .prototyped(let card):
      return card.scryfallID
		}
	}
	
	var borderColor: MTGCard.BorderColor {
		switch self {
		case .alternateFace(let card, _):
			return card.borderColor ?? .black
		case .card(let card):
			return card.borderColor ?? .black
		case .tokenCopy(let card):
			return card.card.borderColor ?? .black
		case .faceDown(_):
			return .black
		case .morph(_):
			return CardRepresentation.morphCard.borderColor ?? .black
		case .manifest(_):
			return CardRepresentation.manifestCard.borderColor ?? .black
		case .foretold(_):
			return CardRepresentation.foretellCard.borderColor ?? .black
    case .prototyped(let card):
      return card.borderColor ?? .black
		}
	}
	
	var keywords: [String] {
		switch self {
		case .card(let card):
			return card.keywords ?? []
		case .alternateFace(let card, _):
			return card.keywords ?? []
		case .faceDown(_), .morph(_), .manifest(_), .foretold(_):
			return []
		case .tokenCopy(let representation):
			return representation.keywords
    case .prototyped(let card):
      return card.keywords ?? []
		}
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
		case .morph(_):
			return CardRepresentation.morphCard.convertedManaCost
		case .manifest(_):
			return CardRepresentation.manifestCard.convertedManaCost
		case .foretold(_):
			return CardRepresentation.foretellCard.convertedManaCost
    case .prototyped(let card):
      return card.prototype?.cmc ?? card.convertedManaCost
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
    case .prototyped(let card):
      return card.image(type: type, alwaysUpright: alwaysUpright)
		case .tokenCopy(let card):
			return card.image(type: type, alwaysUpright: alwaysUpright)
		case .faceDown(_):
			return nil
		case .morph(_):
			return CardRepresentation.morphCard.image(type: type, alwaysUpright: alwaysUpright)
		case .manifest(_):
			return CardRepresentation.manifestCard.image(type: type, alwaysUpright: alwaysUpright)
		case .foretold(_):
			if case .art = type {
				return UIImage(named: "foretellart")
			} else {
				return CardRepresentation.foretellCard.image(type: type, alwaysUpright: alwaysUpright)
			}
		}
	}
	
	var fullArt: Bool {
		switch self {
		case .faceDown(_), .morph(_), .manifest(_), .foretold(_):
			return false
		default:
			return card.isFullArt
		}
	}
	
	var isLand: Bool {
		switch self {
		case .faceDown(_), .morph(_), .manifest(_), .foretold(_):
			return false
		case .alternateFace(_, let face):
			return face.typeLine?.lowercased().contains("land") == true
		default:
			return card.isLand
		}
	}
	
	var isBasicLand: Bool {
		switch self {
		case .faceDown(_), .morph(_), .manifest(_), .foretold(_):
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
		case .faceDown(_), .morph(_), .manifest(_), .foretold(_):
			return nil
		default:
			return card.flavorText
		}
	}
	
	var manaCost: String? {
		switch self {
		case .faceDown(_):
			return nil
		case .morph(_):
			return CardRepresentation.morphCard.manaCost
		case .manifest(_):
			return CardRepresentation.manifestCard.manaCost
		case .foretold(_):
			return CardRepresentation.foretellCard.manaCost
    case .prototyped(let card):
      return card.prototype?.manaCost
		case .alternateFace(_, let face):
			return face.manaCost
		default:
			return card.manaCost
		}
	}
	
	var watermark: String? {
		switch self {
		case .faceDown(_), .morph(_), .foretold(_):
			return nil
		case .alternateFace(_, let face):
			return face.watermark
		default:
			return card.watermark
		}
	}
	
	var artist: String? {
		switch self {
		case .faceDown(_):
			return nil
		case .morph(_):
			return CardRepresentation.morphCard.artist
		case .manifest(_):
			return CardRepresentation.manifestCard.artist
		case .foretold(_):
			return CardRepresentation.foretellCard.artist
		case .alternateFace(let card, let face):
			return face.artist ?? card.artist
		case .tokenCopy(let representation):
			return representation.artist
		default:
			return card.artist
		}
	}
	
	var colorIndicator: [MTGColor]? {
		switch self {
		case .faceDown(_), .morph(_), .manifest(_), .foretold(_):
			return nil
		case .alternateFace(_, let face):
			return face.colorIndicator
		case .tokenCopy(let card):
			return card.colorIndicator
		default:
			return card.colorIndicator
		}
	}
	
	var colors: [MTGColor]? {
		switch self {
		case .faceDown(_), .foretold(_):
			return nil
		case .morph(_):
			return CardRepresentation.morphCard.colors
		case .manifest(_):
			return CardRepresentation.manifestCard.colors
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
    case .prototyped(let card):
      return card.prototype?.colors ?? card.colors
		default:
			return card.colors?.ordered
		}
	}
	
	var scryfallUri: URL? {
		switch self {
		case .faceDown(_):
			return nil
		case .morph(_):
			return CardRepresentation.morphCard.scryfallURL
		case .manifest(_):
			return CardRepresentation.manifestCard.scryfallURL
		case .foretold(_):
			return CardRepresentation.foretellCard.scryfallURL
		default:
			return card.scryfallURL
		}
	}
	
	var isToken: Bool {
		switch self {
		case .faceDown(_):
			return false
		case .morph(_):
			return false
		case .manifest(_):
			return false
		case .tokenCopy(_):
			return true
		case _ where card.layout.contains("token") || card.typeLine?.lowercased().contains("token") == true:
			return true
		default:
			return false
		}
	}
	
	var isEmblem: Bool {
		switch self {
		case .faceDown(_), .morph(_), .manifest(_), .foretold(_):
			return false
		case _ where card.layout == "emblem":
			return true
		default:
			return false
		}
	}
	
	var isFoil: Bool {
		switch self {
		case .faceDown(_), .morph(_), .manifest(_), .foretold(_):
			return false
		default:
			return !card.isNonFoilAvailable
		}
	}
	
	var frameEffects: [String]? {
		switch self {
		case .faceDown(_):
			return nil
		case .morph(_):
			return CardRepresentation.morphCard.frameEffects
		case .manifest(_):
			return CardRepresentation.manifestCard.frameEffects
		case .foretold(_):
			return CardRepresentation.foretellCard.frameEffects
		case .card(let card), .alternateFace(let card, _):
      var effects = card.frameEffects
      
      if card.typeLine?.contains("Omen") == true {
        if effects == nil {
          effects = ["omen"]
        } else {
          effects?.append("omen")
        }
      }
      
			return effects
		case .tokenCopy(let representation):
			return representation.frameEffects
    case .prototyped(let card):
      return card.frameEffects
		}
	}
	
	var layout: String {
		switch self {
		case .faceDown(_):
			return "facedown"
		case .morph(_):
			return "morph"
		case .card(let card), .alternateFace(let card, _):
			return card.layout
		case .tokenCopy(let representation):
			return representation.layout
		case .manifest(_):
			return "manifest"
		case .foretold(_):
			return "foretell"
    case .prototyped(_):
      return "prototype"
		}
	}
	
	var flavorName: String? {
		switch self {
		case .faceDown(_), .morph(_), .manifest(_), .foretold(_):
			return nil
		case .card(let card), .alternateFace(let card, _):
			return card.flavorName
		case .tokenCopy(let representation):
			return representation.flavorName
    case .prototyped(let card):
      return card.flavorName
		}
	}
}

extension MTGCard {
  struct PrototypeParts {
    var manaCost: String
    var power: String
    var toughness: String
    var colors: [MTGColor]
    var cmc: Double
  }
  
  var prototype: PrototypeParts? {
    if let matches = oracleText?.matches(forRegex: #"Prototype (.+) — ([0-9]+)\/([0-9]+)"#).first?.groups, matches.count == 3 {
      let manaCost = matches[0].value
      let power = matches[1].value
      let toughness = matches[2].value
      
      let colors: [MTGColor] = OrderedSet(manaCost.compactMap { MTGColor(rawValue: String($0)) }).contents
      
      let cmc = manaCost.matches(forRegex: "[^{}]+").map(\.fullMatch.value).reduce(0) { partialResult, current in
        var partialResult = partialResult
        
        if let num = Int(current) {
          partialResult += num
        } else if current.count == 1 {
          partialResult += 1
        }
        return partialResult
      }
      
      return .init(
        manaCost: manaCost,
        power: power,
        toughness: toughness,
        colors: colors,
        cmc: Double(cmc)
      )
    }
    return nil
  }
}
