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

extension Card {
	func decodedMTGCard() throws -> MTGCard {
		guard let data = mtgCard else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "No data saved in core data")) }
		return try CoreDataManager.shared.decoder.decode(MTGCard.self, from: data)
	}
}

class CoreDataManager: NSObject {
	
	private override init() {
		super.init()
		
		let bundle = Bundle(for: CoreDataManager.self)
		if let data = NSDataAsset(name: "scryfall-default-cards", bundle: bundle)?.data {
			do {
				try updateFromScryfall(data: data)
			} catch {
				print(error)
			}
		}
	}
	
	static let shared = CoreDataManager()
	
	// MARK: - Loading
	
	enum LoadingError: Error {
		
	}
	
	fileprivate let decoder = JSONDecoder()
	private let encoder = JSONEncoder()
	
	func updateFromScryfall(data: Data) throws {
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		
		let DEBUG_reload = false
		
		if !DEBUG_reload && allCards().count == 52233 {
			print("Skipping loading cards")
			return
		}
		
		print("Loading cards…")
		let allCards = try decoder.decode([Swiftfall.Card].self, from: data)
		print("Decoded \(allCards.count) cards")
		
		let managedCards = self.allCards()
		if !DEBUG_reload && managedCards.count == allCards.count {
			return
		}
		
		for scryfallCard in allCards {
			saveCard(scryfallCard: scryfallCard)
		}
		
		saveContext()
		
		print("Loaded \(allCards.count) cards from data")
	}
	
	let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()
	
	private func saveCard(scryfallCard: Swiftfall.Card) {
		var DEBUG_shouldRewriteCard = false
		
		let card: Card = {
			if let card = self.card(scryfallID: scryfallCard.id) {
				return card
			} else {
				DEBUG_shouldRewriteCard = true
				return makeNewCard()
			}
		}()
		
		if DEBUG_shouldRewriteCard {
			card.name = scryfallCard.name
			card.set = scryfallCard.set
			card.collectorNumber = scryfallCard.collectorNumber
			card.language = scryfallCard.lang.rawValue
			card.scryfallID = scryfallCard.id
			card.releaseDate = dateFormatter.date(from: scryfallCard.releasedAt)
			
			let mtgCard = MTGCard(scryfallCard)
			let data = try? encoder.encode(mtgCard)
			card.mtgCard = data
		}
	}
	
	func makeNewCard() -> Card {
		let context = persistentContainer.viewContext
		let entity = NSEntityDescription.entity(forEntityName: "Card", in: context)!
		let card = Card(entity: entity, insertInto: context)
		return card
	}
	
	func card(scryfallID: UUID) -> Card? {
		let request: NSFetchRequest<Card> = Card.fetchRequest()
		request.fetchLimit = 1
		request.predicate = NSPredicate(format: "scryfallID == %@", scryfallID as NSUUID)
		
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
		
		let predicate = NSPredicate(format: "ANY name LIKE[c] %@", name)
		request.sortDescriptors = [NSSortDescriptor(key: "releaseDate", ascending: false)]
		
		request.predicate = predicate
		
		do {
			let results = try persistentContainer.viewContext.fetch(request)
			return results.first
		} catch {
			return nil
		}
	}
	
	func card(name: String, set: String) -> Card? {
		let request: NSFetchRequest<Card> = Card.fetchRequest()
		request.fetchLimit = 1
		
		let predicate = NSPredicate(format: "ANY name LIKE[c] %@ && set ==[c] %@", name, set)
		request.sortDescriptors = [NSSortDescriptor(key: "releaseDate", ascending: false)]
		
		request.predicate = predicate
		
		do {
			let results = try persistentContainer.viewContext.fetch(request)
			return results.first
		} catch {
			return nil
		}
	}
	
	func card(set: String, collectorNumber: String) -> Card? {
		let request: NSFetchRequest<Card> = Card.fetchRequest()
		request.fetchLimit = 1
		
		let predicate = NSPredicate(format: "set ==[c] %@ && collectorNumber ==[c] %@", set, collectorNumber)
		request.sortDescriptors = [NSSortDescriptor(key: "releaseDate", ascending: false)]
		
		request.predicate = predicate
		
		do {
			let results = try persistentContainer.viewContext.fetch(request)
			return results.first
		} catch {
			return nil
		}
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
		
		let container = NSPersistentContainer(name: "CardService", managedObjectModel: model)
	    container.loadPersistentStores(completionHandler: { (storeDescription, error) in
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
	    })
	    return container
	}()

	// MARK: - Core Data Saving support

	func saveContext () {
	    let context = persistentContainer.viewContext
	    if context.hasChanges {
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
	
}
