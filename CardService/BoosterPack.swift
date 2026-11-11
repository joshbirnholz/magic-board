//
//  BoosterPack.swift
//  CardService
//
//  Created by Josh Birnholz on 5/14/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation

enum PackError: Int, Error {
	case wrongNumberOfCards
	case noImage
	case noValidPromo
	case notInBoosters
	case notEnoughLands
	case noCards
	case unsupported
	case noName
	case invalidURL
	case privateDeck
}

enum Mode {
	/// 1 basic land, 1 rare (or a mythic 1/8 of the time), 3 uncommons, the rest common
	case `default`
	/// Same as default, but gauarantees a planeswalker in every pack
	case warOfTheSpark
	case twoLands
	/// Ensures that between 5 and 10 cards in the back use the future frame.
	case futureSight
	/// 1 basic land, 1 rare, 2 uncommons, 6 commons
	case unglued
	///
	case alliancesChronicles
	/// Like default, but one common slot is replaced by any rarity double-faced card.
	case innistradDoubleFaced
	/// Like default, but one common slot is replaced by a common or uncommon double-faced card. In 1/8 packs, one additional common slot is replaced by a rare/mythic double-faced card.
	case shadowsOverInnistradDoubleFaced
	/// Showcase mutate commons/uncommons show up in 1/3 packs. Showcase rare/mythics show up in 2/29 packs.
	case ikoria
	
	case zendikarExpeditions
	case amonkhetInvocations
	case kaladeshInventions
	
	/// Basic land is replaced with a foil of any rarity, OR, except 1/53 packs, a Power Nine card
	case vintageMasters
}

fileprivate extension MTGCard {
	func partner<S: Sequence>(from cards: S) -> MTGCard? where S.Element == MTGCard {
		guard let allParts = allParts else { return nil }
		guard oracleText?.lowercased().contains("partner with") == true else { return nil }
		guard let part = allParts.first(where: { $0.component == .comboPiece }) else { return nil }
		return cards.first(where: { $0.scryfallID == part.scryfallID })
	}
	
	var hasPartner: Bool {
		return oracleText?.lowercased().contains("partner with") == true
	}
}

enum FoilPolicy {
	/// Foil cards appear 1 in 67 cards, or 22.5% chance in any one booster pack
	case pre2020
	/// Foil cards appear 1 in 45 cards, or 33.4% chance in any one booster pack
	case modern
	
	/// Foil cards appear in 52/53 booster packs
	case vintageMasters
	
	fileprivate var limit: Int {
		switch self {
		case .pre2020: return 225
		case .modern: return 334
		case .vintageMasters: return 981
		}
	}
}

// MARK: Process

struct ProcessedCards {
	var rarities: [MTGCard.Rarity: [MTGCard]]
	var customSlotRarities: [MTGCard.Rarity: [MTGCard]]
	/// The cards that should go into the basic land slot. Usually just basic lands, but not always.
	var basicLandsSlotCards: [MTGCard]
	var tokens: [MTGCard]
	var meldResults: [MTGCard]
	var showcaseRarities: [MTGCard.Rarity: [MTGCard]]
	var extendedArtCards: [MTGCard]
	var masterpieces: [MTGCard]
	/// Only Plains, Island, Swamp, Mountain, and Forest cards.
	var basicLands: [MTGCard]
}

fileprivate func process(cards: [MTGCard], setCode: String?, specialOptions: [String]) throws -> ProcessedCards {
	var mainCards = cards
	
	let basicLandSlotCards: [MTGCard] = { () -> [MTGCard] in
		switch setCode?.lowercased() {
		case "grn", "rna":
			return cards.filter { $0.typeLine?.lowercased().contains("gate") == true }
		case "dgm":
			return Swiftfall
				.getCards(query: "(set:rtr or set:gtc) type:land -type:basic")
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
		case "frf":
			return Swiftfall
				.getCards(query: "((set:ktk oracle:'search your library') or (set:frf oracle:'gain 1 life')) type:land")
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
		case "cns", "cn2":
			return cards.filter { $0.watermark == "conspiracy" }
		case "tsp":
			return Swiftfall
				.getCards(query: "is:timeshifted")
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
		case "emn":
			return Swiftfall
				.getCards(query: "set:soi type:'basic land'", unique: true)
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
		case "aer":
			return Swiftfall
				.getCards(query: "set:kld type:'basic land'", unique: true)
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
		case "ogw":
			return Swiftfall
				.getCards(query: "set:bfz type:'basic land'", unique: true)
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
				+ cards.filter { $0.typeLine?.lowercased().contains("basic") == true && $0.typeLine?.lowercased().contains("land") == true }
		case "bng", "jou":
			return Swiftfall
				.getCards(query: "set:ths type:'basic land'", unique: true)
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
		case "gtc":
			return Swiftfall
				.getCards(query: "set:rtr type:'basic land'", unique: true)
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
		case "dka":
			return Swiftfall
				.getCards(query: "set:isd type:'basic land'", unique: true)
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
		case "wwk":
			return Swiftfall
				.getCards(query: "set:zen type:'basic land'", unique: true)
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
		case "arb", "con":
			return Swiftfall
				.getCards(query: "set:ala type:'basic land'", unique: true)
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
		case "iko":
 			let basicLands = mainCards.separate { $0.typeLine?.lowercased().contains("basic") == true && $0.typeLine?.lowercased().contains("land") == true }
 			let dualLands = mainCards.separate { $0.typeLine?.lowercased().contains("land") == true && $0.oracleText?.contains("enters tapped") == true && $0.oracleText?.contains("gain 1 life") == true }
 			return basicLands + dualLands
		case "mir", "vis", "5ed", "por", "wth", "tmp", "sth", "exo", "p02", "usg", "ulg", "6ed", "ptk", "uds", "mmq", "nem", "pcy", "inv", "pls", "7ed", "csp", "dis", "gpt", "rav", "9ed", "lrw", "mor", "shm", "eve", "apc", "ody", "tor", "jud", "ons", "lgn", "scg", "mrd", "dst", "5dn", "chk", "bok", "sok", "plc":
			return []
		default:
			return mainCards.separate { $0.typeLine?.lowercased().contains("basic") == true && $0.typeLine?.lowercased().contains("land") == true }
		}
		}().filter { $0.isFoundInBoosters && !$0.isPromo }
	
	// Actual basic lands. Used when creating land packs
	let basicLands: [MTGCard] = {
		switch setCode?.lowercased() ?? "" {
		case "dgm":
			return Swiftfall
				.getCards(query: "(set:rtr or set:gtc) type:land type:basic", unique: true)
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
		case "cns", "cn2":
			return []
		// TODO: Find lands for conspiracy.
		case "thb":
			// Use regular, non-Nyx basic lands that aren't found in boosters for THB.
			return cards.filter { $0.typeLine?.lowercased().contains("basic") == true && $0.typeLine?.lowercased().contains("land") == true && !$0.isFoundInBoosters && !$0.isPromo }
		case "tsp",
			 _ where basicLandSlotCards.isEmpty:
			return cards.filter { $0.typeLine?.lowercased().contains("basic") == true && $0.typeLine?.lowercased().contains("land") == true && $0.isFoundInBoosters && !$0.isPromo }
		case "ogw":
			return basicLandSlotCards.filter { $0.name != "Wastes" }
		case _ where Set(basicLandSlotCards.filter { $0.typeLine?.hasPrefix("Basic Land —") == true }.compactMap({ $0.name })).count == 5:
			return basicLandSlotCards.filter { $0.typeLine?.hasPrefix("Basic Land —") == true }
		default:
			// Just get the most recent standard set basic lands if there are none others.
			return Swiftfall
			.getCards(query: "type='basic land –'", unique: false)
			.compactMap { $0?.data }
			.joined()
			.compactMap(MTGCard.init)
		}
	}()
	
	let additionalMainCards: [MTGCard] = try {
		switch setCode?.lowercased() {
		case "dgm":
			return Swiftfall
				.getCards(query: "(set:rtr or set:gtc) type:land oracle:'pay 2 life'")
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
		case "cmb1", "fmb1":
			// Add main mystery booster cards to convention/store set.
			return try Swiftfall
				.getSet(code: "mb1")
				.getCards()
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
		case "mb1":
			// Add foils to normal mystery booster set.
			return try Swiftfall
				.getSet(code: "fmb1")
				.getCards()
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
//		case "iko" where specialOptions.contains("c20partners"):
//			var cards = Swiftfall
//				.getCards(query: "set:c20 o:'partner with'")
//				.compactMap { $0?.data }
//				.joined()
//				.compactMap(MTGCard.init)
//			
//			for i in 0 ..< cards.count {
//				cards[i].isFoundInBoosters = true
//			}
//			return cards
		default:
			return []
		}
		}()
	
	mainCards.append(contentsOf: additionalMainCards)
	
	switch setCode?.lowercased() {
	case "iko":
		let godzillaSeriesCollectorNumbers = (364...387).map(String.init) + ["373A"]
		mainCards.removeAll { card in
			godzillaSeriesCollectorNumbers.contains(card.collectorNumber)
		}
	default:
		break
	}
	
	let showcases: [MTGCard.Rarity: [MTGCard]] = .init(grouping: mainCards.separate { $0.frameEffects?.contains("showcase") == true }, by: \.rarity)
	
	let extendedArt = mainCards.separate { $0.borderColor == .borderless || $0.frameEffects?.contains("extendedart") == true }
	
	let tokensAndEmblems = mainCards.separate {
		$0.typeLine?.lowercased().contains("token") == true || $0.typeLine?.lowercased().contains("emblem") == true
	}
	
	mainCards = mainCards.filter { $0.isFoundInBoosters && $0.language == .english && !$0.isPromo }
	
	guard mainCards.contains(where: { $0.isFoundInBoosters }) else {
		throw PackError.notInBoosters
	}
	
	let meldResults: [MTGCard] = mainCards.separate { card in
		guard card.layout == "meld", let parts = card.allParts else { return false }
		return parts.contains(where: { $0.component == .meldResult && $0.scryfallID == card.scryfallID }) == true
	}
	
	let customSlotRarities: [MTGCard.Rarity: [MTGCard]] = {
		switch setCode?.lowercased() {
		case "isd", "dka", "soi", "emn":
			return .init(grouping: mainCards.separate(by: { $0.layout == "transform" || $0.layout == "meld" }), by: \.rarity)
		case "war":
			return .init(grouping: mainCards.separate(by: { $0.typeLine?.lowercased().contains("planeswalker") == true }), by: \.rarity)
		case "vma":
			return .init(grouping: mainCards.separate { (1...9).contains(Int($0.collectorNumber) ?? 0) }, by: \.rarity)
		default:
			return [:]
		}
	}()
	
	let masterpieces: [MTGCard] = try {
		switch setCode?.lowercased() {
		case "bfz":
			return try Swiftfall
				.getSet(code: "exp")
				.getCards()
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
				.filter { (1...25).contains(Int($0.collectorNumber) ?? 0) }
		case "ogw":
			return try Swiftfall
				.getSet(code: "exp")
				.getCards()
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
				.filter { (26...45).contains(Int($0.collectorNumber) ?? 0) }
		case "kld":
			return try Swiftfall
				.getSet(code: "mps")
				.getCards()
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
				.filter { (1...30).contains(Int($0.collectorNumber) ?? 0) }
		case "aer":
			return try Swiftfall
				.getSet(code: "mps")
				.getCards()
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
				.filter { (31...54).contains(Int($0.collectorNumber) ?? 0) }
		case "akh":
			return try Swiftfall
				.getSet(code: "mp2")
				.getCards()
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
				.filter { (1...30).contains(Int($0.collectorNumber) ?? 0) }
		case "hou":
			return try Swiftfall
				.getSet(code: "mp2")
				.getCards()
				.compactMap { $0?.data }
				.joined()
				.compactMap(MTGCard.init)
				.filter { (31...54).contains(Int($0.collectorNumber) ?? 0) }
		default:
			return []
		}
	}()
	
	let rarities: [MTGCard.Rarity: [MTGCard]] = .init(grouping: mainCards, by: \.rarity)
	
	return ProcessedCards(rarities: rarities,
						  customSlotRarities: customSlotRarities,
						  basicLandsSlotCards: basicLandSlotCards,
						  tokens: tokensAndEmblems,
						  meldResults: meldResults,
						  showcaseRarities: showcases,
						  extendedArtCards: extendedArt,
						  masterpieces: masterpieces,
						  basicLands: basicLands)
}

public extension CardService {
	
	func generateBoosterPack(setCode: String, includeExtendedArt: Bool = true, specialOptions: [String] = []) throws -> [MTGCard] {
		
		let tokens: [MTGCard]
		var foilPolicy: FoilPolicy = .modern
		
		let mtgCards: [MTGCard] = CoreDataManager.shared.cards(setCode: setCode).map { $0.decodedMTGCard() }
		
		let tokenCutoff = Date(timeIntervalSince1970: 1184284800) // Only sets released after this date include tokens
		if let tokenSet = try? Swiftfall.getSet(code: "t\(setCode)"), let releaseDate = mtgCards.first?.releaseDate, releaseDate >= tokenCutoff {
			tokens = tokenSet.getCards().compactMap { $0?.data }.joined().compactMap(MTGCard.init)
		} else {
			tokens = []
		}
		
		if setCode.lowercased() == "vma" {
			foilPolicy = .vintageMasters
		} else {
			let foilCutoff = Date(timeIntervalSince1970: 1562889600) // Sets released after this date use the modern foil policy.
			if let releaseDate = mtgCards.first?.releaseDate, releaseDate < foilCutoff {
				foilPolicy = .pre2020
			}
		}
		
		guard !mtgCards.isEmpty else { throw PackError.noCards }
		
		let mode: Mode = {
			switch setCode.lowercased() {
			case "war": return .warOfTheSpark
			case "s99": return .twoLands
			case "fut": return .futureSight
			case "ugl": return .unglued
			case "all", "chr": return .alliancesChronicles
			case "isd", "dka": return .innistradDoubleFaced
			case "soi", "emn": return .shadowsOverInnistradDoubleFaced
			case "iko": return .ikoria
			case "akh", "hou": return .amonkhetInvocations
			case "bfz", "ogw": return .zendikarExpeditions
			case "kld", "aer": return .kaladeshInventions
			case "vma": return .vintageMasters
			default: return .default
			}
		}()
		
		return try boosterPack(cards: mtgCards, tokens: tokens, setCode: setCode, mode: mode, includeExtendedArt: includeExtendedArt, foilPolicy: foilPolicy, specialOptions: specialOptions)
	}
	
}

// MARK: Generation

fileprivate func boosterPack(cards: [MTGCard], tokens: [MTGCard], setCode: String?, mode: Mode, includeExtendedArt: Bool, foilPolicy: FoilPolicy, specialOptions: [String]) throws -> [MTGCard] {
	if setCode?.lowercased() == "mb1" || setCode?.lowercased() == "fmb1" || setCode?.lowercased() == "cmb1" {
		let cards = processMysteryBoosterCards(cards)
		return generateMysteryBooster(cards: cards)
	} else if setCode?.lowercased() == "plc" {
		let cards = processPlanarChaosCards(cards: cards)
		return generatePlanarChaosPack(normalRarities: cards.normalRarities, colorshiftedRarities: cards.colorshiftedRarities)
	}
	
	let processed = try process(cards: cards, setCode: setCode, specialOptions: specialOptions)
	
	return generatePack(rarities: processed.rarities,
							customSlotRarities: processed.customSlotRarities,
							basicLands: processed.basicLandsSlotCards,
							tokens: tokens + processed.tokens,
							showcaseRarities: processed.showcaseRarities,
							extendedArt: processed.extendedArtCards,
							meldResults: processed.meldResults,
							mode: mode,
							includeExtendedArt: includeExtendedArt,
							masterpieceCards: processed.masterpieces,
							foilPolicy: foilPolicy)
}

fileprivate func generatePack(rarities: [MTGCard.Rarity: [MTGCard]], customSlotRarities: [MTGCard.Rarity: [MTGCard]], basicLands: [MTGCard], tokens: [MTGCard], showcaseRarities: [MTGCard.Rarity: [MTGCard]], extendedArt: [MTGCard], meldResults: [MTGCard], mode: Mode, includeExtendedArt: Bool, masterpieceCards: [MTGCard], foilPolicy: FoilPolicy) -> [MTGCard] {
	var pack: [MTGCard] = []
	
	let guaranteedPlaneswalkerSlot = mode == .warOfTheSpark ? (0...3).randomElement()! : nil
	
	let landRarities: [MTGCard.Rarity: [MTGCard]]? = {
		guard Set(basicLands.map(\.rarity)).count > 1 else {
			return nil
		}
		
		return .init(grouping: basicLands, by: \.rarity)
	}()
	
	enum ShowcaseRarity {
		case random
		case commonUncommon
		case rareMythic
		
		var allowedRarities: Set<MTGCard.Rarity> {
			switch self {
			case .commonUncommon: return [.common, .uncommon]
			case .rareMythic: return [.rare, .mythic]
			case .random: return Set(MTGCard.Rarity.allCases)
			}
		}
	}
	
	let includeMythic = (1...8).randomElement()! == 8
	let includedShowcaseRarity: ShowcaseRarity? = {
		guard !showcaseRarities.values.joined().isEmpty else { return nil }
		
		if mode == .ikoria {
			if (1...29).randomElement()! <= 2 {
				return .rareMythic
			} else if (1...3).randomElement() == 1 {
				return .commonUncommon
			} else {
				return nil
			}
		} else {
			return (1...9).randomElement() == 9 ? .random : nil
		}
	}()
	let shouldIncludeRareMythicDoubleFaced = (1...8).randomElement()! == 8 // for shadowsOverInnistradDoubleFaced mode
	let includeMasterpiece: Bool = {
		guard !masterpieceCards.isEmpty else { return false }
		switch mode {
		case .amonkhetInvocations: return (1...129).randomElement() == 1
		case .kaladeshInventions: return (1...144).randomElement() == 1
		case .zendikarExpeditions: return (1...112).randomElement() == 1
		default: return false
		}
	}()
	let includedFoilRarity: MTGCard.Rarity? = {
		guard (1...1000).randomElement()! <= foilPolicy.limit else { return nil }
		
		let rarityValue = (1...1000).randomElement()!
		switch rarityValue {
		case 1...500: return .common
		case 1...833: return .uncommon
		case 1...979: return .rare
		default: return .mythic
		}
	}()
	
	var uniqueCardCount: Int { Set(pack.compactMap { $0.name }).count }
	var allColorsCount: Int { Set(pack.compactMap { $0.colors }.joined()).count }
	var showcaseOkay: Bool {
		guard let showcaseRarity = includedShowcaseRarity, !showcaseRarities.values.joined().isEmpty else {
			return true
		}
		
		// If the pack should contain a showcase, and there are showcase cards in the set,
		// ensure that the pack actually does contain a showcase card.
		return pack.contains(where: { $0.frameEffects?.contains("showcase") == true && showcaseRarity.allowedRarities.contains($0.rarity) })
	}
	var futureSightOkay: Bool {
		guard mode == .futureSight else { return true }
		let futureCount = pack.reduce(into: 0) { (count, card) in
			if card.frame == "future" {
				count += 1
			}
		}
		return (5...10).contains(futureCount)
	}
	
	let landRarity: MTGCard.Rarity = {
		switch (1...13).randomElement()! {
		case 1:
			if let mythics = landRarities?[.mythic], !mythics.isEmpty, (1...8).randomElement()! == 8 {
				return .mythic
			} else if let rares = landRarities?[.rare], !rares.isEmpty {
				return .rare
			} else {
				fallthrough
			}
		case 2, 3, 4:
			return .uncommon
		default:
			return .common
		}
	}()
	let landCount = mode == .twoLands ? 2 : 1
	
	let cardCount: Int = {
		var nonTokenCount: Int
		
		switch mode {
		case .unglued:
			nonTokenCount = 11
		case .alliancesChronicles:
			nonTokenCount = 14
		default:
			nonTokenCount = 16
		}
		
		if basicLands.isEmpty {
			nonTokenCount -= 1
		}
		
		if tokens.isEmpty {
			nonTokenCount -= 1
		}
		
		if mode == .vintageMasters {
			nonTokenCount += 1
		}
		
		return nonTokenCount
	}()
	
	repeat {
		pack.removeAll()
		
		let lands = landRarities?[landRarity]?.shuffled().prefix(landCount) ?? basicLands.shuffled().prefix(landCount)
		pack.insert(contentsOf: lands, at: 0)
		
		if includeMasterpiece, let masterpiece = masterpieceCards.randomElement() {
			pack.insert(masterpiece, at: 0)
		} /*else if let rarity = includedShowcaseRarity {
			let card: MTGCard? = {
				switch rarity {
				case .random:
					return showcaseRarities.values.joined().randomElement()
				case .commonUncommon:
					return [(showcaseRarities[.common] ?? []), (showcaseRarities[.uncommon] ?? [])].joined().randomElement()
				case .rareMythic:
					return [(showcaseRarities[.rare] ?? []), (showcaseRarities[.mythic] ?? [])].joined().randomElement()
				}
			}()
			if let showcase = card {
				pack.insert(showcase, at: 0)
			}
		} */else if let rarity = includedFoilRarity, let foil = [(rarities[rarity] ?? []), (customSlotRarities[rarity] ?? [])].joined().filter(\.isFoilAvailable).randomElement() {
			if includeExtendedArt, let extendedArtVersion = extendedArt.filter({ $0.name == foil.name }).randomElement() {
				pack.insert(extendedArtVersion, at: 0)
			} else if rarity != .common {
				pack.insert(foil, at: 0)
			}
		} else if mode == .vintageMasters, let powerNine = customSlotRarities.values.joined().randomElement() {
			// Vintage Masters packs that don't contain a foil card instead contain a Power Nine card.
			pack.insert(powerNine, at: 0)
		}
		
		let rareSlotRarities = guaranteedPlaneswalkerSlot == 3 ? customSlotRarities : rarities
		if includeMythic, let mythic = rareSlotRarities[.mythic]?.randomElement() {
			pack.insert(mythic, at: 0)
			
			if mythic.hasPartner, let partner = mythic.partner(from: rarities.values.joined()) {
				pack.insert(partner, at: 0)
			}
		} else if let rare = rareSlotRarities[.rare]?.randomElement() {
			pack.insert(rare, at: 0)
			
			if rare.hasPartner, let partner = rare.partner(from: rarities.values.joined()) {
				pack.insert(partner, at: 0)
			}
		}
		
		let uncommonCount: Int = {
			var base: Int = {
				switch mode {
				case .unglued:
					return 2
				default:
					return 3
				}
			}()
			
			if pack.contains(where: \.hasPartner) {
				base -= 1
			}
			
			return base
		}()
		
//		var uncommons = rarities[.uncommon]?.shuffled().prefix(uncommonCount) ?? []
		var uncommons: [MTGCard] = {
			var uncommons: [MTGCard] = []
			
			while uncommons.count < uncommonCount {
				var card: MTGCard
				
				var cardIsValid: Bool {
					if card.hasPartner && (pack.contains(where: \.hasPartner) || uncommons.contains(where: \.hasPartner)) {
						return false
					}
					return !uncommons.contains(card)
				}
				
				repeat {
					guard let uncommonCard = rarities[.uncommon]?.randomElement() else {
						return []
					}
					card = uncommonCard
				} while !cardIsValid
				
				uncommons.append(card)
				if let partner = card.partner(from: rarities.values.joined()) {
					uncommons.append(partner)
				}
			}
			
			while uncommons.count > uncommonCount {
				guard let index = uncommons.enumerated().compactMap({ $0.element.hasPartner ? nil : $0.offset }).randomElement() else { return [] }
				uncommons.remove(at: index)
			}
			
			return uncommons
		}()
		
		if let slot = guaranteedPlaneswalkerSlot, slot != 3, let uncommonPlaneswalker = customSlotRarities[.uncommon]?.randomElement() {
			uncommons[slot] = uncommonPlaneswalker
		}
		
		pack.insert(contentsOf: uncommons, at: 0)
		
		if mode == .innistradDoubleFaced, let doubleFaced = customSlotRarities.values.joined().randomElement() {
			pack.insert(doubleFaced, at: 0)
		}
		
		if mode == .shadowsOverInnistradDoubleFaced {
			if shouldIncludeRareMythicDoubleFaced {
				let rareOrMythicDoubleFacedCards = (customSlotRarities[.rare] ?? []) + (customSlotRarities[.mythic] ?? [])
				if let doubleFaced = rareOrMythicDoubleFacedCards.randomElement() {
					pack.insert(doubleFaced, at: 0)
				}
			}
			
			let commonOrUncommonDoubleFacedCards = (customSlotRarities[.common] ?? []) + (customSlotRarities[.uncommon] ?? [])
			if let doubleFaced = commonOrUncommonDoubleFacedCards.randomElement() {
				pack.insert(doubleFaced, at: 0)
			}
		}
		
		let commonCount: Int = {
			var count = cardCount-pack.count
			if !tokens.isEmpty {
				count -= 1
			}
			return count
		}()
		let commons = rarities[.common]?.shuffled().prefix(commonCount) ?? []
		pack.insert(contentsOf: commons, at: 0)
		
		// Tokens
		
		func tokensAreEqual(_ first: MTGCard, _ second: MTGCard) -> Bool {
			if first.oracleID == second.oracleID && first.oracleID != nil {
				return true
			}
			if first == second {
				return true
			}
			if first.name == second.name && first.typeLine == second.typeLine && first.colors == second.colors && first.oracleText == second.oracleText && first.power == second.power && first.toughness == second.toughness {
				return true
			}
			
			return false
		}
		
		if !tokens.isEmpty {
			var availableTokens: [MTGCard] = []
			
			let uniqueTokens: [MTGCard] = {
				var uniqueTokens: [MTGCard] = []
				
				for token in tokens {
					if !uniqueTokens.contains(where: { tokensAreEqual(token, $0) }) {
						uniqueTokens.append(token)
					}
				}
				
				return uniqueTokens
			}()
			
			for token in uniqueTokens {
				let cardsToLookAt: [MTGCard] = pack + pack.compactMap { card in
					guard let meldResultRelation = card.allParts?.first(where: { $0.scryfallID != card.scryfallID && $0.component == .meldResult } ),
						let meldResult = meldResults.first(where: { $0.scryfallID == meldResultRelation.scryfallID }) else {
						return nil
					}
					return meldResult
				}
				
				for card in cardsToLookAt {
					if card.allParts?.contains(where: { $0.scryfallID == token.scryfallID }) == true
						|| token.allParts?.contains(where: { $0.scryfallID == card.scryfallID }) == true {
						availableTokens.append(token)
					} /*else if token.name?.lowercased() == "on an adventure" && card.layout == "adventure" {
						availableTokens.append(token)
					} else if token.name?.lowercased() == "the monarch" && card.oracleText?.lowercased().contains("monarch") == true {
						availableTokens.append(token)
					} */else if let name = token.name?.lowercased(), card.oracleText?.contains(name) == true {
						availableTokens.append(token)
					} else if card.allParts?.contains(where: { $0.name == token.name }) == true {
						availableTokens.append(token)
					} else if token.allParts?.contains(where: { $0.name == card.name }) == true {
						availableTokens.append(token)
					}
				}
			}
			
			if availableTokens.isEmpty {
				availableTokens = tokens
			}
			
			if var token = availableTokens.randomElement() {
				token = tokens.shuffled().first(where: { tokensAreEqual(token, $0) })!
				
				// Add a second face to the token.
//				func removeEqualTokens() {
//					availableTokens.removeAll (where: {
//						tokensAreEqual($0, token)
//					})
//				}
//
//				removeEqualTokens()
//
//				if availableTokens.isEmpty {
//					availableTokens = tokens
//					removeEqualTokens()
//				}
//
//				if token.layout != "double_faced_token", var backSide = availableTokens.randomElement() {
//					backSide = tokens.shuffled().first(where: { tokensAreEqual(backSide, $0) })!
//
//					let frontFace = MTGCard.Face(typeLine: token.typeLine,
//												 power: token.power,
//												 toughness: token.toughness,
//												 oracleText: token.oracleText,
//												 flavorText: token.flavorText,
//												 name: token.name,
//												 loyalty: token.loyalty,
//												 manaCost: token.manaCost,
//												 colors: token.colors,
//												 imageUris: token.imageUris)
//					let altface = MTGCard.Face(typeLine: backSide.typeLine,
//											   power: backSide.power,
//											   toughness: backSide.toughness,
//											   oracleText: backSide.oracleText,
//											   flavorText: backSide.flavorText,
//											   name: backSide.name,
//											   loyalty: backSide.loyalty,
//											   manaCost: backSide.manaCost,
//											   colors: backSide.colors,
//											   imageUris: backSide.imageUris)
//					if var faces = token.cardFaces {
//						faces.append(altface)
//						token.cardFaces = faces
//					} else {
//						token.cardFaces = [frontFace, altface]
//					}
//					token.layout = "double_faced_token"
//				}
				
				pack.append(token)
			}
		}
		
		if let includedShowcaseRarity = includedShowcaseRarity {
			let showcaseCards: [(Int, MTGCard)] = pack.filter({ $0.frameEffects?.contains("extendedart") != true }).enumerated().compactMap { (index, card) in
				guard let showcaseCard = includedShowcaseRarity.allowedRarities.compactMap({ showcaseRarities[$0] }).joined().filter({ $0.name == card.name }).randomElement() else { return nil }

				guard includedShowcaseRarity.allowedRarities.contains(showcaseCard.rarity) else {
					return nil
				}

				return (index, showcaseCard)
			}

			if let (index, showcaseCard) = showcaseCards.randomElement() {
				pack[index] = showcaseCard
			}
		}
		
//		if includeExendedArt && !extendedArt.isEmpty {
//			let extendedArtCards: [(Int, MTGCard)] = pack.enumerated().compactMap { (index, card) in
//				guard let extendedArtCard = extendedArt.filter({ $0.name == card.name }).randomElement() else { return nil }
//				return (index, extendedArtCard)
//			}
//
//			if let (index, extendedArtCard) = extendedArtCards.randomElement() {
//				pack[index] = extendedArtCard
//			}
//		}
		
		var problems: [String] = []
		
		if allColorsCount != 5 {
			problems.append("Pack doesn't have 5 colors")
		}
		if uniqueCardCount != cardCount {
			problems.append("Card count is wrong; Should be \(cardCount), was \(uniqueCardCount)")
		}
		if !futureSightOkay {
			problems.append("Future sight isn't satisfied")
		}
		if !showcaseOkay {
			problems.append("No showcase card")
		}
		
		print(problems.joined(separator: ", "))
		
	} while allColorsCount != 5 || uniqueCardCount != cardCount || !futureSightOkay || !showcaseOkay
	
	print("Using pack")
	
	return pack
}

// MARK: Mystery Booster

enum MysterBoosterSlot: Hashable, Equatable {
	case monocolorCommonUncommon(MTGColor)
	case multicolorCommonUncommon
	case artifactLandCommonUncommon
	case preM15card
	case m15RareMythic
	case playtest
	case foil
}

func processMysteryBoosterCards(_ cards: [MTGCard]) -> [MysterBoosterSlot: [MTGCard]] {
	let additionalMainCards: [MTGCard] = {
		do {
			switch cards.first?.set.lowercased() {
			case "cmb1", "fmb1":
				// Add main mystery booster cards to convention/store set.
				return try Swiftfall.getSet(code: "mb1").getCards().compactMap { $0?.data }.joined().compactMap(MTGCard.init)
			case "mb1":
				// Add foils to normal mystery booster set.
				return try Swiftfall.getSet(code: "fmb1").getCards().compactMap { $0?.data }.joined().compactMap(MTGCard.init)
			default:
				return []
			}
		} catch {
			return []
		}
	}()
	
	let cards = cards + additionalMainCards
	
	return .init(grouping: cards) { card in
		if card.set == "cmb1" {
			return .playtest
		}
		
		if card.set == "fmb1" {
			return .foil
		}
		
		guard card.frame == "2015" else {
			return .preM15card
		}
		
		if (card.typeLine?.lowercased().contains("land") == true || card.typeLine?.lowercased().contains("artifact") == true) && (card.rarity == .common || card.rarity == .uncommon) {
			return .artifactLandCommonUncommon
		}
		
		if card.rarity == .rare || card.rarity == .mythic {
			return .m15RareMythic
		}
		
		// cards past here are 2015 frame and common/uncommon, and not lands or artifacts
		
		guard let colors = card.colors, colors.count == 1, let color = colors.first, color.rawValue.count == 1 else {
			return .multicolorCommonUncommon
		}
		
		return .monocolorCommonUncommon(color)
	}
}

func generateMysteryBooster(cards: [MysterBoosterSlot: [MTGCard]]) -> [MTGCard] {
	var pack: [MTGCard] = []
	
	var uniqueCardCount: Int { Set(pack.compactMap { $0.name }).count }
	var allColorsCount: Int { Set(pack.compactMap { $0.colors }.joined()).count }
	
	repeat {
		pack.removeAll()
		
		for color: MTGColor in [.white, .blue, .black, .red, .green] {
			let colorCommonUncommons = cards[.monocolorCommonUncommon(color)]?.shuffled().prefix(2) ?? []
			pack.append(contentsOf: colorCommonUncommons)
		}
		
		if let multicolorCommonUncommon = cards[.multicolorCommonUncommon]?.randomElement() {
			pack.append(multicolorCommonUncommon)
		}
		
		if let artifactLandCommonUncommon = cards[.artifactLandCommonUncommon]?.randomElement() {
			pack.append(artifactLandCommonUncommon)
		}
		
		if let preM15 = cards[.preM15card]?.randomElement() {
			pack.append(preM15)
		}
		
		if let m15RareMythic = cards[.m15RareMythic]?.randomElement() {
			pack.append(m15RareMythic)
		}
		
		if let playtestCard = cards[.playtest]?.randomElement() {
			pack.append(playtestCard)
		} else if let foil = cards[.foil]?.randomElement() {
			pack.append(foil)
		}
	} while allColorsCount != 5 || uniqueCardCount != 15
	
	
	return pack
}

// MARK: Planar Chaos

func processPlanarChaosCards(cards: [MTGCard]) -> (normalRarities: [MTGCard.Rarity: [MTGCard]], colorshiftedRarities: [MTGCard.Rarity: [MTGCard]]) {
	var colorshifted: [MTGCard] = []
	var normal: [MTGCard] = []
	
	for card in cards {
		if card.frameEffects?.contains("colorshifted") == true {
			colorshifted.append(card)
		} else {
			normal.append(card)
		}
	}
	
	return (.init(grouping: normal, by: \.rarity), .init(grouping: colorshifted, by: \.rarity))
}

func generatePlanarChaosPack(normalRarities: [MTGCard.Rarity: [MTGCard]], colorshiftedRarities: [MTGCard.Rarity: [MTGCard]]) -> [MTGCard] {
	var pack: [MTGCard] = []
	
	var uniqueCardCount: Int { Set(pack.compactMap { $0.name }).count }
	var allColorsCount: Int { Set(pack.compactMap { $0.colors }.joined()).count }
	
	repeat {
		pack.removeAll()
		
		if let commons = normalRarities[.common]?.shuffled().prefix(8) {
			pack.append(contentsOf: commons)
		}
		
		if let uncommons = normalRarities[.uncommon]?.shuffled().prefix(2) {
			pack.append(contentsOf: uncommons)
		}
		
		if let rare = normalRarities[.rare]?.randomElement() {
			pack.append(rare)
		}
		
		if let colorshiftedCommons = colorshiftedRarities[.common]?.shuffled().prefix(3) {
			pack.append(contentsOf: colorshiftedCommons)
		}
		
		if let colorshiftedUncommons = colorshiftedRarities[.uncommon], let colorshiftedRares = colorshiftedRarities[.rare] {
			let all = colorshiftedUncommons + colorshiftedRares
			if let colorshiftedUncommonOrRare = all.shuffled().randomElement() {
				pack.append(colorshiftedUncommonOrRare)
			}
		}
	} while allColorsCount != 5 || uniqueCardCount != 15
	
	return pack
}
