//
//  Icons.swift
//  CardView
//
//  Created by Josh Birnholz on 5/11/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation

extension MTGCardView {
	
	public enum IncludedIcons {
		case all
		case permanent
		case none
		
		fileprivate var defaultShowManaCost: Bool {
			return self == .all
		}
	}
	
  public static func properties(includedIcons: IncludedIcons, showManaCost: Bool? = nil, name: String?, manaCost: String?, typeLine: String?, oracleText: String?, colorInitials: [String]?, fullArt: Bool, borderColor: String, frame: String?, frameEffects: [String]?, power: String?, toughness: String?, loyalty: String?, layout: String, flavorName: String?, isAltFace: Bool, keywords: [String]?, securityStamp: String?, isCommander: Bool) -> MTGCardView.CardProperties {
    let showManaCost = showManaCost ?? includedIcons.defaultShowManaCost
    
    var properties = MTGCardView.CardProperties()
    
    properties.art = nil
    properties.name = name
    properties.flavorName = flavorName
    properties.oracleText = oracleText
    
    if showManaCost {
      properties.manaCost = manaCost?.replacingOccurrences(of: "//", with: "/")
    }
    
    let isPermanent = typeLine?.contains("Creature") == true || typeLine?.contains("Artifact") == true || typeLine?.contains("Enchantment") == true || typeLine?.contains("Land") == true || typeLine?.contains("Planeswalker") == true
    
    //		if !isPermanent {
    //			properties.typeLine = typeLine
    //		}
    
    if (typeLine?.lowercased() ?? "").contains("land") {
      let allColorLands = ["Fabled Passage", "Thriving Heath", "Thriving Isle", "Thriving Moor", "Thriving Grove", "Thriving Bluff", "Nykthos, Shrine to Nyx", "Lost Vale", "Prismatic Vista"]
      
      if allColorLands.contains(name ?? "") {
        properties.colors = MTGCardView.Color.allCases
      } else {
        properties.colors = MTGCardView.Color.allCases.compactMap {
          (oracleText ?? "").contains("{\($0.initial)}") ? $0 : nil
        }
        
        if properties.colors.isEmpty {
          let colorlessLands = ["Crumbling Vestige", "Gemstone Caverns"]
          
          if !colorlessLands.contains(name ?? "") && oracleText?.contains("any color") == true {
            properties.colors = MTGCardView.Color.allCases
          } else {
            let lands: [(String, MTGCardView.Color)] = [
              ("plains", .white),
              ("island", .blue),
              ("swamp", .black),
              ("mountain", .red),
              ("forest", .green)
            ]
            properties.colors = lands.compactMap { land, color in
              oracleText?.lowercased().contains(land) == true ? color : nil
            }
          }
        }
      }
    } else {
      properties.colors = colorInitials?.compactMap(MTGCardView.Color.init(initial:)) ?? []
    }
    
    properties.borderColor = MTGCardView.BorderColor(rawValue: borderColor) ?? .black
    
    if (fullArt && typeLine?.contains("Token") == false) || borderColor == "borderless" || frameEffects?.contains("extendedart") == true {
      properties.isFullArt = true
    }
    
    if (typeLine ?? "").contains("Card") {
      properties.isFullArt = true
      properties.colors = [.white, .blue, .black, .red, .green] // give it a gold border.
    }
    
    if frameEffects?.contains("inverted") == true || frameEffects?.contains("colorshifted") == true || (isAltFace && layout == "transform" && frameEffects?.contains("mooneldrazidfc") != true) || (isAltFace && layout == "modal_dfc") {
      properties.isInverted = true
    }
    
    if typeLine?.contains("Legendary") == true && securityStamp != "triangle" {
      if frameEffects?.contains("companion") == true {
        properties.overlay = .companion
      } else if frameEffects?.contains("nyxtouched") == true || typeLine?.lowercased().contains("enchantment") == true {
        properties.overlay = .nyxtouched
      }
    }
    
    if (typeLine?.lowercased() ?? "").contains("land") {
      if (typeLine?.lowercased() ?? "").contains("snow") {
        properties.backgroundStyle = .snowLand
      } else if securityStamp == "triangle" {
        properties.backgroundStyle = .universesBeyondLand
      } else {
        properties.backgroundStyle = .land
      }
    } else if frameEffects?.contains("nyxtouched") == true || typeLine?.lowercased().contains("enchantment") == true {
      if securityStamp == "triangle" {
        if (typeLine?.lowercased() ?? "").contains("artifact") {
          properties.backgroundStyle = .nyxtouchedUniversesBeyondArtifact
        } else {
          properties.backgroundStyle = .nyxtouchedUniversesBeyond
        }
      } else {
        if (typeLine?.lowercased() ?? "").contains("artifact") {
          properties.backgroundStyle = .nyxtouchedArtifact
        } else {
          properties.backgroundStyle = .nyxtouched
        }
      }
    } else if (typeLine?.lowercased() ?? "").contains("snow") {
      if (typeLine?.lowercased() ?? "").contains("artifact") {
        properties.backgroundStyle = .snowArtifact
      } else {
        properties.backgroundStyle = .snow
      }
    } else if securityStamp == "triangle" {
      if (typeLine?.lowercased() ?? "").contains("vehicle") {
        properties.backgroundStyle = .universesBeyondVehicle
      } else if (typeLine?.lowercased() ?? "").contains("artifact") {
        properties.backgroundStyle = .universesBeyondArtifact
      } else {
        properties.backgroundStyle = .universesBeyond
      }
    } else if (typeLine?.lowercased() ?? "").contains("vehicle") {
			properties.backgroundStyle = .vehicle
		} else if (typeLine?.lowercased() ?? "").contains("artifact") {
			properties.backgroundStyle = .artifact
		} else if (typeLine?.lowercased() ?? "").contains("planeswalker") || (typeLine?.lowercased() ?? "").contains("emblem") {
			properties.backgroundStyle = .planeswalker
		} else {
			properties.backgroundStyle = nil
		}
		
		let hybridSymbols: [MTGSymbolName] = [.symbol_W_U, .symbol_W_B, .symbol_B_R, .symbol_B_G, .symbol_U_B, .symbol_U_R, .symbol_R_G, .symbol_R_W, .symbol_G_W, .symbol_G_U]
		properties.isHybrid = hybridSymbols.contains(where: { symbol in manaCost?.contains(symbol.rawValue) == true })
		
		if (typeLine?.lowercased() ?? "").contains("token") || (typeLine ?? "").contains("Card") {
			properties.objectType = .token
		} else if (typeLine?.lowercased() ?? "").contains("emblem") {
			properties.objectType = .emblem
		}
		
    if frame == "1993" || frame == "1997" {
      properties.borderStyle = .retro
    } else if (typeLine?.lowercased() ?? "").contains("planeswalker") {
			properties.borderStyle = .planeswalker
			//				properties.borderStyle = .legendary
		} else if (typeLine?.lowercased() ?? "").contains("legendary") {
			properties.borderStyle = .legendary
		} else {
			properties.borderStyle = nil
		}
		
		properties.value = NSAttributedString(string: [power, toughness, loyalty].compactMap { $0 }.joined(separator: "/"))
		
		guard includedIcons != .none else {
			return properties
		}
		
//		if includedIcons == .all && typeLine?.lowercased().contains("instant") == true {
//			properties.icons = [.instant]
//		} else if includedIcons == .all && typeLine?.lowercased().contains("sorcery") == true {
//			properties.icons = [.sorcery]
//		} else if includedIcons == .all && typeLine?.lowercased().contains("enchantment") == true && typeLine?.lowercased().contains("creature") == false && typeLine?.lowercased().contains("artifact") == false {
//			properties.icons = [.enchantment]
//		}
		
		guard let oracleText = oracleText, (includedIcons != .none || isPermanent) && typeLine != "Card" && typeLine?.hasPrefix("Emblem") == false else {
			return properties
		}
		
		if layout == "adventure" && (typeLine?.contains("Instant") == true || typeLine?.contains("Sorcery") == true) && !properties.icons.contains(.adventure) {
			properties.icons.insert(.adventure, at: 0)
		}
		
		var shortenedAbilityText = oracleText
		
		// Remove parentheses
		for (fullMatch, _) in shortenedAbilityText.matches(forRegex: #"\(([^)]+)\)"#).reversed() {
			shortenedAbilityText.removeSubrange(fullMatch.range)
		}
		
		// Remove text in quotes.
		for (fullMatch, _) in shortenedAbilityText.matches(forRegex: #"["“]([^"”]+)["”]"#).reversed() {
			shortenedAbilityText.removeSubrange(fullMatch.range)
		}
		
		shortenedAbilityText = shortenedAbilityText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
		
		// Remove planeswalker loyalty abilities
		if typeLine?.lowercased().contains("planeswalker") == true {
			let matches = shortenedAbilityText.matches(forRegex: #"^(?:[+-−](?:\d|X)+?|0):.+$"#, options: .anchorsMatchLines)
			for match in matches.reversed() {
				//						shortenedAbilityText.removeSubrange(match.fullMatch.range)
				shortenedAbilityText = shortenedAbilityText.replacingOccurrences(of: match.fullMatch.value, with: "")
			}
		}
		
		if let name = name, let range = shortenedAbilityText.range(of: "\(name) can be your commander.") {
			shortenedAbilityText.removeSubrange(range)
		} else if let name = name, let index = name.firstIndex(of: ","), let range = shortenedAbilityText.range(of: "\(name[..<index]) can be your commander.") {
			shortenedAbilityText.removeSubrange(range)
		}
		
		var icons: OrderedSet<MTGCardView.Icon> = []
		
		var abilityRanges: [(MTGCardView.Icon, Range<String.Index>)] = MTGCardView.Icon.allCases.compactMap { icon in
			if let range = abilityTextRange(ability: icon, name: name, oracleText: shortenedAbilityText) {
				return (icon, range)
			}
			return nil
		}.sorted { $0.1.lowerBound < $1.1.lowerBound }
		
		if abilityRanges.contains(where: { $0.0 == .noattackorblock }) {
			abilityRanges.removeAll { $0.0 == .noattack || $0.0 == .noblock }
		}
		
		for (icon, range) in abilityRanges.reversed() {
			if !icon.has(style: .mention) && range.lowerBound >= shortenedAbilityText.startIndex && range.upperBound <= shortenedAbilityText.endIndex {
				shortenedAbilityText.removeSubrange(range)
			}
			
			guard includedIcons == .all || icon.isPermanentEffect else {
				continue
			}
			
			if icon == .noattackorblock {
				icons.insert(.noblock, at: 0)
				icons.insert(.noattack, at: 0)
			} else {
				icons.insert(icon, at: 0)
			}
		}
		
		// todo: make this not match tap abilities in text like: Enchanted creature has "{T}: Draw a card."
		for (fullMatch, _) in shortenedAbilityText.matches(forRegex: #"^.*\{T\}.*\: .+$"#, options: .anchorsMatchLines).reversed() {
			shortenedAbilityText.removeSubrange(fullMatch.range)
			
			// don't show the tap symbol for mana abilities of lands.
			if !icons.contains(.tap) && !(typeLine?.lowercased().contains("land") == true && (fullMatch.value.range(of: "add {", options: .caseInsensitive) != nil || !fullMatch.value.matches(forRegex: #"add \S+ mana of any color"#, options: .caseInsensitive).isEmpty)) {
				icons.insert(.tap, at: 0)
			}
		}
		
		if frameEffects?.contains("tombstone") == true {
			icons.insert(.tombstone, at: 0)
		}
		
		while let range = abilityTextRange(ability: MTGCardView.Icon.entersthebattlefield, name: name, oracleText: shortenedAbilityText) {
			shortenedAbilityText.removeSubrange(range)
		}
		
		shortenedAbilityText = shortenedAbilityText.replacingOccurrences(of: ",", with: "")
		
//		if !shortenedAbilityText.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: .punctuationCharacters).isEmpty && typeLine?.contains("Instant") == false && typeLine?.contains("Sorcery") == false && (typeLine?.contains("Creature") == false ) {
//			icons.append(.more)
//		}
		
		// Only do this if the keywords don't have "transform"
		if let keywords = keywords, !(layout == "transform" || layout == "modal_dfc" || keywords.contains("Transform") || layout == "adventure" ) {
			for keyword in keywords.reversed() {
				guard
					let icon = Icon.allCases.first(where: { $0.name?.lowercased() == keyword.lowercased() }),
					!icons.contains(icon)
				else { continue }
				
				if includedIcons == .all || (icon.isPermanentEffect && includedIcons == .permanent) {
					icons.insert(icon, at: 0)
				}
			}
		}
    
    if layout == "adventure" && !icons.contains(.adventure) {
      icons.insert(.adventure, at: 0)
    }
    
    if isCommander {
      icons.insert(.commander, at: 0)
    }
		
		properties.icons.append(contentsOf: icons)
		
    if frameEffects?.contains("sunmoondfc") == true {
      properties.dfcIcon = isAltFace ? .moon : .sun
    }
    
    if frameEffects?.contains("compasslanddfc") == true {
      properties.dfcIcon = isAltFace ? .land : .compass
    }
    
    if frameEffects?.contains("originpwdfc") == true {
      properties.dfcIcon = isAltFace ? .planeswalker : .origins
      properties.isInverted = false
    }
    
    if frameEffects?.contains("mooneldrazidfc") == true {
      properties.dfcIcon = isAltFace ? .eldrazi : .fullmoon
    } else if layout == "meld" {
      properties.dfcIcon = .eldrazi
    }
    
    if frameEffects?.contains("closedfanopenfandfc") == true {
      properties.dfcIcon = isAltFace ? .openfan : .closedfan
    }
    
    if frameEffects?.contains("specializeTree") == true {
      properties.dfcIcon = .specialize
    }
		
		if frameEffects?.contains("lesson") == true {
			properties.dfcIcon = .lesson
		}
    
    if frameEffects?.contains("dfcArrow") == true || layout == "transform" && properties.dfcIcon == nil {
      properties.dfcIcon = isAltFace ? .arrowDown : .arrow
    }
    
    if let frameEffects, frameEffects.contains("omen") {
      properties.icons.removeAll(where: { $0 == .adventure })
      properties.icons.insert(.omen, at: 0)
    }
		
		return properties
	}
	
	private static func abilityTextRange(ability: Icon, name: String?, oracleText: String) -> Range<String.Index>? {
		guard let abilityName = ability.name else { return nil }
		
		let oracleText: String = {
			var text = oracleText
			if let name = name {
				text = text.replacingOccurrences(of: name, with: "CARDNAME")
			}
			if let name = name, let index = name.firstIndex(of: ",") {
				let shortName = name[..<index]
				text = text.replacingOccurrences(of: shortName, with: "CARDNAME")
			}
			return text
		}()
		let name = name != nil ? "CARDNAME" : nil
		
		if ability.has(style: .from) {
			let regex = #"(?:^[^:\n]*?)(?:[.,] )*("# + abilityName + #" from [^,.\n]+)(?:[.,]|$)"#
			
			matches: for match in oracleText.matches(forRegex: regex, options: [.anchorsMatchLines, .caseInsensitive]) {
				let terms = ["has", "with", "gains", "have", "gain", "without"]
				let beginningOfLine = oracleText[..<match.groups[0].range.lowerBound].firstIndex(of: "\n") ?? oracleText.startIndex
				var linePrefix = String(oracleText[beginningOfLine ..< match.groups[0].range.lowerBound])
				
				if let index = linePrefix.lastIndex(of: "\n") {
					linePrefix = linePrefix[index...].trimmingCharacters(in: .newlines)
				}
				
				// TODO: In these if statements, change the lower bound to be the beginning of the line.
				if let name = name, linePrefix == "\(name) has " {
					return match.groups.first?.range
				}
				
				for term in terms {
					if linePrefix.contains(term + " ") {
						continue matches
					}
				}
				
				return match.groups.first?.range
			}
		}
		
		if ability.has(style: .forQuality) {
			let regex = #"(?:^[^:\n]*?)(?:[.,] )*("# + abilityName + #" for [^,.\n]+)(?:[.,]|$)"#
			
			matches: for match in oracleText.matches(forRegex: regex, options: [.anchorsMatchLines, .caseInsensitive]) {
				let terms = ["has", "with", "gains", "have", "gain", "without"]
				let beginningOfLine = oracleText[..<match.groups[0].range.lowerBound].firstIndex(of: "\n") ?? oracleText.startIndex
				var linePrefix = String(oracleText[beginningOfLine ..< match.groups[0].range.lowerBound])
				
				if let index = linePrefix.lastIndex(of: "\n") {
					linePrefix = linePrefix[index...].trimmingCharacters(in: .newlines)
				}
				
				// TODO: In these if statements, change the lower bound to be the beginning of the line.
				if let name = name, linePrefix == "\(name) has " {
					return match.fullMatch.range
				}
				
				for term in terms {
					if linePrefix.contains(term + " ") {
						continue matches
					}
				}
				
				return match.groups.first?.range
			}
		}
		
		if ability.has(style: .costDash) {
			if let range = oracleText.matches(forRegex: #"^"# + abilityName + #"—.+$"#, options: .anchorsMatchLines).first?.fullMatch.range {
				return range
			}
		}
		
		if ability.has(style: .abilityWord) || ability.has(style: .requirement) {
			if let range = oracleText.matches(forRegex: "^" + abilityName + " — .+$", options: .anchorsMatchLines).first?.fullMatch.range {
				return range
			}
		}
		
		if ability.has(style: .cost) {
			let regex = #"^\b"# + abilityName + #"\b (?:\{.+\})+.*$"#
			if let range = oracleText.matches(forRegex: regex, options: .anchorsMatchLines).first?.fullMatch.range {
				return range
			}
		}
		
		if ability.has(style: .keywordNumber) {
			let regex = #"^\b"# + abilityName + #"\b (?:[\dX])+.*$"#
			if let range = oracleText.matches(forRegex: regex, options: .anchorsMatchLines).first?.fullMatch.range {
				return range
			}
		}
		
		if ability.has(style: .mention) {
			if let range = oracleText.matches(forRegex: #"\b"# + abilityName + #"\b"#, options: .caseInsensitive).first?.fullMatch.range {
				return range
			}
		}
		
		if let name = name, ability.has(style: .creatureNameText) {
			let text: String = {
				switch ability {
				// "Can't attack" isn't checked here because that's really defender. It's not printed on cards.
				case .noblock: return "can(’|')t block"
				case .noattackorblock: return "can(’|')t attack or block"
				case .cantbeblocked: return "can(’|')t be blocked"
				case .mustattack: return "attacks each combat if able"
				case .entersthebattlefield: return "enters (?! or)(?!.+ leaves the battlefield)"
				default: return ""
				}
			}()
			if let range = oracleText.matches(forRegex: "^.*\(name) \(text).*$", options: .anchorsMatchLines).first?.fullMatch.range {
				return range
			}
		}
		
		if ability.has(style: .phraseAtStartOfLine) {
			let text: String = {
				switch ability {
				case .castingcostmodifier: return "This spell costs .+ to cast"
				case .whenyoucastthisspell: return "When you cast this spell"
				case .whenthiscreaturemutates: return "Whenever this creature mutates"
				default: return ""
				}
			}()
			
			if let range = oracleText.matches(forRegex: ".*" + text +  ".+", options: [.caseInsensitive, .anchorsMatchLines]).first?.fullMatch.range {
				return range
			}
		}
		
		if let name = name, ability.has(style: .phraseAtStartOfLineWithName) {
			let text: String = {
				switch ability {
				case .whenyoucycle: return "When you cycle CARDNAME"
				default: return ""
				}
			}()
			
			if let range = oracleText.matches(forRegex: ".*\(text.replacingOccurrences(of: "CARDNAME", with: name)).+", options: [.caseInsensitive, .anchorsMatchLines]).first?.fullMatch.range {
				return range
			}
		}
		
		guard ability.has(style: .keyword) else { return nil }
		
		let regex = #"(?:^[^:]*?)(?:[.,] )*(\b"# + abilityName + #"\b)(?:[., ]|$| \()"#
		
		matches: for match in oracleText.matches(forRegex: regex, options: [.anchorsMatchLines, .caseInsensitive]) {
			let terms = ["has", "with", "gains", "have", "gain", "without"]
			let beginningOfLine = oracleText[..<match.groups[0].range.lowerBound].firstIndex(of: "\n") ?? oracleText.startIndex
			let linePrefix = oracleText[beginningOfLine ..< match.groups[0].range.lowerBound]
			
			for term in terms {
				if linePrefix.contains(term + " ") {
					continue matches
				}
			}
			
			return match.groups.first?.range
		}
		
		return nil
	}
	
}
