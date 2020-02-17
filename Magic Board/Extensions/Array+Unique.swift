//
//  Array+Unique.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/17/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation

extension Array where Element: Hashable {
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
}
