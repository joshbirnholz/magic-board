//
//  Role.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/8/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation

enum Role: String, Codable {
	case board
	case player1
	case player2
	case boardPlayer1
	case boardPlayer2
	
	var playerIdentifier: Player.Identifier? {
		switch self {
		case .player1, .boardPlayer1: return .a
		case .player2, .boardPlayer2: return .b
		case .board: return nil
		}
	}
	
	var isBoard: Bool {
		switch self {
		case .board, .boardPlayer1, .boardPlayer2: return true
		case .player1, .player2: return false
		}
	}
}
