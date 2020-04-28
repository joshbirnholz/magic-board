//
//  CardInstance.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/5/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import CardService

fileprivate let encoder = JSONEncoder()
fileprivate let decoder = JSONDecoder()

extension CardInstance: NSItemProviderWriting, NSItemProviderReading {
	
	enum ItemError: Error {
		case wrongTypeIdentifier
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
	
	private static let typeIdentifier = "com.josh.birnholz.Magic-Board.\(String(describing: CardInstance.self))"
	static let writableTypeIdentifiersForItemProvider: [String] = [CardInstance.typeIdentifier, "public.plain-text"]
	
	func loadData(withTypeIdentifier typeIdentifier: String, forItemProviderCompletionHandler completionHandler: @escaping (Data?, Error?) -> Void) -> Progress? {
		
		switch typeIdentifier {
		case CardInstance.typeIdentifier:
			do {
				let data = try encoder.encode(self)
				completionHandler(data, nil)
			} catch {
				completionHandler(nil, error)
			}
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
		
		return try decoder.decode(Self.self, from: data)
	}
}
