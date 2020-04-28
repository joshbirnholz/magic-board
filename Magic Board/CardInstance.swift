//
//  CardInstance.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/16/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import CardService
import RxSwift
import RxCocoa
import CoreGraphics

extension BehaviorRelay: Codable where Element: Codable {
	public func encode(to encoder: Encoder) throws {
		try value.encode(to: encoder)
	}
	
	public convenience init(from decoder: Decoder) throws {
		let value = try Element(from: decoder)
		self.init(value: value)
	}
}

class CardInstance: NSObject, Codable {
	
	let uuid: UUID
	
	override var hash: Int {
		var hasher = Hasher()
		hasher.combine(uuid)
		return hasher.finalize()
	}
	
	override func isEqual(_ object: Any?) -> Bool {
		guard let other = object as? CardInstance else {
			return false
		}
		return uuid == other.uuid
	}
	
	private var didAddStartingLoyaltyCounters: Bool
	
	var representation: CardRepresentation {
		didSet {
			representedCardDidChange.onNext(())
			
			if !didAddStartingLoyaltyCounters, let loyalty = representation.loyalty.flatMap(Int.init) {
				self.counters.mutate { counters in
					counters.append(contentsOf: [Counter](repeating: .loyalty, count: loyalty))
				}
				didAddStartingLoyaltyCounters = true
			}
			
			self.power.accept(representation.power ?? "0")
			self.toughness.accept(representation.toughness ?? "0")
			self.isPowerToughnessVisible.accept(representation.power != nil || representation.toughness != nil)
		}
	}
	
	let ownerIdentifier: Player.Identifier
	let controllerIdentifier: BehaviorRelay<Player.Identifier>
	
	let power: BehaviorRelay<String>
	let toughness: BehaviorRelay<String>
	
	let counters: BehaviorRelay<[Counter]>
	
	let isPowerToughnessVisible: BehaviorRelay<Bool>
	let isTapped: BehaviorRelay<Bool>
	let isFlying: BehaviorRelay<Bool>
	let isSummoningSick: BehaviorRelay<Bool>
	let doesNotUntapAutomatically: BehaviorRelay<Bool>
	let doesNotUntapNextTurn: BehaviorRelay<Bool>
	let revealedPlayers: BehaviorRelay<Set<Player.Identifier>>
	
	let remove = PublishSubject<Void>()
	let createCards = PublishSubject<(() throws -> [(Player.Identifier, CardRepresentation)])>()
	let representedCardDidChange = PublishSubject<Void>()
	
	var previouslyViewedFocusIndex: Int
	
	let center: BehaviorRelay<CGPoint?>
	
	private enum CodingKeys: String, CodingKey {
		case uuid, didAddStartingLoyaltyCounters, representation, ownerIdentifier, controllerIdentifier, power, toughness, counters, isPowerToughnessVisible, isTapped, isFlying, isSummoningSick, doesNotUntapAutomatically, revealedPlayers, previouslyViewedFocusIndex, center, doesNotUntapNextTurn
	}
	
	convenience init(card: MTGCard, center: CGPoint?, ownerIdentifier: Player.Identifier) {
		self.init(card: .card(card), center: center, ownerIdentifier: ownerIdentifier)
	}
	
	private static func defaultPower(for representation: CardRepresentation) -> String {
		return representation.power ?? "0"
	}
	
	private static func defaultToughness(for representation: CardRepresentation) -> String {
		return representation.toughness ?? "0"
	}
	
	private static func defaultPowerToughnessVisibility(for representation: CardRepresentation) -> Bool {
		return representation.power != nil || representation.toughness != nil
	}
	
	private static func defaultIsFlying(for representation: CardRepresentation) -> Bool {
//		let isFlying = card.oracleText?.hasPrefix("Flying") ?? false
//		let regex = """
//		(^|[.,] )[Ff]lying[.,]
//		"""
		
		let flyingRegex = #"(^|[.,] *)[Ff]lying([.,]|$)"#
		if let matches = representation.oracleText?.matches(forRegex: flyingRegex, options: .anchorsMatchLines), !matches.isEmpty {
			return true
		}
		return false
	}
	
	private static func defaultIsSummoningSick(for representation: CardRepresentation) -> Bool {
//		return true
		var isSummoningSick = (representation.typeLine?.lowercased() ?? "").contains("creature")
		let hasteRegex = #"(^|[.,] *)[Hh]aste([.,]|$)"#
		if isSummoningSick, let matches = representation.oracleText?.matches(forRegex: hasteRegex, options: .anchorsMatchLines), !matches.isEmpty {
			isSummoningSick = false
		}
		return isSummoningSick
	}
	
	private static func defaultLoyaltyCounters(for representation: CardRepresentation) -> [Counter] {
		if let loyalty = representation.loyalty.flatMap(Int.init) {
			return .init(repeating: .loyalty, count: loyalty)
		} else {
			return []
		}
	}
	
	func reset() {
		switch representation {
		case .card(_):
			break
		case .tokenCopy(let representation):
			self.representation = representation
		case .alternateFace(let card, _):
			self.representation = .card(card)
		case .faceDown(let representation):
			self.representation = representation
		}
		
		power.accept(Self.defaultPower(for: representation))
		toughness.accept(Self.defaultToughness(for: representation))
		isPowerToughnessVisible.accept(Self.defaultPowerToughnessVisibility(for: representation))
		isTapped.accept(false)
		isFlying.accept(Self.defaultIsFlying(for: representation))
		isSummoningSick.accept(Self.defaultIsSummoningSick(for: representation))
		controllerIdentifier.accept(ownerIdentifier)
		doesNotUntapAutomatically.accept(false)
		doesNotUntapNextTurn.accept(false)
		
		let counters = Self.defaultLoyaltyCounters(for: representation)
		self.counters.accept(counters)
		didAddStartingLoyaltyCounters = !counters.isEmpty
	}
	
	init(card: CardRepresentation, center: CGPoint?, ownerIdentifier: Player.Identifier) {
		self.uuid = UUID()
		
		self.representation = card
		
		power = BehaviorRelay(value: Self.defaultPower(for: card))
		toughness = BehaviorRelay(value: Self.defaultToughness(for: card))
		isPowerToughnessVisible = BehaviorRelay(value: Self.defaultPowerToughnessVisibility(for: card))
		isTapped = BehaviorRelay(value: false)
		isFlying = BehaviorRelay(value: Self.defaultIsFlying(for: card))
		isSummoningSick = BehaviorRelay(value: Self.defaultIsSummoningSick(for: card))
		
		self.center = BehaviorRelay(value: center)
		
		self.ownerIdentifier = ownerIdentifier
		self.controllerIdentifier = BehaviorRelay(value: ownerIdentifier)
		self.doesNotUntapAutomatically = BehaviorRelay(value: false)
		self.doesNotUntapNextTurn = BehaviorRelay(value: false)
		
		let counters = Self.defaultLoyaltyCounters(for: card)
		self.counters = BehaviorRelay(value: counters)
		didAddStartingLoyaltyCounters = !counters.isEmpty
		
		self.revealedPlayers = BehaviorRelay(value: [])
		
		self.previouslyViewedFocusIndex = 0
	}
	
}
