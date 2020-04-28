//
//  CGAffineTransform+Degrees.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/7/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import CoreGraphics

extension CGAffineTransform {
	init(rotationAngleRadians: CGFloat) {
		self.init(rotationAngle: rotationAngleRadians)
	}
	init(rotationAngleDegrees: CGFloat) {
		let radians: CGFloat = .pi * rotationAngleDegrees / 180
		self.init(rotationAngle: radians)
	}
}
