//
//  Card+Image.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/12/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import UIKit
import Swiftfall

extension Swiftfall.Card {
	enum ImageType: String, CaseIterable {
		/// A transparent, rounded full card PNG. This is the best image to use for videos or other high-quality content.
		///
		/// PNG, 745 x 1040
		case png
		/// A full card image with the rounded corners and the majority of the border cropped off. Designed for dated contexts where rounded images can’t be used.
		///
		/// JPG, 460 x 640
		case borderCropped = "border_crop"
		/// A rectangular crop of the card’s art only. Not guaranteed to be perfect for cards with outlier designs or strange frame arrangements
		///
		/// JPG, Resolution varies
		case art = "art_crop"
		/// A large full card image
		///
		/// JPG, 672 x 936
		case large
		/// A medium-sized full card image
		///
		/// JPG, 488 x 680
		case normal
		/// A small full card image. Designed for use as thumbnail or list icon.
		///
		/// JPG, 146 x 204
		case small
	}
	
	func image(type: ImageType) -> UIImage? {
		guard let url = imageUris?[type.rawValue].flatMap(URL.init(string:)) else { return nil }
		
		var result: Result<Data, Error>?
		
        let task = URLSession.shared.dataTask(with: url) {(data, response, error) in
            
            guard let content = data else {
                print("Error: There was no data returned from image file.")
                return
            }
            
            let httpStatus = (response as! HTTPURLResponse).statusCode
			result = Result {
				if (200..<300).contains(httpStatus), let data = data {
					// Decode JSON file starting from Response struct.
					return data
				} else {
					struct ScryfallError: Codable, Error, CustomStringConvertible {
						
						let code: String
						let type: String
						let status: Int
						let details: String
						
						public var description: String {
							return "Error: \(code)\nDetails: \(details)\n"
						}
					}
					let decoded: ScryfallError = try JSONDecoder().decode(ScryfallError.self, from: content)
					throw decoded
				}
			}
        }
        task.resume()
		
		while result == nil {
			
		}
		
		guard let data = try? result?.get() else { return nil }
		return UIImage(data: data)
    }
}
