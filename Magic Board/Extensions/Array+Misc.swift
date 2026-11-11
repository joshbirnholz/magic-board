//
//  Array+Unique.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/17/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation

public extension Array where Element: Hashable {
    var uniques: [Element] {
        var buffer = Array()
        var added = Set<Element>()
        for elem in self {
            if !added.contains(elem) {
                buffer.append(elem)
                added.insert(elem)
            }
        }
        return buffer
    }
	
	var uniquesPreferringLast: [Element] {
		var buffer = Array()
		for (index, elem) in enumerated() {
			let lastIndex = self.lastIndex(of: elem)
			if index == lastIndex {
				buffer.append(elem)
			}
		}
		return buffer
	}
}

public extension Array {
    func chunked(into size: Int) -> [ArraySlice<Element>] {
        return stride(from: 0, to: count, by: size).map {
            self[$0 ..< Swift.min($0 + size, count)]
        }
    }
}
