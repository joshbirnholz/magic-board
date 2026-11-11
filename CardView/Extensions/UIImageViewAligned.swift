//
//  UIImageViewAligned.swift
//  CardView
//
//  Created by Josh Birnholz on 10/18/23.
//  Copyright © 2023 Josh Birnholz. All rights reserved.
//

import UIKit

public class UIImageViewAligned: UIImageView {
  
  public struct AlignmentMask: OptionSet {
    
    public let rawValue: Int
    
    public init(rawValue: Int) {
      self.rawValue = rawValue
    }
    
    public static let center = AlignmentMask(rawValue: 1 << 0)
    public static let left = AlignmentMask(rawValue: 1 << 1)
    public static let right =  AlignmentMask(rawValue: 1 << 2)
    public static let top = AlignmentMask(rawValue: 1 << 4)
    public static let bottom = AlignmentMask(rawValue: 1 << 8)
    
    public static let bottomLeft: AlignmentMask = [.bottom, .left]
    public static let bottomRight: AlignmentMask = [.bottom, .right]
    public static let topLeft: AlignmentMask = [.top, .left]
    public static let topRight: AlignmentMask = [.top, .right]
  }
  
  public var alignment: AlignmentMask? {
    didSet {
      if alignment != oldValue {
        setNeedsLayout()
      }
    }
  }
  
  public var enableScaleUp: Bool!
  public var enableScaleDown: Bool!
  
  public private(set) var realImageView: UIImageView!
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    commonInit()
  }
  
  override init(image: UIImage?) {
    super.init(image: image)
    commonInit()
  }
  
  override init(image: UIImage?, highlightedImage: UIImage?) {
    super.init(image: image, highlightedImage: highlightedImage)
    commonInit()
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    commonInit()
  }
  
  private func commonInit() {
    enableScaleDown = true
    enableScaleUp = true
    
    alignment = .center
    
    realImageView = UIImageView(frame: bounds)
    realImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    realImageView.contentMode = contentMode
    addSubview(realImageView)
    
    if super.image != nil {
      let img = super.image
      super.image = nil
      self.image = img
    }
  }
  
  override public var image: UIImage? {
    get {
      realImageView.image
    }
    set {
      realImageView.image = newValue
      setNeedsLayout()
    }
  }
  
  override public var contentMode: UIView.ContentMode {
    get {
      super.contentMode
    }
    set {
      super.contentMode = newValue
      realImageView.contentMode = contentMode
      setNeedsLayout()
    }
  }
  
  override public func layoutSubviews() {
    let realSize = realContentSize
    
    // Start centered
    var realFrame = CGRect(
      x: (self.bounds.size.width - realSize.width)/2,
      y: (self.bounds.size.height - realSize.height) / 2,
      width: realSize.width,
      height: realSize.height
    )
    
    if let alignment {
      if alignment.contains(.left) {
        realFrame.origin.x = 0
      } else if alignment.contains(.right) {
        realFrame.origin.x = bounds.maxX - realFrame.size.width
      }
      
      if alignment.contains(.top) {
        realFrame.origin.y = 0
      } else if alignment.contains(.bottom) {
        realFrame.origin.y = bounds.maxY - realFrame.size.height
      }
    }
    
    realImageView.frame = realFrame
    
    // Make sure we clear the contents of this container layer, since it refreshes from the image property once in a while.
    layer.contents = nil
  }
  
  private var realContentSize: CGSize {
    guard let image = realImageView.image else {
      return bounds.size
    }
    
    switch contentMode {
    case .scaleAspectFit:
      let scaleX = bounds.size.width / image.size.width
      let scaleY = bounds.size.height / image.size.height
      var scale = min(scaleX, scaleY)
      
      if (scale > 1.0 && !enableScaleUp) || (scale < 1.0 && !enableScaleDown) {
        scale = 1.0
      }
      return CGSize(
        width: realImageView.image!.size.width * scale,
        height: realImageView.image!.size.height * scale
      )
    case .scaleAspectFill:
      let scaleX = bounds.size.width / image.size.width
      let scaleY = bounds.size.height / image.size.height
      var scale = max(scaleX, scaleY)
      
      if (scale > 1.0 && !enableScaleUp) || (scale < 1.0 && !enableScaleDown) {
        scale = 1.0
      }
      return CGSize(
        width: realImageView.image!.size.width * scale,
        height: realImageView.image!.size.height * scale
      )
    case .scaleToFill:
      var scaleX = bounds.size.width / image.size.width
      var scaleY = bounds.size.height / image.size.height
      
      if (scaleX > 1.0 && !enableScaleUp) || (scaleX < 1.0 && !enableScaleDown) {
        scaleX = 1.0
      }
      if (scaleY > 1.0 && !enableScaleUp) || (scaleY < 1.0 && !enableScaleDown) {
        scaleY = 1.0
      }
      return CGSize(
        width: image.size.width * scaleX,
        height: image.size.height * scaleY
      )
    default:
      return realImageView.image!.size
    }
  }
  
  override public var isHighlighted: Bool {
    get {
      super.isHighlighted
    }
    set {
      super.isHighlighted = newValue
      layer.contents = nil
    }
  }
  
  // MARK: Properties needed for Interface Builder
  
  @IBInspectable
  public var alignLeft: Bool {
    get {
      guard let alignment else { return false }
      return alignment.contains(.left)
    }
    set {
      if var alignment {
        alignment.formUnion(.left)
        self.alignment = alignment
      } else {
        alignment = .left
      }
    }
  }
  
  @IBInspectable
  public var alignRight: Bool {
    get {
      guard let alignment else { return false }
      return alignment.contains(.right)
    }
    set {
      if var alignment {
        alignment.formUnion(.right)
        self.alignment = alignment
      } else {
        alignment = .right
      }
    }
  }
  
  @IBInspectable
  public var alignTop: Bool {
    get {
      guard let alignment else { return false }
      return alignment.contains(.top)
    }
    set {
      if var alignment {
        alignment.formUnion(.top)
        self.alignment = alignment
      } else {
        alignment = .top
      }
    }
  }
  
  @IBInspectable
  public var alignBottom: Bool {
    get {
      guard let alignment else { return false }
      return alignment.contains(.bottom)
    }
    set {
      if var alignment {
        alignment.formUnion(.bottom)
        self.alignment = alignment
      } else {
        alignment = .bottom
      }
    }
  }
}
