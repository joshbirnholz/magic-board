//
//  BehaviorRelay+PropertyWrapper.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/16/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa

@propertyWrapper
class BehaviorRelayWrapped<Element> {
	private var behaviorRelay: BehaviorRelay<Element>
	
	var wrappedValue: Element {
		get {
			return behaviorRelay.value
		}
		set {
			behaviorRelay.accept(newValue)
		}
	}
	
	init(_ value: Element) {
		self.behaviorRelay = BehaviorRelay(value: value)
	}
}
