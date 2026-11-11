//
//  UIView+Tooltips.swift
//  Countdowns
//
//  Created by Josh Birnholz on 10/18/19.
//  Copyright © 2019 Joshua Birnholz. All rights reserved.
//

import UIKit
import ObjectiveC

@available(iOS 13.0, *)
public class UITooltipView: UIView {
	
	public var isVisible: Bool = false
	
	public static let shared = UITooltipView()
	
	public let tooltipLabel = UILabel()
	
	fileprivate var point: CGPoint = .zero
	
	private init() {
		super.init(frame: .zero)
		
		isUserInteractionEnabled = false
		
		let blurEffect = UIBlurEffect(style: .systemMaterial)
		let blurView = UIVisualEffectView(effect: blurEffect)
		
		blurView.bounds = self.bounds
		blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		
		addSubview(blurView)
		
		tooltipLabel.text = ""
		tooltipLabel.font = UIFont.systemFont(ofSize: 14)
		tooltipLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		tooltipLabel.lineBreakMode = .byClipping
		
		blurView.contentView.addSubview(tooltipLabel)
		
		layer.borderWidth = 1.0/UIScreen.main.scale
		layer.borderColor = UIColor.secondarySystemFill.cgColor
		
		layer.shadowColor = UIColor.black.cgColor
		layer.shadowRadius = 6
		layer.shadowOffset = .zero
		layer.shadowOpacity = 0.3
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	private func _sizeToFit() {
		tooltipLabel.sizeToFit()
		
		frame = tooltipLabel.bounds.insetBy(dx: -5, dy: -3)
		
		tooltipLabel.frame = bounds.insetBy(dx: 5, dy: 3)
	}
	
	public func show(from point: CGPoint) {
		CATransaction.setDisableActions(true)
		_sizeToFit()
		
//		let labelRect = bounds
		alpha = 0
		frame = CGRect(origin: point, size: frame.size)
//		frame = CGRect(x: rect.origin.x+rect.size.width/2-labelRect.size.width/2, y: rect.origin.y+rect.size.height, width: self.frame.size.width, height: self.frame.size.height)
		CATransaction.setDisableActions(false)
		
		isVisible = true
		
		UIView.animate(withDuration: 0) {
			self.alpha = 1
		}

	}
	
	public func show(from rect: CGRect) {
			CATransaction.setDisableActions(true)
			_sizeToFit()
			
			let labelRect = bounds
			alpha = 0
			frame = CGRect(x: rect.origin.x+rect.size.width/2-labelRect.size.width/2, y: rect.origin.y+rect.size.height, width: self.frame.size.width, height: self.frame.size.height)
			CATransaction.setDisableActions(false)
			
			isVisible = true
			
			UIView.animate(withDuration: 0) {
				self.alpha = 1
			}

		}
	
	public func hide() {
		UIView.animate(withDuration: 1.0, animations: {
			self.alpha = 0
		}) { (finished) in
			self.isVisible = false
		}
	}
	
}

fileprivate var tooltipMouseOverAssociatedHandle: UInt8 = 0
fileprivate var tooltipRecognizerAssociatedHandle: UInt8 = 0
fileprivate var tooltipAssociatedHandle: UInt8 = 0

@available(iOS 13.0, *)
extension UIView {
	
	private var tooltipMouseOver: Bool {
		set {
			objc_setAssociatedObject(self, &tooltipMouseOverAssociatedHandle, newValue, .OBJC_ASSOCIATION_ASSIGN)
		}
		get {
			return objc_getAssociatedObject(self, &tooltipMouseOverAssociatedHandle) as? Bool ?? false
		}
	}
	
	private var tooltipRecognizer: UIHoverGestureRecognizer? {
		set {
			objc_setAssociatedObject(self, &tooltipRecognizerAssociatedHandle, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		}
		get {
			return objc_getAssociatedObject(self, &tooltipRecognizerAssociatedHandle) as? UIHoverGestureRecognizer
		}
	}
	
	public var toolTip: String? {
		set {
			objc_setAssociatedObject(self, &tooltipAssociatedHandle, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
			
			if tooltipRecognizer == nil && newValue?.isEmpty == false {
				installTooltipRecognizer()
			}
		}
		get {
			return objc_getAssociatedObject(self, &tooltipAssociatedHandle) as? String
		}
	}
	
	// MARK: Recognizer
	
	private func installTooltipRecognizer() {
		#if targetEnvironment(macCatalyst)
		let recognizer = UIHoverGestureRecognizer(target: self, action: #selector(tooltipHover(_:)))
		self.tooltipRecognizer = recognizer
		addGestureRecognizer(recognizer)
		#endif
	}
	
	private func beginTooltipTimer() {
		var time: TimeInterval = 2
		
		if UITooltipView.shared.isVisible {
			time = 0
		}
		
		Timer.scheduledTimer(withTimeInterval: time, repeats: false) { [weak self] timer in
			guard let self = self, self.tooltipMouseOver, let toolTip = self.toolTip else { return }
			
//			let convertedRect = self.convert(self.bounds, to: self.window)
			let point = self.tooltipRecognizer?.location(in: self) ?? .zero
			var convertedPoint = self.convert(point, to: self.window)
			convertedPoint.y += 26 // Move the tooltip below the cursor
			
			UITooltipView.shared.tooltipLabel.text = toolTip
			self.window?.addSubview(UITooltipView.shared)
//			UITooltipView.shared.show(from: convertedRect)
			UITooltipView.shared.show(from: convertedPoint)
		}
	}
	
	@objc private func tooltipHover(_ recognizer: UIHoverGestureRecognizer) {
		switch recognizer.state {
		case .began:
			tooltipMouseOver = true
			beginTooltipTimer()
		case .failed, .ended:
			tooltipMouseOver = false
			UITooltipView.shared.hide()
		default:
			break
		}
	}
	
}
