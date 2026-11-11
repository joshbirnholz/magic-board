//
//  Array+Separate.swift
//  CardService
//
//  Created by Josh Birnholz on 5/14/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation

extension Array {
	/// Removes all the elements that satisfy the given predicate, and returns a new array containing the removed elements.
	/// - Parameter shouldBeRemoved: A closure that takes an element of the sequence as its argument and returns a Boolean value indicating whether the element should be removed from the array.
	/// - Returns: The removed elements.
	mutating func separate(by shouldBeRemoved: (Element) throws -> Bool) rethrows -> [Element] {
		var separation: [Element] = []
		for (index, element) in enumerated().reversed() {
			if try shouldBeRemoved(element) {
				separation.insert(remove(at: index), at: 0)
			}
		}
		return separation
	}
	
	public func chunked(by chunkSize: Int) -> [[Element]] {
		guard !isEmpty else { return [] }
		return stride(from: 0, to: self.count, by: chunkSize).map {
			Array(self[$0..<Swift.min($0 + chunkSize, self.count)])
		}
	}
	
	public func choose(_ n: Int) -> ArraySlice<Element> {
		guard n >= 0 else { return [] }
		let n = Swift.min(n, count)
		
		var copy = self
		for i in stride(from: count - 1, to: count - n - 1, by: -1) {
			copy.swapAt(i, Int.random(in: 0..<(i+1)))
		}
		return copy.suffix(n)
	}
}
