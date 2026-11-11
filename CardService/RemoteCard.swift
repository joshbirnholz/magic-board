//
//  RemoteCard.swift
//  Magic Board
//
//  Created by Josh Birnholz on 9/2/22.
//  Copyright © 2022 Josh Birnholz. All rights reserved.
//

import Foundation
import CardService

struct RemoteCard: Codable, Hashable, Equatable, Identifiable {
	let id = UUID()
	
	struct Back: Codable, Hashable, Equatable {
		let imageURL: URL
		let name: String
	}
	
	let name: String
	let set: String
	let imageURL: URL
	let foil: Bool
	let collectorNumber: String
	let back: Back?
//	let scryfallURI: URL?
	
	var identifier: MTGCardIdentifier {
		return .collectorNumberSet(collectorNumber: collectorNumber, set: set, name: name)
	}
}

extension RemoteCard {
	static func loadPack(set: String) async throws -> [RemoteCard] {
		let url = URL(string: "https://tts-magic-booster.fly.dev/pack/\(set)?&outputformat=json")!
		var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
		request.httpMethod = "POST"
		
		let data = try await URLSession.shared.data(from: request).data
		let decoder = JSONDecoder()
		return try decoder.decode([RemoteCard].self, from: data)
	}
}

fileprivate extension URLSession {
	func data(from request: URLRequest) async throws -> (data: Data, response: URLResponse) {
		return try await withCheckedThrowingContinuation { continuation in
			dataTask(with: request) { data, response, error in
				continuation.resume(with: Swift.Result {
					if let error = error {
						throw error
					} else if let data = data, let response = response {
						return (data, response)
					} else {
						fatalError()
					}
				})
			}.resume()
		}
	}
}
