//
//  CardInstance.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/5/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import CardService

extension CardInstance: NSItemProviderWriting, NSItemProviderReading {
	
	enum ItemError: Error {
		case wrongTypeIdentifier
		case unableToFindCard
	}
	
	var pile: Pile? {
		for player in GameState.current.allPlayers {
			for pile in player.allPiles {
				if pile.cards.value.contains(self) {
					return pile
				}
			}
		}
		
		return nil
	}
	
	var indexInPile: Int? {
		guard let pile = pile else { return nil }
		return pile.cards.value.firstIndex(of: self)
	}
	
	public static let typeIdentifier = "com.josh.birnholz.Magic-Board.\(String(describing: CardInstance.self))"
	static let writableTypeIdentifiersForItemProvider: [String] = [CardInstance.typeIdentifier, "public.plain-text"]
	
	func loadData(withTypeIdentifier typeIdentifier: String, forItemProviderCompletionHandler completionHandler: @escaping (Data?, Error?) -> Void) -> Progress? {
		
		switch typeIdentifier {
		case CardInstance.typeIdentifier:
			let data = uuid.uuidString.data(using: .utf8)
			completionHandler(data, nil)
		case "public.plain-text":
			let isHidden: Bool = pile?.isHidden == true
			guard !isHidden else {
				completionHandler(nil, nil)
				break
			}
			let data = representation.scryfallUri?.absoluteString.data(using: .utf8)
			completionHandler(data, nil)
		default:
			completionHandler(nil, ItemError.wrongTypeIdentifier)
		}
		
		return nil
	}
	
	static let readableTypeIdentifiersForItemProvider: [String] = [CardInstance.typeIdentifier]
	
	static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self {
		
		guard typeIdentifier == CardInstance.typeIdentifier else {
			throw ItemError.wrongTypeIdentifier
		}
		
		guard let uuidString = String(data: data, encoding: .utf8),
			let uuid = UUID(uuidString: uuidString),
			let cardInstance = GameState.current.cardInstance(with: uuid) else {
				throw ItemError.unableToFindCard
		}
		print("Found card instance from item provider for \(cardInstance.representation.name ?? "")")
		return cardInstance as! Self
	}
}

extension NSItemProvider {
	
	/// Synchronously attempts to load a card instance.
	var cardInstance: CardInstance? {
		guard canLoadObject(ofClass: CardInstance.self) else { return nil }
		
		var cardInstance: CardInstance?
		
		let semaphore = DispatchSemaphore(value: 0)
		
		DispatchQueue.global(qos: .userInteractive).async { [weak self] in
			guard let self = self else { semaphore.signal(); return }
			self.loadObject(ofClass: CardInstance.self) { (object, error) in
				cardInstance = object as? CardInstance
				semaphore.signal()
			}
		}
		
		semaphore.wait()
		
		return cardInstance
	}
	
}

extension UIDragItem {
	var cardInstance: CardInstance? {
		if let cardInstance = localObject as? CardInstance {
			return cardInstance
		}
		
		if let data = itemProvider.teamData, let string = String(data: data, encoding: .utf8), let uuid = UUID(uuidString: string), let cardInstance = GameState.current.cardInstance(with: uuid) {
			return cardInstance
		}
		
		return itemProvider.cardInstance
	}
}

extension NSItemProvider {
	convenience init(card: CardInstance) {
		self.init(object: card)
		teamData = card.uuid.uuidString.data(using: .utf8)
	}
}
