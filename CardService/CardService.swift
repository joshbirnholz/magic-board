//
//  CardService.swift
//  CardService
//
//  Created by Josh Birnholz on 3/9/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import SDWebImage
import Network
// https://stackoverflow.com/questions/65816559/using-reachability-library-to-swiftui-based-app-to-notify-when-network-is-lost

class Monitor: ObservableObject {
  static let shared = Monitor()
  
  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "Monitor")

  /// A status indicating whether a path can be used by connections.
  @Published var isConnected: Bool = true
  /// A Boolean indicating whether the path uses an interface in Low Data Mode.
  @Published var isConstrained: Bool = false
  /// A Boolean indicating whether the path uses an interface that is considered expensive, such as Cellular or a Personal Hotspot.
  @Published var isExpensive: Bool = false

  private init() {
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self = self else { return }

      // Monitor runs on a background thread so we need to publish
      // on the main thread
      DispatchQueue.main.async {
        self.isConnected = path.status == .satisfied
        
        if path.status == .satisfied {
          print("We're connected!")
          self.isConnected = true

        } else {
          print("No connection.")
          self.isConnected = false
        }
        
        self.isConstrained = path.isConstrained
        self.isExpensive = path.isExpensive
      }
    }
    monitor.start(queue: queue)
  }
}


public struct CardService {
	
	private init() {
		if CardService.shouldInitializeCards {
			_ = CoreDataManager.shared
		}
	}
	
	public static var shouldInitializeCards: Bool = true
	
	public static let shared = CardService()

	/// The progress of the card database load currently running, or `nil` if none is.
	/// Main thread only. Observe `.cardServiceInitializationProgressDidChange` for updates.
	public var initializationProgress: CardLoadingProgress? {
		guard CardService.shouldInitializeCards else { return nil }
		return CoreDataManager.shared.currentProgress
	}

	public enum CardServiceError: Error {
		case cardNotFound
	}
	
	// MARK: Get Cards
	
	public func getCard(fuzzy: String) throws -> MTGCard {
    if Monitor.shared.isConnected {
      do {
        let scryfallCard = try Swiftfall.getCard(fuzzy: fuzzy)
        return MTGCard(scryfallCard)
      } catch {
        let scryfallCard = try Swiftfall.getCard(fuzzy: fuzzy, source: .custom)
        return MTGCard(scryfallCard)
      }
    } else {
      guard let card = CoreDataManager.shared.card(fuzzy: fuzzy) else {
        throw CardServiceError.cardNotFound
      }
      
      return card.decodedMTGCard()
    }
	}
	
	public func getCard(name: String) throws -> MTGCard {
    if Monitor.shared.isConnected {
      do {
        let scryfallCard = try Swiftfall.getCard(exact: name)
        return MTGCard(scryfallCard)
      } catch {
        do {
          let scryfallCard = try Swiftfall.getCard(exact: name, source: .custom)
          return MTGCard(scryfallCard)
        } catch {
          print(error)
          throw error
        }
      }
    } else {
      guard let card = CoreDataManager.shared.card(name: name) else {
        throw CardServiceError.cardNotFound
      }
      
      return card.decodedMTGCard()
    }
	}
	
	public func getCard(scryfallID: UUID) throws -> MTGCard {
    if Monitor.shared.isConnected {
      do {
        let scryfallCard = try Swiftfall.getCard(id: scryfallID.uuidString)
        return MTGCard(scryfallCard)
      } catch {
        let scryfallCard = try Swiftfall.getCard(id: scryfallID.uuidString, source: .custom)
        return MTGCard(scryfallCard)
      }
    } else {
      guard let card = CoreDataManager.shared.card(scryfallID: scryfallID) else {
        throw CardServiceError.cardNotFound
      }
      
      return card.decodedMTGCard()
    }
	}
	
	public func getCollection(identifiers: [MTGCardIdentifier]) throws -> (cards: [MTGCard], notFound: [MTGCardIdentifier]) {
    guard !Monitor.shared.isConnected else {
      let identifiers: [MTGCardIdentifier] = identifiers.map {
        switch $0 {
        case .name(let name):
          if let index = name.firstRange(of: " //")?.lowerBound {
            let name = String(name[..<index])
            return .name(name)
          } else {
            return $0
          }
        case .nameSet(let name, let set):
          if let index = name.firstRange(of: " //")?.lowerBound {
            let name = String(name[..<index])
            return .nameSet(name: name, set: set)
          } else {
            return $0
          }
        case .collectorNumberSet(let collectoNumber, let set, let name):
          if let name, let index = name.firstRange(of: " //")?.lowerBound {
            let name = String(name[..<index])
            return .collectorNumberSet(collectorNumber: collectoNumber, set: set, name: name)
          } else {
            return $0
          }
        default:
          return $0
        }
      }
      
      let chunks = identifiers.chunked(by: 75)
      let lists = try chunks.map { try Swiftfall.getCollection(identifiers: $0) }
      
      var cards = Array(lists.map { $0.data }.joined()).map(MTGCard.init)
      var notFound = Array(lists.compactMap { $0.notFound }.joined())
      
      if !notFound.isEmpty {
        let chunks = identifiers.chunked(by: 75)
        let lists = try chunks.map { try Swiftfall.getCollection(identifiers: $0, source: .custom) }
        cards.append(contentsOf: Array(lists.map { $0.data }.joined()).map(MTGCard.init))
        notFound = Array(lists.compactMap { $0.notFound }.joined())
      }
      
      return (cards: cards, notFound: notFound)
    }
    
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
      print("Fetching card for identifier \(identifier)")
      
			switch identifier {
      case .id(let id), .idName(let id, _):
				if let card = CoreDataManager.shared.card(scryfallID: id) {
					let decoded = card.decodedMTGCard()
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
				if let card = CoreDataManager.shared.card(name: name) {
					let decoded = card.decodedMTGCard()
					cards.append(decoded)
				} else {
					notFound.append(identifier)
				}
			case .nameSet(let name, let set):
				if let card = CoreDataManager.shared.card(name: name, set: set) {
					let decoded = card.decodedMTGCard()
					cards.append(decoded)
				} else {
					notFound.append(identifier)
				}
			case .collectorNumberSet(let collectorNumber, let set, _):
				if let card = CoreDataManager.shared.card(set: set, collectorNumber: collectorNumber) {
					let decoded = card.decodedMTGCard()
					cards.append(decoded)
				} else {
					notFound.append(identifier)
				}
			}
		}
		
		return (cards, notFound)
	}
	
	public func getCard(code: String, number: String) throws -> MTGCard {
    if Monitor.shared.isConnected {
      do {
        let scryfallCard = try Swiftfall.getCard(code: code, number: number)
        return MTGCard(scryfallCard)
      } catch {
        let scryfallCard = try Swiftfall.getCard(code: code, number: number, source: .custom)
        return MTGCard(scryfallCard)
      }
    } else {
      guard let card = CoreDataManager.shared.card(for: .collectorNumberSet(collectorNumber: number, set: code, name: nil))?.decodedMTGCard() else {
        throw CardServiceError.cardNotFound
      }
      return card
    }
	}
  
  public func getForetellCard() -> MTGCard {
    return .init(scryfallID: UUID(uuidString: "fb02637f-1385-4d3d-8dc0-de513db7633a")!, typeLine: "Card", power: nil, toughness: nil, oracleText: "(After you foretell a card, you can place the exiled card here. You may cast it on a later turn for its foretell cost.)", flavorText: nil, name: "Foretell", loyalty: nil, cardFaces: nil, convertedManaCost: 0, layout: "normal", manaCost: nil, scryfallURL: URL(string: "https://scryfall.com/card/tkhm/23/foretell?utm_source=api"), borderColor: .black, isFullArt: false, allParts: nil, collectorNumber: "23", set: "tkhm", colors: [], colorIndicator: nil, producedMana: nil, printedName: nil, printedText: nil, printedTypeLine: nil, flavorName: nil, artist: nil, rarity: .common, oracleID: UUID(uuidString: "ef221d59-b8d5-4e85-a7ec-dc1cbc3ac969")!, frame: "2015", keywords: nil, isPromo: false, isFoundInBoosters: false, isFoilAvailable: false, isNonFoilAvailable: true, language: .english, releaseDate: nil, watermark: nil, frameEffects: nil, securityStamp: nil, imageUris: [
      "small": URL(string: "https://cards.scryfall.io/small/front/f/b/fb02637f-1385-4d3d-8dc0-de513db7633a.jpg")!,
      "normal": URL(string: "https://cards.scryfall.io/normal/front/f/b/fb02637f-1385-4d3d-8dc0-de513db7633a.jpg")!,
      "large": URL(string: "https://cards.scryfall.io/large/front/f/b/fb02637f-1385-4d3d-8dc0-de513db7633a.jpg")!,
      "png": URL(string: "https://cards.scryfall.io/png/front/f/b/fb02637f-1385-4d3d-8dc0-de513db7633a.png")!,
      "art_crop": URL(string: "https://cards.scryfall.io/art_crop/front/f/b/fb02637f-1385-4d3d-8dc0-de513db7633a.jpg")!,
      "border_crop": URL(string: "https://cards.scryfall.io/border_crop/front/f/b/fb02637f-1385-4d3d-8dc0-de513db7633a.jpg")!
    ])
  }
  
  public func getMorphCard() -> MTGCard {
    return .init(scryfallID: UUID(uuidString: "e9375cbe-93c0-41a5-a6e3-fb4416f54a69")!, typeLine: "Card", power: "2", toughness: "2", oracleText: "(You can cover a face-down creature with this reminder card.\nA card with morph can be turned face up any time for its morph cost.)", flavorText: nil, name: "Morph", loyalty: nil, cardFaces: nil, convertedManaCost: 0, layout: "normal", manaCost: nil, scryfallURL: URL(string: "https://scryfall.com/card/tc19/27/morph?utm_source=api"), borderColor: .black, isFullArt: false, allParts: nil, collectorNumber: "27", set: "tc19", colors: [], colorIndicator: nil, producedMana: nil, printedName: nil, printedText: nil, printedTypeLine: nil, flavorName: nil, artist: nil, rarity: .common, oracleID: UUID(uuidString: "8f92f8d7-ec89-426f-86dc-fbc259eb5559")!, frame: "2015", keywords: nil, isPromo: false, isFoundInBoosters: false, isFoilAvailable: false, isNonFoilAvailable: true, language: .english, releaseDate: nil, watermark: nil, frameEffects: nil, securityStamp: nil, imageUris: [
      "small": URL(string: "https://cards.scryfall.io/small/front/e/9/e9375cbe-93c0-41a5-a6e3-fb4416f54a69.jpg")!,
      "normal": URL(string: "https://cards.scryfall.io/normal/front/e/9/e9375cbe-93c0-41a5-a6e3-fb4416f54a69.jpg")!,
      "large": URL(string: "https://cards.scryfall.io/large/front/e/9/e9375cbe-93c0-41a5-a6e3-fb4416f54a69.jpg")!,
      "png": URL(string: "https://cards.scryfall.io/png/front/e/9/e9375cbe-93c0-41a5-a6e3-fb4416f54a69.png")!,
      "art_crop": URL(string: "https://cards.scryfall.io/art_crop/front/e/9/e9375cbe-93c0-41a5-a6e3-fb4416f54a69.jpg")!,
      "border_crop": URL(string: "https://cards.scryfall.io/border_crop/front/e/9/e9375cbe-93c0-41a5-a6e3-fb4416f54a69.jpg")!
    ])
  }
  
  public func getManifestCard() -> MTGCard {
    return .init(scryfallID: UUID(uuidString: "56ae2eb8-5090-412a-ad72-46ec4861d599")!, typeLine: "Card", power: "2", toughness: "2", oracleText: "(You can cover a face-down manifested creature with this reminder card.\nA manifested creature card can be turned face up any time for its mana cost. A face-down card can also be turned face up for its morph cost.)", flavorText: nil, name: "Manifest", loyalty: nil, cardFaces: nil, convertedManaCost: 0, layout: "normal", manaCost: nil, scryfallURL: URL(string: "https://scryfall.com/card/tcmm/56/manifest?utm_source=api"), borderColor: .black, isFullArt: false, allParts: nil, collectorNumber: "56", set: "tcmm", colors: [], colorIndicator: nil, producedMana: nil, printedName: nil, printedText: nil, printedTypeLine: nil, flavorName: nil, artist: nil, rarity: .common, oracleID: UUID(uuidString: "f4f184ef-f456-47d8-9012-095629a5ea4d")!, frame: "2015", keywords: nil, isPromo: false, isFoundInBoosters: false, isFoilAvailable: false, isNonFoilAvailable: true, language: .english, releaseDate: nil, watermark: nil, frameEffects: nil, securityStamp: nil, imageUris: [
      "small": URL(string: "https://cards.scryfall.io/small/front/5/6/56ae2eb8-5090-412a-ad72-46ec4861d599.jpg")!,
      "normal": URL(string: "https://cards.scryfall.io/normal/front/5/6/56ae2eb8-5090-412a-ad72-46ec4861d599.jpg")!,
      "large": URL(string: "https://cards.scryfall.io/large/front/5/6/56ae2eb8-5090-412a-ad72-46ec4861d599.jpg")!,
      "png": URL(string: "https://cards.scryfall.io/png/front/5/6/56ae2eb8-5090-412a-ad72-46ec4861d599.png")!,
      "art_crop": URL(string: "https://cards.scryfall.io/art_crop/front/5/6/56ae2eb8-5090-412a-ad72-46ec4861d599.jpg")!,
      "border_crop": URL(string: "https://cards.scryfall.io/border_crop/front/5/6/56ae2eb8-5090-412a-ad72-46ec4861d599.jpg")!
    ])
  }
	
  public func getRandomCard(query: String? = nil) throws -> MTGCard {
    if Monitor.shared.isConnected {
      let scryfallCard = try Swiftfall.getRandomCard(query: query)
      return MTGCard(scryfallCard)
    } else {
      guard let card = CoreDataManager.shared.randomCard(query: query) else {
        throw CardServiceError.cardNotFound
      }
      return card.decodedMTGCard()
    }
	}
	
	public func getJumpstartDecklist() throws -> (decklist: String, packName: String) {
		guard let url = Bundle(for: CoreDataManager.self).urls(forResourcesWithExtension: "txt", subdirectory: nil)?.randomElement() else {
			throw PackError.unsupported
		}
		
		let decklist = try String(contentsOf: url)
		let name = String(url.lastPathComponent.prefix(while: { !$0.isNumber && $0 != "." }).trimmingCharacters(in: .whitespacesAndNewlines))
		
		return (decklist, name)
	}
  
  public func getDandanDecklist() throws -> String {
    guard let url = Bundle(for: CoreDataManager.self).url(forResource: "Dandan", withExtension: "txt") else {
      throw PackError.unsupported
    }
    
    return try String(contentsOf: url)
  }
	
	public func getRulings(oracleID: UUID) -> [MTGRuling] {
    if Monitor.shared.isConnected {
      do {
        let rulings = try Swiftfall.getRulingList(id: oracleID).data
        return rulings.map {
          MTGRuling(source: $0.source, publishedAt: $0.publishedAt, comment: $0.comment)
        }
      } catch {
        return []
      }
    } else {
      let rulings = CoreDataManager.shared.rulings(oracleID: oracleID)
      return rulings.map(\.mtgRuling)
    }
	}
	
	public func getMomirCard(convertedManaCost: Int, legality: String? = nil, set: String? = nil) throws -> MTGCard {
	//		let scryfallCard = try Swiftfall.getRandomCard()
	//		return MTGCard(scryfallCard)
		guard let card = CoreDataManager.shared.momirCard(convertedManaCost: convertedManaCost, legality: legality, set: set) else {
				throw CardServiceError.cardNotFound
			}
			return card.decodedMTGCard()
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
	
	public func updateDatabase() {
		CoreDataManager.shared.initialize()
	}
	
}

fileprivate let dateFormatter: DateFormatter = {
	let formatter = DateFormatter()
	formatter.dateFormat = "yyyy-MM-dd"
	return formatter
}()

extension MTGCard {
	init(_ scryfallCard: Swiftfall.Card) {
    let faces: [MTGCard.Face]? = scryfallCard.cardFaces?.map { face in
      return MTGCard.Face.init(
        typeLine: face.typeLine,
        power: face.power,
        toughness: face.toughness,
        oracleText: face.oracleText,
        flavorText: face.flavorText,
        printedText: face.printedText,
        printedTypeLine: face.printedTypeLine,
        printedName: face.printedName,
        name: face.name,
        loyalty: face.loyalty,
        manaCost: face.manaCost,
        colors: face.colors?.compactMap(MTGColor.init(rawValue:)),
        colorIndicator: face.colorIndicator?.compactMap(MTGColor.init(rawValue:)),
        watermark: face.watermark,
        artist: face.artist,
        imageUris: face.imageUris
      )
    }
		
		let relatedCards: [MTGCard.RelatedCard]? = scryfallCard.allParts?.compactMap { part in
			MTGCard.RelatedCard(scryfallID: part.id,
								component: RelatedCard.Component(rawValue: part.component),
								name: part.name,
								typeLine: part.typeLine,
								url: URL(string: part.uri)!)
		}
		
		let date = dateFormatter.date(from: scryfallCard.releasedAt)
		
		self.init(scryfallID: scryfallCard.id,
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
              colorIndicator: scryfallCard.colorIndicator?.compactMap(MTGColor.init(rawValue:)),
              producedMana: scryfallCard.producedMana?.compactMap(MTGColor.init(rawValue:)),
				  printedName: scryfallCard.printedName,
				  printedText: scryfallCard.printedText?.typographized(language: scryfallCard.lang.rawValue, isHTML: false),
          printedTypeLine: scryfallCard.printedTypeLine,
				  flavorName: scryfallCard.flavorName,
				  artist: scryfallCard.artist,
				  rarity: Rarity(rawValue: scryfallCard.rarity) ?? .common,
				  oracleID: scryfallCard.oracleId,
				  frame: scryfallCard.frame,
				  keywords: scryfallCard.keywords,
				  isPromo: scryfallCard.promo,
				  isFoundInBoosters: scryfallCard.booster,
				  isFoilAvailable: scryfallCard.foil,
				  isNonFoilAvailable: scryfallCard.nonfoil,
				  language: Language(rawValue: scryfallCard.lang.rawValue)!,
				  releaseDate: date,
				  watermark: scryfallCard.watermark,
          frameEffects: scryfallCard.frameEffects,
          securityStamp: scryfallCard.securityStamp,
				  imageUris: scryfallCard.imageUris)
	}
}
