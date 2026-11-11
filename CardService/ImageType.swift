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
import Combine

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
	fileprivate func urlToLoad(type: ImageType, face: Face? = nil, alwaysUpright: Bool = false) -> URL? {
		return (face?.imageUris ?? imageUris ?? cardFaces?.first?.imageUris)?[type.rawValue]
	}
	
	func imageLoader(type: ImageType, for face: Face? = nil, alwaysUpright: Bool = false) -> (imageExistsInCache: Bool, loader: AnyPublisher<UIImage?, Never>) {
		guard let url = urlToLoad(type: type, face: face) else { return (false, AnyPublisher(Just<UIImage?>(nil))) }
		
		let imageExists = SDImageCache.shared.diskImageDataExists(withKey: url.absoluteString)
		
		let loader: AnyPublisher<UIImage?, Never> = {
			
			func process(_ image: UIImage) -> UIImage {
				if let face = face {
					// TODO: Split images from HOU and AKH sets aren't 50/50.
					if type == .art, self.layout == "split", self.cardFaces?.count == 2, let index = self.cardFaces?.firstIndex(of: face), let splitImage = image.horizontalSplit(index: index, of: 2) {
						return splitImage
					}
				}
				
				if !alwaysUpright {
					if type == .png || type == .large && self.layout == "split" && self.cardFaces?.count == 2, let cgImage = image.cgImage {
						return UIImage(cgImage: cgImage, scale: 1, orientation: .right)
					}
				}
				
				return image
			}
			
			if imageExists, let image = SDImageCache.shared.imageFromCache(forKey: url.absoluteString) {
				return AnyPublisher(Just<UIImage?>(process(image)))
			}
			
			return AnyPublisher(URLSession.shared.dataTaskPublisher(for: url)
            .map { imageData in
				guard let image = UIImage(data: imageData.data) else { return nil }
				
				SDImageCache.shared.store(image, forKey: url.absoluteString, completion: nil)
				
				return process(image)
			}
            .replaceError(with: nil)
            .receive(on: DispatchQueue.main))
			
//			let image: UIImage? = {
//
//
//				if let image = SDImageCache.shared.imageFromCache(forKey: url.absoluteString) {
//					return image
//				}
//
//				guard let data = try? Data(contentsOf: url) else { return nil }
//
//				let image = UIImage(data: data)
//
//				SDImageCache.shared.store(image, forKey: url.absoluteString, completion: nil)
//
//				return image
//			}()
//
//			if let face = face {
//				// TODO: Split images from HOU and AKH sets aren't 50/50.
//				if type == .art, layout == "split", cardFaces?.count == 2, let index = cardFaces?.firstIndex(of: face), let splitImage = image?.horizontalSplit(index: index, of: 2) {
//					return splitImage
//				}
//			}
//
//			if !alwaysUpright {
//				if type == .png || type == .large && layout == "split" && cardFaces?.count == 2, let cgImage = image?.cgImage {
//					return UIImage(cgImage: cgImage, scale: 1, orientation: .right)
//				}
//			}
//
//			return image
		}()
		
		return (imageExists, loader)
	}
	
	func isImageInCache(type: ImageType, for face: Face? = nil) -> Bool {
		guard let url = urlToLoad(type: type, face: face) else { return false }
		return SDImageCache.shared.diskImageDataExists(withKey: url.absoluteString)
	}
	
	func imageIfLoaded(type: ImageType, for face: Face? = nil, alwaysUpright: Bool = false) -> UIImage? {
		guard isImageInCache(type: type, for: face) else { return nil }
		
		return image(type: type, for: face, alwaysUpright: alwaysUpright)
	}
	
	func image(type: ImageType, for face: Face? = nil, alwaysUpright: Bool = false) -> UIImage? {
		
		let image: UIImage? = {
			guard let url = urlToLoad(type: type, face: face) else { return nil }
			
			if let image = SDImageCache.shared.imageFromCache(forKey: url.absoluteString) {
        print("Loaded image from cache for \(url.absoluteString)")
				return image
			}
			
			guard let data = try? Data(contentsOf: url) else { return nil }
			
			let image = UIImage(data: data)
			
			SDImageCache.shared.store(image, forKey: url.absoluteString, completion: nil)
      print("Stored image in cache for \(url.absoluteString)")
			
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
  
  func imageURL(type: ImageType, for face: Face? = nil) -> URL? {
    return urlToLoad(type: type, face: face)
  }
	
	enum SymbolSize: String {
		case small, medium, large
	}
	
	func symbolImage(size: SymbolSize = .medium) -> UIImage? {
		if set.lowercased() == "net" {
			return UIImage(named: "netropolis-\(rarity.rawValue)")
		}
		
		var set = self.set
		
		if set.count > 3 && set.lowercased().hasPrefix("p") {
			set = String(set.dropFirst())
		}
		
		switch Int(collectorNumber) ?? 0 {
		case 1...25 where set == "gk1": set = "gk1_DIMIR"
		case 26...49 where set == "gk1": set = "gk1_IZZET"
		case 50...76 where set == "gk1": set = "gk1_GOLGAR"
		case 51...101 where set == "gk1": set = "gk1_BOROS"
		case 102...127 where set == "gk1": set = "gk1_SELESN"
		case 1...27 where set == "gk2": set = "gk2_AZORIU"
		case 28...51 where set == "gk2": set = "gk2_ORZHOV"
		case 52...79 where set == "gk2": set = "gk2_RAKDOS"
		case 80...106 where set == "gk2": set = "gk2_GRUUL"
		case 107...133 where set == "gk2": set = "gk2_SIMIC"
		default: break
		}
		
    let rarity = switch rarity.rawValue.first?.uppercased() {
    case "C": "common"
    case "U": "uncommon"
    case "R": "rare"
    case "M": "mythic"
    case "S": "special"
    case "B": "bonus"
    default: "common"
    }
    
    let url = URL(string: "https://gatherer-static.wizards.com/set_symbols/\(set)/large-\(rarity)-\(set).png")!
		
		if let image = SDImageCache.shared.imageFromCache(forKey: url.absoluteString) {
			return image
		}
		
		guard let data = try? Data(contentsOf: url) else { return nil }
		
		let image = UIImage(data: data)
		
		SDImageCache.shared.store(image, forKey: url.absoluteString, completion: nil)
		
		return image
	}
}
