//
//  CoreDataManager.swift
//  CardService
//
//  Created by Josh Birnholz on 3/20/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import CoreData
import UIKit
import ReerJSON

/// All of these notifications are posted on the main thread.
public extension NSNotification.Name {
	static let cardServiceDidBeginInitialization = NSNotification.Name("com.josh.birnholz.Magic-Board.CardServiceDidBeginInitializationNotificationName")
	static let cardServiceDidEndInitialization = NSNotification.Name("com.josh.birnholz.Magic-Board.CardServiceDidEndInitializationNotificationName")
	/// The error encountered will be in the user info dictionary under the "error" key.
	static let cardServiceInitializationDidFail = NSNotification.Name("com.josh.birnholz.Magic-Board.CardServiceInitializationDidFailNotificationName")
	/// The current `CardLoadingProgress` will be in the user info dictionary under the "progress" key.
	static let cardServiceInitializationProgressDidChange = NSNotification.Name("com.josh.birnholz.Magic-Board.CardServiceInitializationProgressDidChangeNotificationName")
}

/// How far along loading the card database is.
public struct CardLoadingProgress {
	/// Overall progress from 0 to 1.
	public let fractionCompleted: Double
	/// A short description of the current step, suitable for display.
	public let message: String
}

extension Card {
	func decodedMTGCard() -> MTGCard {
		let cardFaces: [MTGCard.Face]? = faces?.compactMap { cardFace in
			guard let cardFace = cardFace as? CardFace else { return nil }
      return MTGCard.Face.init(
        typeLine: cardFace.typeLine,
        power: cardFace.power,
        toughness: cardFace.toughness,
        oracleText: cardFace.oracleText,
        flavorText: cardFace.flavorText,
        printedText: cardFace.printedText,
        printedTypeLine: cardFace.printedTypeLine,
        printedName: cardFace.printedName,
        name: cardFace.name,
        loyalty: cardFace.loyalty,
        manaCost: cardFace.manaCost,
        colors: cardFace.colors?.compactMap(MTGColor.init(rawValue:)),
        colorIndicator: cardFace.colorIndicator?.compactMap(MTGColor.init(rawValue:)),
        watermark: cardFace.watermark,
        artist: cardFace.artist,
        imageUris: cardFace.imageURIs
      )
		}
		
    let related: [MTGCard.RelatedCard]? = relatedCards?.compactMap { relatedCard in
			guard let relatedCard = relatedCard as? CardRelatedCard, let id = relatedCard.scryfallID else { return nil }
			return MTGCard.RelatedCard(scryfallID: id,
									   component: relatedCard.component.flatMap(MTGCard.RelatedCard.Component.init(rawValue:)),
									   name: relatedCard.name ?? "",
									   typeLine: relatedCard.typeLine ?? "",
									   url: relatedCard.url!)
		}
    return MTGCard.init(
      scryfallID: scryfallID ?? UUID(),
      typeLine: typeLine,
      power: power,
      toughness: toughness,
      oracleText: oracleText,
      flavorText: flavorText,
      name: name,
      loyalty: loyalty,
      cardFaces: cardFaces,
      convertedManaCost: convertedManaCost == -1 ? nil : convertedManaCost,
      layout: layout ?? "normal",
      manaCost: manaCost,
      scryfallURL: scryfallURL,
      borderColor: borderColor.flatMap(MTGCard.BorderColor.init(rawValue:)),
      isFullArt: isFullArt,
      allParts: related,
      collectorNumber: collectorNumber ?? "",
      set: set ?? "",
      colors: colors?.compactMap(MTGColor.init(rawValue:)),
      colorIndicator: colorIndicator?.compactMap(MTGColor.init(rawValue:)),
      producedMana: producedMana?.compactMap(MTGColor.init(rawValue:)),
      printedName: printedName,
      printedText: printedText,
      printedTypeLine: printedTypeLine,
      flavorName: flavorName,
      artist: artist,
      rarity: rarity.flatMap(MTGCard.Rarity.init(rawValue:)) ?? .common,
      oracleID: oracleID,
      frame: frame ?? "normal",
      keywords: keywords ?? [],
      isPromo: isPromo,
      isFoundInBoosters: isFoundInBoosters,
      isFoilAvailable: isFoilAvailable,
      isNonFoilAvailable: isNonFoilAvailable,
      language: language.flatMap(MTGCard.Language.init(rawValue:)) ?? .english,
      releaseDate: releaseDate,
      watermark: watermark,
      frameEffects: frameEffects,
      securityStamp: securityStamp,
      imageUris: imageURIs
    )
		
//		guard let data = mtgCard else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "No data saved in core data")) }
//		return try CoreDataManager.shared.decoder.decode(MTGCard.self, from: data)
	}
}

class CoreDataManager: NSObject {
	
	private override init() {
		super.init()
		
		let needsInitialization = CoreDataManager.needsInitialization
		
		func continuation() {
			if needsInitialization {
				print("No persistent store exists. Initializing")
				DispatchQueue.main.async {
					self.initialize()
				}
			}
		}
		
		persistentContainer.loadPersistentStores { storeDescription, error in
			if let error = error {
				let url: URL = {
					let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CardService.sqlite")
					return url
				}()
				
				do {
					if FileManager.default.fileExists(atPath: url.path) {
						try self.persistentContainer.persistentStoreCoordinator.destroyPersistentStore(at: url, ofType: "sqlite", options: nil)
						print("Destroyed store")
						
						self.persistentContainer.loadPersistentStores { storeDescription, error in
							if let error = error {
								fatalError("Unresolved error \(error), \((error as NSError).userInfo)")
							} else {
								continuation()
							}
						}
					}
				} catch let innerError {
					print(innerError)
					fatalError("Unresolved error \(error), \((error as NSError).userInfo)")
				}
			} else {
				continuation()
			}
		}
	}
	
	func clearDatabase() {
		privateContext.performAndWait {
			do {
				for entityName in ["Card", "CardFace", "CardRelatedCard", "Ruling"] {
					let deleteFetch = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
					let deleteRequest = NSBatchDeleteRequest(fetchRequest: deleteFetch)
					
					try privateContext.execute(deleteRequest)
					//				try persistentContainer.viewContext.execute(deleteRequest)
				}
			} catch {
				print("Error clearing database: \(error.localizedDescription)")
			}
		}
	}
	
	/// call before loadPersistentStores otherwise it will always return true.
	static var needsInitialization: Bool {
		let storeURL = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("CardService.sqlite")
		let storeExists = FileManager.default.fileExists(atPath: storeURL.path)
		return !storeExists
	}
	// MARK: - Initialization
	
	/// The progress of the current initialization, or `nil` if none is running. Main thread only.
	private(set) var currentProgress: CardLoadingProgress?
	
	/// Main thread only.
	private var isInitializing = false
	
	private let importQueue = DispatchQueue(label: "com.josh.birnholz.Magic-Board.CardImport", qos: .userInitiated)
	
	/// Downloads all cards and rulings from Scryfall and replaces the database with them.
	/// Returns immediately; the work happens on a background queue. Does nothing if already running.
	func initialize() {
		DispatchQueue.main.async {
			guard !self.isInitializing else { return }
			self.isInitializing = true
			// Create the lazy context on the main thread before the import queue touches it.
			_ = self.privateContext
			
			NotificationCenter.default.post(Notification(name: .cardServiceDidBeginInitialization))
			self.publish(CardLoadingProgress(fractionCompleted: 0, message: "Preparing card database…"))
			
			self.importQueue.async {
				self.runImport()
			}
		}
	}
	
	private func runImport() {
		let reporter = ProgressReporter { [weak self] progress in
			DispatchQueue.main.async { self?.publish(progress) }
		}
		
		do {
			print("Clearing database")
			clearDatabase()
			print("Cleared database")
			
			let startDate = Date()
			
			print("Loading bulk data list")
			let bulkData = try Swiftfall.getBulkData()
			
			guard let cardsObject = bulkData.first(.defaultCards) else { throw LoadingError.noBulkDataObject }
			
			print("Downloading cards, elapsed time: \(Date().timeIntervalSince(startDate)) sec")
			let cardCount = try privateContext.performAndWait {
				try cardsObject.forEachCard(progress: { reporter.report(cards: $0, $1) }) { scryfallCard in
					saveCard(scryfallCard: fix(scryfallCard))
				}
			}
			print("Saved \(cardCount) cards, elapsed time: \(Date().timeIntervalSince(startDate)) sec")
			
			if let rulingsObject = bulkData.first(.rulings) {
				print("Downloading rulings, elapsed time: \(Date().timeIntervalSince(startDate)) sec")
				let rulingCount = try privateContext.performAndWait {
					try rulingsObject.forEachRuling(progress: { reporter.report(rulings: $0, $1) }) { ruling in
						saveRuling(scryfallRuling: ruling)
					}
				}
				print("Saved \(rulingCount) rulings")
			}
			
			reporter.report(CardLoadingProgress(fractionCompleted: 1, message: "Saving card database…"), force: true)
			saveContext()
			
			print("Done, elapsed time: \(Date().timeIntervalSince(startDate)) sec")
			finishInitialization(error: nil)
		} catch {
			print(error)
			saveContext()
			finishInitialization(error: error)
		}
	}
	
	private func finishInitialization(error: Error?) {
		DispatchQueue.main.async {
			self.isInitializing = false
			self.currentProgress = nil
			if let error {
				NotificationCenter.default.post(Notification(name: .cardServiceInitializationDidFail, object: nil, userInfo: ["error": error]))
			} else {
				NotificationCenter.default.post(Notification(name: .cardServiceDidEndInitialization))
			}
		}
	}
	
	/// Main thread only.
	private func publish(_ progress: CardLoadingProgress) {
		guard isInitializing else { return }
		currentProgress = progress
		NotificationCenter.default.post(name: .cardServiceInitializationProgressDidChange, object: nil, userInfo: ["progress": progress])
	}
	
	/// Maps the stages of the bulk downloads onto one overall fraction, and throttles updates
	/// so the main thread isn't flooded. Safe to call from any thread.
	private final class ProgressReporter {
		private let lock = NSLock()
		private var lastReported: CardLoadingProgress?
		private let send: (CardLoadingProgress) -> Void
		
		init(send: @escaping (CardLoadingProgress) -> Void) {
			self.send = send
		}
		
		/// The cards file is much larger than the rulings file, so it gets most of the bar.
		func report(cards stage: Swiftfall.BulkData.Stage, _ fraction: Double) {
			switch stage {
			case .downloading:
				report(CardLoadingProgress(fractionCompleted: 0.30 * fraction, message: "Downloading cards…"))
			case .decompressing:
				report(CardLoadingProgress(fractionCompleted: 0.30 + 0.10 * fraction, message: "Unpacking cards…"))
			case .decoding:
				report(CardLoadingProgress(fractionCompleted: 0.40 + 0.50 * fraction, message: "Importing cards…"))
			}
		}
		
		func report(rulings stage: Swiftfall.BulkData.Stage, _ fraction: Double) {
			let stageFraction: Double
			switch stage {
			case .downloading: stageFraction = 0.4 * fraction
			case .decompressing: stageFraction = 0.4 + 0.1 * fraction
			case .decoding: stageFraction = 0.5 + 0.5 * fraction
			}
			report(CardLoadingProgress(fractionCompleted: 0.90 + 0.10 * stageFraction, message: "Loading rulings…"))
		}
		
		func report(_ progress: CardLoadingProgress, force: Bool = false) {
			lock.lock()
			defer { lock.unlock() }
			if !force, let last = lastReported, last.message == progress.message,
			   abs(progress.fractionCompleted - last.fractionCompleted) < 0.005 {
				return
			}
			lastReported = progress
			send(progress)
		}
	}
	
	static let shared = CoreDataManager()
	
	// MARK: - Loading
	
	enum LoadingError: Error {
		case noBulkDataObject
	}
	
	fileprivate let decoder = ReerJSONDecoder()
	private let encoder = JSONEncoder()
	
	
	let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()
	
	private func saveCard(scryfallCard: Swiftfall.Card) {
		let card = makeNewCard()
		
		card.artist = scryfallCard.artist
		card.borderColor = scryfallCard.borderColor
		card.collectorNumber = scryfallCard.collectorNumber
		card.colors = scryfallCard.colors
		card.colorIndicator = scryfallCard.colorIndicator
    card.producedMana = scryfallCard.producedMana
		card.convertedManaCost = scryfallCard.cmc ?? -1
		card.flavorName = scryfallCard.flavorName
		card.flavorText = scryfallCard.flavorText?.typographized(language: "en", isHTML: false)
		card.frameEffects = scryfallCard.frameEffects
		card.imageURIs = scryfallCard.imageUris
		card.isFoilAvailable = scryfallCard.foil
		card.isFullArt = scryfallCard.fullArt
		card.loyalty = scryfallCard.loyalty?.replacingOccurrences(of: "*", with: "★")
		card.isNonFoilAvailable = scryfallCard.nonfoil
		card.language = scryfallCard.lang.rawValue
		card.layout = scryfallCard.layout
		card.manaCost = scryfallCard.manaCost
		card.name = scryfallCard.name
		card.oracleText = scryfallCard.oracleText?.typographized(language: "en", isHTML: false)
		card.power = scryfallCard.power?.replacingOccurrences(of: "*", with: "★")
		card.printedName = scryfallCard.printedName
		card.printedText = scryfallCard.printedText?.typographized(language: "en", isHTML: false)
		card.printedTypeLine = scryfallCard.printedTypeLine
		card.releaseDate = dateFormatter.date(from: scryfallCard.releasedAt)
		card.scryfallID = scryfallCard.id
		card.scryfallURL = URL(string: scryfallCard.scryfallUri)
		card.set = scryfallCard.set
		card.setType = scryfallCard.setType
		card.toughness = scryfallCard.toughness?.replacingOccurrences(of: "*", with: "★")
		card.typeLine = scryfallCard.typeLine
		card.legalities = scryfallCard.legalities.filter { $0.value == "legal" }.map { $0.key }.joined(separator: ",")
		card.isDigital = scryfallCard.digital
		card.rarity = scryfallCard.rarity
		card.oracleID = scryfallCard.oracleId
		card.frame = scryfallCard.frame
		card.keywords = scryfallCard.keywords
		card.isFoundInBoosters = scryfallCard.booster
		card.isPromo = scryfallCard.promo
		card.watermark = scryfallCard.watermark
    card.securityStamp = scryfallCard.securityStamp
		
		let cardFaces: [CardFace]? = scryfallCard.cardFaces?.map { face in
			let cardFace: CardFace = self.makeNewCardFace()
			cardFace.colors = face.colors
			cardFace.colorIndicator = face.colorIndicator
			cardFace.flavorText = face.flavorText?.typographized(language: "en", isHTML: false)
			cardFace.loyalty = face.loyalty?.replacingOccurrences(of: "*", with: "★")
			cardFace.manaCost = face.manaCost
			cardFace.name = face.name
			cardFace.oracleText = face.oracleText?.typographized(language: "en", isHTML: false)
			cardFace.power = face.power?.replacingOccurrences(of: "*", with: "★")
			cardFace.toughness = face.toughness?.replacingOccurrences(of: "*", with: "★")
			cardFace.typeLine = face.typeLine
			cardFace.imageURIs = face.imageUris
			cardFace.watermark = face.watermark
			cardFace.artist = face.artist
      cardFace.printedName = face.printedName
      cardFace.printedText = face.printedText
      cardFace.printedTypeLine = face.printedTypeLine
			return cardFace
		}
		
		if let faces = cardFaces {
			card.faces = NSOrderedSet(array: faces)
		}
		
		let relatedCards: [CardRelatedCard]? = scryfallCard.allParts?.map { relatedPart in
			let part: CardRelatedCard = self.makeNewRelatedCard()
			part.component = relatedPart.component
			part.name = relatedPart.name
			part.scryfallID = relatedPart.id
			part.typeLine = relatedPart.typeLine
			part.url = URL(string: relatedPart.uri)
			
			return part
		}
		
		if let related = relatedCards {
			card.relatedCards = NSOrderedSet(array: related)
		}
	}
	
	private func fix(_ card: Swiftfall.Card) -> Swiftfall.Card {
		var fixedCard = card
		
		var frameEffects = fixedCard.frameEffects ?? []
    
    if (fixedCard.set == "who") {
      fixedCard.securityStamp = "triangle"
    }
		
		if ((fixedCard.set == "iko" && fixedCard.frameEffects?.contains("showcase") == true)) || fixedCard.preview?.sourceUri?.contains("godzilla-lands") == true {
			fixedCard.fullArt = true
		}
		
		if (fixedCard.set == "sld" && (fixedCard.collectorNumber == "81" ||
			fixedCard.frameEffects?.contains("nyxtouched") == true)) {
			fixedCard.fullArt = false
		}
		
		if ((fixedCard.set == "thb" || fixedCard.set == "iko" || fixedCard.set == "dmu") && fixedCard.frameEffects?.contains("showcase") == true) || (fixedCard.set == "sld" && (fixedCard.collectorNumber == "81" || fixedCard.frameEffects?.contains("nyxtouched") == true)) {
			frameEffects.append("inverted")
		}
		
		if (fixedCard.typeLine?.contains("Enchantment") == true) && fixedCard.layout != "flip" && fixedCard.layout != "transform" && fixedCard.layout != "modal_dfc" && fixedCard.frame != "future" {
			frameEffects.append("nyxtouched")
		}
		
		if fixedCard.name == "Bow of Nylea" {
			frameEffects.append("nyxtouched")
		}
		
		if fixedCard.set == "iko" {
			if let number = Int(fixedCard.collectorNumber), number >= 370 || number == 275 {
				frameEffects.append("inverted")
			} else if fixedCard.collectorNumber == "373A" {
				frameEffects.append("inverted")
			}
		}
		
		if fixedCard.set == "plgs" && fixedCard.collectorNumber == "2" {
			frameEffects.append("inverted")
		}
		
		if fixedCard.set == "m21" && fixedCard.frameEffects?.contains("showcase") == true {
			frameEffects.append("inverted")
		}
		
		if (fixedCard.set == "m21" || fixedCard.set == "2xm") && fixedCard.borderColor == "borderless" && (fixedCard.typeLine?.contains("Planeswalker") == false || fixedCard.colors == ["B"]) {
			frameEffects.append("inverted")
		}
		
		if (fixedCard.set == "neo" && fixedCard.layout == "transform") {
			frameEffects.append("closedfanopenfandfc")
		}
		
		if fixedCard.set == "hbg", let allParts = fixedCard.allParts, !allParts.isEmpty {
			if fixedCard.id == allParts.first?.id {
				frameEffects.append("dfcArrow")
			} else {
				frameEffects.append("specializeTree")
			}
		}
    
    // add arrow to Incubator // Phyrexian token
    if fixedCard.oracleId == UUID(uuidString: "dd3bf75e-9ef0-4ded-9b65-1a60a78a6253") {
      frameEffects.append("dfcArrow")
    }
		
		fixedCard.frameEffects = frameEffects
		
		return fixedCard
	}
	
	private func saveRuling(scryfallRuling: Swiftfall.Ruling) {
		let ruling = makeNewRuling()
		
		ruling.comment = scryfallRuling.comment
		ruling.oracleID = scryfallRuling.oracleId
		ruling.source = scryfallRuling.source
		ruling.publishDate = scryfallRuling.publishedAt
	}
	
	func makeNewCard() -> Card {
		var card: Card!
		
		privateContext.performAndWait {
			let entity = NSEntityDescription.entity(forEntityName: "Card", in: privateContext)!
			card = Card(entity: entity, insertInto: privateContext)
		}
		
		return card
	}
	
	func makeNewCardFace() -> CardFace {
		var face: CardFace!
		
		privateContext.performAndWait {
			let entity = NSEntityDescription.entity(forEntityName: "CardFace", in: privateContext)!
			face = CardFace(entity: entity, insertInto: privateContext)
		}
		
		return face
	}
	
	func makeNewRelatedCard() -> CardRelatedCard {
		var related: CardRelatedCard!
		
		privateContext.performAndWait {
			let entity = NSEntityDescription.entity(forEntityName: "CardRelatedCard", in: privateContext)!
			related = CardRelatedCard(entity: entity, insertInto: privateContext)
		}
		
		return related!
	}
	
	func makeNewRuling() -> Ruling {
		var ruling: Ruling!
		
		privateContext.performAndWait {
			let entity = NSEntityDescription.entity(forEntityName: "Ruling", in: privateContext)!
			ruling = Ruling(entity: entity, insertInto: privateContext)
		}
		
		return ruling!
	}
	
	private func resultComparator(_ lhs: Card, _ rhs: Card) -> Bool {
		func isLessDesirable(_ card: Card) -> Bool {
			if let releaseDate = card.releaseDate, releaseDate > Date() {
				return true
			}
			return card.isPromo || card.frameEffects?.contains("extendedart") == true || card.frameEffects?.contains("showcase") == true || card.borderColor == "borderless" || card.isFullArt || card.set == "dbl" || card.isDigital || card.setType == "masterpiece" || card.typeLine?.contains("Token") == true || card.borderColor == "gold" || card.borderColor == "white" || card.set == "sld"
		}
		
		if lhs.set == rhs.set, let num0 = lhs.collectorNumber.flatMap(Int.init), let num1 = rhs.collectorNumber.flatMap(Int.init) {
			return num0 < num1
		}
		
		switch (isLessDesirable(lhs), isLessDesirable(rhs)) {
		case(true, true):
			return false
		case (true, false):
			return false
		case (false, true):
			return true
		case (false, false):
			return false
		}
	}
	
	func card(for identifier: MTGCardIdentifier) -> Card? {
		let request: NSFetchRequest<Card> = Card.fetchRequest()
//		request.fetchLimit = 1
		
		request.predicate = predicate(for: identifier)
		request.sortDescriptors = [NSSortDescriptor(key: "releaseDate", ascending: false)]
		
		do {
			var results = try persistentContainer.viewContext.fetch(request)
			
			results = results.sorted(by: resultComparator(_:_:))
			
			return results.first
		} catch {
			return nil
		}
	}
	
	func cards(for identifiers: [MTGCardIdentifier]) -> [Card] {
		let request: NSFetchRequest<Card> = Card.fetchRequest()
		
		let predicates = identifiers.compactMap { predicate(for: $0) }
		request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
		request.sortDescriptors = [NSSortDescriptor(key: "releaseDate", ascending: false)]
		
		do {
			let results = try persistentContainer.viewContext.fetch(request)
			return results
		} catch {
			return []
		}
	}
	
	func predicate(for identifier: MTGCardIdentifier) -> NSPredicate? {
		switch identifier {
    case .id(let scryfallID), .idName(let scryfallID, _):
			return NSPredicate(format: "scryfallID == %@", scryfallID as NSUUID)
		case .name(let name):
      return NSPredicate(format: "name LIKE[c] %@ AND set !=[c] 'prm' AND set !=[c] 'sld' AND set !=[c] 'psld'", name)
		case .nameSet(name: let name, set: let set):
      return NSPredicate(format: "ANY name LIKE[c] %@ && set ==[c] %@", name, set)
		case .collectorNumberSet(collectorNumber: let collectorNumber, set: let set, name: _):
			return NSPredicate(format: "set ==[c] %@ && collectorNumber ==[c] %@", set, collectorNumber)
		case .mtgoID(_), .multiverseID(_), .oracleID(_), .illustrationID(_):
			return nil
		}
	}
	
	func rulings(oracleID: UUID) -> [Ruling] {
		let request: NSFetchRequest<Ruling> = Ruling.fetchRequest()
		request.predicate = NSPredicate(format: "oracleID == %@", oracleID as NSUUID)
		
		do {
			return try persistentContainer.viewContext.fetch(request)
		} catch {
			return []
		}
	}
	
	func card(scryfallID: UUID) -> Card? {
		let request: NSFetchRequest<Card> = Card.fetchRequest()
		request.fetchLimit = 1
		request.predicate = predicate(for: .id(scryfallID))
    request.fetchBatchSize = 1
		
		do {
			let results = try persistentContainer.viewContext.fetch(request)
			return results.first
		} catch {
			return nil
		}
	}
	
	func card(name: String) -> Card? {
		let request: NSFetchRequest<Card> = Card.fetchRequest()
		request.fetchLimit = 1
		
		request.predicate = predicate(for: .name(name))
		request.sortDescriptors = [NSSortDescriptor(key: "releaseDate", ascending: false)]
		
		do {
			var results = try persistentContainer.viewContext.fetch(request)
			
			results = results.sorted(by: resultComparator(_:_:))
			
			return results.first
		} catch {
			return nil
		}
	}
  
  func card(fuzzy name: String) -> Card? {
    let request: NSFetchRequest<Card> = Card.fetchRequest()
//    request.fetchLimit = 1
    
    request.predicate = NSPredicate(format: "name BEGINSWITH[c] %@ AND set !=[c] 'prm' AND set !=[c] 'sld' AND set !=[c] 'psld'", name)
    request.sortDescriptors = [NSSortDescriptor(key: "releaseDate", ascending: false)]
    
    do {
      var results = try persistentContainer.viewContext.fetch(request)
      
      results = results.sorted(by: resultComparator(_:_:))
      
      return results.first
    } catch {
      return nil
    }
  }
	
	func card(name: String, set: String) -> Card? {
		let request: NSFetchRequest<Card> = Card.fetchRequest()
//		request.fetchLimit = 1
		
		request.predicate = self.predicate(for: .nameSet(name: name, set: set))
		request.sortDescriptors = [NSSortDescriptor(key: "releaseDate", ascending: false)]
		
		do {
			var results = try persistentContainer.viewContext.fetch(request)
			
			results = results.sorted(by: resultComparator(_:_:))
			
			return results.first
		} catch {
			return nil
		}
	}
	
	func card(set: String, collectorNumber: String) -> Card? {
		let request: NSFetchRequest<Card> = Card.fetchRequest()
		request.fetchLimit = 1
		
		request.predicate = predicate(for: .collectorNumberSet(collectorNumber: collectorNumber, set: set, name: nil))
		request.sortDescriptors = [NSSortDescriptor(key: "releaseDate", ascending: false)]
		
		do {
			let results = try persistentContainer.viewContext.fetch(request)
			return results.first
		} catch {
			return nil
		}
	}
	
	func cards(setCode: String) -> [Card] {
		let request: NSFetchRequest<Card> = Card.fetchRequest()
		
		request.predicate = NSPredicate(format: "set ==[c] %@", setCode)
		request.sortDescriptors = [NSSortDescriptor(key: "releaseDate", ascending: false)]
		
		do {
			return try persistentContainer.viewContext.fetch(request)
		} catch {
			return []
		}
	}
	
  func randomCard(query: String? = nil) -> Card? {
    return allCards().randomElement()
		
    // TODO: Implement random within query
	}
	
	func momirCard(convertedManaCost: Int, legality: String?, set: String?) -> Card? {
		let column = "name"

		// 2. Get the NSManagedObjectContext, for example:
		let moc = persistentContainer.viewContext

		// 3. Create the request for your entity
		let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Card")

		// 4. Use the only result type allowed for getting distinct values
		request.resultType = .dictionaryResultType

		// 5. Set that you want distinct results
		request.returnsDistinctResults = true

		// 6. Set the column you want to fetch
		request.propertiesToFetch = [column]
		
		var predicate: NSPredicate = {
			let base = NSPredicate(format: "convertedManaCost == %d AND isCustom == NO AND borderColor != 'silver' AND borderColor != 'gold' AND isDigital == NO AND NOT (layout CONTAINS 'token') AND set != 'cmb1'", convertedManaCost)
			
			let cardType = NSPredicate(format: "typeLine CONTAINS 'Creature'")
			
//			let frontFaceType = NSPredicate(format: "faces[0].typeLine CONTAINS 'Creature'")
			
//			let types = NSCompoundPredicate(orPredicateWithSubpredicates: [cardType, frontFaceType])
			return NSCompoundPredicate(andPredicateWithSubpredicates: [base, cardType])
		}()
		
		if let legality = legality {
			let legalityPredicate = NSPredicate(format: "legalities CONTAINS[c] %@", legality)
			predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, legalityPredicate])
		}
		
		if let set = set {
			let setPredicate = NSPredicate(format: "set LIKE[c] %@", set)
			predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, setPredicate])
		}
		
		request.predicate = predicate
		
		// 7. Execute the request. You'll get an array of dictionaries with the column
		// as the name and the distinct value as the value
		if let res = try? moc.fetch(request) as? [[String: String]], let cardName = res.randomElement()?[column] {
			
			if let card = self.card(name: cardName) {
				if let faces = card.faces, faces.count > 1, let frontFace = faces.firstObject as? CardFace {
					if frontFace.typeLine?.contains("Creature") == true {
						return card
					} else {
						return self.momirCard(convertedManaCost: convertedManaCost, legality: legality, set: set)
					}
				} else {
					return card
				}
			}
			
		}
		
		return nil
//		let request: NSFetchRequest<Card> = Card.fetchRequest()
//		request.predicate = NSPredicate(format: "convertedManaCost == \(convertedManaCost) AND typeLine CONTAINS 'Creature' AND isCustom == NO")
//
//		do {
//			let results = try persistentContainer.viewContext.fetch(request)
//			return results.randomElement()
//		} catch {
//			return nil
//		}
	}
	
	func allCards() -> [Card] {
		let request: NSFetchRequest<Card> = Card.fetchRequest()
//		request.fetchLimit = 1
//		request.predicate = NSPredicate(format: "scryfallID == %@", scryfallID as NSUUID)
		
		do {
			let results = try persistentContainer.viewContext.fetch(request)
			return results
		} catch {
			return []
		}
	}
	
	// MARK: - Core Data stack
	
	lazy var persistentContainer: NSPersistentContainer = {
	    /*
	     The persistent container for the application. This implementation
	     creates and returns a container, having loaded the store for the
	     application to it. This property is optional since there are legitimate
	     error conditions that could cause the creation of the store to fail.
	    */
		
		let modelURL = Bundle(for: CoreDataManager.self).url(forResource: "CardService", withExtension: "momd")!
		let model = NSManagedObjectModel(contentsOf: modelURL)!
		
		return NSPersistentContainer(name: "CardService", managedObjectModel: model)
	}()
	
	fileprivate func loadPersistentStores(_ completion: (() -> Void)? = nil) {
		self.persistentContainer.loadPersistentStores(completionHandler: { (storeDescription, error) in
	        if let error = error as NSError? {
	            // Replace this implementation with code to handle the error appropriately.
	            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
	             
	            /*
	             Typical reasons for an error here include:
	             * The parent directory does not exist, cannot be created, or disallows writing.
	             * The persistent store is not accessible, due to permissions or data protection when the device is locked.
	             * The device is out of space.
	             * The store could not be migrated to the current model version.
	             Check the error message to determine what the actual problem was.
	             */
	            fatalError("Unresolved error \(error), \(error.userInfo)")
	        }
			
			completion?()
	    })
	}
	
	lazy var privateContext: NSManagedObjectContext = {
		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		context.parent = persistentContainer.viewContext
		return context
	}()

	// MARK: - Core Data Saving support

	/// Pushes the private context's changes into the view context, then saves the view context to the store.
	/// Each context is saved on its own queue, so this can be called from any thread except the main thread
	/// while the private context is busy.
	func saveContext () {
		func save(_ context: NSManagedObjectContext) {
			context.performAndWait {
				guard context.hasChanges else { return }
				do {
					try context.save()
				} catch {
					// Replace this implementation with code to handle the error appropriately.
					// fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
					let nserror = error as NSError
					fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
				}
			}
		}
		
		save(privateContext)
		save(persistentContainer.viewContext)
	}
	
}
