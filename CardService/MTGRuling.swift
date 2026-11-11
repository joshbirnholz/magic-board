//
//  MTGRuling.swift
//  CardService
//
//  Created by Josh Birnholz on 6/13/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation

public struct MTGRuling: Codable, Hashable, Equatable {
	//     A computer-readable string indicating which company produced this ruling, either wotc or scryfall.
	public let source: String
	
	// The date when the ruling or note was published.
	public let publishedAt: String
	
	// The text of the ruling.
	public let comment: String
}

extension Ruling {
	var mtgRuling: MTGRuling {
		return MTGRuling(source: source!, publishedAt: publishDate!, comment: comment!)
	}
}
