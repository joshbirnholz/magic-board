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
		guard AppDelegate.shared.role.isBoard else { return }
		AppDelegate.shared.transceiver.broadcast(self)
		try writeToDisk()
	}
	
	private func writeToDisk() throws {
		let encoder = JSONEncoder()
		let data = try encoder.encode(self)
		try data.write(to: GameState.currentGameStateURL)
	}
	
	func update(withValuesFrom otherGameState: GameState) {
		for (localPlayer, remotePlayer) in zip(self.allPlayers, otherGameState.allPlayers) {
			for (localPlayerPile, remotePlayerPile) in zip(localPlayer.allPiles, remotePlayer.allPiles) {
				localPlayerPile.cards.accept(remotePlayerPile.cards.value)
        localPlayerPile.isTopCardRevealed.accept(remotePlayerPile.isTopCardRevealed.value)
			}
			
			localPlayer.name.accept(remotePlayer.name.value)
			localPlayer.life.accept(remotePlayer.life.value)
		}
		
		battlefield.accept(otherGameState.battlefield.value)
		
    for (id, cardInstance) in otherGameState.allCards {
			if let otherCard = otherGameState.allCards[id] {
				cardInstance.representation = otherCard.representation
				cardInstance.center.accept(otherCard.center.value)
				cardInstance.controllerIdentifier.accept(otherCard.controllerIdentifier.value)
				cardInstance.counters.accept(otherCard.counters.value)
				cardInstance.doesNotUntapAutomatically.accept(otherCard.doesNotUntapAutomatically.value)
				cardInstance.isFlying.accept(otherCard.isFlying.value)
				cardInstance.isPowerToughnessVisible.accept(otherCard.isPowerToughnessVisible.value)
				cardInstance.isSummoningSick.accept(otherCard.isSummoningSick.value)
				cardInstance.isTapped.accept(otherCard.isTapped.value)
				cardInstance.power.accept(otherCard.power.value)
        cardInstance.colors.accept(otherCard.colors.value)
        cardInstance.isCommander.accept(otherCard.isCommander.value)
				cardInstance.toughness.accept(otherCard.toughness.value)
			} else {
				cardInstance.remove.onNext(())
			}
		}
		
		if AppDelegate.shared.role.isBoard {
			try? writeToDisk()
		}
	}
	
	var battlefield: BehaviorRelay<OrderedSet<CardInstance>>
	
	let player1: Player
	let player2: Player
	
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
