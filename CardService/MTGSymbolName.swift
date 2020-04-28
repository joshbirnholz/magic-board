//
//  SymbolName.swift
//  CardService
//
//  Created by Josh Birnholz on 3/9/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import UIKit

public enum MTGSymbolName: String, CaseIterable {
	case tap = "{T}"
	case symbol_Q = "{Q}"
	case symbol_E = "{E}"
	case symbol_PW = "{PW}"
//	case symbol_ARON = "{A}"
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

	public var image: UIImage {
		return UIImage(named: rawValue.replacingOccurrences(of: "/", with: "-"))!.withRenderingMode(.alwaysOriginal)
	}
}
