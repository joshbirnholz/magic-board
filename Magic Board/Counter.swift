//
//  Counter.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/4/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import UIKit

enum Counter: Int, Equatable, Hashable, Codable, CaseIterable {
	case plusOnePlusOne
	case minusOneMinusOne
	case loyalty
	case lore
	
	case deathtouch
	case doublestrike
	case firststrike
	case flying
	case hexproof
	case indestructible
	case lifelink
	case menace
	case reach
	case trample
	case vigilance
	
	case gray
	case red
	case green
	case purple
	case yellow
  
  case stun
	
	var color: UIColor {
		switch self {
		case .plusOnePlusOne:
			return #colorLiteral(red: 0.2349261343, green: 0.4487332702, blue: 0.6934463382, alpha: 1)
		case .minusOneMinusOne:
			return #colorLiteral(red: 0.1512642913, green: 0.2112584658, blue: 0.3822596464, alpha: 1)
		case .loyalty:
			return #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
		case .gray:
			return #colorLiteral(red: 0.501960814, green: 0.501960814, blue: 0.501960814, alpha: 1)
		case .red:
			return #colorLiteral(red: 0.8078431487, green: 0.02745098062, blue: 0.3333333433, alpha: 1)
		case .green:
			return #colorLiteral(red: 0.3411764801, green: 0.6235294342, blue: 0.1686274558, alpha: 1)
		case .purple:
			return #colorLiteral(red: 0.5326987213, green: 0.1988100325, blue: 0.9686274529, alpha: 1)
		case .yellow:
			return #colorLiteral(red: 0.9529411793, green: 0.6587831172, blue: 0.2176297476, alpha: 1)
		case .lore:
			return #colorLiteral(red: 0.9538559318, green: 0.8971239924, blue: 0.7882547975, alpha: 1)
		case .deathtouch:
			return #colorLiteral(red: 0.3050225377, green: 0.3543257713, blue: 0.3664812148, alpha: 1)
		case .doublestrike:
			return #colorLiteral(red: 0.4098989367, green: 0, blue: 0.004982399289, alpha: 1)
		case .firststrike:
			return #colorLiteral(red: 0.8262283206, green: 0.8080766797, blue: 0.7249318957, alpha: 1)
		case .flying:
			return #colorLiteral(red: 0.001011309098, green: 0.32381019, blue: 0.5295761228, alpha: 1)
		case .hexproof:
			return #colorLiteral(red: 0.001011309098, green: 0.32381019, blue: 0.5295761228, alpha: 1)
		case .indestructible:
			return #colorLiteral(red: 0.8262283206, green: 0.8080766797, blue: 0.7249318957, alpha: 1)
		case .lifelink:
			return #colorLiteral(red: 0.8262283206, green: 0.8080766797, blue: 0.7249318957, alpha: 1)
		case .menace:
			return #colorLiteral(red: 0.4098989367, green: 0, blue: 0.004982399289, alpha: 1)
		case .reach:
			return #colorLiteral(red: 0.002303533489, green: 0.4835820198, blue: 0.2841368616, alpha: 1)
		case .trample:
			return #colorLiteral(red: 0.4098989367, green: 0, blue: 0.004982399289, alpha: 1)
		case .vigilance:
			return #colorLiteral(red: 0.002303533489, green: 0.4835820198, blue: 0.2841368616, alpha: 1)
    case .stun:
      return #colorLiteral(red: 0.001011309098, green: 0.32381019, blue: 0.5295761228, alpha: 1)
		}
	}
	
	var name: String {
		switch self {
		case .plusOnePlusOne:
			return "+1/+1"
		case .minusOneMinusOne:
			return "-1/-1"
		case .loyalty:
			return "Loyalty"
		case .gray, .red, .green, .purple, .yellow:
			return ""
		case .deathtouch:
			return "Deathtouch"
		case .doublestrike:
			return "Double Strike"
		case .firststrike:
			return "First Strike"
		case .flying:
			return "Flying"
		case .hexproof:
			return "Hexproof"
		case .indestructible:
			return "Indestructible"
		case .lifelink:
			return "Lifelink"
		case .menace:
			return "Menace"
		case .reach:
			return "Reach"
		case .trample:
			return "Trample"
		case .vigilance:
			return "Vigilance"
		case .lore:
			return "Lore"
    case .stun:
      return "Stun"
		}
	}
	
	// MARK: Codable
	
//	func encode(to encoder: Encoder) throws {
//		var container = encoder.singleValueContainer()
//
//		switch self {
//		case .plusOnePlusOne:
//			try container.encode(CodingKeys.plusOnePlusOne)
//		case .minusOneMinusOne:
//			try container.encode(CodingKeys.minusOneMinusOne)
//		case .loyalty:
//			try container.encode(CodingKeys.loyalty)
//		case .custom(let customType):
//			try container.encode(customType)
//		}
//	}
//
//	init(from decoder: Decoder) throws {
//		let container = try decoder.singleValueContainer()
//
//		if let codingKey = try? container.decode(CodingKeys.self) {
//			switch codingKey {
//			case .plusOnePlusOne:
//				self = .plusOnePlusOne
//			case .minusOneMinusOne:
//				self = .minusOneMinusOne
//			case .loyalty:
//				self = .loyalty
//			}
//		} else if let customType = try? container.decode(CustomCounter.self) {
//			self = .custom(customType)
//		} else {
//			throw DecodingError.dataCorruptedError(in: container, debugDescription: "Could not decode counter")
//		}
//	}
}
