//
//  Card.swift
//  CardService
//
//  Created by Josh Birnholz on 3/9/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import UIKit


public struct MTGCard: Codable, Equatable, Hashable {
	
	public func hash(into hasher: inout Hasher) {
		hasher.combine(self.scyfallID)
	}
	
	public enum BorderColor: String, Codable {
		case black
		case borderless
		case gold
		case silver
		case white
		
		public var uiColor: UIColor {
			switch self {
			case .gold: return #colorLiteral(red: 0.6444242001, green: 0.5267884135, blue: 0.2910364866, alpha: 1)
			case .silver: return #colorLiteral(red: 0.6396835446, green: 0.6834098697, blue: 0.7172803283, alpha: 1)
			case .white: return .white
			case .black: return .black
			case .borderless: return .black
			}
		}
	}
	
	public struct Face: Codable, Equatable, Hashable {
		public let typeLine: String?
		public let power: String?
		public let toughness: String?
		public let oracleText: String?
		public let flavorText: String?
		public let name: String?
		public let loyalty: String?
		public let manaCost: String?
		public let colors: [MTGColor]?
		
		var imageUris: [String: URL]?
	}
	
	public struct RelatedCard: Codable, Equatable, Hashable {
		public enum Component: String, Codable {
			case token
			case meldPart
			case meldResult
			case comboPiece
		}
		public let scryfallID: UUID
		public let component: Component?
		public let name: String
		public let typeLine: String?
		public let url: URL
	}
	
	public enum Language: String, Codable, Equatable, Hashable {
		case english = "en"
		case spanish = "es"
		case french = "fr"
		case german = "de"
		case italian = "it"
		case portuguese = "pt"
		case japanese = "ja"
		case korean = "ko"
		case russian = "ru"
		case simplifiedChinese = "zhs"
		case traditionalChinese = "zht"
		case hebrew = "he"
		case latin = "la"
		case ancientGreek = "grc"
		case arabic = "ar"
		case sanskrit = "sa"
		case phyrexian = "px"
	}
	
	public let scyfallID: UUID
	public let typeLine: String?
	public let power: String?
	public let toughness: String?
	public let oracleText: String?
	public let flavorText: String?
	public let name: String?
	public let loyalty: String?
	public let cardFaces: [Face]?
	public let convertedManaCost: Double?
	public let layout: String
	public let manaCost: String?
	public let scryfallURL: URL?
	public let borderColor: BorderColor?
	public let isFullArt: Bool
	public let allParts: [RelatedCard]?
	public let collectorNumber: String
	public let set: String
	public let colors: [MTGColor]?
	
	public let printedName: String?
	public let printedText: String?
	public let printedTypeLine: String?
	public let artist: String?
	
	public let isFoilAvailable: Bool
	public let isNonFoilAvailable: Bool
	
	public let language: Language
	public let releaseDate: Date?
	
	let imageUris: [String: URL]?
	
}

public extension MTGCard {
	var isBasicLand: Bool {
		(typeLine?.lowercased().contains("basic land") == true) || (typeLine?.lowercased().contains("basic snow land") == true)
	}
	
	var isLand: Bool {
		typeLine?.lowercased().contains("land") == true
	}
	
	var isFoil: Bool {
		if !isNonFoilAvailable { return true }
		return false
//		return isFoilAvailable && collectorNumber.hasSuffix("★")
	}
}
