/*
This source file is part of the Swift.org open source project
Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception
See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

// https://github.com/apple/swift-package-manager/blob/5d05348c6fd072ae7989ed8b55ac2b017486acf4/Sources/Basic/OrderedSet.swift

/// An ordered set is an ordered collection of instances of `Element` in which
/// uniqueness of the objects is guaranteed.
public struct OrderedSet<E: Hashable>: Equatable, MutableCollection, Sequence {
	public typealias Element = E
	public typealias Index = Int
	
	#if swift(>=4.1.50)
	public typealias Indices = Range<Int>
	#else
	public typealias Indices = CountableRange<Int>
	#endif
	
	private var array: [Element]
	private var set: Set<Element>
	
	/// Creates an empty ordered set.
	public init() {
		self.array = []
		self.set = Set()
	}
	
	/// Creates an ordered set with the contents of `array`.
	///
	/// If an element occurs more than once in `element`, only the first one
	/// will be included.
	public init(_ array: [Element]) {
		self.init()
		for element in array {
			append(element)
		}
	}
	
	// MARK: Working with an ordered set
	/// The number of elements the ordered set stores.
	public var count: Int { return array.count }
	
	/// Returns `true` if the set is empty.
	public var isEmpty: Bool { return array.isEmpty }
	
	/// Returns the contents of the set as an array.
	public var contents: [Element] { return array }
	
	/// Returns `true` if the ordered set contains `member`.
	public func contains(_ member: Element) -> Bool {
		return set.contains(member)
	}
	
	/// Adds an element to the ordered set.
	///
	/// If it already contains the element, then the set is unchanged.
	///
	/// - returns: True if the item was inserted.
	@discardableResult
	public mutating func append(_ newElement: Element) -> Bool {
		let inserted = set.insert(newElement).inserted
		if inserted {
			array.append(newElement)
		}
		return inserted
	}
	
	/// Inserts a new element into the ordered set at the specified position, if it is not already present.
	///
	/// If it already contains the element, then the set is unchanged.
	///
	/// - returns: True if the item was inserted.
	@discardableResult
	public mutating func insert(_ newElement: Element, at i: Int) -> Bool {
		let inserted = set.insert(newElement).inserted
		if inserted {
			array.insert(newElement, at: i)
		}
		return inserted
	}
	
	/// Inserts the elements of a sequence that are not contained in the set into the set at the specified position.
	///
	/// If it already contains the element, then the set is unchanged.
	///
	/// - returns: True if the item was inserted.
	public mutating func insert<C: Collection>(contentsOf collection: C, at i: Int) where C.Element == Element {
		let newElements = collection.filter { !set.contains($0) }
		set.formUnion(newElements)
		array.insert(contentsOf: newElements, at: i)
	}
	
	public mutating func formUnion<S: Sequence>(_ other: S) where S.Element == Element {
		for element in other {
			append(element)
		}
	}
	
	public mutating func formIntersection<S: Sequence>(_ other: S) where S.Element == Element {
		for element in other {
			remove(element)
		}
	}
	
	public mutating func formSymmetricDifference<S: Sequence>(_ other: S) where S.Element == Element {
		for element in self where other.contains(element) {
			remove(element)
		}
		for element in other where !self.contains(element) {
			append(element)
		}
	}
	
	/// Remove and return the element at the beginning of the ordered set.
	public mutating func removeFirst() -> Element {
		let firstElement = array.removeFirst()
		set.remove(firstElement)
		return firstElement
	}
	
	/// Remove and return the element at the end of the ordered set.
	public mutating func removeLast() -> Element {
		let lastElement = array.removeLast()
		set.remove(lastElement)
		return lastElement
	}
	
	/// Remove all elements.
	public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
		array.removeAll(keepingCapacity: keepCapacity)
		set.removeAll(keepingCapacity: keepCapacity)
	}
	
	/// Removes the given element and any elements subsumed by the given element.
	@discardableResult
	public mutating func remove(_ member: Element) -> Element? {
		let element = set.remove(member)
		while let index = array.firstIndex(of: member) {
			array.remove(at: index)
		}
		return element
	}
	
	func isSubset<S: Sequence>(of sequence: S) -> Bool where S.Element == (Element) {
		return set.isSubset(of: sequence)
	}
	
	func isSubset(of other: Set<Element>) -> Bool {
		return set.isSubset(of: other)
	}
	
	func isSubset(of other: OrderedSet<Element>) -> Bool {
		return set.isSubset(of: other.set)
	}
}

extension OrderedSet: ExpressibleByArrayLiteral {
	/// Create an instance initialized with `elements`.
	///
	/// If an element occurs more than once in `element`, only the first one
	/// will be included.
	public init(arrayLiteral elements: Element...) {
		self.init(elements)
	}
}

extension OrderedSet: RandomAccessCollection {
	public var startIndex: Int { return contents.startIndex }
	public var endIndex: Int { return contents.endIndex }
	public subscript(index: Int) -> Element {
    get {
      return array[index]
    }
    set {
      array[index] = newValue
    }
	}
}

extension OrderedSet: RangeReplaceableCollection {
  public mutating func replaceSubrange<C>(_ subrange: Range<Int>, with newElements: C) where C : Collection, E == C.Element {
    for oldElement in array[subrange] {
      set.remove(oldElement)
    }
    self.array.replaceSubrange(subrange, with: newElements)
    for newElement in newElements {
      set.insert(newElement)
    }
  }
}

public func == <T>(lhs: OrderedSet<T>, rhs: OrderedSet<T>) -> Bool {
	return lhs.contents == rhs.contents
}

extension OrderedSet: Hashable where Element: Hashable { }

extension OrderedSet: CustomStringConvertible {
	public var description: String {
		return contents.description
	}
}

extension OrderedSet: CustomDebugStringConvertible {
	public var debugDescription: String {
		return contents.debugDescription
	}
}

extension OrderedSet: Encodable where E: Encodable {
	public func encode(to encoder: Encoder) throws {
		try array.encode(to: encoder)
	}
}

extension OrderedSet: Decodable where E: Decodable {
	public init(from decoder: Decoder) throws {
		let arr = try [E].init(from: decoder)
		self.init(arr)
	}
}
