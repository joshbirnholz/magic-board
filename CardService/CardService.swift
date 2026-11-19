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
import ReerJSON
import zlib
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
		ContentLoader.shared.currentProgress
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
    if let card = OfflineGameLibrary.shared.card(for: .name(name)) { return card }
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
	
	/// A token by name, preferring the token set that goes with `set` (Scryfall's "t" + set code).
	public func getToken(name: String, set: String?) throws -> MTGCard {
		if let set, !set.isEmpty, let card = try? Swiftfall.getCard(exact: name, set: "t" + set.lowercased()) { return MTGCard(card) }
		// Otherwise the newest token printing with that exact name (a plain name lookup can find a
		// double-faced token such as "Dinosaur // Treasure").
		let quoted = name.replacingOccurrences(of: "\"", with: "")
		if let token = Swiftfall.getCards(query: "!\"\(quoted)\" t:token", order: .released, dir: .descending).first??.data.first {
			return MTGCard(token)
		}
		return try getCard(name: name)
	}
	
	public func getCard(scryfallID: UUID) throws -> MTGCard {
    if let card = OfflineGameLibrary.shared.card(for: .id(scryfallID)) { return card }
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
    if let card = OfflineGameLibrary.shared.card(for: .collectorNumberSet(collectorNumber: number, set: code, name: nil)) { return card }
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
  
  /// The reminder card for a face-down creature that was cloaked or cast with disguise (MKM token 21).
  public func getMysteriousCreatureCard() -> MTGCard {
    let id = "241b3b6d-a25f-4a43-b5d6-1d1079e7e498"
    func url(_ kind: String, _ ext: String = "jpg") -> URL { URL(string: "https://cards.scryfall.io/\(kind)/front/2/4/\(id).\(ext)")! }
    return .init(scryfallID: UUID(uuidString: id)!, typeLine: "Creature", power: "2", toughness: "2", oracleText: "You can cover a face-down creature with this reminder card. A face-down creature that was cloaked or cast with disguise has ward {2}. (Whenever that creature becomes the target of a spell or ability an opponent controls, counter it unless that player pays {2}.)", flavorText: nil, name: "A Mysterious Creature", loyalty: nil, cardFaces: nil, convertedManaCost: 0, layout: "normal", manaCost: nil, scryfallURL: URL(string: "https://scryfall.com/card/tmkm/21/a-mysterious-creature"), borderColor: .black, isFullArt: false, allParts: nil, collectorNumber: "21", set: "tmkm", colors: [], colorIndicator: nil, producedMana: nil, printedName: nil, printedText: nil, printedTypeLine: nil, flavorName: nil, artist: nil, rarity: .common, oracleID: UUID(uuidString: "6481a124-6859-4f02-9fd3-b1302528dd2e")!, frame: "2015", keywords: ["Ward"], isPromo: false, isFoundInBoosters: false, isFoilAvailable: false, isNonFoilAvailable: true, language: .english, releaseDate: nil, watermark: nil, frameEffects: nil, securityStamp: nil, imageUris: [
      "small": url("small"), "normal": url("normal"), "large": url("large"), "png": url("png", "png"),
      "art_crop": url("art_crop"), "border_crop": url("border_crop")
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
	
	/// Bundled packets are available without the remote pack service.
	public func localJumpstartPackets() -> [(name: String, decklist: String)] {
		(Bundle(for: CoreDataManager.self).urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? [])
			.filter { $0.deletingPathExtension().lastPathComponent != "Dandan" }
			.compactMap { url in
				guard let list = try? String(contentsOf: url) else { return nil }
				return (url.deletingPathExtension().lastPathComponent, list)
			}.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
	}

	/// Local-first lookup for nearby games. Never makes a network request.
	public func localCard(for identifier: MTGCardIdentifier) -> MTGCard? {
        if let card = OfflineGameLibrary.shared.card(for: identifier) { return card }
		var result: MTGCard?
		CoreDataManager.shared.persistentContainer.viewContext.performAndWait {
			result = CoreDataManager.shared.card(for: identifier)?.decodedMTGCard()
		}
		return result
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
        CardService.shouldInitializeCards = true
		CoreDataManager.shared.initialize() // also queues the artwork step when images are missing
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
        imageUris: face.imageUris,
        flavorName: face.flavorName
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


/// Immutable card records shipped with the app (catalog.json), plus their artwork, which is
/// NOT bundled: it's downloaded once into Application Support (see `downloadMissingArtworkIfNeeded`)
/// and survives cache purges, so preloaded games work offline.
public final class OfflineGameLibrary {
    public static let shared = OfflineGameLibrary()
    public struct Entry: Decodable { public let key: String; public let count: Int }
    public struct Game: Decodable { public let name: String; public let kind: String; public let entries: [Entry]; public let setCode: String?; public let pack1: String?; public let pack2: String? }
    private struct Catalog: Decodable {
        let games: [Game]
        let cards: [String: Swiftfall.Card]
        let images: [String: String]
        let jumpInPackets: [JumpInPacket]?
        let frontCards: [String: [String: String]]?
        let jumpInBasics: [String: [String: [String]]]?
        let jumpInDuals: [String: [String: String]]?
        let oracleTags: [String: [UUID]]?
    }
    public let games: [Game]
    public let jumpInPacketPool: [JumpInPacket]
    private let records: [String: MTGCard]
    private let images: [String: String]
    /// JumpStart packet theme cards: set code -> theme name -> normal image URL (Scripts/add_front_cards.py).
    private let frontCards: [String: [String: String]]
    private let jumpInBasics: [String: [String: [String]]]
    /// Each Jump In set's common two-color lands: set code -> color pair ("UW") -> card key
    /// (Scripts/add_jumpin_duals.py). DMU's cycle is the fallback, as on the server.
    private let jumpInDuals: [String: [String: String]]
    /// Bundled Scryfall Tagger oracle tags (Scripts/add_oracle_tags.py): slug -> oracle IDs.
    public let bundledOracleTags: [String: [UUID]]
    private let directory: URL?
    /// Where downloaded artwork lives. Not a cache: iOS must not purge it.
    public static let artworkDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var url = base.appendingPathComponent("OfflineArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()
    private init() {
        directory = Bundle(for: OfflineGameLibrary.self).url(forResource: "OfflineGames", withExtension: nil)
        let decoder = ReerJSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let url = directory?.appendingPathComponent("catalog.json"),
           let data = try? Data(contentsOf: url), let catalog = try? decoder.decode(Catalog.self, from: data) {
            jumpInPacketPool = catalog.jumpInPackets ?? []
            games = catalog.games
            records = catalog.cards.mapValues { MTGCard($0) }
            images = catalog.images
            frontCards = catalog.frontCards ?? [:]
            jumpInBasics = catalog.jumpInBasics ?? [:]
            jumpInDuals = catalog.jumpInDuals ?? [:]
            bundledOracleTags = catalog.oracleTags ?? [:]
        } else { games = []; records = [:]; images = [:]; jumpInPacketPool = []; frontCards = [:]; jumpInBasics = [:]; jumpInDuals = [:]; bundledOracleTags = [:] }
    }
    public struct JumpInSlotCard: Decodable { public let name: String; public let probability: Double }
    public struct JumpInPacket: Decodable {
        public let name: String
        public let setCode: String
        public let colors: [String]
        public let randomSlots: [[JumpInSlotCard]]
        public let fixedCards: [String]
    }
    /// Offer distinct packet display names, excluding all names shown in the previous round.
    /// Repeated draws preserve Jump In's existing colour constraints.
    public func distinctPacketOffers(kind: String, set: String, first: String?, shown: [String] = []) -> [String] {
        let excluded = Set((shown + [first].compactMap { $0 }).map(Self.packetDisplayName))
        if kind != "Jump In" {
            var seen = excluded
            return Array(games.filter { $0.kind == kind && ($0.setCode ?? "JMP") == set.uppercased() }
                .map(\.name).shuffled().filter { seen.insert(Self.packetDisplayName($0)).inserted }.prefix(3))
        }
        var best: [String] = []
        for _ in 0..<40 {
            let draw = jumpInPackets(set: set, first: first, excludingNames: excluded)
            var seen = excluded
            let unique = draw.filter { seen.insert(Self.packetDisplayName($0)).inserted }
            if unique.count > best.count { best = unique }
            if best.count >= 3 { break }
        }
        // Cross-set variants can still share display names. Fill a short draw from the
        // remaining pool, preferring the fewest extra colors without repeating earlier offers.
        if best.count < 3 {
            let colors = Set(first.flatMap { jumpInPacket(set: set, choice: $0) }?.colors ?? [])
            let allSets = set.uppercased() == "ALL"
            let remaining = jumpInPacketPool.filter { allSets || $0.setCode == set.uppercased() }
                .shuffled().sorted { colors.union($0.colors).count < colors.union($1.colors).count }
            var seen = excluded.union(best.map(Self.packetDisplayName))
            for packet in remaining where best.count < 3 {
                let choice = allSets ? packet.setCode + " · " + packet.name : packet.name
                if seen.insert(Self.packetDisplayName(choice)).inserted { best.append(choice) }
            }
        }
        return Array(best.prefix(3))
    }

    public func packetColorNames(kind: String, set: String, name: String) -> String {
        let colors: [MTGColor]
        if kind == "Jump In", let packet = jumpInPacket(set: set, choice: name) {
            colors = packet.colors.compactMap(MTGColor.init(rawValue:))
        } else if let game = games.first(where: { $0.setCode == set.uppercased() && ($0.name == name || $0.name == set.uppercased() + " · " + name) }) {
            colors = Array(Set(game.entries.compactMap { records[$0.key] }.flatMap { $0.colors ?? [] }))
        } else { colors = [] }
        return colors.isEmpty ? "Colorless" : colors.ordered.map { $0.name.capitalized }.joined(separator: " · ")
    }
    /// The packet's JumpStart front card image (downloaded file if present, else remote), or nil
    /// when the set has no front cards (Jump In, SuperJump): those picks stay a mystery.
    public func packetFrontCardURL(kind: String, set: String, name: String) -> URL? {
        func normalized(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
        guard kind != "Jump In",
              let game = games.first(where: { $0.kind == kind && ($0.name == name || $0.name.hasSuffix(" · " + name)) })
                ?? games.first(where: { $0.setCode == set.uppercased() && ($0.name == name || $0.name == set.uppercased() + " · " + name) }),
              let themes = game.setCode.flatMap({ frontCards[$0] }) else { return nil }
        let key = normalized(Self.packetDisplayName(game.name.components(separatedBy: " · ").last ?? game.name))
        let match = themes.first { normalized($0.key) == key } ?? themes.first { normalized($0.key).hasPrefix(key) }
        guard let remote = match.flatMap({ URL(string: $0.value) }) else { return nil }
        return artworkURL(for: remote) ?? remote
    }

    /// "Vampires 4" -> "Vampires" (variant numbers aren't shown in packet pickers).
    public static func packetDisplayName(_ name: String) -> String {
        // Only the theme: no set prefix ("SuperJump · Zombies" → "Zombies") and no variant number.
        let theme = name.components(separatedBy: " · ").last ?? name
        return theme.replacingOccurrences(of: #"\s+\d+$"#, with: "", options: .regularExpression)
    }

    /// The packet's colors as mana symbols, e.g. "{W}{U}"; "{C}" when colorless.
    public func packetColorSymbols(kind: String, set: String, name: String) -> String {
        let colors: [MTGColor]
        if kind == "Jump In", let packet = jumpInPacket(set: set, choice: name) {
            colors = packet.colors.compactMap(MTGColor.init(rawValue:))
        } else if let game = games.first(where: { $0.kind == kind && ($0.name == name || $0.name.hasSuffix(" · " + name)) })
                    ?? games.first(where: { $0.setCode == set.uppercased() && ($0.name == name || $0.name == set.uppercased() + " · " + name) }) {
            colors = Array(Set(game.entries.compactMap { records[$0.key] }.flatMap { $0.colors ?? [] }))
        } else { colors = [] }
        let mana = colors.ordered.filter { ["W", "U", "B", "R", "G"].contains($0.rawValue) }
        return mana.isEmpty ? "{C}" : mana.map { "{\($0.rawValue)}" }.joined()
    }
    private func card(named name: String) -> MTGCard? {
        records.first { $0.key.components(separatedBy: "|").first == name.lowercased() }?.value
    }
    public var jumpInSets: [String] { Array(Set(jumpInPacketPool.map(\.setCode))).sorted() }
    public var jumpInSetOptions: [String] { jumpInSets.isEmpty ? [] : ["ALL"] + jumpInSets }
    /// All-set choices carry their set code so identically named packets remain distinct.
    public func jumpInPacket(set: String, choice: String) -> JumpInPacket? {
        jumpInPacketPool.first {
            set.uppercased() == "ALL" ? $0.setCode + " · " + $0.name == choice
                : $0.setCode == set.uppercased() && $0.name == choice
        }
    }
    /// Same color constraints as the packet server, sampling without replacement.
    public func jumpInPackets(set: String, first: String?, excludingNames: Set<String> = []) -> [String] {
        let allSets = set.uppercased() == "ALL"
        func choice(_ packet: JumpInPacket) -> String { allSets ? packet.setCode + " · " + packet.name : packet.name }
        let eligible = jumpInPacketPool.filter {
            (allSets || $0.setCode == set.uppercased()) && choice($0) != first
                && !excludingNames.contains(Self.packetDisplayName(choice($0)))
        }
        var remaining = eligible
        let chosen = first.flatMap { jumpInPacket(set: set, choice: $0) }
        var result: [JumpInPacket] = []
        func take(_ predicate: (JumpInPacket) -> Bool) -> JumpInPacket? {
            guard let index = remaining.indices.filter({ predicate(remaining[$0]) }).randomElement() else { return nil }
            return remaining.remove(at: index)
        }
        if let chosen, chosen.colors.count == 1 {
            if let mono = take({ $0.colors.count == 1 }) { result.append(mono) }
            if let multi = take({ $0.colors.count > 1 && $0.colors.contains(chosen.colors[0]) }) { result.append(multi) }
            if let other = take({ $0.colors.count == 1 || $0.colors.contains(chosen.colors[0]) }) { result.append(other) }
        } else if let chosen, chosen.colors.count == 2 {
            for color in chosen.colors { if let mono = take({ $0.colors == [color] }) { result.append(mono) } }
            if let other = take({ $0.colors.count == 1 || Set($0.colors) == Set(chosen.colors) || ($0.colors.count == 3 && Set(chosen.colors).isSubset(of: Set($0.colors))) }) { result.append(other) }
        } else if let chosen, chosen.colors.count == 3 {
            if let mono = take({ $0.colors.count == 1 && chosen.colors.contains($0.colors[0]) }) { result.append(mono) }
            if let mono = take({ $0.colors.count == 1 && chosen.colors.contains($0.colors[0]) && $0.colors != result.first?.colors }) { result.append(mono) }
            if let other = take({ $0.colors.count == 1 || Set($0.colors).isSubset(of: Set(chosen.colors)) }) { result.append(other) }
        } else {
            if let mono = take({ $0.colors.count == 1 }) { result.append(mono) }
            if let multi = take({ $0.colors.count > 1 && Set($0.colors) != Set(result.first?.colors ?? []) }) { result.append(multi) }
            if let other = take({ candidate in !result.contains { Set($0.colors) == Set(candidate.colors) } }) { result.append(other) }
        }
        // A small set may lack one of the preferred color categories.
        while result.count < min(3, eligible.count), let next = take({ _ in true }) { result.append(next) }
        return result.shuffled().map(choice)
    }
    /// One printing per basic-land illustration, preferring the set's non-full-art cards.
    public func jumpInBasicPrintings(set: String, name: String) -> [MTGCard] {
        (jumpInBasics[set.uppercased()]?[name] ?? []).compactMap { records[$0] }
    }

    /// The common dual for a color pair: the packets' own set's land (a packet sharing more of the
    /// pair's colors wins in cross-set decks), else DMU's, as the server's Jump In decks do.
    public func jumpInDual(for pair: Set<String>, sets packets: [JumpInPacket]) -> MTGCard? {
        let key = String("WUBRG".filter { pair.contains(String($0)) })
        let ranked = packets.enumerated()
            .sorted { lhs, rhs in
                let l = pair.intersection(lhs.element.colors).count, r = pair.intersection(rhs.element.colors).count
                return l != r ? l > r : lhs.offset < rhs.offset
            }
            .map { $0.element.setCode.uppercased() }
        for code in ranked + ["DMU"] {
            if let cardKey = jumpInDuals[code]?[key], let card = records[cardKey] { return card }
        }
        return nil
    }

    public func jumpInDeck(set: String, first: String, second: String) -> String? {
        guard first != second, let a = jumpInPacket(set: set, choice: first),
              let b = jumpInPacket(set: set, choice: second) else { return nil }
        var deck: [MTGCard] = []
        let basicNames: Set<String> = ["Plains", "Island", "Swamp", "Mountain", "Forest"]
        var basicCounts: [String: [String: Int]] = [:]
        for packet in [a, b] {
            var names = packet.fixedCards
            for slot in packet.randomSlots {
                let total = slot.reduce(0) { $0 + $1.probability }
                guard total > 0 else { return nil }
                var pick = Double.random(in: 0..<total)
                for option in slot {
                    pick -= option.probability
                    if pick < 0 { names.append(option.name); break }
                }
            }
            for name in names {
                guard let card = card(for: .nameSet(name: name, set: packet.setCode)) ?? card(for: .name(name)) else { return nil }
                deck.append(card)
                if basicNames.contains(name) { basicCounts[packet.setCode, default: [:]][name, default: 0] += 1 }
            }
        }
        let ca = Set(a.colors), cb = Set(b.colors), colors = ca.union(cb).sorted()
        var duals: [Set<String>: Int] = [:]
        func addDuals(_ colors: Set<String>) {
            let c = colors.sorted()
            for i in c.indices { for j in c.indices where j > i { duals[Set([c[i],c[j]]), default: 0] += c.count == 2 ? 2 : 1 } }
        }
        if ca.count == 1 && cb.count == 1 && ca != cb { addDuals(ca.union(cb)) }
        for c in [ca, cb] where c.count > 1 { addDuals(c) }
        if ca.count == 1 && cb.count == 2 && ca.isDisjoint(with: cb) { for c in cb { duals[ca.union([c]), default: 0] += 1 } }
        if cb.count == 1 && ca.count == 2 && cb.isDisjoint(with: ca) { for c in ca { duals[cb.union([c]), default: 0] += 1 } }
        let fixing = games.first { $0.kind == "Mana fixing" }?.entries.compactMap { card(forKey: $0.key) } ?? []
        for (pair, count) in duals.sorted(by: { $0.key.sorted().joined() < $1.key.sorted().joined() }) {
            let land = jumpInDual(for: pair, sets: [a, b]) ?? fixing.first { $0.name == "Evolving Wilds" }
            if let land { for _ in 0..<min(count, max(0,40-deck.count)) { deck.append(land) } }
        }
        var weights: [String: Int] = [:]
        for card in deck {
            for text in [card.manaCost ?? "", card.oracleText ?? ""] {
                for symbol in text.components(separatedBy: CharacterSet(charactersIn: "{}")) where colors.contains(symbol) { weights[symbol, default: 0] += 1 }
            }
        }
        let basics = ["W":"Plains", "U":"Island", "B":"Swamp", "R":"Mountain", "G":"Forest"]
        let slots = max(0,40-deck.count), total = max(1,weights.values.reduce(0,+))
        var allocations = Dictionary(uniqueKeysWithValues: colors.map { ($0, Int((Double(weights[$0,default: 0])/Double(total)*Double(slots)).rounded())) })
        if colors.count == 2 { for c in colors { allocations[c] = max(5,allocations[c,default: 0]) } }
        while allocations.values.reduce(0,+) > slots {
            guard let c = colors.max(by: { allocations[$0,default: 0] < allocations[$1,default: 0] }) else { return nil }
            allocations[c,default: 0] -= 1
        }
        var index = 0
        while allocations.values.reduce(0,+) < slots {
            guard !colors.isEmpty else { return nil }
            allocations[colors[index % colors.count],default: 0] += 1; index += 1
        }
        for color in colors {
            guard let name = basics[color] else { return nil }
            // In All Sets, a color uses only the sets of packets that actually contain it.
            let sets = Array(Set([a, b].filter { $0.colors.contains(color) }.map(\.setCode))).sorted()
            guard !sets.isEmpty else { return nil }
            for index in 0..<allocations[color, default: 0] { basicCounts[sets[index % sets.count], default: [:]][name, default: 0] += 1 }
        }
        // Some packet definitions already include basics. Redistribute those too, so art
        // balance applies to the complete deck rather than just the generated filler lands.
        deck.removeAll { basicNames.contains($0.name ?? "") }
        for (code, names) in basicCounts.sorted(by: { $0.key < $1.key }) {
            for (name, count) in names.sorted(by: { $0.key < $1.key }) {
                let arts = jumpInBasicPrintings(set: code, name: name).shuffled()
                guard !arts.isEmpty else { return nil }
                for index in 0..<count { deck.append(arts[index % arts.count]) }
            }
        }
        guard deck.count == 40 else { return nil }
        return deck.compactMap { card in card.name.map { "1 \($0) (\(card.set)) \(card.collectorNumber)" } }.joined(separator: "\n")
    }
    public var jumpStartSets: [(code: String, name: String)] {
        [("JMP","JumpStart (2020)"),("J22","JumpStart 2022"),("J25","Foundations JumpStart"),("TLA","Avatar: The Last Airbender JumpStart"),("MSH","Marvel Super Heroes JumpStart"),("SJM","SuperJump")]
            .filter { set in games.contains { $0.kind == "JumpStart" && ($0.setCode ?? "JMP") == set.0 } }
    }
    public func jumpStartOffers(set: String, excluding: String? = nil) -> [String] {
        Array(games.filter { $0.kind == "JumpStart" && ($0.setCode ?? "JMP") == set && $0.name != excluding }.shuffled().prefix(3)).map(\.name)
    }
    public func jumpStartDeck(first: String, second: String) -> String? {
        guard let a = games.first(where: { $0.kind == "JumpStart" && $0.name == first }),
              let b = games.first(where: { $0.kind == "JumpStart" && $0.name == second }) else { return nil }
        return (a.entries+b.entries).compactMap { entry in
            guard let card = card(forKey: entry.key), let name = card.name else { return nil }
            return "\(entry.count) \(name) (\(card.set)) \(card.collectorNumber)"
        }.joined(separator: "\n")
    }
    public func card(forKey key: String) -> MTGCard? { records[key] }
    public func card(for identifier: MTGCardIdentifier) -> MTGCard? {
        switch identifier {
        case .id(let id), .idName(let id, _): return records.values.first { $0.scryfallID == id }
        case .name(let name): return records.first { $0.key.components(separatedBy: "|").first == name.lowercased() }?.value ?? records.values.first { $0.name?.lowercased() == name.lowercased() }
        case .nameSet(let name, let set):
            return records[name.lowercased() + "|" + set.lowercased() + "|"] ?? records.values.first { $0.name?.lowercased() == name.lowercased() && $0.set.lowercased() == set.lowercased() }
        case .collectorNumberSet(let number, let set, let name):
            if let name, let card = records[name.lowercased() + "|" + set.lowercased() + "|" + number] { return card }
            return records.values.first { $0.collectorNumber == number && $0.set.lowercased() == set.lowercased() }
        default: return nil
        }
    }
    public func artworkURL(for remoteURL: URL) -> URL? {
        guard let name = images[remoteURL.absoluteString] else { return nil }
        let file = Self.artworkDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }
    /// How many of the card's normal/art-crop images are downloaded and available offline.
    public func artworkCount(for card: MTGCard) -> Int {
        [ImageType.normal, .art].filter { card.imageURL(type: $0)?.isFileURL == true }.count
    }
    /// How many of the card's normal/art-crop images the catalog knows how to provide offline.
    public func catalogArtworkCount(for card: MTGCard) -> Int {
        [ImageType.normal, .art].filter { type in
            guard let url = card.imageURL(type: type) else { return false }
            let remote = url.isFileURL ? nil : url.absoluteString
            return url.isFileURL || remote.map { images[$0] != nil } == true
        }.count
    }

    // MARK: - Artwork download

    /// One remote source per local file. Several catalog URLs (small/large/png) share the normal
    /// image's file; download each file from the URL whose path matches its kind.
    public lazy var artworkSources: [(file: String, url: URL)] = {
        var sources: [String: URL] = [:]
        for (remote, file) in images {
            guard let url = URL(string: remote) else { continue }
            let kind = file.contains("-art_crop-") ? "art_crop" : "normal"
            if url.pathComponents.dropFirst().first == kind || sources[file] == nil { sources[file] = url }
        }
        return sources.map { ($0.key, $0.value) }.sorted { $0.file < $1.file }
    }()

    public func missingArtwork() -> [(file: String, url: URL)] {
        artworkSources.filter { !FileManager.default.fileExists(atPath: Self.artworkDirectory.appendingPathComponent($0.file).path) }
    }

    public struct ArtworkDownloadError: LocalizedError {
        public let failed: Int
        public var errorDescription: String? { "\(failed) card images couldn't be downloaded. They'll be retried next launch." }
    }

    private var artworkStepQueued = false

    /// Queues the "Downloading artwork" step of the content-loading process when any catalog image
    /// is missing. Main thread only. Safe to call repeatedly.
    public func downloadMissingArtworkIfNeeded() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !artworkStepQueued, !images.isEmpty else { return }
        artworkStepQueued = true
        ContentLoader.shared.enqueue { [self] report in
            defer { DispatchQueue.main.async { self.artworkStepQueued = false } }
            let missing = missingArtwork()
            guard !missing.isEmpty else { return }
            try downloadArtwork(missing, report: report)
        }
    }

    /// Synchronous; runs on the loader's queue with a few parallel requests.
    private func downloadArtwork(_ items: [(file: String, url: URL)], report: @escaping (CardLoadingProgress) -> Void) throws {
        let total = items.count
        let lock = NSLock()
        var done = 0, failed = 0, consecutiveFailures = 0
        let slots = DispatchSemaphore(value: 6)
        let group = DispatchGroup()
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        func label(_ n: Int) -> String { formatter.string(from: NSNumber(value: n)) ?? String(n) }
        report(CardLoadingProgress(fractionCompleted: 0, message: "Downloading artwork…"))
        for item in items {
            lock.lock(); let offline = consecutiveFailures >= 25; lock.unlock()
            if offline { break } // no connection: stop early and retry next launch
            slots.wait(); group.enter()
            URLSession.shared.downloadTask(with: item.url) { temporary, response, _ in
                var ok = false
                if let temporary, (response as? HTTPURLResponse)?.statusCode == 200 {
                    let target = Self.artworkDirectory.appendingPathComponent(item.file)
                    try? FileManager.default.removeItem(at: target)
                    ok = (try? FileManager.default.moveItem(at: temporary, to: target)) != nil
                }
                lock.lock()
                done += 1
                if ok { consecutiveFailures = 0 } else { failed += 1; consecutiveFailures += 1 }
                let n = done
                lock.unlock()
                report(CardLoadingProgress(fractionCompleted: Double(n) / Double(total),
                                           message: "Downloading artwork… \(label(n)) of \(label(total))"))
                slots.signal(); group.leave()
            }.resume()
        }
        group.wait()
        let notAttempted = total - done
        if failed + notAttempted > 0 { throw ArtworkDownloadError(failed: failed + notAttempted) }
    }
}


// MARK: - Scryfall Tagger oracle tags

/// Cards with selected Scryfall Tagger oracle tags (each tag including its descendant tags), used
/// to handle things automatically, e.g. `tapland` cards enter the battlefield tapped.
///
/// Built at runtime from Scryfall's `oracle_tags` bulk data (data.scryfall.io, not rate-limited)
/// and kept current: at most once a day it checks when Scryfall last updated that file, and
/// rebuilds the lists only when it changed, so newly tagged cards are recognized without an app
/// update. The copy bundled in the offline catalog only covers a first launch with no connection.
public final class OracleTags {
    public static let shared = OracleTags()
    /// Keep in sync with TRACKED in Scripts/add_oracle_tags.py.
    public static let tracked = ["tapland"]

    /// `updated`: when this device last checked; `source`: Scryfall's `updated_at` for the file it was built from.
    private struct Stored: Codable { var updated: Date; var source: String?; var tags: [String: [UUID]] }
    private let lock = NSLock()
    private var tags: [String: Set<UUID>]
    private var refreshing = false
    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("OracleTags.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            tags = stored.tags.mapValues(Set.init)
        } else {
            tags = OfflineGameLibrary.shared.bundledOracleTags.mapValues(Set.init)
        }
    }

    /// Whether the card with this oracle ID has the tag (or one of its descendant tags).
    public func has(_ slug: String, oracleID: UUID?) -> Bool {
        guard let oracleID else { return false }
        lock.lock(); defer { lock.unlock() }
        return tags[slug]?.contains(oracleID) == true
    }

    /// Checks Scryfall (at most once a day, in the background) and rebuilds the lists when its tag
    /// file has changed since they were built, or when this device has never built them.
    public func refreshIfNeeded() {
        let stored = (try? Data(contentsOf: Self.fileURL)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        if let stored, Date().timeIntervalSince(stored.updated) < 24 * 3600 { return }
        lock.lock()
        guard !refreshing else { lock.unlock(); return }
        refreshing = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { lock.lock(); refreshing = false; lock.unlock() }
            guard let entry = try? Self.bulkEntry() else { return }
            if let stored, stored.source == entry.updatedAt {
                // Unchanged on Scryfall: just note the check.
                var checked = stored; checked.updated = Date()
                if let data = try? JSONEncoder().encode(checked) { try? data.write(to: Self.fileURL, options: .atomic) }
                return
            }
            guard let fresh = try? Self.download(entry.url) else { return }
            lock.lock(); tags = fresh.mapValues(Set.init); lock.unlock()
            if let data = try? JSONEncoder().encode(Stored(updated: Date(), source: entry.updatedAt, tags: fresh)) {
                try? data.write(to: Self.fileURL, options: .atomic)
            }
        }
    }

    /// The `oracle_tags` file's download URL and when Scryfall last updated it (a small request).
    private static func bulkEntry() throws -> (url: URL, updatedAt: String) {
        struct Bulk: Decodable { struct Entry: Decodable { let type: String; let updated_at: String?; let jsonl_download_uri: URL? }; let data: [Entry] }
        let bulk = try JSONDecoder().decode(Bulk.self, from: fetch(URL(string: "https://api.scryfall.com/bulk-data")!))
        guard let entry = bulk.data.first(where: { $0.type == "oracle_tags" }), let url = entry.jsonl_download_uri else { throw URLError(.badServerResponse) }
        return (url, entry.updated_at ?? url.lastPathComponent)
    }

    private static func fetch(_ url: URL) throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.setValue("MagicBoard/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(URLError(.unknown))
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data, (response as? HTTPURLResponse)?.statusCode == 200 { result = .success(data) }
            else { result = .failure(error ?? URLError(.badServerResponse)) }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try result.get()
    }

    /// Downloads the bulk file and collects the tracked tags (with their descendants) in two passes
    /// over its lines, so only the tracked tags' oracle IDs are kept in memory.
    private static func download(_ url: URL) throws -> [String: [UUID]] {
        let raw = try fetch(url)
        let text = try gunzip(raw)
        let lines = text.split(separator: UInt8(ascii: "\n"))
        // Pass 1: the tag hierarchy.
        var slugs: [String: String] = [:], children: [String: [String]] = [:]
        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = object["id"] as? String, let slug = object["slug"] as? String else { continue }
            slugs[slug] = id
            children[id] = object["child_ids"] as? [String] ?? []
        }
        var wanted: [String: String] = [:] // tag id -> tracked slug
        for slug in tracked {
            guard let root = slugs[slug] else { continue }
            var stack = [root]
            while let id = stack.popLast() {
                guard wanted[id] == nil else { continue }
                wanted[id] = slug
                stack += children[id] ?? []
            }
        }
        // Pass 2: the oracle IDs of the wanted tags.
        var result: [String: Set<UUID>] = [:]
        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = object["id"] as? String, let slug = wanted[id],
                  let taggings = object["taggings"] as? [[String: Any]] else { continue }
            for tagging in taggings {
                if let oracle = (tagging["oracle_id"] as? String).flatMap(UUID.init(uuidString:)) { result[slug, default: []].insert(oracle) }
            }
        }
        guard !result.isEmpty else { throw URLError(.cannotParseResponse) }
        return result.mapValues { Array($0) }
    }

    private static func gunzip(_ data: Data) throws -> Data {
        guard data.starts(with: [0x1f, 0x8b]) else { return data } // already decompressed
        var stream = z_stream()
        guard inflateInit2_(&stream, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw URLError(.cannotDecodeRawData) }
        defer { inflateEnd(&stream) }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 256 * 1024)
        var status = Z_OK
        try data.withUnsafeBytes { raw in
            stream.next_in = UnsafeMutablePointer(mutating: raw.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(data.count)
            repeat {
                try buffer.withUnsafeMutableBufferPointer { out in
                    stream.next_out = out.baseAddress
                    stream.avail_out = uInt(out.count)
                    status = inflate(&stream, Z_NO_FLUSH)
                    guard status == Z_OK || status == Z_STREAM_END else { throw URLError(.cannotDecodeRawData) }
                    output.append(out.baseAddress!, count: out.count - Int(stream.avail_out))
                }
            } while status != Z_STREAM_END
        }
        return output
    }
}
