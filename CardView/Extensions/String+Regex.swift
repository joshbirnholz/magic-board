//
//  String+Regex.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/15/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation

typealias Match = (range: Range<String.Index>, value: String)

extension String {

	func matches(forRegex regex: String, options: NSRegularExpression.Options = []) -> [(fullMatch: Match, groups: [Match])] {
		do {
			let regex = try NSRegularExpression(pattern: regex, options: options)
			let results = regex.matches(in: self, range: NSRange(startIndex..., in: self))
			return results.map { result in
				let fullMatchRange = Range(result.range, in: self)!
				let groups: [Match]
				
				if result.numberOfRanges > 1 {
					groups = (1 ..< result.numberOfRanges).compactMap { i in
						guard let range = Range(result.range(at: i), in: self) else {
							return nil
						}
						let value = String(self[range])
						return (range: range, value: value)
					}
				} else {
					groups = []
				}
				
				let fullMatch = (range: fullMatchRange, value: String(self[fullMatchRange]))
				
				return (fullMatch, groups)
			}
		} catch {
			print("Regex error:", error)
			return []
		}
	}
	
}
