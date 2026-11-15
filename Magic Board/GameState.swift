//
//  GameState.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/18/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import CoreGraphics
import CardService
import RxSwift
import RxCocoa
import MultipeerKit

extension Observable {
    static func attemptJust(_ f: @escaping () throws -> Element) -> Observable<Element> {
        return Observable.create { observer -> Disposable in
            do {
                observer.on(.next(try f()))
                observer.on(.completed)
            } catch {
                observer.on(.error(error))
            }
            return Disposables.create()
        }
    }
}

extension BehaviorRelay {
	func mutate(_ transform: (inout Element) -> Void) {
		var value = self.value
		transform(&value)
		accept(value)
	}
}

extension BehaviorRelay where Element: AnyObject {
	func update() {
		accept(value)
	}
}

struct GameState: Codable {
    // Shared controllers can participate in a hosted phone session without
    // depending on its transport or presentation types.
    static var sessionSave: ((GameState) -> Void)?
    static var sessionDraw: ((Player.Identifier, Int, Bool) -> Void)?
    static var sessionCards: (() -> [CardInstance])?
    static var sessionPile: ((Player.Identifier, Pile.Location) -> Pile)?

    func effectivePile(_ location: Pile.Location, player: Player.Identifier) -> Pile {
        Self.sessionPile?(player, location) ?? self[player: player][location]
    }

	
	static let currentGameStateURL: URL = {
		let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
		let documentsDirectory = paths[0]
		return documentsDirectory.appendingPathComponent("currentGame.json")
	}()
	
	static var current = load() {
		didSet {
			do {
				try GameState.current.save()
				print("Saved game state (caller: \(#function))")
			} catch {
				print(error)
			}
		}
	}
	
	private static func load() -> GameState {
		do {
			let data = try Data(contentsOf: currentGameStateURL)
			
			let decoder = JSONDecoder()
			let gameState = try decoder.decode(GameState.self, from: data)
			
			return gameState
		} catch {
			return GameState()
		}
	}
	
	func save(caller: String = #function) throws {
		guard Thread.isMainThread else {
			try DispatchQueue.main.sync {
				try self.save(caller: caller)
			}
			return
		}
        if let sessionSave = Self.sessionSave { sessionSave(self); return }
		guard AppDelegate.shared.role.isBoard else { return }
		AppDelegate.shared.transceiver.broadcast(self)
		try writeToDisk()
	}
	
	private func writeToDisk() throws {
		let encoder = JSONEncoder()
		let data = try encoder.encode(self)
		try data.write(to: GameState.currentGameStateURL)
	}
	
    /// Keep the objects observed by the storyboard controllers alive across updates.
    @discardableResult
    func update(withValuesFrom other: GameState, additionalCards: [CardInstance] = []) -> [UUID: CardInstance] {
        let local = allCards
        var incoming = other.cardsInZones
        for card in additionalCards { incoming[card.uuid] = card }
        var canonical: [UUID: CardInstance] = [:]
        for (id, remote) in incoming {
            let card = local[id] ?? remote
            if card !== remote { card.applyValues(from: remote) }
            canonical[id] = card
        }
        for (player, remote) in zip(allPlayers, other.allPlayers) {
            for (pile, remotePile) in zip(player.allPiles, remote.allPiles) {
                pile.cards.accept(OrderedSet(remotePile.cards.value.compactMap { canonical[$0.uuid] }))
                pile.isTopCardRevealed.accept(remotePile.isTopCardRevealed.value)
            }
            player.name.accept(remote.name.value)
            player.life.accept(remote.life.value)
            if player.isHidden != remote.isHidden { player.isHidden = remote.isHidden }
        }
        battlefield.accept(OrderedSet(other.battlefield.value.compactMap { canonical[$0.uuid] }))
        if Self.sessionSave == nil, AppDelegate.shared.role.isBoard { try? writeToDisk() }
        return canonical
    }

	var battlefield: BehaviorRelay<OrderedSet<CardInstance>>
	
	let player1: Player
	let player2: Player

	/// Each player's last loaded deck (player raw → location raw → card IDs), for Reset Decks and Life.
	/// Optional so older saves still decode.
	var deckLayout: [String: [String: [UUID]]]?
	
	var allPlayers: [Player] {
		[player1, player2]
	}
	
	func cardInstance(with id: UUID) -> CardInstance? {
		allCards[id]
	}
	
	func cardInstances<C: Collection>(with ids: C) -> [UUID: CardInstance] where C.Element == UUID {
    var result: [UUID: CardInstance] = [:]
    for id in ids {
      result[id] = allCards[id]
    }
    return result
	}
	
    var allCards: [UUID: CardInstance] {
        var cards = cardsInZones
        for card in Self.sessionCards?() ?? [] { cards[card.uuid] = card }
        return cards
    }

	var cardsInZones: [UUID: CardInstance] {
		var cards = Set(allPlayers.map { $0.allPiles }.joined().map { $0.cards.value }.joined())
		cards.formUnion(battlefield.value)
		return [UUID: [CardInstance]](grouping: cards, by: { $0.uuid }).compactMapValues { $0.first }
	}
	
	subscript(player identifier: Player.Identifier) -> Player {
		switch identifier {
		case .a: return player1
		case .b: return player2
		}
	}
	
	init(player1Name: String? = nil, player2Name: String? = nil) {
		battlefield = BehaviorRelay(value: [])
		player1 = Player(identifier: .a, name: player1Name)
		player2 = Player(identifier: .b, name: player2Name)
	}
	
	func move(cardInstances: [CardInstance], to destination: Pile, at insertionIndex: Int? = nil) {
		guard !cardInstances.isEmpty else { return }
		var cardInstances = cardInstances
		
		if cardInstances.count > 1 {
			var indicesForCardInstances: [CardInstance: Int?] = [:]
			func index(for cardInstance: CardInstance) -> Int? {
				if let index = indicesForCardInstances[cardInstance] {
					return index
				}
				let index = cardInstance.indexInPile
				indicesForCardInstances[cardInstance] = index
				return index
			}
			cardInstances = cardInstances.sorted { (first, second) -> Bool in
				if let firstIndex = index(for: first), let secondIndex = index(for: second) {
					return firstIndex > secondIndex
				} else {
					return false
				}
			}
		}
		
		let cardInstancesGroupedBySources: [Pile?: [CardInstance]] = Dictionary.init(grouping: cardInstances, by: { $0.pile })
		
		for (source, cardInstances) in cardInstancesGroupedBySources {
			// Source will be the pile it comes from, or nil if it's not in a pile (battlefield)
			for cardInstance in cardInstances {
				var cardsToMove: [CardInstance] = []
				guard !cardInstance.representation.isToken && !cardInstance.representation.isEmblem else {
					cardInstance.remove.onNext(())
					continue
				}
				cardsToMove.append(cardInstance)
				if let source = source {
					source.cards.mutate {
						$0.remove(cardInstance)
					}
				} else {
					cardInstance.remove.onNext(())
				}
				
        let shouldKeepCounters = [UUID(uuidString: "26ad696e-9f17-4110-9c59-b9211e662900")!, UUID(uuidString: "088ac883-6f44-4046-bf19-81c7fd952e55")!].contains(cardInstance.representation.card.oracleID) && destination.location != .hand && destination.location != .library
        
				cardInstance.reset(removingCounters: !shouldKeepCounters)
				
				var insertionIndex = insertionIndex ?? destination.cards.value.count
				if source != destination {
					insertionIndex += cardsToMove.count // TODO: Don't do this sometimes????? put on bottom
				}
				insertionIndex = max(min(destination.cards.value.count, insertionIndex), 0)
				destination.cards.mutate { (destinationCards) in
					destinationCards.insert(contentsOf: cardsToMove, at: insertionIndex)
				}
			}
		}
		
		try? GameState.current.save()
	}
	
//	/// Moves the cards at `indices` from the `source` pile to the
//	func move(cardsAt indices: IndexSet, from source: Pile, to destination: Pile, at insertionIndex: Int? = nil) {
//		guard !indices.isEmpty else { return } // If there is nothing to move, don't do anything!
//
//		let orderedIndices = indices.sorted(by: >)
//		var cardsToMove: [CardInstance] = []
//		source.cards.mutate { sourceCards in
//			for index in orderedIndices {
//				if let typeLine = sourceCards[index].typeLine?.lowercased(), typeLine.contains("token") || typeLine.contains("emblem") {
//					continue
//				}
//				let removedCard = sourceCards.remove(at: index)
//				let source = CardItem.Source.pile(CardItem.Source.PileItemIdentifier(location: source.location, playerIdentifier: source.playerIdentifier, index: index))
//				cardsToMove.append((removedCard, source))
//			}
//		}
//		var insertionIndex = insertionIndex ?? destination.cards.value.count
//		if source != destination {
//			insertionIndex += cardsToMove.count
//		}
//		insertionIndex = max(min(destination.cards.value.count, insertionIndex), 0)
//
//		// Update indices of revealed cards.
//		// Map each card to move to the index of that card in each player's revealed cards set, if any.
//		let sources = cardsToMove.map { $0.source }
//		let playersAndRevealedSourceIndices: [(Player, [Int?])] = GameState.current.allPlayers.map { player in
//			let revealedCards = player.revealedCards.value.contents
//			let revealedSourceIndices: [Int?] = sources.map { source in
//				revealedCards.firstIndex(where: { $0.source == source })
//			}
//			return (player, revealedSourceIndices)
//		}
//
//		let cards = cardsToMove.map { $0.card }
//		destination.cards.mutate { (destinationCards) in
//			destinationCards.insert(contentsOf: cards, at: insertionIndex)
//		}
//
//		let insertedCardsNewSources: [CardItem.Source] = cardsToMove.indices.reversed().map {
//			let newIndex = insertionIndex + $0
//			let identifier = CardItem.Source.PileItemIdentifier(location: destination.location, playerIdentifier: destination.playerIdentifier, index: newIndex)
//			return CardItem.Source.pile(identifier)
//		}
//
//		for (player, revealedSourceIndices) in playersAndRevealedSourceIndices {
//			var newRevealedCards = Array(player.revealedCards.value)
//			for (revealedSourceIndex, newSource) in zip(revealedSourceIndices, insertedCardsNewSources) {
//				guard let index = revealedSourceIndex else { continue }
//				newRevealedCards[index] = CardItem(source: newSource)
//			}
//			player.revealedCards.accept(OrderedSet(newRevealedCards))
//		}
//
//		try? GameState.current.save()
//	}
	
//	func move(cardsAt indices: IndexSet, from source: inout Cards, to destination: inout Cards, at insertionIndex: Int? = nil) {
//		guard !indices.isEmpty else { return } // If there is nothing to move, don't do anything!
//		let orderedIndices = indices.sorted().reversed()
//		let cards = orderedIndices.map { source.remove(at: $0) }
//		let insertionIndex = insertionIndex ?? destination.count
//		destination.insert(contentsOf: cards, at: insertionIndex)
//
//		try? GameState.current.save()
//	}
	
}

extension Array {
	mutating func moveElements(at sourceIndices: IndexSet, to targetIndex: Int?) {
		let targetIndex = targetIndex ?? count
		
		// Defining the offsets that occur in destination and source indexes when we iterate over them one by one
		var array = self
		var draggedItemOffset = 0
		var targetIndexOffset = 0

		// Items being dragged ordered by their indexPaths
		let orderedDragIndices = sourceIndices.sorted() // Add {$0.row < $1.row for sorting IndexPaths}

		// Items being dragged ordered by their selection order
		var selectionOrderDragItems: [Element] = []

		sourceIndices.forEach { (index) in
			selectionOrderDragItems.append(array[index])
		}

		// Reordering the list
		for i in (0...(orderedDragIndices.count - 1)).reversed()  {
			let removedItem = array.remove(at: orderedDragIndices[i] + draggedItemOffset)

			array.insert(removedItem, at: targetIndex + targetIndexOffset)

			if (i - 1 >= 0) && orderedDragIndices[i - 1] >= targetIndex {
				draggedItemOffset += 1
			} else {
				draggedItemOffset = 0
				targetIndexOffset -= 1
			}
		}

		// Right now the dropped items are in the order of their source indexPaths. Returning them back to the order of selection
		for index in Array<Int>(targetIndex + targetIndexOffset + 1 ... targetIndexOffset).sorted(by: >) {
			array.remove(at: index)
		}
		array.insert(contentsOf: selectionOrderDragItems, at: targetIndex + targetIndexOffset + 1)

		self = array
		
	}
}


extension Notification.Name {
    static let phoneGameDidChange = Notification.Name("MagicBoard.phoneGameDidChange")
}
