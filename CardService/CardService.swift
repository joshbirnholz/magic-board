//
//  CardService.swift
//  CardService
//
//  Created by Josh Birnholz on 3/9/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import SDWebImage

public struct CardService {
	
	private init() {
		if CardService.shouldInitializeCards {
			_ = CoreDataManager.shared
		}
	}
	
	public static var shouldInitializeCards: Bool = true
	
	public static let shared = CardService()
	
	public enum CardServiceError: Error {
		case cardNotFound
	}
	
	// MARK: Get Cards
	
	public func getCard(fuzzy: String) throws -> MTGCard {
		let scryfallCard = try Swiftfall.getCard(fuzzy: fuzzy)
		return MTGCard(scryfallCard)
	}
	
	public func getCard(name: String) throws -> MTGCard {
//		let scryfallCard = try Swiftfall.getCard(id: scryfallID.uuidString)
//		return MTGCard(scryfallCard)
		guard let card = CoreDataManager.shared.card(name: name) else {
			throw CardServiceError.cardNotFound
		}
		
		return try card.decodedMTGCard()
	}
	
	public func getCard(scryfallID: UUID) throws -> MTGCard {
//		let scryfallCard = try Swiftfall.getCard(id: scryfallID.uuidString)
//		return MTGCard(scryfallCard)
		guard let card = CoreDataManager.shared.card(scryfallID: scryfallID) else {
			throw CardServiceError.cardNotFound
		}
		
		return try card.decodedMTGCard()
	}
	
	public func getCollection(identifiers: [MTGCardIdentifier]) throws -> (cards: [MTGCard], notFound: [MTGCardIdentifier]) {
//		let list = try Swiftfall.getCollection(identifiers: identifiers)
//
//		let cards = list.data.map {
//			MTGCard($0)
//		}
//
//		return (cards: cards, notFound: list.notFound ?? [])
		
		var cards: [MTGCard] = []
		var notFound: [MTGCardIdentifier] = []
		
		for identifier in identifiers {
			switch identifier {
			case .id(let id):
				if let card = CoreDataManager.shared.card(scryfallID: id), let decoded = try? card.decodedMTGCard() {
					cards.append(decoded)
				} else {
					notFound.append(identifier)
				}
			case .mtgoID(_):
				notFound.append(identifier)
			case .multiverseID(_):
				notFound.append(identifier)
			case .oracleID(_):
				notFound.append(identifier)
			case .illustrationID(_):
				notFound.append(identifier)
			case .name(let name):
				if let card = CoreDataManager.shared.card(name: name), let decoded = try? card.decodedMTGCard() {
					cards.append(decoded)
				} else {
					notFound.append(identifier)
				}
			case .nameSet(let name, let set):
				if let card = CoreDataManager.shared.card(name: name, set: set), let decoded = try? card.decodedMTGCard() {
					cards.append(decoded)
				} else {
					notFound.append(identifier)
				}
			case .collectorNumberSet(let collectorNumber, let set):
				if let card = CoreDataManager.shared.card(set: set, collectorNumber: collectorNumber), let decoded = try? card.decodedMTGCard() {
					cards.append(decoded)
				} else {
					notFound.append(identifier)
				}
			}
		}
		
		return (cards, notFound)
	}
	
	public func getCard(code: String, number: String) throws -> MTGCard {
		let scryfallCard = try Swiftfall.getCard(code: code, number: number)
		return MTGCard(scryfallCard)
	}
	
	public func getRandomCard() throws -> MTGCard {
		let scryfallCard = try Swiftfall.getRandomCard()
		return MTGCard(scryfallCard)
	}
	
	// MARK: Cache Images
	
	public func cacheImagesIfNeeded(for card: MTGCard, types: Set<ImageType>) {
		var uris: [[String: URL]] = []
		
		if let cardURIs = card.imageUris {
			uris.append(cardURIs)
		}
		for face in card.cardFaces ?? [] {
			if let faceURIs = face.imageUris {
				uris.append(faceURIs)
			}
		}
		
		if CardService.shouldInitializeCards { // this is needed because the database shouldn't exist on the phone.
			for part in card.allParts ?? [] {
				guard let card = try? self.getCard(scryfallID: part.scryfallID) else { continue }
				if let partURIs = card.imageUris {
					uris.append(partURIs)
				}
				for face in card.cardFaces ?? [] {
					if let faceURIs = face.imageUris {
						uris.append(faceURIs)
					}
				}
			}
		}
		
		for uris in uris {
			for type in types {
				guard let url = uris[type.rawValue] else { continue }
				if !SDImageCache.shared.diskImageDataExists(withKey: url.absoluteString) {
					DispatchQueue.global(qos: .background).async {
						if let data = try? Data(contentsOf: url) {
							SDImageCache.shared.storeImageData(toDisk: data, forKey: url.absoluteString)
							print("Added image data from \(url) to cache")
						}
					}
				}
			}
		}
	}
	
}

fileprivate let dateFormatter: DateFormatter = {
	let formatter = DateFormatter()
	formatter.dateFormat = "yyyy-MM-dd"
	return formatter
}()

extension MTGCard {
	init(_ scryfallCard: Swiftfall.Card) {
		let faces = scryfallCard.cardFaces?.map { face in
			MTGCard.Face(typeLine: face.typeLine,
						 power: face.power,
						 toughness: face.toughness,
						 oracleText: face.oracleText,
						 flavorText: face.flavorText,
						 name: face.name,
						 loyalty: face.loyalty,
						 manaCost: face.manaCost,
						 colors: face.colors?.compactMap(MTGColor.init(rawValue:)),
						 imageUris: face.imageUris)
		}
		
		let relatedCards: [MTGCard.RelatedCard]? = scryfallCard.allParts?.compactMap { part in
			MTGCard.RelatedCard(scryfallID: part.id,
								component: part.component.flatMap(MTGCard.RelatedCard.Component.init(rawValue:)),
								name: part.name,
								typeLine: part.typeLine,
								url: URL(string: part.uri)!)
		}
		
		let date = dateFormatter.date(from: scryfallCard.releasedAt)
		
		self.init(scyfallID: scryfallCard.id,
				  typeLine: scryfallCard.typeLine,
				  power: scryfallCard.power,
				  toughness: scryfallCard.toughness,
				  oracleText: scryfallCard.oracleText?.typographized(language: "en", isHTML: false),
				  flavorText: scryfallCard.flavorText?.typographized(language: scryfallCard.lang.rawValue, isHTML: false),
				  name: scryfallCard.name,
				  loyalty: scryfallCard.loyalty,
				  cardFaces: faces,
				  convertedManaCost: scryfallCard.cmc,
				  layout: scryfallCard.layout,
				  manaCost: scryfallCard.manaCost,
				  scryfallURL: URL(string: scryfallCard.scryfallUri),
				  borderColor: BorderColor(rawValue: scryfallCard.borderColor),
				  isFullArt: scryfallCard.fullArt,
				  allParts: relatedCards,
				  collectorNumber: scryfallCard.collectorNumber,
				  set: scryfallCard.set,
				  colors: scryfallCard.colors?.compactMap(MTGColor.init(rawValue:)),
				  printedName: scryfallCard.printedName,
				  printedText: scryfallCard.printedText?.typographized(language: scryfallCard.lang.rawValue, isHTML: false),
				  printedTypeLine: scryfallCard.printedTypeLine,
				  artist: scryfallCard.artist,
				  isFoilAvailable: scryfallCard.foil,
				  isNonFoilAvailable: scryfallCard.nonfoil,
				  language: Language(rawValue: scryfallCard.lang.rawValue)!,
				  releaseDate: date,
				  imageUris: scryfallCard.imageUris?.compactMapValues(URL.init(string:)))
	}
}
