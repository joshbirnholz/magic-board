//
//  DeckParser.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/20/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import ReerJSON

enum Deck {
	case arena(String)
	case deckstats(String)
	case moxfield(MoxfieldDeck)
	case archidekt(ArchidektDeck)
}

public struct ArchidektDeck: Decodable, Sendable {
  struct CardInfo: Decodable {
    struct Card: Decodable {
      struct Edition: Decodable {
        let editioncode: String
      }
      struct OracleCard: Decodable {
        let name: String
      }
      let uid: UUID?
      let edition: Edition
      let collectorNumber: String
      let oracleCard: OracleCard
    }
    let card: Card
    let quantity: Int
    let categories: [String]
    
    var cardCount: DeckParser.CardCount {
      if let id = card.uid {
        return DeckParser.CardCount(identifier: .idName(id, card.oracleCard.name), count: quantity)
      } else {
        return DeckParser.CardCount(identifier: .nameSet(name: card.oracleCard.name, set: card.edition.editioncode), count: quantity)
      }
    }
  }

  struct CustomCardInfo: Decodable {
    struct CustomCard: Decodable {
      let setCode: String?
      let collectorNumber: String?
      let frontName: String
      let frontImageUrl: URL?
      let hasBack: Bool
      let backName: String?
      let backImageUrl: URL?
    }

    let card: CustomCard
    let categories: [String]
    let quantity: Int

    var cardCount: DeckParser.CardCount {
      if let setCode = card.setCode, let collectorNumber = card.collectorNumber {
        return DeckParser.CardCount(identifier: .collectorNumberSet(collectorNumber: collectorNumber, set: setCode, name: card.frontName), count: quantity, alter: card.frontImageUrl)
      } else if let setCode = card.setCode {
        return DeckParser.CardCount(identifier: .nameSet(name: card.frontName, set: setCode), count: quantity, alter: card.frontImageUrl)
      } else {
        return DeckParser.CardCount(identifier: .name(card.frontName), count: quantity, alter: card.frontImageUrl)
      }
    }
  }

  struct Category: Decodable {
    let id: Int
    let name: String
    let includedInDeck: Bool
    let isPremier: Bool
  }

  let name: String
  let cards: [CardInfo]
  let customCards: [CustomCardInfo]
  let categories: [Category]
}

public struct MoxfieldDeck: Decodable {
	struct CardInfo: Decodable {
		struct Card: Decodable {
			let scryfallID: UUID?
			let set: String
			let name: String
		}
		let quantity: Int
		let card: Card
		
		var cardCount: DeckParser.CardCount {
			if let id = card.scryfallID {
				return DeckParser.CardCount(identifier: .id(id), count: quantity)
			} else {
				return DeckParser.CardCount(identifier: .nameSet(name: card.name, set: card.set), count: quantity)
			}
		}
	}
	
	let id: String
	let name: String
	let mainboard: [String: CardInfo]
	let sideboard: [String: CardInfo]?
	let commanders: [String: CardInfo]?
	let maybeboard: [String: CardInfo]?
}

public struct DeckParser {
	public struct CardGroup {
		public enum GroupName: String {
			case deck = "Deck"
			case sideboard = "Sideboard"
			case command = "Commander"
			case companion = "Companion"
			case maybeboard = "Maybeboard"
		}
		
		public static func name(for line: String, defaultToMain: Bool = false) -> String {
			switch line.lowercased() {
			case "deck", "main deck", "maindeck", "main", "creatures", "creature", "instant", "instants", "land", "lands", "sorceries", "sorcery", "spell", "spells", "enchantment", "enchantments", "artifact", "artifacts": return GroupName.deck.rawValue
			case "sideboard", "", "\n": return GroupName.sideboard.rawValue
			case "commander", "command": return GroupName.command.rawValue
			case "companion": return GroupName.companion.rawValue
			case "maybe", "maybeboard": return GroupName.maybeboard.rawValue
			case _ where defaultToMain: return GroupName.deck.rawValue
			default:
				return line
			}
		}
		
		public var name: String?
		public var cardCounts: [CardCount]
	}
	
	public struct CardCount: Hashable, Equatable {
		public var identifier: MTGCardIdentifier
		public var count: Int
		public var alter: URL?
	}
	
	static let fixedSetCodes: [String: String] = [
		"1e": "lea",
		"2e": "leb",
		"an": "arn",
		"aq": "atq",
		"3d": "3ed",
		"le": "leg",
		"dk": "drk",
		"fe": "fem",
		"4e": "4ed",
		"ia": "ice",
		"ch": "chr",
		"hm": "hml",
		"al": "all",
		"mi": "mir",
		"vi": "vis",
		"5e": "5ed",
		"po": "por",
		"wl": "wth",
		"te": "tmp",
		"st": "sth",
		"ex": "exo",
		"p2": "p02",
		"ug": "ugl",
		"uz": "usg",
		"ul": "ulg",
		"6e": "6ed",
		"pk": "ptk",
		"ud": "uds",
		"p3": "s99",
		"mm": "mmq",
		"ne": "nem",
		"pr": "pcy",
		"in": "inv",
		"ps": "pls",
		"7e": "7ed",
		"ap": "apc",
		"od": "ody",
		"dar": "dom",
		"pwp21": "pw21"
	]
	
	private static func fixSetCodes(_ cardGroups: inout [CardGroup]) {
		cardGroups = cardGroups.map { group in
			var group = group
			
			group.cardCounts = group.cardCounts.map { cardCount in
				var cardCount = cardCount
				
				switch cardCount.identifier {
				case .nameSet(name: let name, set: let set):
					if let fixedSet = DeckParser.fixedSetCodes[set.lowercased()] {
						cardCount.identifier = .nameSet(name: name, set: fixedSet)
					}
				case .collectorNumberSet(collectorNumber: let collectorNumber, set: let set, name: let name):
					if let fixedSet = DeckParser.fixedSetCodes[set.lowercased()] {
						cardCount.identifier = .collectorNumberSet(collectorNumber: collectorNumber, set: fixedSet, name: name)
					}
				default:
					break
				}
				
				return cardCount
			}
			
			return group
		}
	}
	
	public static func parse(deckList: String, autofix: Bool) -> [CardGroup] {
		var deckList = deckList.replacingOccurrences(of: "\r", with: "")
		
		var commanderLines: [String] = []
		
		if let range = deckList.range(of: "\n\n") {
			deckList.replaceSubrange(range, with: "\n\nSideboard\n")
		}
		
		var lines: [String] = deckList
			.components(separatedBy: .newlines)
			.compactMap {
				var line = $0
				if line.hasPrefix("//"), let range = line.range(of: "//") {
					line.removeSubrange(range)
				}
				
				let isCommander = line.contains("!Commander")
				
				guard !isCommander else {
					commanderLines.append(line)
					return nil
				}
				
				line = line.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !line.isEmpty else { return nil }
				
				return line
		}
		
		if !commanderLines.isEmpty {
			commanderLines.insert("Commander", at: 0)
			lines.insert(contentsOf: commanderLines, at: 0)
		}
		
		deckList = lines.joined(separator: "\n")
		
		let regex = #"^(?:(?:\/\/)?(\S*)\s*$|\s*(\d+)\s+([^\(\n]+\S)(?:\s*|\s+\(\s*(\S*)\s*\)(?:\h+(\S+)\s*|\s*)))$"#
		
		let matches = deckList.matches(forRegex: regex, options: [.anchorsMatchLines])
		var cardGroups: [CardGroup] = []
		
		for (_, groups) in matches {
			switch groups.count {
			case 1:
				let value = groups[0].value.trimmingCharacters(in: .whitespacesAndNewlines)
				let newGroup = CardGroup(name: CardGroup.name(for: value, defaultToMain: true), cardCounts: [])
				cardGroups.append(newGroup)
			case 2:
				if cardGroups.isEmpty {
					let newGroup = CardGroup(name: cardGroups.isEmpty ? CardGroup.GroupName.deck.rawValue : nil, cardCounts: [])
					cardGroups.append(newGroup)
				}
				
				let count = groups[0].value
				let name: String = {
					let value = groups[1].value
					if let index = value.lastIndex(of: "#") {
						return String(value.prefix(upTo: index)).trimmingCharacters(in: .whitespacesAndNewlines)
					} else {
						return value
					}
				}()
				guard let number = Int(count) else { continue }
				let cardCount = CardCount(identifier: .name(name), count: number)
				cardGroups[cardGroups.count-1].cardCounts.append(cardCount)
			case 3:
				if cardGroups.isEmpty {
					let newGroup = CardGroup(name: cardGroups.isEmpty ? CardGroup.GroupName.deck.rawValue : nil, cardCounts: [])
					cardGroups.append(newGroup)
				}
				
				let count = groups[0].value
				let name: String = {
					let value = groups[1].value
					if let index = value.lastIndex(of: "#") {
						return String(value.prefix(upTo: index)).trimmingCharacters(in: .whitespacesAndNewlines)
					} else {
						return value
					}
				}()
				let set = groups[2].value
				
				guard let number = Int(count) else { continue }
				
				if autofix && set.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
					let cardCount = CardCount(identifier: .name(name), count: number)
					cardGroups[cardGroups.count-1].cardCounts.append(cardCount)
				} else {
					let cardCount = CardCount(identifier: .nameSet(name: name, set: set), count: number)
					cardGroups[cardGroups.count-1].cardCounts.append(cardCount)
				}
			case 4:
				if cardGroups.isEmpty {
					let newGroup = CardGroup(name: cardGroups.isEmpty ? CardGroup.GroupName.deck.rawValue : nil, cardCounts: [])
					cardGroups.append(newGroup)
				}
				
				let count = groups[0].value
				let name: String = {
					let value = groups[1].value
					if let index = value.lastIndex(of: "#") {
						return String(value.prefix(upTo: index)).trimmingCharacters(in: .whitespacesAndNewlines)
					} else {
						return value
					}
				}()
				let set = groups[2].value
				let collectorNumber = groups[3].value
				
				guard let number = Int(count) else { continue }
				
				if autofix && set.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
					let cardCount = CardCount(identifier: .name(name), count: number)
					cardGroups[cardGroups.count-1].cardCounts.append(cardCount)
				} else {
					let cardCount = CardCount(identifier: .collectorNumberSet(collectorNumber: collectorNumber, set: set, name: name), count: number)
					cardGroups[cardGroups.count-1].cardCounts.append(cardCount)
				}
			default:
				break
			}
		}
		
		// Merge groups with the same names
		cardGroups = cardGroups.reduce([], { partialResult, currentGroup in
			guard !currentGroup.cardCounts.isEmpty else { return partialResult }
			
			var partialResult = partialResult
			
			if let existingGroupIndex = partialResult.firstIndex(where: { $0.name == currentGroup.name }) {
				partialResult[existingGroupIndex].cardCounts.append(contentsOf: currentGroup.cardCounts)
			} else {
				partialResult.append(currentGroup)
			}
			
			return partialResult
		})
		
		fixSetCodes(&cardGroups)
		return cardGroups
	}
	
	public static func parse(deckstatsDecklist: String) -> [CardGroup] {
		let regex = #"(?:^\/\/(\S+)$|^([0-9]+) (?:\[(.+)\] (.+)$|(.+)$))|(.+$)"#
		
		var commanderLines: [String] = []
		
		var lines: [String] = deckstatsDecklist
			.components(separatedBy: .newlines)
			.compactMap {
				var line = $0
				if line.hasPrefix("//"), let range = line.range(of: "//") {
					line.removeSubrange(range)
				}
				
				if line.hasPrefix("SB: "), let range = line.range(of: "SB: ") {
					line.removeSubrange(range)
				}
				
				let isCommander = line.contains("!Commander")
				
				guard !isCommander else {
					commanderLines.append(line)
					return nil
				}
				
				line = line.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !line.isEmpty else { return nil }
				
				return line
		}
		
		if !commanderLines.isEmpty {
			commanderLines.insert("Commander", at: 0)
			lines.insert(contentsOf: commanderLines, at: 0)
		}
		
		let deckList = lines.joined(separator: "\n")
		
		let matches = deckList.matches(forRegex: regex, options: [.anchorsMatchLines])
		var cardGroups: [CardGroup] = []
		
		for (_, groups) in matches {
			switch groups.count {
			case 1:
				let value = groups[0].value.trimmingCharacters(in: .whitespacesAndNewlines)
				let newGroup = CardGroup(name: CardGroup.name(for: value, defaultToMain: true), cardCounts: [])
				cardGroups.append(newGroup)
			case 2:
				if cardGroups.isEmpty {
					let newGroup = CardGroup(name: cardGroups.isEmpty ? CardGroup.GroupName.deck.rawValue : nil, cardCounts: [])
					cardGroups.append(newGroup)
				}
				
				let count = groups[0].value
				var alterURL: URL?
				let name: String = {
					var value = groups[1].value
					if let index = value.firstIndex(of: "<") {
						value.removeSubrange(index...)
						value = value.trimmingCharacters(in: .whitespacesAndNewlines)
					}
					
					if let index = value.lastIndex(of: "#") {
						let commentIndex = value.index(after: index)
						if value.indices.contains(commentIndex) {
							let comment = String(value.suffix(from: commentIndex)).trimmingCharacters(in: .whitespacesAndNewlines)
							let commentComponents = comment.components(separatedBy: .whitespacesAndNewlines)
							alterURL = commentComponents.first(where: {
								guard let url = URL(string: $0), ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) else { return false }
								return true
							}).flatMap(URL.init(string:))
						}
						return String(value.prefix(upTo: index)).trimmingCharacters(in: .whitespacesAndNewlines)
					} else {
						return value
					}
				}()
				guard let number = Int(count) else { continue }
				var cardCount = CardCount(identifier: .name(name), count: number)
				cardCount.alter = alterURL
				cardGroups[cardGroups.count-1].cardCounts.append(cardCount)
			case 3:
				if cardGroups.isEmpty {
					let newGroup = CardGroup(name: cardGroups.isEmpty ? CardGroup.GroupName.deck.rawValue : nil, cardCounts: [])
					cardGroups.append(newGroup)
				}
				
				let count = groups[0].value
				var alterURL: URL?
				let name: String = {
					var value = groups[2].value
					if let index = value.firstIndex(of: "<") {
						value.removeSubrange(index...)
						value = value.trimmingCharacters(in: .whitespacesAndNewlines)
					}
					
					if let index = value.lastIndex(of: "#") {
						let commentIndex = value.index(after: index)
						if value.indices.contains(commentIndex) {
							let comment = String(value.suffix(from: commentIndex)).trimmingCharacters(in: .whitespacesAndNewlines)
							let commentComponents = comment.components(separatedBy: .whitespacesAndNewlines)
							alterURL = commentComponents.first(where: {
								guard let url = URL(string: $0), ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) else { return false }
								return true
							}).flatMap(URL.init(string:))
						}
						return String(value.prefix(upTo: index)).trimmingCharacters(in: .whitespacesAndNewlines)
					} else {
						return value
					}
				}()
				
				let setComponents = groups[1].value.components(separatedBy: "#")
				
				let set = setComponents[0]
				
				guard let number = Int(count) else { continue }
				var cardCount: CardCount
				
				if setComponents.count > 1, let collectorNumber = setComponents.last {
					cardCount = CardCount(identifier: .collectorNumberSet(collectorNumber: collectorNumber, set: set, name: name), count: number)
				} else {
					cardCount = CardCount(identifier: .nameSet(name: name, set: set), count: number)
				}
				
				cardCount.alter = alterURL
				cardGroups[cardGroups.count-1].cardCounts.append(cardCount)
			default:
				break
			}
		}
		
		// Merge groups with the same names
		cardGroups = cardGroups.reduce([], { partialResult, currentGroup in
			guard !currentGroup.cardCounts.isEmpty else { return partialResult }
			
			var partialResult = partialResult
			
			if let existingGroupIndex = partialResult.firstIndex(where: { $0.name == currentGroup.name }) {
				partialResult[existingGroupIndex].cardCounts.append(contentsOf: currentGroup.cardCounts)
			} else {
				partialResult.append(currentGroup)
			}
			
			return partialResult
		})
		
		fixSetCodes(&cardGroups)
		return cardGroups
	}
	
	public static func parse(moxfieldDeck: MoxfieldDeck) -> [CardGroup] {
		var groups: [CardGroup] = []
		
		let cardInfos = Array(moxfieldDeck.mainboard.values).sorted(by: { $0.card.name < $1.card.name })
		
		let counts: [CardCount] = cardInfos.map(\.cardCount)
		groups.append(CardGroup(name: CardGroup.GroupName.deck.rawValue, cardCounts: counts))
		
		if let commanders = moxfieldDeck.commanders {
			let commanderCardCounts = commanders.values.map(\.cardCount)
			groups.append(CardGroup(name: CardGroup.GroupName.command.rawValue, cardCounts: commanderCardCounts))
		}
		
		if let sideboard = moxfieldDeck.sideboard {
			let counts: [CardCount] = sideboard.values.map(\.cardCount)
			groups.append(CardGroup(name: CardGroup.GroupName.sideboard.rawValue, cardCounts: counts))
		}
		
		fixSetCodes(&groups)
		return groups
	}
	
  public static func parse(archidektDeck: ArchidektDeck) -> [CardGroup] {
    var groups: [CardGroup] = []
    let excludedCategories: Set<String> = Set(archidektDeck.categories.compactMap { $0.includedInDeck ? nil : $0.name })
    let commanderCategories: Set<String> = Set(archidektDeck.categories.compactMap { $0.isPremier ? $0.name : nil })
    
    var cards = archidektDeck.cards.sorted { $0.card.oracleCard.name < $1.card.oracleCard.name }
    var customCards = archidektDeck.customCards.sorted { $0.card.frontName < $1.card.frontName }

    let commanderCards = cards.separate { $0.categories.contains(where: { cat in commanderCategories.contains(cat) }) }
    let commanderCustomCards = customCards.separate { $0.categories.contains(where: { cat in commanderCategories.contains(cat) }) }
    let sideboardCards = cards.separate { $0.categories.contains("Sideboard") }
    let sideboardCustomCards = customCards.separate { $0.categories.contains("Sideboard") }
    
    cards.removeAll { card in card.categories.contains { excludedCategories.contains($0) } }
    customCards.removeAll { card in card.categories.contains { excludedCategories.contains($0) } }
    
    groups.append(CardGroup(name: CardGroup.GroupName.deck.rawValue, cardCounts: cards.map(\.cardCount) + customCards.map(\.cardCount)))
    
    if !commanderCards.isEmpty || !commanderCustomCards.isEmpty {
      groups.append(CardGroup(name: CardGroup.GroupName.command.rawValue, cardCounts: commanderCards.map(\.cardCount) + commanderCustomCards.map(\.cardCount)))
    }
    
    if !sideboardCards.isEmpty || !sideboardCustomCards.isEmpty {
      groups.append(CardGroup(name: CardGroup.GroupName.sideboard.rawValue, cardCounts: sideboardCards.map(\.cardCount) + sideboardCustomCards.map(\.cardCount)))
    }
    
    return groups
  }
}

extension DeckParser {
	public static func load(fromURL deckURL: URL) async throws -> [CardGroup] {
		guard let components = URLComponents(url: deckURL, resolvingAgainstBaseURL: false) else {
			throw PackError.invalidURL
		}
		
		switch components.host {
		case "www.archidekt.com", "archidekt.com":
			guard deckURL.pathComponents.count >= 2, deckURL.pathComponents[1] == "decks", let decklistURL = URL(string: "https://archidekt.com/api/decks/\(deckURL.pathComponents[2])/") else {
				throw PackError.invalidURL
			}
			
			let request = URLRequest(url: decklistURL, cachePolicy: .reloadIgnoringLocalCacheData)
			let data = try await URLSession.shared.data(from: request).data
			
			let decoder = ReerJSONDecoder()
			let archidektDeck = try decoder.decode(ArchidektDeck.self, from: data)
			
			return parse(archidektDeck: archidektDeck)
		case "moxfield.com", "www.moxfield.com":
			guard deckURL.pathComponents.count >= 2, deckURL.pathComponents[1] == "decks", let decklistURL = URL(string: "https://api.moxfield.com/v2/decks/all/\(deckURL.pathComponents[2])") else { throw PackError.invalidURL }
			
			let request = URLRequest(url: decklistURL, cachePolicy: .reloadIgnoringLocalCacheData)
			let data = try await URLSession.shared.data(from: request).data
			
			let decoder = ReerJSONDecoder()
			let moxfieldDeck = try decoder.decode(MoxfieldDeck.self, from: data)
			
			return parse(moxfieldDeck: moxfieldDeck)
		case "deckstats.net", "www.deckstats.net":
			guard var components = URLComponents(url: deckURL, resolvingAgainstBaseURL: false) else { throw PackError.invalidURL  }
			components.queryItems = [
				URLQueryItem(name: "export_dec", value: "1"),
				URLQueryItem(name: "include_comments", value: "1"),
				URLQueryItem(name: "include_collector_numbers", value: "1")
			]
			
			guard let decklistURL = components.url else { throw PackError.invalidURL }
			
			let request = URLRequest(url: decklistURL, cachePolicy: .reloadIgnoringLocalCacheData)
			let (data, response) = try await URLSession.shared.data(from: request)
			
			if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 400 {
				throw PackError.privateDeck
			}
			
			guard let decklist = String(data: data, encoding: .utf8) else {
				throw PackError.invalidURL
			}
			
			return parse(deckstatsDecklist: decklist)
		case "www.tappedout.net", "tappedout.net":
			let request = URLRequest(url: deckURL, cachePolicy: .reloadIgnoringLocalCacheData)
			let (data, response) = try await URLSession.shared.data(from: request)
			
			if let response = response as? HTTPURLResponse, response.statusCode == 404 {
				throw PackError.privateDeck
			}
			
			guard let page = String(data: data, encoding: .utf8) else {
				throw PackError.invalidURL
			}
			
			guard let arenaDecklist = page.matches(forRegex: #"<textarea id="mtga-textarea">(.*)<\/textarea>"#, options: .dotMatchesLineSeparators).first?.groups.first?.value else {
				throw PackError.invalidURL
			}
			
			return parse(deckList: arenaDecklist, autofix: true)
		case "www.mtggoldfish.com", "mtggoldfish.com":
			let request = URLRequest(url: deckURL, cachePolicy: .reloadIgnoringLocalCacheData)
			let (data, response) = try await URLSession.shared.data(from: request)
			
			if let response = response as? HTTPURLResponse, response.statusCode == 404 {
				throw PackError.privateDeck
			}
			
			guard let page = String(data: data, encoding: .utf8) else {
				throw PackError.invalidURL
			}
			
			guard let arenaDownloadLink = page.matches(forRegex: #"<a class="btn btn-secondary deck-tools-btn" href="(\/deck\/arena_download\/.+)">"#).first?.groups.first?.value, let arenaDownloadURL = URL(string: "https://www.mtggoldfish.com" + arenaDownloadLink) else {
				throw PackError.invalidURL
			}
			
			let arenaDownloadRequest = URLRequest(url: arenaDownloadURL, cachePolicy: .reloadIgnoringLocalCacheData)
			let deckData = try await URLSession.shared.data(from: arenaDownloadRequest).data
			
			guard let page2 = String(data: deckData, encoding: .utf8) else {
				throw PackError.invalidURL
			}
			
			guard let decklist = page2.matches(forRegex: #"<textarea class='copy-paste-box'>(.*)<\/textarea>"#, options: .dotMatchesLineSeparators).first?.groups.first?.value.decodingHTMLEntities else {
				throw PackError.invalidURL
			}
			
			return parse(deckList: decklist, autofix: true)
		default:
			throw PackError.invalidURL
		}
	}
}

extension Collection {
	func sorted<Value: Comparable>(on property: KeyPath<Element, Value>, by areInIncreasingOrder: (Value, Value) -> Bool) -> [Element] {
		return sorted { currentElement, nextElement in
			areInIncreasingOrder(currentElement[keyPath: property], nextElement[keyPath: property])
		}
	}
	
	func sorted<Value: Comparable>(on property: KeyPath<Element, Value>) -> [Element] {
		return sorted { currentElement, nextElement in
			currentElement[keyPath: property] < nextElement[keyPath: property]
		}
	}
}

extension URLSession {
	func data(from request: URLRequest) async throws -> (data: Data, response: URLResponse) {
		return try await withCheckedThrowingContinuation { continuation in
			dataTask(with: request) { data, response, error in
				continuation.resume(with: Swift.Result {
					if let error = error {
						throw error
					} else if let data = data, let response = response {
						return (data, response)
					} else {
						fatalError()
					}
				})
			}.resume()
		}
	}
}

// Mapping from XML/HTML character entity reference to character
// From http://en.wikipedia.org/wiki/List_of_XML_and_HTML_character_entity_references
private let characterEntities : [ String : Character ] = [
	// XML predefined entities:
	"&quot;"    : "\"",
	"&amp;"     : "&",
	"&apos;"    : "'",
	"&lt;"      : "<",
	"&gt;"      : ">",
	
	// HTML character entity references:
	"&nbsp;"    : "\u{00a0}",
	// ...
	"&diams;"   : "♦",
]

extension String {
	/// Returns a new string made by replacing in the `String`
	/// all HTML character entity references with the corresponding
	/// character.
	public var decodingHTMLEntities: String {
		
		// ===== Utility functions =====
		
		// Convert the number in the string to the corresponding
		// Unicode character, e.g.
		//    decodeNumeric("64", 10)   --> "@"
		//    decodeNumeric("20ac", 16) --> "€"
		func decodeNumeric(_ string : String, base : Int) -> Character? {
			guard let code = UInt32(string, radix: base),
				let uniScalar = UnicodeScalar(code) else { return nil }
			return Character(uniScalar)
		}
		
		// Decode the HTML character entity to the corresponding
		// Unicode character, return `nil` for invalid input.
		//     decode("&#64;")    --> "@"
		//     decode("&#x20ac;") --> "€"
		//     decode("&lt;")     --> "<"
		//     decode("&foo;")    --> nil
		func decode(_ entity : String) -> Character? {
			
			if entity.hasPrefix("&#x") || entity.hasPrefix("&#X") {
				return decodeNumeric(String(entity[entity.index(entity.startIndex, offsetBy: 3) ..< entity.index(entity.endIndex, offsetBy: -1)]), base: 16)
			} else if entity.hasPrefix("&#") {
				return decodeNumeric(String(entity[entity.index(entity.startIndex, offsetBy: 2) ..< entity.index(entity.endIndex, offsetBy: -1)]), base: 10)
			} else {
				return characterEntities[entity]
			}
		}
		
		// ===== Method starts here =====
		
		var result = ""
		var position = startIndex
		
		// Find the next '&' and copy the characters preceding it to `result`:
		while let ampRange = self.range(of: "&", range: position ..< endIndex) {
			result.append(String(self[position ..< ampRange.lowerBound]))
			position = ampRange.lowerBound
			
			// Find the next ';' and copy everything from '&' to ';' into `entity`
			if let semiRange = self.range(of: ";", range: position ..< endIndex) {
				let entity = self[position ..< semiRange.upperBound]
				position = semiRange.upperBound
				
				if let decoded = decode(String(entity)) {
					// Replace by decoded character:
					result.append(decoded)
				} else {
					// Invalid entity, copy verbatim:
					result.append(String(entity))
				}
			} else {
				// No matching ';'.
				break
			}
		}
		// Copy remaining characters to `result`:
		result.append(String(self[position ..< endIndex]))
		return result
	}
}
