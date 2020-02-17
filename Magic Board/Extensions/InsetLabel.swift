//
//  InsetLabel.swift
//  Magic Board
//
// https://blog.chrishannah.me/adding-insets-to-a-uilabel/
//
//  Created by Josh Birnholz on 2/16/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit

@IBDesignable class InsetLabel: UILabel {

	@IBInspectable var contentInsets = UIEdgeInsets.zero

	override func drawText(in rect: CGRect) {
		let insetRect = rect.inset(by: contentInsets)
		super.drawText(in: insetRect)
	}

	override var intrinsicContentSize: CGSize {
		return addInsets(to: super.intrinsicContentSize)
	}

	override func sizeThatFits(_ size: CGSize) -> CGSize {
		return addInsets(to: super.sizeThatFits(size))
	}

	private func addInsets(to size: CGSize) -> CGSize {
		let width = size.width + contentInsets.left + contentInsets.right
		let height = size.height + contentInsets.top + contentInsets.bottom
		return CGSize(width: width, height: height)
	}

}
