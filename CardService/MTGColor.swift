//
//  MTGColor.swift
//  CardService
//
//  Created by Josh Birnholz on 3/9/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import UIKit

public extension Array where Element == MTGColor {
	var ordered: [MTGColor] {
		switch Set(self) {
		case [.white, .blue]: return [.white, .blue]
		case [.blue, .black]: return [.blue, .black]
		case [.black, .red]: return [.black, .red]
		case [.red, .green]: return [.red, .green]
		case [.green, .white]: return [.green, .white]
		case [.white, .black]: return [.white, .black]
		case [.blue, .red]: return [.blue, .red]
		case [.black, .green]: return [.black, .green]
		case [.red, .white]: return [.red, .white]
		case [.green, .blue]: return [.green, .blue]
		case [.red, .green, .white]: return [.red, .green, .white]
		case [.blue, .black, .red]: return [.blue, .black, .red]
		default: break
		}
		
		return self.sorted {
			switch ($0.orderNumber, $1.orderNumber) {
			case (let first?, let second?): return first < second
			case (.some, nil): return true
			case (nil, .some): return false
			case (nil, nil): return true
			}
		}
	}
}

public enum MTGColor: String, Codable, CaseIterable, Hashable {
	case white = "W"
	case blue = "U"
	case black = "B"
	case red = "R"
	case green = "G"
	case multicolor
	case artifact
	case colorless
	
	public var name: String {
		switch self {
		case .white:
			return "white"
		case .blue:
			return "blue"
		case .black:
			return "black"
		case .red:
			return "red"
		case .green:
			return "green"
		case .multicolor:
			return "multicolor"
		case .artifact:
			return "artifact"
		case .colorless:
			return "colorless"
		}
	}
	
	public var initial: String {
		return String(rawValue.first!)
	}
	
	public var orderNumber: Int? {
		switch self {
		case .white: return 0
		case .blue: return 1
		case .black: return 2
		case .red: return 3
		case .green: return 4
		default: return nil
		}
	}
	
	public var land: String? {
		switch self {
		case .white:
			return "plains"
		case .blue:
			return "island"
		case .black:
			return "swamp"
		case .red:
			return "mountain"
		case .green:
			return "forest"
		case .multicolor:
			return nil
		case .artifact:
			return nil
		case .colorless:
			return "wastes"
		}
	}
	
	public init?(landName: String) {
		for color in MTGColor.allCases where color.land == landName.lowercased() {
			self = color
			return
		}
		return nil
	}
	
	public var textBackgroundColor: UIColor {
		return UIColor(named: "textbox-\(rawValue.first!.lowercased())")!
	}
	
	public static func colors(for card: MTGCard) -> [MTGColor] {
		var colors: [MTGColor] = []
		
		if (card.typeLine?.lowercased() ?? "").contains("land") {
			colors = MTGColor.allCases.compactMap {
				(card.oracleText ?? "").contains("{\($0.initial)}") ? $0 : nil
			}
			
			if colors.isEmpty {
				let colorlessLands = ["Crumbling Vestige", "Gemstone Caverns"]
				let allColorLands = ["Fabled Passage"]
				if(allColorLands.contains(card.name ?? "") || !colorlessLands.contains(card.name ?? "") && card.oracleText?.contains("any color") == true) {
					colors = [.white, .blue, .black, .red, .green]
				} else {
					let lands: [(String, MTGColor)] = [
						("plains", .white),
						("island", .blue),
						("swamp", .black),
						("mountain", .red),
						("forest", .green)
					]
					colors = lands.compactMap { land, color in
						card.oracleText?.lowercased().contains(land) == true ? color : nil
					}
				}
			}
			
		} else {
			colors = card.colors ?? []
		}
		
		return colors
	}
	
}
