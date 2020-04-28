//
//  ImageType.swift
//  CardService
//
//  Created by Josh Birnholz on 3/9/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import UIKit
import SDWebImage

public enum ImageType: String, CaseIterable {
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

public extension MTGCard {
	func image(type: ImageType, for face: Face? = nil, alwaysUpright: Bool = false) -> UIImage? {
		
		let image: UIImage? = {
			guard let url = (face?.imageUris ?? imageUris ?? cardFaces?.first?.imageUris)?[type.rawValue] else { return nil }
			
			if let image = SDImageCache.shared.imageFromCache(forKey: url.absoluteString) {
				return image
			}
			
			guard let data = try? Data(contentsOf: url) else { return nil }
			
			let image = UIImage(data: data)
			
			SDImageCache.shared.store(image, forKey: url.absoluteString, completion: nil)
			
			return image
		}()
		
		if let face = face {
			// TODO: Split images from HOU and AKH sets aren't 50/50.
			if type == .art, layout == "split", cardFaces?.count == 2, let index = cardFaces?.firstIndex(of: face), let splitImage = image?.horizontalSplit(index: index, of: 2) {
				return splitImage
			}
		}
		
		if !alwaysUpright {
			if type == .png || type == .large && layout == "split" && cardFaces?.count == 2, let cgImage = image?.cgImage {
				return UIImage(cgImage: cgImage, scale: 1, orientation: .right)
			}
		}
		
		return image
    }
}
