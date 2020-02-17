//
//  CardInstance.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/16/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import Swiftfall
import RxSwift
import RxCocoa

class CardInstance: NSObject {
	
	let card: Swiftfall.Card
	
	typealias Stats = (power: String, toughness: String)
	
	let power = BehaviorRelay(value: "0")
	let toughness = BehaviorRelay(value: "0")
	
	let loyalty: BehaviorRelay<Int?> = BehaviorRelay(value: 0)
	let isPowerToughnessVisible = BehaviorRelay<Bool>(value: false)
	let isTapped = BehaviorRelay<Bool>(value: false)
	let isFlying = BehaviorRelay<Bool>(value: false)
	let isSummoningSick = BehaviorRelay<Bool>(value: false)
	
	let flip = PublishSubject<Void>()
	let remove = PublishSubject<Void>()
	
	init(card: Swiftfall.Card) {
		self.card = card
		
		super.init()
		
		bind()
	}
	
	private func bind() {
		power.accept(card.power ?? "0")
		toughness.accept(card.toughness ?? "0")
		
		if card.power != nil || card.toughness != nil {
			isPowerToughnessVisible.accept(true)
		}
		
//		isFlying.accept(card.oracleText?.hasPrefix("Flying") ?? false)
//		let regex = """
//		(^|[.,] )[Ff]lying[.,]
//		"""
		
		let regex = """
		(^|[.,] *)[Ff]lying([.,]|$)
		"""
		if let matches = card.oracleText?.matches(forRegex: regex), !matches.isEmpty {
			isFlying.accept(true)
		}
		
		isSummoningSick.accept((card.typeLine?.lowercased() ?? "").contains("creature"))
		
		if let loyalty = card.loyalty.flatMap(Int.init) {
			self.loyalty.accept(loyalty)
		}
		
		loyalty.accept(card.loyalty.flatMap(Int.init))
	}
	
}
