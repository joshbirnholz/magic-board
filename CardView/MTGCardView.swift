//
//  CardView.swift
//  CardTEst
//
//  Created by Josh Birnholz on 4/29/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import UIKit
import SwiftUI
import MagicBoardResources

fileprivate func UIImage(named name: String) -> UIImage? {
	UIKit.UIImage.resource(named: name)
}

/// Images live in the shared MagicBoardResources package (outside the app's folder). A few that
/// storyboards and xibs use also stay in the app's and CardView's own catalogs.
public extension UIImage {
	/// Looks in the app's catalog, then CardView's, then the shared resources package.
	static func resource(named name: String) -> UIImage? {
		UIImage(named: name, in: .main, compatibleWith: nil)
			?? UIImage(named: name, in: Bundle(for: MTGCardView.self), compatibleWith: nil)
			?? UIImage(named: name, in: MagicBoardResources.bundle, compatibleWith: nil)
	}
}

public extension Image {
	/// A SwiftUI image from whichever catalog has it (see `UIImage.resource(named:)`).
	init(resource name: String) {
		if UIImage(named: name, in: .main, compatibleWith: nil) != nil {
			self.init(name)
		} else if UIImage(named: name, in: Bundle(for: MTGCardView.self), compatibleWith: nil) != nil {
			self.init(name, bundle: Bundle(for: MTGCardView.self))
		} else {
			self.init(name, bundle: MagicBoardResources.bundle)
		}
	}
}

public class MTGCardView: UIView {
    /// Strengthen the existing typography for compact battlefield rendering.
    public var prefersLargeBattlefieldText = false { didSet { setNeedsLayout() } }
    /// The card itself within this view (after layout): the mana cost draws above it, so the
    /// rendered image's visible pixels are taller than the card.
    public var cardBodyFrame: CGRect { cardView.frame }


	public struct CardProperties: Equatable {
		public var name: String?
		public var flavorName: String?
		public var typeLine: String?
		public var oracleText: String?
		public var art: UIImage?

		public var colors: [MTGCardView.Color] = [] {
			didSet {
				switch Set(colors) {
				case [.white, .blue]: colors = [.white, .blue]
				case [.blue, .black]: colors = [.blue, .black]
				case [.black, .red]: colors = [.black, .red]
				case [.red, .green]: colors = [.red, .green]
				case [.green, .white]: colors = [.green, .white]
				case [.white, .black]: colors = [.white, .black]
				case [.blue, .red]: colors = [.blue, .red]
				case [.black, .green]: colors = [.black, .green]
				case [.red, .white]: colors = [.red, .white]
				case [.green, .blue]: colors = [.green, .blue]
				default: break
				}
			}
		}
		public var icons: [Icon] = []
		public var borderStyle: BorderStyle?
		public var borderColor: BorderColor = .black
		public var isHybrid: Bool = false
		public var objectType: Object = .card
		public var backgroundStyle: BackgroundStyle?
		public var overlay: OverlayStyle?
		public var value: NSAttributedString? = nil
		public var manaCost: String?
		public var isFullArt = false
		/// Large art behind a fully transparent frame (no lightening, unlike colorless cards), with the
		/// card's own colored bars and border: Planets and Spacecraft are printed this way.
		public var isPinlineFrame = false
		public var isInverted = false
		public var dfcIcon: DFCIcon?
    public var isCommander = false

    public var isRetro: Bool {
      if objectType != .card {
        return false
      }

      return borderStyle == .retro
    }

		public var isTapped = false
		public var isChained = false

    public init(name: String? = nil, flavorName: String? = nil, typeLine: String? = nil, oracleText: String? = nil, art: UIImage? = nil, colors: [MTGCardView.Color] = [], icons: [MTGCardView.Icon] = [], borderStyle: MTGCardView.BorderStyle? = nil, borderColor: MTGCardView.BorderColor = .black, isHybrid: Bool = false, objectType: MTGCardView.Object = .card, backgroundStyle: MTGCardView.BackgroundStyle? = nil, overlay: MTGCardView.OverlayStyle? = nil, value: NSAttributedString? = NSAttributedString(string: "4/3"), manaCost: String? = nil, isFullArt: Bool = false, isInverted: Bool = false, dfcIcon: DFCIcon? = nil, isCommander: Bool = false) {
			self.name = name
			self.flavorName = flavorName
			self.typeLine = typeLine
			self.oracleText = oracleText
			self.art = art
			self.colors = colors
			self.icons = icons
			self.borderStyle = borderStyle
			self.borderColor = borderColor
			self.isHybrid = isHybrid
			self.objectType = objectType
			self.backgroundStyle = backgroundStyle
			self.overlay = overlay
			self.value = value
			self.manaCost = manaCost
			self.isFullArt = isFullArt
			self.isInverted = isInverted
			self.dfcIcon = dfcIcon
      self.isCommander = isCommander
		}
	}

	public var properties: CardProperties = CardProperties() {
		didSet {
			updateBackground()
		}
	}

	@IBOutlet private var contentView: UIView!
	@IBOutlet private weak var cardView: UIView!

	/// The drawn card itself (inside this view's padding), in this view's coordinates.
	public var cardFrame: CGRect { cardView.convert(cardView.bounds, to: self) }

	@IBOutlet private weak var valueLabel: UILabel!
	@IBOutlet private weak var loyaltyLabel: UILabel!
	@IBOutlet private weak var textLabel: UILabel!
	@IBOutlet private weak var topBarImageView: UIImageView!
	@IBOutlet private weak var bottomBarImageView: UIImageView!
	@IBOutlet private weak var borderImageView: UIImageView!
	@IBOutlet private weak var overlayImageView: UIImageView!
	@IBOutlet private weak var crownImageView: UIImageView!
	@IBOutlet private weak var backgroundImageView: UIImageView!
	@IBOutlet private(set) public weak var artImageView: UIImageView!
	@IBOutlet private weak var ptImageView: UIImageView!
	@IBOutlet private weak var manaCostLabel: UILabel!
	@IBOutlet private weak var typeLineLabel: UILabel!
	@IBOutlet private weak var realNameLabel: UILabel!
	@IBOutlet weak var bottomBlock: UIImageView!
	@IBOutlet private weak var iconStackView: UIStackView!
	@IBOutlet weak var dfcImageView: UIImageView!

  @IBOutlet weak var dfcIconImageView: UIImageView!
	@IBOutlet private var iconPlates: [UIImageView]!
	@IBOutlet weak var dfcSpacerView: UIView!
	@IBOutlet private var iconImageViews: [UIImageView]!

	@IBOutlet private weak var artViewWidthConstraint: NSLayoutConstraint!
	@IBOutlet private var artViewCenterYConstraint: NSLayoutConstraint!
	@IBOutlet private weak var tappedDarkeningView: UIImageView!

  @IBOutlet var valueYConstraint: NSLayoutConstraint!
  @IBOutlet var titleStackYConstraint: NSLayoutConstraint!
  @IBOutlet weak var titleStack: UIStackView!

	override public init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		let bundle = Bundle(for: Self.self)
		bundle.loadNibNamed("MTGCardView", owner: self, options: nil)
		addSubview(contentView)
		contentView.frame = self.bounds
		contentView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
//		artImageView.alignment = UIImageViewAlignmentMaskTop


		updateBackground()
	}

	public override func layoutSubviews() {


		super.layoutSubviews()
		updateFontSize()
		updateValueFontSize()
		updateRealNameFontSize()
		if let cost = properties.manaCost, !cost.isEmpty {
			updateManaCost()
		}

//		artImageView.alignment = UIImageViewAlignmentMaskTop

		cardView.layer.masksToBounds = true
//		cardView.mask = cardMask
		cardView.layer.cornerRadius = self.frame.width * 0.0455
	}

	private func updateFontSize() {
		let descriptor = textLabel.font.fontDescriptor
		let font = UIFont(descriptor: descriptor, size: frame.width * 0.063445)

		textLabel.font = font
		typeLineLabel.font = font
	}

	private func updateRealNameFontSize() {
		let descriptor = realNameLabel.font.fontDescriptor
		let font = UIFont(descriptor: descriptor, size: frame.width * 0.04166666667)

		realNameLabel.font = font
	}

	private func updateValueFontSize() {
		let descriptor = valueLabel.font.fontDescriptor
		let loyaltyFont = UIFont(descriptor: descriptor, size: frame.width * 0.09)
		loyaltyLabel.font = loyaltyFont

		let ptFont = UIFont(descriptor: descriptor, size: frame.width * 0.11)
		valueLabel.font = ptFont

	}

	public enum Object {
		case card
		case token
		case emblem
	}

	public enum Color: String, Comparable, CaseIterable, Equatable {
		public static func < (lhs: MTGCardView.Color, rhs: MTGCardView.Color) -> Bool {
			return lhs.value < rhs.value
		}

		case white, blue, black, red, green

		public var initial: String {
			switch self {
			case .white: return "W"
			case .blue: return "U"
			case .black: return "B"
			case .red: return "R"
			case .green: return "G"
			}
		}

    public var name: String {
      switch self {
      case .white: return "White"
      case .blue: return "Blue"
      case .black: return "Black"
      case .red: return "Red"
      case .green: return "Green"
      }
    }

		var value: Int {
			switch self {
			case .white: return 0
			case .blue: return 1
			case .black: return 2
			case .red: return 3
			case .green: return 4
			}
		}

		public init?(initial: String) {
			let initial = initial.uppercased()
			for color in Color.allCases {
				if color.initial == initial {
					self = color
					return
				}
			}
			return nil
		}

	}

	public enum DFCIcon: String {
		case sun
		case moon

		case compass
		case land

		case origins
		case planeswalker

		case eldrazi
		case fullmoon

		case lesson

		case closedfan
		case openfan

		case arrow
    case arrowDown

		case specialize

		var image: UIImage? {
			UIImage(named: "dfc-icon-" + rawValue)
		}
	}

	public enum BackgroundStyle {
		case artifact
		case vehicle
		case land
		case planeswalker
		case nyxtouched
		case nyxtouchedArtifact
    case nyxtouchedUniversesBeyond
    case nyxtouchedUniversesBeyondArtifact
		case snow
		case snowArtifact
		case snowLand
    case universesBeyond
    case universesBeyondLand
    case universesBeyondArtifact
    case universesBeyondVehicle

    public var isArtifact: Bool {
      if isVehicle {
        return true
      }
      return [.artifact, .snowArtifact, .nyxtouchedArtifact, .universesBeyondArtifact, .nyxtouchedUniversesBeyondArtifact].contains(self)
    }

    public var isVehicle: Bool {
      [.vehicle, .universesBeyondVehicle].contains(self)
    }

    public var isLand: Bool {
      [.land, .snowLand, .universesBeyondLand].contains(self)
    }

    public var isSnow: Bool {
      [.snow, .snowLand, .snowArtifact].contains(self)
    }

    public var isUniversesBeyond: Bool {
      [.universesBeyond, .universesBeyondLand, .universesBeyondVehicle, .universesBeyondArtifact, .nyxtouchedUniversesBeyond, .nyxtouchedUniversesBeyondArtifact].contains(self)
    }

    public var isNyxtouched: Bool {
      [.nyxtouched, .nyxtouchedArtifact, .nyxtouchedUniversesBeyond, .nyxtouchedUniversesBeyondArtifact].contains(self)
    }
	}

	public enum BorderStyle {
		case legendary
		case planeswalker
    case retro
	}

	public enum BorderColor: String {
		case black
		case borderless
		case gold
		case silver
		case white

		fileprivate var color: UIColor {
			return #colorLiteral(red: 0.08844196051, green: 0.07416503876, blue: 0.05679614097, alpha: 1)
//			return #colorLiteral(red: 0.09286607057, green: 0.09286607057, blue: 0.09286607057, alpha: 1)
//			switch self {
//			case .black, .borderless: return #colorLiteral(red: 0.09286607057, green: 0.09286607057, blue: 0.09286607057, alpha: 1)
//			case .white: return .white
//			case .gold: return #colorLiteral(red: 0.6519989967, green: 0.529964149, blue: 0.2993342876, alpha: 1)
//			case .silver: return #colorLiteral(red: 0.6432507038, green: 0.6843975186, blue: 0.719160378, alpha: 1)
//			}
		}
	}

	public enum OverlayStyle {
		case companion
		case nyxtouched
	}

	private var topBarImage: UIImage? {

    if properties.isRetro {
      return nil
    }

		let suffix: String = {
			var result = ""

			if properties.borderStyle == .planeswalker {
				result += "-planeswalker"
			}

			if properties.isInverted {
				result += "-inverted"
			}

			// TODO: Add inverted bars for planeswalkers

			return result
		}()

		if properties.objectType == .token || properties.objectType == .emblem {
			if properties.borderStyle == .planeswalker {
				return UIImage(named: "bar-token-planeswalker")
			} else {
				return UIImage(named: "bar-token")
			}
    } else if (properties.colors.isEmpty || properties.colors.count == 2) && (properties.backgroundStyle?.isLand == true) {
			return UIImage(named: "bar-land\(suffix)")
    } else if properties.colors.isEmpty && (properties.backgroundStyle?.isArtifact == true || properties.backgroundStyle?.isVehicle == true) {
			return UIImage(named: "bar-artifact\(suffix)")
		} else if properties.colors.count == 1, let color = properties.colors.first {
			return UIImage(named: "bar-\(color.rawValue)\(suffix)")
		} else if properties.colors.count >= 2 && !((properties.isHybrid || properties.objectType == .token || properties.objectType == .emblem) && properties.colors.count == 2) {
			return UIImage(named: "bar-gold\(suffix)")
		} else if properties.isHybrid {
			return UIImage(named: "bar-land\(suffix)")
		} else {
			return UIImage(named: "bar-colorless\(suffix)")
		}
	}

	private var bottomBarImage: UIImage? {

		let suffix: String = {
			var result = ""

			if properties.isInverted {
				result += "-inverted"
			}

			return result
		}()

		if properties.isFullArt || properties.borderStyle == .planeswalker {
			return nil
    } else if (properties.colors.isEmpty || properties.colors.count == 2) && (properties.backgroundStyle?.isLand == true) {
			return UIImage(named: "bar-land\(suffix)")
		} else if properties.colors.isEmpty && (properties.backgroundStyle == .artifact || properties.backgroundStyle == .snowArtifact) {
			return UIImage(named: "bar-artifact\(suffix)")
		} else if properties.colors.count == 1, let color = properties.colors.first {
			return UIImage(named: "bar-\(color.rawValue)\(suffix)")
		} else if properties.colors.count >= 2 && !((properties.isHybrid || properties.objectType == .token) && properties.colors.count == 2) {
			return UIImage(named: "bar-gold\(suffix)")
		} else if properties.isHybrid || (properties.objectType == .token && !properties.colors.isEmpty) {
			return UIImage(named: "bar-land\(suffix)")
		} else {
			return UIImage(named: "bar-colorless\(suffix)")
		}
	}

	func maskImage(_ image: UIImage?, withMask maskImage: UIImage?) -> UIImage? {
		guard let maskRef = maskImage?.cgImage, let provider = maskRef.dataProvider else {
			return nil
		}

		let mask = CGImage(
			maskWidth: maskRef.width,
			   height: maskRef.height,
			   bitsPerComponent: maskRef.bitsPerComponent,
			   bitsPerPixel: maskRef.bitsPerPixel,
			   bytesPerRow: maskRef.bytesPerRow,
			   provider: provider,
			   decode: nil,
			   shouldInterpolate: false)

		if let mask = mask, let maskedImageRef = image?.cgImage?.masking(mask) {
			return UIImage(cgImage: maskedImageRef)
		}

		return nil
	}

	private func mergeImages(left: UIImage?, right: UIImage?, maskName: String?) -> UIImage? {
		guard let left, var right else {
			return left ?? right
		}

    let size = left.size

    if let maskName, let mask = UIImage(named: maskName), let rightMasked = maskImage(right, withMask: mask) {
      right = rightMasked
//      size = mask.size
    }

		UIGraphicsBeginImageContext(size)

    let areaSize = CGRect(x: 0, y: 0, width: size.width, height: size.height)
		left.draw(in: areaSize)

		right.draw(in: areaSize)

		let mergedImage = UIGraphicsGetImageFromCurrentImageContext()!
		UIGraphicsEndImageContext()
		return mergedImage
	}

	private func mergedImage(left: String, right: String, maskName: String?) -> UIImage? {
		let left = UIImage(named: left)
		let right = UIImage(named: right)

		return mergeImages(left: left, right: right, maskName: maskName)
	}

	private var overlayImage: UIImage? {

		guard let overlay = properties.overlay else { return nil }

		let suffix: String = {
			switch overlay {
			case .companion: return "-companion"
			case .nyxtouched: return "-nyx"
			}
		}()

		if properties.colors.isEmpty || properties.backgroundStyle == .nyxtouchedArtifact {
			return UIImage(named: "overlay-colorless\(suffix)")
		} else if properties.colors.count == 1, let color = properties.colors.first {
			return UIImage(named: "overlay-\(color.rawValue)\(suffix)")
		} else if properties.isHybrid || properties.objectType == .token {
      return mergedImage(left: "overlay-\(properties.colors[0].rawValue)\(suffix)", right: "overlay-\(properties.colors[1].rawValue)\(suffix)", maskName: "mask")
		} else {
			return UIImage(named: "overlay-gold\(suffix)")
		}
	}

	private var valueImage: UIImage? {

    if properties.isRetro {
      return nil
    }

		guard let value = properties.value, value.length > 0 else { return nil }

		let suffix: String = {
      if properties.borderColor == .borderless {
        return "-borderless"
      } else if properties.isInverted {
				return "-inverted"
			}

      return ""
		}()

    if properties.backgroundStyle == .vehicle || properties.backgroundStyle == .universesBeyondVehicle {
			return UIImage(named: "pt-vehicle")
		} else if properties.borderStyle == .planeswalker {
			return UIImage(named: "pt-loyalty")
		} else if (properties.colors.isEmpty || properties.colors.count == 2) && (properties.backgroundStyle == .land || properties.backgroundStyle == .snowLand) {
			return UIImage(named: "pt-land\(suffix)")
		} else if properties.colors.isEmpty && (properties.backgroundStyle == .artifact || properties.backgroundStyle == .snowArtifact) {
			return UIImage(named: "pt-artifact\(suffix)")
		} else if properties.colors.count == 1, let color = properties.colors.first {
			return UIImage(named: "pt-\(color.rawValue)\(suffix)")
		} else if properties.colors.count >= 2 && !((properties.isHybrid || properties.objectType == .token) && properties.colors.count == 2) {
			return UIImage(named: "pt-gold\(suffix)")
		} else if properties.isHybrid || properties.objectType == .token {
			return UIImage(named: "pt-land\(suffix)")
		} else {
			return UIImage(named: "pt-colorless\(suffix)")
		}
	}

	private var borderImage: UIImage? {

    if properties.isRetro {
      if properties.isFullArt && properties.borderStyle == .legendary {
        return nil
      } else if properties.backgroundStyle?.isLand == true {
        if properties.colors.isEmpty || properties.colors.count > 2 {
          return UIImage(named: "border-land-gold-retro")
        } else if properties.colors.count == 1, let color = properties.colors.first {
          return UIImage(named: "border-land-\(color.rawValue)-retro")
        } else {
          let maskName = "mask"

          let base = mergedImage(left: "border-land-\(properties.colors[0].rawValue)-retro", right: "border-land-\(properties.colors[1].rawValue)-retro", maskName: maskName)

          return base
//          return mergeImages(left: base, right: UIImage(named: "border-land-gold-retro-pinline"), maskName: nil)
        }
      } else if properties.colors.isEmpty && (properties.backgroundStyle?.isArtifact == true || properties.backgroundStyle?.isVehicle == true) {
        return UIImage(named: "border-artifact-retro")
      } else if properties.colors.count == 1, let color = properties.colors.first {
        return UIImage(named: "border-\(color.rawValue)-retro")
      } else if properties.colors.count == 2 && properties.isHybrid {
        let maskName = "mask"

        return mergedImage(left: "border-\(properties.colors[0].rawValue)-retro", right: "border-\(properties.colors[1].rawValue)-retro", maskName: maskName)
      } else if properties.colors.count >= 2 {
        return UIImage(named: "border-gold-retro")
      } else {
        return UIImage(named: "border-colorless-retro")
      }
    }

		let suffix: String = {
			var result = ""

			if properties.flavorName != nil {
				result += "-flavor"
			} else if properties.borderStyle == .legendary {
				result += "-legendary"
			} else if properties.borderStyle == .planeswalker {
				result += "-planeswalker"
			}

			if properties.isFullArt {
				result += "-full"
			}

			return result
		}()

		if properties.isFullArt && properties.borderStyle == .legendary {
			return nil
    } else if properties.colors.isEmpty && (properties.backgroundStyle?.isLand == true) {
			return UIImage(named: "border-land\(suffix)")
    } else if properties.colors.isEmpty && (properties.backgroundStyle?.isArtifact == true || properties.backgroundStyle?.isVehicle == true) {
			return UIImage(named: "border-artifact\(suffix)")
		} else if properties.colors.count == 1, let color = properties.colors.first {
			return UIImage(named: "border-\(color.rawValue)\(suffix)")
		} else if properties.colors.count > 2 {
			return UIImage(named: "border-gold\(suffix)")
		} else if properties.colors.count == 2 {
			let maskName = "mask"

			return mergedImage(left: "border-\(properties.colors[0].rawValue)\(suffix)", right: "border-\(properties.colors[1].rawValue)\(suffix)", maskName: maskName)
		} else {
			return UIImage(named: "border-colorless\(suffix)")
		}
	}

	private var dfcMaskImage: UIImage? {
    if properties.objectType == .token && properties.borderStyle == .legendary {
      return UIImage(named: "dfc-gold")
    } else if properties.isFullArt && properties.borderStyle == .legendary {
			return nil
		} else if properties.colors.isEmpty && (properties.backgroundStyle == .land || properties.backgroundStyle == .snowLand) {
			return UIImage(named: "dfc-land")
		} else if properties.colors.isEmpty && (properties.backgroundStyle == .artifact || properties.backgroundStyle == .snowArtifact) {
			return UIImage(named: "dfc-artifact")
		} else if properties.colors.count > 2 {
			return UIImage(named: "dfc-gold")
		} else if let color = properties.colors.first {
			return UIImage(named: "dfc-\(color.rawValue)")
		} else {
			return UIImage(named: "dfc-colorless")
		}
	}

	private var crownImage: UIImage? {

    if properties.isRetro {
      return nil
    }

		let suffix: String = {
			if properties.flavorName != nil {
				return "-flavor"
			} else {
				return ""
			}
		}()

		guard properties.borderStyle == .legendary else {
			return nil
		}

		if properties.objectType == .token {
			return UIImage(named: "crown-gold\(suffix)")
		} else if properties.colors.isEmpty && (properties.backgroundStyle == .land || properties.backgroundStyle == .snowLand) {
			return UIImage(named: "crown-land\(suffix)")
		} else if properties.colors.isEmpty && (properties.backgroundStyle == .artifact || properties.backgroundStyle == .snowArtifact) {
			return UIImage(named: "crown-artifact\(suffix)")
		} else if properties.colors.count == 1, let color = properties.colors.first {
			return UIImage(named: "crown-\(color.rawValue)\(suffix)")
		} else if properties.colors.count > 2 {
			return UIImage(named: "crown-gold\(suffix)")
		} else if properties.colors.count == 2 {
      return mergedImage(left: "crown-\(properties.colors[0].rawValue)\(suffix)", right: "crown-\(properties.colors[1].rawValue)\(suffix)", maskName: "mask")
		} else {
			return UIImage(named: "crown-colorless\(suffix)")
		}
	}

	private var backgroundImage: UIImage? {

    if properties.isRetro {
      return nil
    }

		let suffix: String = {
      if properties.backgroundStyle?.isUniversesBeyond == true {
        return "-ub"
      } else if properties.backgroundStyle == .planeswalker {
				return "-planeswalker"
			} else if properties.backgroundStyle == .snow || properties.backgroundStyle == .snowArtifact {
				return "-snow"
      } else if properties.backgroundStyle?.isNyxtouched == true {
				return "-nyx"
			} else {
				return ""
			}
		}()

		if properties.isFullArt {
			return UIImage(named: "bg-full")
		} else if properties.isPinlineFrame {
			return nil // fully transparent: the art shows through, unlike a colorless card's lightened frame
		} else if properties.backgroundStyle == .nyxtouchedArtifact {
			return UIImage(named: "bg-colorless-nyx")
		} else if properties.backgroundStyle == .snowArtifact {
			return UIImage(named: "bg-artifact-snow")
		} else if properties.backgroundStyle == .snowLand {
			return UIImage(named: "bg-land-snow")
		} else if properties.backgroundStyle == .universesBeyondArtifact {
      return UIImage(named: "bg-artifact-ub")
    } else if properties.backgroundStyle == .universesBeyondLand {
      return UIImage(named: "bg-land-ub")
    } else if properties.backgroundStyle == .land {
			return UIImage(named: "bg-land")
		} else if properties.backgroundStyle == .artifact {
			return UIImage(named: "bg-artifact")
		} else if properties.backgroundStyle == .vehicle {
			return UIImage(named: "bg-vehicle")
		} else if properties.backgroundStyle == .universesBeyondVehicle {
      return UIImage(named: "bg-vehicle-ub")
    } else if properties.colors.count == 1, let color = properties.colors.first {
			return UIImage(named: "bg-\(color.rawValue)\(suffix)")
		} else if properties.colors.count > 2 {
			return UIImage(named: "bg-gold\(suffix)")
		} else if properties.colors.isEmpty {
			return UIImage(named: "bg-colorless\(suffix)")
		} else if properties.isHybrid || properties.objectType == .token {
      return mergedImage(left: "bg-\(properties.colors[0].rawValue)\(suffix)", right: "bg-\(properties.colors[1].rawValue)\(suffix)", maskName: "mask")
		} else {
			return UIImage(named: "bg-gold\(suffix)")
		}
	}

	public indirect enum Icon: Equatable, CaseIterable, Hashable {
		case deathtouch
		case defender
		case doublestrike
		case firststrike
		case flying
		case haste
		case hexproof
		case indestructible
		case lifelink
		case menace
		case protection
		case reach
		case trample
		case vigilance
		case flash
		case fear
		case shroud
		case intimidate
		case escape
		case devotion
		case companion
		case constellation
		case mutate
		case embalm
		case ingest
		case devoid
		case entersthebattlefield
		case skulk
		case tap
		case more
		case noattack
		case noblock
		case noattackorblock
		case cantbeblocked
		case mustattack
		case castingcostmodifier
		case additionalcastingcost
		case whenyoucastthisspell
		case whenthiscreaturemutates
		case whenyoucycle
		case cycling
		case horsemanship
		case morph
		case megamorph
		case kicker
		case multikicker
		case flashback
		case echo
		case addendum
		case equip
		case surveil
		case adapt
		case fortify
		case undergrowth
		case haunt
		case transmute
		case afterlife
		case cipher
		case forecast
		case dredge
		case ferocious
		case extort
		case evolve
		case hellbent
		case adventure
    case omen
		case graft
		case battalion
		case madness
		case replicate
		case dash
		case radiance
		case raid
		case scry
		case unleash
		case cantbecountered
		case affinity
		case adamant
    case paradox
    case magecraft
		case detain
		case bloodthirst
		case bloodrush
		case prowess
		case overload
		case mentor
		case populate
		case riot
		case scavenge
		case exploit
		case outlast
		case formidable
		case superiority
		case upload
		case fight
		case delve
		case proliferate
		case convoke
		case spectacle
		case tombstone
		case bolster
		case jumpstart
		case instant
		case transform
		case sorcery
		case enchantment
		case party
		case encore
		case foretell
		case boast
		case learn
		case disturb
		case ward
		case coven
		case decayed
		case training
		case cleave
		case reconfigure
		case connive
		case casualty
		case blitz
		case specialize
		case custom(UIImage, name: String? = nil, styles: Set<Icon.Style> = [], isInherent: Bool = false, isPermanent: Bool = false)
		case gained(Icon)
		case counter(Icon)
    case commander

    case enlist
    case readAhead
    case cascade
    case squad
    case prototype
    case livingMetal

    // Arena's ability icons (from mtg.wiki, MTGA_<Ability>.png), added 2026-11-17.
    case changeling
    case aftermath
    case improvise
    case ascend
    case partner
    case spree
    case gift
    case bargain
    case station
    case craft
    case toxic
    case afflict
    case renown
    case backup
    case mobilize
    case fabricate
    case hideaway
    case saddle
    case offspring
    case ninjutsu
    case unearth
    case eternalize
    case plot
    case disguise
    case warp
    case harmonize
    case mayhem
    case channel
    case landfall
    case morbid
    case revolt
    case enrage
    case celebration
    case eerie
    case valiant
    case survival
    case void
    case flurry
    case renew
    case exhaust
    case explore
    case investigate
    case mill
    case venture
    case incubate
    case discover
    case forage
    case amass
    case monstrosity
    case expend
    case endure
    case cloak

		public var name: String? {
			switch self {
			case .doublestrike: return "Double strike"
			case .firststrike: return "First strike"
			case .noattack: return "Can’t attack"
			case .noblock: return "Can’t block"
			case .noattackorblock: return "Can’t attack or block"
			case .mustattack: return "Must attack"
			case .cantbeblocked: return "Can’t be blocked"
			case .castingcostmodifier: return "Modified casting cost"
			case .cantbecountered: return "Can't be countered"
			case .whenthiscreaturemutates: return "When this creature mutates"
			case .jumpstart: return "Jump-Start"
      case .readAhead: return "Read Ahead"
      case .livingMetal: return "Living Metal"
			case .tombstone: return nil
			case .custom: return nil
			case .tap: return nil
			case .more: return nil
			case .gained(let icon), .counter(let icon): return icon.name
			default: return String(describing: self).capitalized
			}
		}

		public enum Style {
			/// Like "Protection from red"
			case from
			/// Like "Affinity for artifacts"
			case forQuality
			/// Like "Escape—{4}{W}{W}, Exile four other cards from your graveyard."
			case costDash
			/// Like "Adamant — If at least three white mana was spent to cast this spell…"
			case abilityWord
			/// Like "Companion — Your starting deck contains only cards with even converted mana costs."
			case requirement
			/// Like "Cycling {2}"
			case cost
			/// Like "Callaphe's power is equal to your devotion to blue."
			case mention
			/// Like "Underworld Rage-Hound attacks each combat if able."
			case creatureNameText
			/// Like "This spell costs {2} less to cast…"
			case phraseAtStartOfLine
			/// Like "When you cycle Avian Oddity…"
			case phraseAtStartOfLineWithName
			/// Like "Trample"
			case keyword
			/// Like "Afterlife 3"
			case keywordNumber
		}

		public func has(style: Style) -> Bool {
			if case .gained(let icon) = self {
				return icon.has(style: style)
			} else if case .counter(let icon) = self {
				return icon.has(style: style)
			}

			if case .custom(_, _, let styles,_ , _) = self {
				return styles.contains(style)
			}

			let styles: [Style: Set<Icon>] = [
				.from:
					[.hexproof,
					 .protection],
				.costDash:
					[.escape,
					 .morph,
					 .megamorph,
					 .forecast,
					 .foretell,
					 .disturb,
					 .boast],
				.abilityWord:
					[.constellation,
					 .adamant,
           .paradox,
           .magecraft,
					 .superiority,
					 .addendum,
					 .hellbent,
					 .bloodrush,
					 .formidable,
					 .undergrowth,
					 .ferocious,
					 .radiance,
					 .raid,
					 .battalion,
					 .coven,
					 .channel,
					 .landfall,
					 .morbid,
					 .revolt,
					 .enrage,
					 .celebration,
					 .eerie,
					 .valiant,
					 .survival,
					 .void,
					 .flurry,
					 .renew,
					 .exhaust],
				.requirement:
					[.companion],
				.cost:
					[.mutate,
					 .embalm,
					 .cycling,
					 .equip,
					 .fortify,
					 .echo,
					 .kicker,
					 .multikicker,
					 .outlast,
					 .flashback,
					 .dash,
					 .madness,
					 .morph,
					 .megamorph,
					 .transmute,
					 .spectacle,
					 .scavenge,
					 .replicate,
					 .overload,
					 .cleave,
					 .reconfigure,
					 .casualty,
					 .blitz,
					 .specialize,
           .squad,
           .prototype,
           .offspring,
           .ninjutsu,
           .unearth,
           .eternalize,
           .plot,
           .disguise,
           .warp,
           .harmonize,
           .mayhem,
          ],
				.mention:
					[.devotion,
					 .haunt,
					 .surveil,
					 .populate,
					 .upload,
					 .bolster,
					 .scry,
					 .fight,
					 .exploit,
					 .proliferate,
					 .detain,
					 .adapt,
					 .party,
					 .connive,
					 .explore,
					 .investigate,
					 .mill,
					 .venture,
					 .incubate,
					 .discover,
					 .forage,
					 .amass,
					 .monstrosity,
					 .expend,
					 .endure,
					 .cloak],
				.creatureNameText:
					[.noblock,
					 .noattackorblock,
					 .cantbeblocked,
					 .mustattack,
					 .entersthebattlefield],
				.phraseAtStartOfLine:
					[.castingcostmodifier,
					 .whenyoucastthisspell,
					 .whenthiscreaturemutates],
				.phraseAtStartOfLineWithName:
					[.whenyoucycle],
				.forQuality:
					[.affinity],
				.keywordNumber:
					[.afterlife,
					 .bloodthirst,
					 .dredge,
					 .graft,
					 .toxic,
					 .afflict,
					 .renown,
					 .backup,
					 .mobilize,
					 .fabricate,
					 .hideaway,
					 .saddle]
			]

			if style == .keyword {
				if self == .hexproof {
					return true
				}
				return !styles.values.joined().contains(self)
			}

			if self == .transform {
				return false
			}

			return styles[style]?.contains(self) ?? false
		}

		public typealias AllCases = [Icon]

		public static var allCases: [Icon] {
      [.deathtouch, .defender, .doublestrike, .firststrike, .flying, .haste, .hexproof, .indestructible, .lifelink, .menace, .protection, .reach, .trample, .vigilance, .flash, .noblock, .noattackorblock, .cantbeblocked, .fear, .shroud, .intimidate, .escape, .devotion, .mutate, .companion, .constellation, .embalm, .ingest, .devoid, .skulk, .mustattack, .castingcostmodifier, .whenyoucastthisspell, .cantbecountered, .cycling, .whenyoucycle, .equip, .adamant, .echo, .horsemanship, .kicker, .multikicker, .flashback, .madness, .morph, .megamorph, .affinity, .haunt, .addendum, .afterlife, .extort, .surveil, .cipher, .transmute, .spectacle, .unleash, .hellbent, .bloodthirst, .bloodrush, .riot, .convoke, .populate, .forecast, .detain, .dredge, .scavenge, .undergrowth, .graft, .evolve, .adapt, .replicate, .overload, .jumpstart, .radiance, .battalion, .mentor, .raid, .formidable, .ferocious, .dash, .delve, .exploit, .prowess, .outlast, .bolster, .proliferate, .scry, .fight, .superiority, .upload, .party, .encore, .foretell, .boast, .learn, .disturb, .ward, .coven, .decayed, .cleave, .reconfigure, .training, .connive, .casualty, .blitz, .specialize, .enlist, .readAhead, .cascade, .squad, .prototype, .magecraft, .paradox, livingMetal,
       .changeling, .aftermath, .improvise, .ascend, .partner, .spree, .gift, .bargain, .station, .craft, .toxic, .afflict, .renown, .backup, .mobilize, .fabricate, .hideaway, .saddle, .offspring, .ninjutsu, .unearth, .eternalize, .plot, .disguise, .warp, .harmonize, .mayhem, .channel, .landfall, .morbid, .revolt, .enrage, .celebration, .eerie, .valiant, .survival, .void, .flurry, .renew, .exhaust, .explore, .investigate, .mill, .venture, .incubate, .discover, .forage, .amass, .monstrosity, .expend, .endure, .cloak]
		}

		// True for inherent properties of cards, like alt layouts.
		public var isInherent: Bool {
			switch self {
      case .adventure, .transform, .commander, .omen:
				return true
			case .custom(_, _, _, let isInherent, _):
				return isInherent
			default:
				return false
			}
		}

		// True for icons representing effects that don't apply after the spell has been resolved, e.e. flash, haste.
		public var isPermanentEffect: Bool {
			switch self {
      case .flash, .haste, .entersthebattlefield, .castingcostmodifier, .additionalcastingcost, .whenyoucastthisspell, .companion, .mutate, .cantbecountered, .adventure, .whenyoucycle, .cycling, .adamant, .kicker, .multikicker, .flashback, .madness, .morph, .megamorph, .affinity, .addendum, .transmute, .spectacle, .unleash, .bloodthirst, .bloodrush, .riot, .convoke, .forecast, .scavenge, .undergrowth, .replicate, .overload, .dash, .delve, .foretell, .casualty, .readAhead, .cascade, .squad,
           .offspring, .ninjutsu, .unearth, .eternalize, .plot, .disguise, .warp, .harmonize, .mayhem,
           .spree, .gift, .bargain, .aftermath, .improvise, .channel:
				return false
			case .custom(_, _, _, _, let isPermanent):
				return isPermanent
			case .gained(let icon), .counter(let icon):
				return icon.isPermanentEffect
			default:
				return true
			}
		}

		fileprivate var isGold: Bool {
			switch self {
			case .cantbeblocked:
				return true
			default:
				return !isPermanentEffect || isInherent || has(style: .mention) || has(style: .abilityWord)
			}
		}

		public var image: UIImage? {
			switch self {
			case .custom(let image, _, _, _, _): return image
			case .gained(let icon), .counter(let icon):
				return icon.image
			case .haunt, .extort:
				return UIImage(named: "Icon_Orzhov")
			case .forecast, .detain:
				return UIImage(named: "Icon_Azorius")
			case .cipher, .transmute:
				return UIImage(named: "Icon_Dimir")
      case .surveil:
        return UIImage(named: "Icon_Surveil")
			case .unleash, .hellbent:
				return UIImage(named: "Icon_Rakdos")
			case .bloodthirst, .bloodrush:
				return UIImage(named: "Icon_Gruul")
			case .populate:
				return UIImage(named: "Icon_Selesnya")
      case .convoke:
        return UIImage(named: "Icon_Convoke")
			case .dredge, .scavenge:
				return UIImage(named: "Icon_Golgari")
			case .graft, .evolve:
				return UIImage(named: "Icon_Simic")
			case .replicate, .overload:
				return UIImage(named: "Icon_Izzet")
			case .radiance, .battalion:
				return UIImage(named: "Icon_Boros")
			case .formidable:
				return UIImage(named: "Icon_Atarka")
			case .dash:
				return UIImage(named: "Icon_Kolaghan")
//			case .exploit:
//				return UIImage(named: "Icon_Silumgar")
			case .bolster:
				return UIImage(named: "Icon_Dromoka")
			case .superiority:
				return UIImage(named: "Icon_NET")
			case .multikicker:
				return Icon.kicker.image
			case .whenyoucycle:
				return Icon.cycling.image
			case .megamorph:
				return Icon.morph.image
			default: return UIImage(named: "Icon_\(String(describing: self).capitalized)")
			}
		}

		public var reminderText: String? {
			switch self {
			case .deathtouch:
				return "Any amount of damage a source with deathtouch deals to a creature is enough to destroy it."
			case .defender:
				return "A creature with defender can't attack."
			case .doublestrike:
				return "A creature with double strike deals both first-strike and reguar combat damage."
			case .firststrike:
				return "A creature with first strike deals combat damage before creatures without first strike."
			case .flying:
				return "A creature with flying can't be blocked except by creatures with flying and or reach."
			case .haste:
				return "A creature with haste can attack and tap as soon as it comes under your control."
			case .hexproof:
				return "A player or permanent with hexproof can't be the target of spells or abilities your opponents control."
			case .indestructible:
				return "Effects that say \"destroy\" don't destroy a permanent with indestructible, and if it's a creature, it can't be destroyed by damage."
			case .lifelink:
				return "Damage dealt by a creature, planeswalker or spell with lifelink also cause its controller to gain that much life."
			case .menace:
				return "A creature with menace can't be blocked except by two or more creatures."
			case .protection:
				return "A player or permanent with protection can't be blocked, targeted, dealt damage, enchanted, or equipped by anything with the specified quality."
			case .reach:
				return "A creature with reach can block creatures with flying."
			case .trample:
				return "A creature with trample can deal excess combat damage to the player or planeswalker it's attacking."
			case .vigilance:
				return "Attacking doesn't cause a creature with vigilance to tap."
			case .flash:
				return "You may cast spells with flash any time you could cast an instant."
			case .fear:
				return "A creature with fear can't be blocked except by artifact creatures and/or black creatures."
			case .shroud:
				return "A player or permanent with shroud can't be the target of spells or abilities."
			case .intimidate:
				return "A creature with intimidate can't be blocked except by artifact creatures and/or creatures that share a color with it."
			case .escape:
				return "You may cast this card from your graveyard for its escape cost."
			case .devotion:
				return "Each mana symbol of a certain color in the mana costs of permanents you control counts toward your devotion to that color."
			case .mutate:
				return "If you cast a creature spell for its mutate cost, put it over or under target non-Human creature you own. They mutate into the creature on top plus all abilities from under it."
			case .adventure:
				return "You may cast this card as an Adventure, after you do exile it. You may then cast the creature later from exile."
			case .proliferate:
				return "Choose any number of permanents and/or players, then give each another counter of each kind already there."
			case .constellation:
				return "This ability triggers when an enchantment you control enters."
			case .companion:
				return "If your starting deck meets the companion's restriction you may choose it to be your companion and cast it once from outside the game."
			case .scry:
				return "Look at a number of cards from the top of your library, then put any number of them on the bottom of your library and the rest on top in any order."
			case .fight:
				return "When two creatures fight each deals noncombat damage equal to its power to the other."
			case .undergrowth:
				return "This ability checks the number of creature cards in your graveyard."
			case .addendum:
				return "This spell has an additional effect if you cast it during your main phase."
			case .cycling:
				return "You may pay the cycling cost to discard this card and draw a card."
			case .embalm:
				return "You may pay the embalm cost to create a token that's a copy of this card, except it's white, it has no mana cost, and it's a Zombie in addition to its other types. You can activate this ability only any time you could cast a sorcery."
			case .ingest:
				return "Whenever a creature with ingest deals combat damage to a player, that player exiles the top card of their library."
			case .devoid:
				return "Cards with devoid have no color."
			case .entersthebattlefield:
				return nil
			case .skulk:
				return "A creature with skulk can't be blocked by creatures with greater power."
			case .tap:
				return nil
			case .more:
				return nil
			case .noattack:
				return "This creature can't attack."
			case .noblock:
				return "This creature can't block."
			case .noattackorblock:
				return "This creature can't attack or block."
			case .cantbeblocked:
				return "This creature can't be blocked."
			case .mustattack:
				return "This creature attacks each turn if able."
			case .castingcostmodifier:
				return nil
			case .additionalcastingcost:
				return nil
			case .whenyoucastthisspell:
				return nil
			case .whenthiscreaturemutates:
				return nil
			case .whenyoucycle:
				return nil
			case .horsemanship:
				return "A creature with horsemanship can only be blocked by creatures with horsemanship."
			case .morph:
				return "You may pay {3} to cast this creature face down as a 2/2 creature {3}. Turn it face up any time for its morph cost."
			case .megamorph:
				return "You may pay {3} to cast this creature face down as a 2/2 creature {3}. Turn it face up any time for its megamorph cost and put a +1/+1 counter on it."
			case .kicker:
				return "You may pay the kicker cost as you cast this spell for an additional effect."
			case .multikicker:
				return "You may pay the multikicker cost any number of times as you cast this spell for an additional effect."
			case .flashback:
				return "You may cast this card from your graveyard for its flashback cost. Then exile it."
			case .echo:
				return "At the beginning of your upkeep, if this came under your control since the beginning of your last upkeep, sacrifice it unless you pay its echo cost."
			case .equip:
				return "Attach this permanent to target creature you control. Activate this ability only any time you could cast a sorcery."
			case .surveil:
				return "Look at the top N cards of your library, then put any number of them into your graveyard and the rest on top of your library in any order."
			case .adapt:
				return "If this creature has no +1/+1 counters on it, put N +1/+1 counter(s) on it."
			case .evolve:
				return "Whenever a creature you control enters, if that creature has greater power or toughness than this creature, put a +1/+1 counter on this creature."
			case .haunt:
				return "When this creature dies, exile it haunting target creature."
			case .afterlife:
				return "When this creature dies, create N 1/1 white and black Sprit creature token(s) with flying."
				/*
			case .fortify:
				<#code#>
			case .transmute:
				<#code#>
			case .cipher:
				<#code#>
			case .forecast:
				<#code#>
			case .dredge:
				<#code#>
			case .ferocious:
				<#code#>
			case .extort:
				<#code#>
			case .hellbent:
				<#code#>
			case .graft:
				<#code#>
			case .battalion:
				<#code#>
			case .madness:
				<#code#>
			case .replicate:
				<#code#>
			case .dash:
				<#code#>
			case .radiance:
				<#code#>
			case .raid:
				<#code#>
			case .unleash:
				<#code#>
			case .cantbecountered:
				<#code#>
			case .affinity:
				<#code#>
			case .adamant:
				<#code#>
			case .detain:
				<#code#>
			case .bloodthirst:
				<#code#>
			case .bloodrush:
				<#code#>
			case .prowess:
				<#code#>
			case .overload:
				<#code#>
			case .mentor:
				<#code#>
			case .populate:
				<#code#>
			case .riot:
				<#code#>
			case .scavenge:
				<#code#>
			case .exploit:
				<#code#>
			case .outlast:
				<#code#>
			case .formidable:
				<#code#>
			case .delve:
				<#code#>
			case .convoke:
				<#code#>
			case .spectacle:
				<#code#>
			case .tombstone:
				<#code#>
			case .bolster:
				<#code#>
			case .jumpstart:
				<#code#>
			case .instant:
				<#code#>
			case .transform:
				<#code#>
			case .sorcery:
				<#code#>
			case .enchantment:
				<#code#>
			case .custom(_, name: let name, styles: let styles, isInherent: let isInherent, isPermanent: let isPermanent):
				<#code#>
			case .gained(_):
				<#code#>
			case .counter(_):
				<#code#>
				*/
			default: return nil
			}
		}
	}

	fileprivate func updateManaCost() {
		manaCostLabel.layer.shadowColor = UIColor.black.cgColor
		manaCostLabel.layer.shadowRadius = 0
		manaCostLabel.layer.masksToBounds = false
		manaCostLabel.layer.shadowOpacity = 1
		manaCostLabel.layer.shadowOffset = CGSize(width: manaCostLabel.frame.height * -0.04,
												  height: manaCostLabel.frame.height * 0.05)

		guard let cost = properties.manaCost?.replacingOccurrences(of: "}{", with: "} {") else {
			manaCostLabel.text = nil
			return
		}

		let attributedString = NSMutableAttributedString(string: cost, attributes: [.kern: manaCostLabel.frame.height * -0.07])

		for symbol in MTGSymbolName.allCases {
			let attachment = NSTextAttachment()
			attachment.image = symbol.image
			attachment.setImageHeight(height: manaCostLabel.frame.height * 0.8)
			attachment.bounds = attachment.bounds.offsetBy(dx: 0, dy: -(manaCostLabel.frame.height * 0.15))
			let attachmentString = NSAttributedString(attachment: attachment)

			while let range = attributedString.string.range(of: symbol.rawValue) {
				attributedString.replaceCharacters(in: NSRange(range, in: attributedString.string), with: attachmentString)
			}
		}

		let fontDescriptor = manaCostLabel.font.fontDescriptor
		manaCostLabel.font = UIFont(descriptor: fontDescriptor, size: contentView.frame.width * 0.0825)
		manaCostLabel.attributedText = attributedString
	}

	fileprivate func updateIcons() {
		iconImageViews.forEach { $0.isHidden = true }
		iconPlates.forEach {
			$0.isHidden = true
			$0.toolTip = nil
		}

		var visibleIcons = properties.icons.filter { $0.image != nil }

		let maxIcons = properties.borderStyle == .planeswalker ? 2 : 4

		if visibleIcons.count > maxIcons {
			visibleIcons.removeAll { $0 == .more }
			visibleIcons = Array(visibleIcons.prefix(maxIcons-1))
			visibleIcons.append(.more)
		}

		for (index, icon) in visibleIcons.prefix(maxIcons).enumerated() {
			iconImageViews[index].isHidden = false
			iconPlates[index].isHidden = false
			iconImageViews[index].image = icon.image

			let plate: UIImage? = {
				if icon.isGold {
					return UIImage(named: "icon-reminder")
				} else if case .gained = icon {
					return UIImage(named: "icon-gained")
				} else if case .counter = icon {
					return UIImage(named: "icon-counter")
				} else {
					return UIImage(named: "icon")
				}
			}()

			if case .counter = icon {
				iconImageViews[index].tintColor = .white
			} else {
				iconImageViews[index].tintColor = .black
			}

			iconPlates[index].image = plate
			iconPlates[index].isUserInteractionEnabled = true

			iconPlates[index].toolTip = icon.name
		}
	}

	private func updateBackground() {
		let artViewWidthMultiplier: CGFloat = {
      if properties.isRetro {
//        return 0.78 // True value
        return 0.85 // Scaled up slightly because of incorrectly cropped Scryfall cards (BRC decks, etc)
      } else if properties.isFullArt {
				return 1.015
      } else if properties.isPinlineFrame {
				return 0.931
      } else if properties.colors.isEmpty && properties.backgroundStyle != .artifact && properties.backgroundStyle != .snowArtifact && properties.backgroundStyle != .vehicle && properties.backgroundStyle != .universesBeyondVehicle && properties.backgroundStyle != .universesBeyondArtifact && (properties.backgroundStyle != .land && properties.backgroundStyle != .universesBeyondLand && properties.backgroundStyle != .snowLand) && properties.objectType != .emblem {
				return 0.931
			} else if properties.borderStyle == .planeswalker {
				return 0.88
			} else {
				return 0.848
			}
		}()

		let artViewCenterYMultiplier: CGFloat = {
      if properties.isRetro {
        return 0.93
      } else if properties.isFullArt {
				return 1.137
			} else {
				return 1
			}
		}()

		if artViewWidthConstraint.multiplier != artViewWidthMultiplier {
			artViewWidthConstraint.isActive = false
			artViewWidthConstraint = artImageView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: artViewWidthMultiplier)
			artViewWidthConstraint.isActive = true
		}

		if artViewCenterYConstraint.multiplier != artViewCenterYMultiplier {
			artViewCenterYConstraint.isActive = false
			artViewCenterYConstraint = NSLayoutConstraint(item: artImageView!, attribute: .centerY, relatedBy: .equal, toItem: contentView, attribute: .centerY, multiplier: artViewCenterYMultiplier, constant: 1)
			artViewCenterYConstraint.isActive = true
		}


    let titleStackYMultiplier = properties.isRetro ? 0.275 : 0.295

    if titleStackYConstraint.multiplier != titleStackYMultiplier {
      titleStackYConstraint.isActive = false
      titleStackYConstraint = NSLayoutConstraint(item: titleStack!, attribute: .centerY, relatedBy: .equal, toItem: contentView, attribute: .centerY, multiplier: titleStackYMultiplier, constant: 1)
      titleStackYConstraint.isActive = true
    }

    let valueYMultiplier = properties.isRetro ? 1.62 : 1.72

    if valueYConstraint.multiplier != valueYMultiplier {
      valueYConstraint.isActive = false
      valueYConstraint = NSLayoutConstraint(item: valueLabel!, attribute: .centerY, relatedBy: .equal, toItem: contentView, attribute: .centerY, multiplier: valueYMultiplier, constant: 1)
      valueYConstraint.isActive = true
    }

    if properties.borderStyle == .planeswalker && !properties.isFullArt && !properties.isRetro {
			artImageView.layer.masksToBounds = true
			artImageView.layer.cornerRadius = cardView.frame.width * 0.061
		} else {
			artImageView.layer.cornerRadius = 0
		}

		topBarImageView.image = topBarImage
		bottomBarImageView.image = bottomBarImage

    borderImageView.image = borderImage
    borderImageView.contentMode = properties.isRetro ? .scaleAspectFill : .scaleAspectFit

		overlayImageView.image = overlayImage
		backgroundImageView.image = backgroundImage
		crownImageView.image = crownImage
		ptImageView.image = valueImage

		tappedDarkeningView.backgroundColor = properties.isTapped ? #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.4) : .clear
		tappedDarkeningView.image = properties.isChained ? UIImage(named: "chains") : nil

		cardView.backgroundColor = properties.borderColor.color
    bottomBlock.isHidden = properties.isFullArt || (properties.backgroundStyle == .planeswalker && properties.objectType != .emblem) || properties.isRetro
		bottomBlock.tintColor = properties.borderColor.color

		if let title = properties.flavorName ?? properties.name, !title.isEmpty {
      textLabel.text = title.withSmartQuotes
		} else {
			textLabel.text = nil
		}

    for label in [textLabel!, valueLabel!] {
      if properties.isRetro {
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowRadius = 0
        label.layer.masksToBounds = false
        label.layer.shadowOpacity = 1
        label.layer.shadowOffset = CGSize(
          width: 2 * label.frame.height * 0.04,
          height: 2 * label.frame.height * 0.05
        )
      } else {
        label.layer.shadowColor = UIColor.clear.cgColor
        label.layer.shadowOpacity = 0
      }
    }

		if properties.flavorName != nil {
      realNameLabel.text = properties.name?.withSmartQuotes
			realNameLabel.isHidden = false
		} else {
			realNameLabel.text = nil
			realNameLabel.isHidden = true
		}

		if let typeLine = properties.typeLine, !typeLine.isEmpty {
			typeLineLabel.text = typeLine
		} else {
			typeLineLabel.text = nil
		}

		let textLabelColor: UIColor = {
			if properties.objectType == .token {
				return #colorLiteral(red: 0.8666666667, green: 0.7607843137, blue: 0.4039215686, alpha: 1)
      } else if properties.isRetro {
        return .white
      } else if properties.objectType == .emblem {
				return #colorLiteral(red: 0.8980834926, green: 0.9056943696, blue: 0.9056943696, alpha: 1)
			} else if properties.isInverted {
				return .white
			} else {
				return .black
			}
		}()

		textLabel.textColor = textLabelColor
		typeLineLabel.textColor = properties.isInverted ? .white : .black

		let fontName = properties.objectType == .card ? "Beleren2016" : "Beleren Small Caps"
		textLabel.font = UIFont(name: fontName, size: textLabel.font.pointSize)

		textLabel.textAlignment = properties.objectType == .card ? .left : .center

    if properties.isInverted || properties.backgroundStyle == .vehicle || properties.backgroundStyle == .universesBeyondVehicle || properties.isRetro {
			valueLabel.textColor = .white
		} else {
			valueLabel.textColor = .black
		}

		if let value = properties.value, value.length > 0 {
			if properties.borderStyle == .planeswalker {
				loyaltyLabel.text = value.string
				valueLabel.attributedText = nil
			} else {
				loyaltyLabel.text = nil
				valueLabel.attributedText = value
			}
		} else {
			valueLabel.attributedText = nil
			loyaltyLabel.text = nil
		}

		if let dfcIcon = properties.dfcIcon, let image = dfcIcon.image {
			dfcImageView.isHidden = false
			dfcIconImageView.isHidden = false
			dfcImageView.image = dfcMaskImage
			dfcIconImageView.image = image
			dfcSpacerView.isHidden = false
		} else {
			dfcImageView.isHidden = true
			dfcIconImageView.isHidden = true
			dfcImageView.image = nil
			dfcIconImageView.image = nil
			dfcSpacerView.isHidden = true
		}

		artImageView.image = properties.art

		updateIcons()

		updateManaCost()
	}

}

// MARK: - Ability frames

/// Frames for abilities on the stack (Josh's ability frames, at CardConjurer's M15 proportions:
/// 2010 × 2814, kept at half size in MagicBoardResources/AbilityFrames). Each piece follows the
/// same rules as a mini card's: the rules box takes the card's background, the outer frame its
/// border (split down the middle for two colors), and the name and type bars its bar.
public extension MTGCardView {
	/// Where an ability frame's pieces sit, as fractions of the frame (CardConjurer's packM15Regular).
	enum AbilityLayout {
		public static let art = CGRect(x: 0.0767, y: 0.1129, width: 0.8476, height: 0.4429)
		public static let title = CGRect(x: 0.0854, y: 0.0522, width: 0.8292, height: 0.0543)
		public static let titleSize: CGFloat = 0.0381
		public static let type = CGRect(x: 0.0854, y: 0.5664, width: 0.8292, height: 0.0543)
		public static let typeSize: CGFloat = 0.0324
		/// CardConjurer's rules box is {0.086, 0.6303, 0.828, 0.2875}, but these frames round off
		/// below about 0.8 of the height, so the text stays in the part that's still full width.
		public static let rules = CGRect(x: 0.092, y: 0.6303, width: 0.816, height: 0.2)
		public static let rulesSize: CGFloat = 0.0362
		/// Width ÷ height.
		public static let aspect: CGFloat = 2010.0 / 2814.0
	}

	private static var abilityFrameCache: [String: UIImage] = [:]

	/// Every ability frame's outline (they all share one shape), for clipping and outlining.
	static let abilityFrameSilhouette: UIImage? = {
		guard let url = MagicBoardResources.bundle.url(forResource: "c", withExtension: "webp", subdirectory: "AbilityFrames/regular"),
			  let frame = UIImage(contentsOfFile: url.path) else { return nil }
		let size = frame.size
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		// The frame with its art window filled in.
		return UIGraphicsImageRenderer(size: size, format: format).image { context in
			frame.draw(at: .zero)
			UIColor.black.setFill()
			let art = AbilityLayout.art
			context.fill(CGRect(x: art.minX * size.width, y: art.minY * size.height, width: art.width * size.width, height: art.height * size.height))
		}
	}()

	/// The composed ability frame for a card's frame properties (the art window is transparent).
	static func abilityFrame(for properties: CardProperties) -> UIImage? {
		let style = properties.backgroundStyle
		// No ub-nyx mini card frames exist yet, so ub-nyx sources use the plain Universes Beyond frame.
		let folder = style?.isUniversesBeyond == true ? "ub" : style?.isNyxtouched == true ? "nyx" : "regular"
		let colors = properties.colors.map { $0.initial.lowercased() }
		let isLand = style?.isLand == true
		let isVehicle = style?.isVehicle == true
		let isArtifact = style?.isArtifact == true || isVehicle
		let isHybrid = colors.count == 2 && (properties.isHybrid || properties.objectType == .token)
		// Each piece is one letter, or two that fade from left to right. A "regular/" prefix
		// takes that letter from the regular frames whatever the source's frame folder.
		let frame: [String], pinline: [String], rules: [String], typeTitle: [String]
		if isLand {
			// Lands: the colored land frames throughout (two colors fade); colorless lands use the plain land frame.
			let land = colors.count == 1 ? [colors[0] + "l"] : colors.count == 2 ? colors.map { $0 + "l" } : colors.isEmpty ? ["l"] : ["ml"]
			frame = land; pinline = land; rules = land
			typeTitle = colors.count == 2 ? ["l"] : land
		} else {
			// Everything else; an artifact or Vehicle only swaps in its own outer frame.
			let colorFrame: [String]
			switch colors.count {
			case 0: colorFrame = [isArtifact ? "a" : "c"]; pinline = colorFrame; rules = colorFrame; typeTitle = colorFrame
			case 1: colorFrame = colors; pinline = colors; rules = colors; typeTitle = colors
			// Hybrid: everything fades from one color to the other, under colorless bars.
			case 2 where isHybrid: colorFrame = colors; pinline = colors; rules = colors; typeTitle = ["c"]
			// Two colors: a gold frame and bars, with the pinlines and rules box fading between the colors.
			case 2: colorFrame = ["m"]; pinline = colors; rules = colors; typeTitle = ["m"]
			default: colorFrame = ["m"]; pinline = ["m"]; rules = ["m"]; typeTitle = ["m"]
			}
			// Vehicles share one riveted frame; Universes Beyond Vehicles keep their UB pieces inside it.
			frame = isVehicle ? ["regular/v"] : isArtifact ? ["a"] : colorFrame
		}
		let key = "\(folder)|\(frame)|\(pinline)|\(rules)|\(typeTitle)"
		if let cached = abilityFrameCache[key] { return cached }

		func image(_ piece: String) -> UIImage? {
			let parts = piece.split(separator: "/").map(String.init)
			let letter = parts.last ?? piece
			// Nyx has no land / vehicle / colored-land variants: use regular.
			for candidate in parts.count > 1 ? [parts[0]] : [folder, "regular"] {
				if let url = MagicBoardResources.bundle.url(forResource: letter, withExtension: "webp", subdirectory: "AbilityFrames/\(candidate)"),
				   let image = UIImage(contentsOfFile: url.path) { return image }
			}
			return nil
		}
		func mask(_ name: String) -> UIImage? {
			MagicBoardResources.bundle.url(forResource: name, withExtension: "png", subdirectory: "AbilityFrames/masks")
				.flatMap { UIImage(contentsOfFile: $0.path) }
		}
		guard let first = image(frame[0]) else { return nil }
		let size = first.size
		let rect = CGRect(origin: .zero, size: size)
		/// The fade from a piece's left color to its right one: a soft step across the middle fifth,
		/// like the mini cards' mask (white where the right color shows).
		let fade: CGImage? = {
			let width = 100
			var pixels = (0..<width).map { x -> UInt8 in
				let t = (CGFloat(x) / CGFloat(width - 1) - 0.4) / 0.2
				return UInt8(max(0, min(1, t)) * 255)
			}
			guard let provider = CGDataProvider(data: Data(bytes: &pixels, count: width) as CFData) else { return nil }
			return CGImage(width: width, height: 1, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
			               space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
			               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
		}()
		/// Clips the current (UIKit-flipped) context to a grayscale mask, white where drawing shows.
		func clip(_ context: CGContext, to mask: CGImage) {
			context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
			context.clip(to: rect, mask: mask)
			context.scaleBy(x: 1, y: -1); context.translateBy(x: 0, y: -size.height)
		}
		/// Draws one piece: one letter, or two fading from left to right.
		func draw(_ letters: [String], clippedTo maskName: String?) {
			guard let context = UIGraphicsGetCurrentContext() else { return }
			context.saveGState()
			if let maskName, let cg = mask(maskName)?.cgImage { clip(context, to: cg) }
			image(letters[0])?.draw(in: rect)
			if letters.count > 1, let fade {
				context.saveGState()
				clip(context, to: fade)
				image(letters[1])?.draw(in: rect)
				context.restoreGState()
			}
			context.restoreGState()
		}
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		let composed = UIGraphicsImageRenderer(size: size, format: format).image { _ in
			draw(frame, clippedTo: nil)
			draw(pinline, clippedTo: "pinline")
			draw(rules, clippedTo: "rules")
			draw(typeTitle, clippedTo: "typetitle")
		}
		abilityFrameCache[key] = composed
		return composed
	}
}
