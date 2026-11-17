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

  // Keyword counters added later: keep them after `stun` so stored raw values never change.
  case decayed
  case exalted
  case haste
  case shadow
  case finality
  /// The "prepared" marker on a prepare-layout card (Secrets of Strixhaven): its spell can be cast.
  case prepared
  /// A Room's locked doors: the first door (left, once the card is turned sideways) and the second.
  case lockedDoorLeft
  case lockedDoorRight
  case shield
  /// Phased out (CR 702.26): treated as though it doesn't exist until it phases in.
  case phasedOut

  /// Every keyword counter (CR 122.1b), in the order the counter menu lists them.
  static let keywordCounters: [Counter] = [.flying, .firststrike, .doublestrike, .deathtouch, .decayed, .exalted, .haste,
                                           .hexproof, .indestructible, .lifelink, .menace, .reach, .shadow, .trample, .vigilance]
  var isKeyword: Bool { Counter.keywordCounters.contains(self) }
  /// Room door locks are drawn on the card itself, not as counters.
  var isDoorLock: Bool { self == .lockedDoorLeft || self == .lockedDoorRight }
  /// States drawn on the card itself (locks, phasing) rather than as counter discs.
  var isCardState: Bool { isDoorLock || self == .phasedOut }
  static func doorLock(_ face: Int) -> Counter { face == 0 ? .lockedDoorLeft : .lockedDoorRight }
  /// The LOCKED door from Duskmourn's Room tokens (template).
  static var lockedDoorImage: UIImage? {
    UIImage.resource(named: "Icon_LockedDoor")?.withRenderingMode(.alwaysTemplate)
      ?? UIImage(systemName: "lock.fill")
  }
	
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
    case .finality:
      return .black
    case .prepared:
      return #colorLiteral(red: 0.42, green: 0.25, blue: 0.62, alpha: 1)
    case .lockedDoorLeft, .lockedDoorRight, .phasedOut:
      return .darkGray
    case .shield:
      return #colorLiteral(red: 0.2, green: 0.24, blue: 0.3, alpha: 1)
    case .decayed, .exalted, .haste, .shadow:
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
    case .decayed: return "Decayed"
    case .exalted: return "Exalted"
    case .haste: return "Haste"
    case .shadow: return "Shadow"
    case .finality: return "Finality"
    case .prepared: return "Prepared"
    case .lockedDoorLeft: return "Locked (First Door)"
    case .lockedDoorRight: return "Locked (Second Door)"
    case .shield: return "Shield"
    case .phasedOut: return "Phased Out"
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

import CardView

extension Counter {
    /// The ability tile a keyword counter adds to the card (drawn on the blue counter plate).
    var keywordIcon: MTGCardView.Icon? {
        let icon: MTGCardView.Icon
        switch self {
        case .flying: icon = .flying
        case .firststrike: icon = .firststrike
        case .doublestrike: icon = .doublestrike
        case .deathtouch: icon = .deathtouch
        case .decayed: icon = .decayed
        case .haste: icon = .haste
        case .hexproof: icon = .hexproof
        case .indestructible: icon = .indestructible
        case .lifelink: icon = .lifelink
        case .menace: icon = .menace
        case .reach: icon = .reach
        case .trample: icon = .trample
        case .vigilance: icon = .vigilance
        case .shadow, .exalted:
            // Arena's ability icons, shipped in CardView's asset catalog (template images).
            let asset = self == .shadow ? "Icon_Shadow" : "Icon_Exalted"
            guard let image = UIImage.resource(named: asset)?
                .withRenderingMode(.alwaysTemplate) else { return nil }
            icon = .custom(image, name: name, isPermanent: true)
        default: return nil
        }
        return .counter(icon)
    }
}

extension Counter {
    /// Counters drawn as a symbol rather than a number (Arena's stun and finality icons), as
    /// templates to draw in white on the counter's color.
    var symbolImage: UIImage? {
        let asset: String
        switch self {
        case .stun: asset = "Icon_Stun"
        case .finality: asset = "Icon_Finality"
        case .prepared: asset = "Icon_Prepared"
        case .shield: asset = "Icon_Shield"
        default: return nil
        }
        let image = UIImage.resource(named: asset)
            // Stand-in until the prepared symbol asset is added.
            ?? (self == .prepared ? UIImage(systemName: "sparkles") : nil)
        return image?.withRenderingMode(.alwaysTemplate)
    }
}

extension Counter {
    /// The keyword's ability icon for menus (template, so it follows the menu's text color).
    var keywordMenuImage: UIImage? {
        guard case .counter(let icon)? = keywordIcon else { return nil }
        return icon.image?.withRenderingMode(.alwaysTemplate)
    }
}
