//
//  UIColor+Blended.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/17/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit

extension UIColor {
	func blended(with color2: UIColor) -> UIColor {
		var (r1, g1, b1, a1) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
		var (r2, g2, b2, a2) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))

		self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
		color2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

		// add the components, but don't let them go above 1.0
		return UIColor(red: min(r1 + r2, 1), green: min(g1 + g2, 1), blue: min(b1 + b2, 1), alpha: (a1 + a2) / 2)
	}
}

extension UIColor {
	func lightened(by amount: CGFloat = 0.25) -> UIColor {
		return hueColorWithBrightnessAmount(amount: 1 + amount)
	}
	
	func darkened(by amount: CGFloat = 0.25) -> UIColor {
		return hueColorWithBrightnessAmount(amount: 1 - amount)
	}
	
	private func hueColorWithBrightnessAmount(amount: CGFloat) -> UIColor {
		var hue         : CGFloat = 0
		var saturation  : CGFloat = 0
		var brightness  : CGFloat = 0
		var alpha       : CGFloat = 0
		
		if getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
			return UIColor( hue: hue,
							saturation: saturation,
							brightness: brightness * amount,
							alpha: alpha )
		} else {
			return self
		}
		
	}
}
