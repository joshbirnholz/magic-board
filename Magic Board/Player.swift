//
//  Player.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/20/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import CardService
import RxSwift
import RxCocoa

class Player: Codable {
	
	private let bag = DisposeBag()
	
	enum Identifier: String, Codable {
		case a
		case b
	}
	
	var identifier: Identifier
	
	let hand: Pile
	let library: Pile
	let graveyard: Pile
	let sideboard: Pile
	let commandZone: Pile
	let exile: Pile
	
	private(set) lazy var revealedCards: Observable<OrderedSet<CardInstance>> = {
		let allPiles = Array(GameState.current.allPlayers.map { $0.allPiles.map { $0.cards } }.joined()) + [GameState.current.battlefield]
		return Observable.combineLatest(allPiles).map { [weak self] sets in
			guard let self = self else { return [] }
			let allRevealedCards: OrderedSet<CardInstance> = OrderedSet(sets.joined().filter { $0.revealedPlayers.value.contains(self.identifier) })
			return allRevealedCards
		}
	}()
	
	let life: BehaviorRelay<Int>
	
	let name: BehaviorRelay<String>
	
	enum CodingKeys: String, CodingKey {
		case identifier, hand, library, graveyard, sideboard, commandZone, exile, life, name
	}
	
	init(identifier: Identifier, name: String? = nil, hand: Cards = [], library: Cards = [], graveyard: Cards = [], sideboard: Cards = [], commandZone: Cards = [], exile: Cards = [], life: Int = 20) {
		self.identifier = identifier
		self.hand = Pile(location: .hand, isHidden: true, playerIdentifier: identifier, cards: hand)
		self.library = Pile(location: .library, isHidden: true, playerIdentifier: identifier, cards: library)
		self.graveyard = Pile(location: .graveyard, isHidden: false, playerIdentifier: identifier, cards: graveyard)
		self.sideboard = Pile(location: .sideboard, isHidden: true, playerIdentifier: identifier, cards: sideboard)
		self.commandZone = Pile(location: .command, isHidden: false, playerIdentifier: identifier, cards: commandZone)
		self.exile = Pile(location: .exile, isHidden: false, playerIdentifier: identifier, cards: exile)
		self.life = BehaviorRelay(value: life)
		self.name = BehaviorRelay(value: name ?? (identifier == .a ? "Player 1" : "Player 2"))
	}
	
	var allPiles: [Pile] {
		[hand, library, graveyard, exile, commandZone, sideboard]
	}
	
	subscript(_ pileLocation: Pile.Location) -> Pile {
		switch pileLocation {
		case .library:
			return library
		case .sideboard:
			return sideboard
		case .graveyard:
			return graveyard
		case .hand:
			return hand
		case .exile:
			return exile
		case .command:
			return commandZone
		}
	}
	
}
