//
//  Swiftfall+Misc.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/15/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import Swiftfall

extension Swiftfall {
	
	enum BorderColor: String {
		case black
		case borderless
		case gold
		case silver
		case white
		
		var uiColor: UIColor {
			switch self {
			case .gold: return #colorLiteral(red: 0.6444242001, green: 0.5267884135, blue: 0.2910364866, alpha: 1)
			case .silver: return #colorLiteral(red: 0.6396835446, green: 0.6834098697, blue: 0.7172803283, alpha: 1)
			case .white: return .white
			case .black: return .black
			case .borderless: return .black
			}
		}
	}
	
	enum Color: String, CaseIterable {
		case white = "W"
		case blue = "U"
		case black = "B"
		case red = "R"
		case green = "G"
		case multicolor
		case artifact
		case colorless
		
		var name: String {
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
		
		var land: String? {
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
		
		var symbolColor: UIColor {
			return UIColor(named: "\(name) mana")!
		}
		
		var borderColor: UIColor {
			return UIColor(named: "\(name) border")!
		}
		
		var textBackgroundColor: UIColor {
			return UIColor(named: "\(name) background")!
		}
		
		var boxBackgroundColor: UIColor {
			return UIColor(named: "\(name) box background")!
		}
		
		var cardEdgeColor: UIColor {
			return UIColor(named: "\(name) edge")!
		}
		
	}
	
	enum SymbolName: String, CaseIterable {
		case symbol_T = "{T}"
		case symbol_Q = "{Q}"
		case symbol_E = "{E}"
		case symbol_PW = "{PW}"
		case symbol_CHAOS = "{CHAOS}"
		case symbol_X = "{X}"
		case symbol_Y = "{Y}"
		case symbol_Z = "{Z}"
		case symbol_0 = "{0}"
		case symbol_½ = "{½}"
		case symbol_1 = "{1}"
		case symbol_2 = "{2}"
		case symbol_3 = "{3}"
		case symbol_4 = "{4}"
		case symbol_5 = "{5}"
		case symbol_6 = "{6}"
		case symbol_7 = "{7}"
		case symbol_8 = "{8}"
		case symbol_9 = "{9}"
		case symbol_10 = "{10}"
		case symbol_11 = "{11}"
		case symbol_12 = "{12}"
		case symbol_13 = "{13}"
		case symbol_14 = "{14}"
		case symbol_15 = "{15}"
		case symbol_16 = "{16}"
		case symbol_17 = "{17}"
		case symbol_18 = "{18}"
		case symbol_19 = "{19}"
		case symbol_20 = "{20}"
		case symbol_100 = "{100}"
		case symbol_1000000 = "{1000000}"
		case symbol_INFINITE = "{∞}"
		case symbol_W_U = "{W/U}"
		case symbol_W_B = "{W/B}"
		case symbol_B_R = "{B/R}"
		case symbol_B_G = "{B/G}"
		case symbol_U_B = "{U/B}"
		case symbol_U_R = "{U/R}"
		case symbol_R_G = "{R/G}"
		case symbol_R_W = "{R/W}"
		case symbol_G_W = "{G/W}"
		case symbol_G_U = "{G/U}"
		case symbol_2_W = "{2/W}"
		case symbol_2_U = "{2/U}"
		case symbol_2_B = "{2/B}"
		case symbol_2_R = "{2/R}"
		case symbol_2_G = "{2/G}"
		case symbol_P = "{P}"
		case symbol_W_P = "{W/P}"
		case symbol_U_P = "{U/P}"
		case symbol_B_P = "{B/P}"
		case symbol_R_P = "{R/P}"
		case symbol_G_P = "{G/P}"
		case symbol_HW = "{HW}"
		case symbol_HR = "{HR}"
		case symbol_W = "{W}"
		case symbol_U = "{U}"
		case symbol_B = "{B}"
		case symbol_R = "{R}"
		case symbol_G = "{G}"
		case symbol_C = "{C}"
		case symbol_S = "{S}"

		var image: UIImage {
			return UIImage(named: rawValue.replacingOccurrences(of: "/", with: "-"))!.withRenderingMode(.alwaysOriginal)
		}
	}
}
