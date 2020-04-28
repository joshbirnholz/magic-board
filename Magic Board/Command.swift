//
//  Command.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/8/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation

enum Command: Codable {
	struct MoveCommandParameters: Codable {
		var cardInstanceIDs: [UUID]
		struct PileIdentifier: Codable {
			var location: Pile.Location
			var playerIdentifier: Player.Identifier
			
			var pile: Pile? {
				for player in [GameState.current.player1, GameState.current.player2] {
					guard player.identifier == playerIdentifier else { continue }
					return player[location]
				}
				
				return nil
			}
		}
		var destination: PileIdentifier
		var insertionIndex: Int? = nil
	}
	
	struct PlayCardParameters: Codable {
		var cardInstanceID: UUID
		/// nil is no alt face, a negative value is face-down, and a positive value is an index pointing a face in the card's `cardFaces` array
		var faceIndex: Int?
	}
	
	struct LoadDeckParameters: Codable {
		var playerIdentifier: Player.Identifier
		var deckList: String
	}
	
	struct RevealCardsToPlayerParameters: Codable {
		var cardInstanceIDs: [UUID]
		var playerIdentifier: Player.Identifier
	}
	
	enum CodingKeys: String, CodingKey {
		case moveCards
		case moveToBattlefield
		case rebroadcast
		case loadDeck
		case revealCardsToPlayer
		case removeAllRevealedCards
		case unrevealCardsToPlayer
	}
	
	case moveCards(MoveCommandParameters)
	case moveCardsToBattlefield([PlayCardParameters])
	case rebroadcast
	case loadDeck(LoadDeckParameters)
	case revealCardsToPlayer(RevealCardsToPlayerParameters)
	case removeAllRevealedCards(Player.Identifier)
	case unrevealCardsToPlayer(RevealCardsToPlayerParameters)
	
	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		switch self {
		case .moveCards(let parameters):
			try container.encode(parameters, forKey: .moveCards)
		case .moveCardsToBattlefield(let cardItems):
			try container.encode(cardItems, forKey: .moveToBattlefield)
		case .rebroadcast:
			try container.encode(CodingKeys.rebroadcast.rawValue, forKey: .rebroadcast)
		case .loadDeck(let parameters):
			try container.encode(parameters, forKey: .loadDeck)
		case .revealCardsToPlayer(let parameters):
			try container.encode(parameters, forKey: .revealCardsToPlayer)
		case .removeAllRevealedCards(let playerIdentifier):
			try container.encode(playerIdentifier, forKey: .removeAllRevealedCards)
		case .unrevealCardsToPlayer(let parameters):
			try container.encode(parameters, forKey: .unrevealCardsToPlayer)
		}
	}
	
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		if let moveCardsParameters = try container.decodeIfPresent(MoveCommandParameters.self, forKey: .moveCards) {
			self = .moveCards(moveCardsParameters)
		} else if let cardItems = try container.decodeIfPresent([PlayCardParameters].self, forKey: .moveToBattlefield) {
			self = .moveCardsToBattlefield(cardItems)
		} else if container.contains(.rebroadcast) {
			self = .rebroadcast
		} else if let parameters = try container.decodeIfPresent(LoadDeckParameters.self, forKey: .loadDeck) {
			self = .loadDeck(parameters)
		} else if let parameters = try container.decodeIfPresent(RevealCardsToPlayerParameters.self, forKey: .revealCardsToPlayer) {
			self = .revealCardsToPlayer(parameters)
		} else if let playerIdentifier = try container.decodeIfPresent(Player.Identifier.self, forKey: .removeAllRevealedCards) {
			self = .removeAllRevealedCards(playerIdentifier)
		} else if let parameters = try container.decodeIfPresent(RevealCardsToPlayerParameters.self, forKey: .unrevealCardsToPlayer) {
			self = .unrevealCardsToPlayer(parameters)
		} else {
			throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Could not decode a command"))
		}
	}
}
