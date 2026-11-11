//
//  CardView.swift
//  CardTEst
//
//  Created by Josh Birnholz on 4/29/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import UIKit

fileprivate func UIImage(named name: String) -> UIImage? {
	let bundle = Bundle(for: MTGCardView.self)
	return UIImage(named: name, in: bundle, compatibleWith: nil)
}

public class MTGCardView: UIView {
	
	public struct CardProperties {
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
		public var backgroundStyle: MTGCardView.BackgroundStyle?
		public var overlay: MTGCardView.OverlayStyle?
		public var value: NSAttributedString? = nil
		public var manaCost: String?
		public var isFullArt = false
		public var isInverted = false
		
		public init(name: String? = nil, flavorName: String? = nil, typeLine: String? = nil, oracleText: String? = nil, art: UIImage? = nil, colors: [MTGCardView.Color] = [], icons: [MTGCardView.Icon] = [], borderStyle: MTGCardView.BorderStyle? = nil, borderColor: MTGCardView.BorderColor = .black, isHybrid: Bool = false, objectType: MTGCardView.Object = .card, backgroundStyle: MTGCardView.BackgroundStyle? = nil, overlay: MTGCardView.OverlayStyle? = nil, value: NSAttributedString? = NSAttributedString(string: "4/3"), manaCost: String? = nil, isFullArt: Bool = false, isInverted: Bool = false) {
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
		}
	}
	
	public var cardImage: UIImage? {
		didSet {
			cardImageView.image = cardImage
			setCardViewHidden(true)
		}
	}
	
	public var properties: CardProperties? {
		didSet {
			if properties != nil {
				updateBackground()
				setCardViewHidden(false)
			} else {
				setCardViewHidden(true)
			}
		}
	}
	
	private func setCardViewHidden(_ cardViewIsHidden: Bool) {
		let cardImageIsHidden = !cardViewIsHidden
		
		cardView.isHidden = cardViewIsHidden
		manaCostLabel.isHidden = cardViewIsHidden
		
		cardImageView.isHidden = cardImageIsHidden
	}
	
	@IBInspectable public var areIconsHidden: Bool {
		get {
			iconStackView.isHidden
		}
		set {
			iconStackView.isHidden = newValue
		}
	}
	
	@IBInspectable public var isManaCostHidden: Bool {
		get {
			manaCostLabel.isHidden
		}
		set {
			manaCostLabel.isHidden = newValue
		}
	}
	
	@IBOutlet private var contentView: UIView!
	@IBOutlet private weak var cardView: UIView!
	
	@IBOutlet private weak var valueLabel: UILabel!
	@IBOutlet private weak var loyaltyLabel: UILabel!
	@IBOutlet private weak var textLabel: UILabel!
	@IBOutlet private weak var topBarImageView: UIImageView!
	@IBOutlet private weak var bottomBarImageView: UIImageView!
	@IBOutlet private weak var borderImageView: UIImageView!
	@IBOutlet private weak var overlayImageView: UIImageView!
	@IBOutlet private weak var crownImageView: UIImageView!
	@IBOutlet private weak var backgroundImageView: UIImageView!
	@IBOutlet private(set) weak var artImageView: UIImageViewAligned!
	@IBOutlet private weak var ptImageView: UIImageView!
	@IBOutlet private weak var manaCostLabel: UILabel!
	@IBOutlet private weak var typeLineLabel: UILabel!
	@IBOutlet private weak var realNameLabel: UILabel!
	@IBOutlet private weak var iconStackView: UIStackView!
	@IBOutlet private weak var cardImageView: UIImageView!
	
	@IBOutlet private var iconPlates: [UIImageView]!
	@IBOutlet private var iconImageViews: [UIImageView]!
	
	@IBOutlet private weak var artViewWidthConstraint: NSLayoutConstraint!
	@IBOutlet private weak var artViewCenterYConstraint: NSLayoutConstraint!
	
	override init(frame: CGRect) {
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
		updateBackground()
	}
	
	public override func layoutSubviews() {
		super.layoutSubviews()
		updateFontSize()
		updateValueFontSize()
		updateRealNameFontSize()
		if let cost = properties?.manaCost, !cost.isEmpty {
			updateManaCost()
		}
		
//		artImageView.alignment = UIImageViewAlignmentMaskTop
		
		cardView.layer.masksToBounds = true
//		cardView.mask = cardMask
		cardView.layer.cornerRadius = cardView.frame.width * 0.02275
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
		
		var initial: String {
			switch self {
			case .white: return "W"
			case .blue: return "U"
			case .black: return "B"
			case .red: return "R"
			case .green: return "G"
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
		
		init?(initial: String) {
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
	
	public enum BackgroundStyle {
		case artifact
		case vehicle
		case land
		case planeswalker
		case nyxtouched
		case nyxtouchedArtifact
	}
	
	public enum BorderStyle {
		case legendary
		case planeswalker
	}
	
	public enum BorderColor: String {
		case black
		case borderless
		case gold
		case silver
		case white
		
		fileprivate var color: UIColor {
			switch self {
			case .black, .borderless: return .black
			case .white: return .white
			case .gold: return #colorLiteral(red: 0.6519989967, green: 0.529964149, blue: 0.2993342876, alpha: 1)
			case .silver: return #colorLiteral(red: 0.6432507038, green: 0.6843975186, blue: 0.719160378, alpha: 1)
			}
		}
	}
	
	public enum OverlayStyle {
		case companion
		case nyxtouched
	}
	
	private var topBarImage: UIImage? {
		guard let properties = properties else { return nil }
		
		let suffix: String = {
			var result = ""
			
			if properties.isInverted {
				result += "-inverted"
			}
			
			if properties.borderStyle == .planeswalker {
				result += "-planeswalker"
			}
			
			// TODO: Add inverted bars for planeswalkers
			
			return result
		}()
		
		if properties.objectType == .token || properties.objectType == .emblem {
			return UIImage(named: "bar-token")
		} else if (properties.colors.isEmpty || properties.colors.count == 2) && properties.backgroundStyle == .land {
			return UIImage(named: "bar-land\(suffix)")
		} else if properties.colors.isEmpty && properties.backgroundStyle == .artifact {
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
		guard let properties = properties else { return nil }
		
		let suffix: String = {
			var result = ""
			
			if properties.isInverted {
				result += "-inverted"
			}
			
			return result
		}()
		
		if properties.isFullArt || properties.borderStyle == .planeswalker {
			return nil
		} else if (properties.colors.isEmpty || properties.colors.count == 2) && properties.backgroundStyle == .land {
			return UIImage(named: "bar-land\(suffix)")
		} else if properties.colors.isEmpty && properties.backgroundStyle == .artifact {
			return UIImage(named: "bar-artifact\(suffix)")
		} else if properties.colors.count == 1, let color = properties.colors.first {
			return UIImage(named: "bar-\(color.rawValue)\(suffix)")
		} else if properties.colors.count >= 2 && !((properties.isHybrid || properties.objectType == .token) && properties.colors.count == 2) {
			return UIImage(named: "bar-gold\(suffix)")
		} else if properties.isHybrid || properties.objectType == .token {
			return UIImage(named: "bar-land\(suffix)")
		} else {
			return UIImage(named: "bar-colorless\(suffix)")
		}
	}
	
	private var overlayImage: UIImage? {
		guard let properties = properties else { return nil }
		
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
			return UIImage(named: "overlay-\(properties.colors[0].rawValue)-\(properties.colors[1].rawValue)\(suffix)")
		} else {
			return UIImage(named: "overlay-gold\(suffix)")
		}
	}
	
	private var valueImage: UIImage? {
		guard let properties = properties else { return nil }
		
		guard let value = properties.value, value.length > 0 else { return nil }
		
		let suffix: String = {
			var result = ""
			
			if properties.isInverted {
				result += "-inverted"
			}
			
			return result
		}()
		
		if properties.backgroundStyle == .vehicle {
			return UIImage(named: "pt-vehicle")
		} else if properties.borderStyle == .planeswalker {
			return UIImage(named: "pt-loyalty")
		} else if (properties.colors.isEmpty || properties.colors.count == 2) && properties.backgroundStyle == .land {
			return UIImage(named: "pt-land\(suffix)")
		} else if properties.colors.isEmpty && properties.backgroundStyle == .artifact {
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
		guard let properties = properties else { return nil }
		
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
		} else if properties.colors.isEmpty && properties.backgroundStyle == .land {
			return UIImage(named: "border-land\(suffix)")
		} else if properties.colors.isEmpty && properties.backgroundStyle == .artifact {
			return UIImage(named: "border-artifact\(suffix)")
		} else if properties.colors.count == 1, let color = properties.colors.first {
			return UIImage(named: "border-\(color.rawValue)\(suffix)")
		} else if properties.colors.count > 2 {
			return UIImage(named: "border-gold\(suffix)")
		} else if properties.colors.count == 2 {
			return UIImage(named: "border-\(properties.colors[0].rawValue)-\(properties.colors[1].rawValue)\(suffix)")
		} else {
			return UIImage(named: "border-colorless\(suffix)")
		}
	}
	
	private var crownImage: UIImage? {
		guard let properties = properties else { return nil }
		
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
		} else if properties.colors.isEmpty && properties.backgroundStyle == .land {
			return UIImage(named: "crown-land\(suffix)")
		} else if properties.colors.isEmpty && properties.backgroundStyle == .artifact {
			return UIImage(named: "crown-artifact\(suffix)")
		} else if properties.colors.count == 1, let color = properties.colors.first {
			return UIImage(named: "crown-\(color.rawValue)\(suffix)")
		} else if properties.colors.count > 2 {
			return UIImage(named: "crown-gold\(suffix)")
		} else if properties.colors.count == 2 {
			return UIImage(named: "crown-\(properties.colors[0].rawValue)-\(properties.colors[1].rawValue)\(suffix)")
		} else {
			return UIImage(named: "crown-colorless\(suffix)")
		}
	}
	
	private var backgroundImage: UIImage? {
		guard let properties = properties else { return nil }
		
		let suffix: String = {
			if properties.backgroundStyle == .planeswalker {
				return "-planeswalker"
			} else if properties.backgroundStyle == .nyxtouched || properties.backgroundStyle == .nyxtouchedArtifact {
				return "-nyx"
			} else {
				return ""
			}
		}()
		
		if properties.isFullArt {
			return UIImage(named: "bg-full")
		} else if properties.backgroundStyle == .nyxtouchedArtifact {
			return UIImage(named: "bg-colorless-nyx")
		} else if properties.backgroundStyle == .land {
			return UIImage(named: "bg-land")
		} else if properties.backgroundStyle == .artifact {
			return UIImage(named: "bg-artifact")
		} else if properties.backgroundStyle == .vehicle {
			return UIImage(named: "bg-vehicle")
		} else if properties.colors.count == 1, let color = properties.colors.first {
			return UIImage(named: "bg-\(color.rawValue)\(suffix)")
		} else if properties.colors.count > 2 {
			return UIImage(named: "bg-gold\(suffix)")
		} else if properties.colors.isEmpty {
			return UIImage(named: "bg-colorless\(suffix)")
		} else if properties.isHybrid || properties.objectType == .token {
			return UIImage(named: "bg-\(properties.colors[0].rawValue)-\(properties.colors[1].rawValue)\(suffix)")
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
		case custom(UIImage, name: String? = nil, styles: Set<Icon.Style> = [], isInherent: Bool = false, isPermanent: Bool = false)
		case gained(Icon)
		case counter(Icon)
		
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
					 .forecast],
				.abilityWord:
					[.constellation,
					 .adamant,
					 .addendum,
					 .hellbent,
					 .bloodrush,
					 .formidable,
					 .undergrowth,
					 .ferocious,
					 .radiance,
					 .raid,
					 .battalion],
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
					 .overload],
				.mention:
					[.devotion,
					 .haunt,
					 .surveil,
					 .populate,
					 .bolster,
					 .scry,
					 .fight,
					 .exploit,
					 .proliferate,
					 .detain,
					 .adapt],
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
					 .graft]
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
			[.deathtouch, .defender, .doublestrike, .firststrike, .flying, .haste, .hexproof, .indestructible, .lifelink, .menace, .protection, .reach, .trample, .vigilance, .flash, .noblock, .noattackorblock, .cantbeblocked, .fear, .shroud, .intimidate, .escape, .devotion, .mutate, .companion, .constellation, .embalm, .ingest, .devoid, .skulk, .mustattack, .castingcostmodifier, .whenyoucastthisspell, .cantbecountered, .cycling, .whenyoucycle, .equip, .adamant, .echo, .horsemanship, .kicker, .multikicker, .flashback, .madness, .morph, .megamorph, .affinity, .haunt, .addendum, .afterlife, .extort, .surveil, .cipher, .transmute, .spectacle, .unleash, .hellbent, .bloodthirst, .bloodrush, .riot, .convoke, .populate, .forecast, .detain, .dredge, .scavenge, .undergrowth, .graft, .evolve, .adapt, .replicate, .overload, .jumpstart, .radiance, .battalion, .mentor, .raid, .formidable, .ferocious, .dash, .delve, .exploit, .prowess, .outlast, .bolster, .proliferate, .scry, .fight]
		}
		
		// True for inherent properties of cards, like alt layouts.
		public var isInherent: Bool {
			switch self {
			case .adventure, .transform:
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
			case .flash, .haste, .entersthebattlefield, .castingcostmodifier, .additionalcastingcost, .whenyoucastthisspell, .companion, .mutate, .cantbecountered, .adventure, .whenyoucycle, .cycling, .adamant, .kicker, .multikicker, .flashback, .madness, .morph, .megamorph, .affinity, .addendum, .transmute, .spectacle, .unleash, .bloodthirst, .bloodrush, .riot, .convoke, .forecast, .scavenge, .undergrowth, .replicate, .overload, .dash, .delve:
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
			case .haunt, .afterlife, .extort:
				return UIImage(named: "Icon_Orzhov")
			case .addendum, .forecast, .detain:
				return UIImage(named: "Icon_Azorius")
			case .surveil, .cipher, .transmute:
				return UIImage(named: "Icon_Dimir")
			case .spectacle, .unleash, .hellbent:
				return UIImage(named: "Icon_Rakdos")
			case .bloodthirst, .bloodrush, .riot:
				return UIImage(named: "Icon_Gruul")
			case .convoke, .populate:
				return UIImage(named: "Icon_Selesnya")
			case .dredge, .scavenge, .undergrowth:
				return UIImage(named: "Icon_Golgari")
			case .graft, .evolve, .adapt:
				return UIImage(named: "Icon_Simic")
			case .replicate, .overload, .jumpstart:
				return UIImage(named: "Icon_Izzet")
			case .radiance, .battalion, .mentor:
				return UIImage(named: "Icon_Boros")
			case .raid:
				return UIImage(named: "Icon_Mardu")
			case .formidable:
				return UIImage(named: "Icon_Atarka")
			case .ferocious:
				return UIImage(named: "Icon_Temur")
			case .dash:
				return UIImage(named: "Icon_Kolaghan")
			case .delve:
				return UIImage(named: "Icon_Sultai")
			case .exploit:
				return UIImage(named: "Icon_Silumgar")
			case .prowess:
				return UIImage(named: "Icon_Jeskai")
			case .outlast:
				return UIImage(named: "Icon_Abzan")
			case .bolster:
				return UIImage(named: "Icon_Dromoka")
			case .multikicker:
				return Icon.kicker.image
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
				return "This ability triggers when an enchantment enters the battlefield under your control."
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
				return "Whenever a creature enters the battlefield under your control, if that creature has greater power or toughness than this creature, put a +1/+1 counter on this creature."
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
		guard let properties = properties else {
			manaCostLabel.text = nil
			return
		}
		
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
		guard let properties = properties else { return }
		
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
		guard let properties = properties else { return }
		
		let artViewWidthMultiplier: CGFloat = {
			if properties.isFullArt {
				return 1.015
			} else if properties.colors.isEmpty && properties.backgroundStyle != .artifact {
				return 0.931
			} else if properties.borderStyle == .planeswalker {
				return 0.88
			} else {
				return 0.848
			}
		}()
		
		let artViewCenterYMultiplier: CGFloat = {
			if properties.isFullArt {
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
			artViewCenterYConstraint = NSLayoutConstraint(item: artImageView, attribute: .centerY, relatedBy: .equal, toItem: contentView, attribute: .centerY, multiplier: artViewCenterYMultiplier, constant: 1)
			artViewCenterYConstraint.isActive = true
		}
		
		if properties.borderStyle == .planeswalker {
			artImageView.layer.masksToBounds = true
			artImageView.layer.cornerRadius = cardView.frame.width * 0.061
		} else {
			artImageView.layer.cornerRadius = 0
		}
		
		topBarImageView.image = topBarImage
		bottomBarImageView.image = bottomBarImage
		borderImageView.image = borderImage
		overlayImageView.image = overlayImage
		backgroundImageView.image = backgroundImage
		crownImageView.image = crownImage
		ptImageView.image = valueImage
		
		cardView.backgroundColor = properties.borderColor.color
		
		if let title = properties.flavorName ?? properties.name, !title.isEmpty {
			textLabel.text = title
		} else {
			textLabel.text = nil
		}
		
		if properties.flavorName != nil {
			realNameLabel.text = properties.name
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
		
		if properties.isInverted || properties.backgroundStyle == .vehicle {
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
		
		artImageView.image = properties.art
		
		updateIcons()
		
		updateManaCost()
	}
	
}
