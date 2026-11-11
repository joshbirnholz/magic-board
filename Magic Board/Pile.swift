//
//  Pile.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/4/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import CardService
import RxSwift
import RxCocoa

typealias Cards = [MTGCard]

struct Pile: Codable, Equatable, Hashable {
	
	enum Location: String, Codable {
		case library = "Library"
		case sideboard = "Sideboard"
		case graveyard = "Graveyard"
		case hand = "Hand"
		case exile = "Exile"
		case command = "Command"
	}
	
	private let id: UUID
	
	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
	
	static func == (lhs: Pile, rhs: Pile) -> Bool {
		return lhs.id == rhs.id
	}
	
	let location: Location
	let isHidden: Bool
	let playerIdentifier: Player.Identifier
	
	var cards: BehaviorRelay<OrderedSet<CardInstance>>
  var isTopCardRevealed: BehaviorRelay<Bool>
	
	init(location: Location, isHidden: Bool, playerIdentifier: Player.Identifier, cards: Cards = []) {
		self.id = UUID()
		self.location = location
		self.isHidden = isHidden
		self.cards = BehaviorRelay<OrderedSet<CardInstance>>(value: OrderedSet(cards.map { card in
			let representation = CardRepresentation.card(card)
			let instance = CardInstance(card: representation,
										center: nil,
										ownerIdentifier: playerIdentifier)
			return instance
		}))
		self.playerIdentifier = playerIdentifier
    self.isTopCardRevealed = BehaviorRelay(value: false)
	}
	
	var topCardImage: UIImage? {
		if cards.value.isEmpty {
			return nil
    } else if !isHidden || isTopCardRevealed.value {
			return cards.value.last?.representation.image(type: .small)
		} else {
      return #imageLiteral(resourceName: "mtg-card-back-png-1")
		}
	}
}
