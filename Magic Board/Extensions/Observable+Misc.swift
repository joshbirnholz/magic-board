//
//  Observable+Misc.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/16/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa

extension ObservableType {

	func withPrevious(startWith first: Element) -> Observable<(previousValue: Element, value: Element)> {
        return scan((first, first)) { ($0.1, $1) }.skip(1)
    }
}

extension BehaviorRelay where Element == Bool {
	func toggle() {
		accept(!value)
	}
}
