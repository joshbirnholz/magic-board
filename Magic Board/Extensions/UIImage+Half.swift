//
//  UIImage+Half.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/6/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit

extension UIImage {
	
	func horizontalSplit(index: Int, of count: Int) -> UIImage? {
		let imageWidth: CGFloat = size.width/CGFloat(count)
		let imageHeight: CGFloat = size.height
		
		let imageFrame = CGRect(x: imageWidth * CGFloat(index), y: 0, width: imageWidth, height: imageHeight)
		
		return cgImage?.cropping(to: imageFrame).map(UIImage.init)
	}
	
	func horizontalSplitImage(index: Int, ratio: CGFloat) -> UIImage? {
//		0.61328125
		let ratio: CGFloat = index == 0 ? ratio : 1-ratio
		let imageWidth: CGFloat = size.width*ratio
		let imageHeight: CGFloat = size.height
		
		let imageFrame = CGRect(x: imageWidth * CGFloat(index), y: 0, width: imageWidth, height: imageHeight)
		
		return cgImage?.cropping(to: imageFrame).map(UIImage.init)
	}
	
}
