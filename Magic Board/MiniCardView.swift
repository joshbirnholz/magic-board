//
//  MiniCardView.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/12/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import CardService
import RxSwift
import RxCocoa
import CardView
import SwiftUI

func romanNumeralFor(_ n: Int) -> String? {
	guard n > 0 && n < 4000 else {
		return nil
	}
	
	var returnString = ""
	let arabicNumbers = [1000,  900, 500,  400, 100,   90,  50,   40,  10,    9,   5,    4,  1]
	let romanLetters  = [ "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]

	var num = n
	for (ar, rome) in zip(arabicNumbers, romanLetters) {
		let repeats = num / ar
		returnString += String(repeating: rome, count: repeats)
		num = num % ar
	}
	return returnString
}

class MiniCardView: UIView {
	
	private var bag = DisposeBag()
	/// The frame colors the card itself implies (a land's from the mana it makes), used when no colors are set.
	private var defaultFrameColors: [MTGCardView.Color] = []

	@IBOutlet var contentView: UIView!
	@IBOutlet weak var countersStackView: UIStackView!
	@IBOutlet weak var cardView: RMShapedImageView!
	
    /// Rules supplies this from the engine. Sandbox views keep their existing appearance.
    var showsRulesSummoningSickness = false {
        didSet {
            guard showsRulesSummoningSickness != oldValue else { return }
            setNeedsLayout()
        }
    }
    private var summoningSicknessMark: UIImageView?

	private enum Contents: Equatable {
		case image(UIImage)
		case cardProperties(MTGCardView.CardProperties)
		
		static let backFace: Contents = .image(UIImage.resource(named: "mtg-card-back-png-1")!)
	}
	
	/// Where the drawn card sits inside the rendered image (fractions of its size), when the image
	/// is a rendered mini card with padding around it; nil for plain card images.
	private(set) var renderedCardFraction: CGRect?

	private var contents: Contents = .backFace {
		didSet {
      guard contents != oldValue else { return }
      
      switch self.contents {
      case .image(let image):
        renderedCardFraction = nil
        self.cardView.image = image
      case .cardProperties(let properties):
        self.cardView.image = self.image(for: properties, size: self.cardView.bounds.size)
      }
      setNeedsLayout()
      updateFullImageTapShade()
    }
  }
  
  private var properties: MTGCardView.CardProperties? {
    get {
			if case .cardProperties(let properties) = contents {
				return properties
			}
			return nil
		}
		set {
			if var properties = newValue {
				// Initial renders and delayed artwork must use the current tap state too.
				properties.isTapped = cardInstance?.isTapped.value ?? properties.isTapped
				// Keyword counters show as blue counter tiles after any commander tile, like Arena.
				properties.icons.removeAll { if case .counter = $0 { return true }; return false }
				var seen: [MTGCardView.Icon] = []
				for icon in (cardInstance?.counters.value ?? []).compactMap(\.keywordIcon) where !seen.contains(icon) { seen.append(icon) }
				properties.icons.insert(contentsOf: seen, at: properties.icons.first == .commander ? 1 : 0)
				contents = .cardProperties(properties)
			} else if case .cardProperties = contents {
				contents = .backFace
			}
			// Cards drawn as their full image (sagas, undecided double-faced cards) have no
			// properties; clearing them must not turn the image into a card back (tapping did).
		}
	}
	
	private var cardImage: UIImage? {
		get {
			if case .image(let image) = contents {
				return image
			}
			return nil
		}
		set {
			if let image = newValue {
				contents = .image(image)
			} else {
				contents = .backFace
			}
			
		}
	}
	
	private func image(for properties: MTGCardView.CardProperties, size: CGSize) -> UIImage! {
		let frame = CGRect(origin: .zero, size: size)
		let cardView = MTGCardView(frame: frame)
        cardView.prefersLargeBattlefieldText = usesPlayerPerspective
		cardView.backgroundColor = .clear
		cardView.properties = properties
		cardView.layoutIfNeeded()
		if cardInstance?.representation.drawsFullCardImage == true {
			cardView.topAlignArt()
		}
		
		UIGraphicsBeginImageContextWithOptions(cardView.bounds.size, false, 2)
		defer { UIGraphicsEndImageContext() }
		guard let context = UIGraphicsGetCurrentContext() else { return nil }
		cardView.layer.render(in: context)
		let image = UIGraphicsGetImageFromCurrentImageContext()
		// The card body, not the visible pixels: the mana cost pips sit above the card, and
		// outlines (opponent looking, combat) drawn around the pixels came out too tall.
		let body = cardView.cardBodyFrame
		renderedCardFraction = frame.width > 0 && frame.height > 0 && body.width > 0 && body.height > 0
			? CGRect(x: body.minX / frame.width, y: body.minY / frame.height,
					 width: body.width / frame.width, height: body.height / frame.height)
			: image.flatMap(Self.opaqueFraction(of:))
		return image
	}
	
	/// The bounding box of the image's visible pixels, as fractions of its size: the drawn card
	/// without the transparent padding around it. Sampled at reduced resolution.
	static func opaqueFraction(of image: UIImage) -> CGRect? {
		guard let source = image.cgImage else { return nil }
		let width = max(1, source.width / 4), height = max(1, source.height / 4)
		var pixels = [UInt8](repeating: 0, count: width * height)
		guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
									  bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
									  bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
		context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
		var minX = width, minY = height, maxX = -1, maxY = -1
		for y in 0..<height {
			for x in 0..<width where pixels[y * width + x] > 40 {
				minX = min(minX, x); maxX = max(maxX, x)
				minY = min(minY, y); maxY = max(maxY, y)
			}
		}
		guard maxX >= minX, maxY >= minY else { return nil }
		// Bitmap rows run top to bottom here (CGContext memory starts at the top row).
		return CGRect(x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
					  width: CGFloat(maxX - minX + 1) / CGFloat(width), height: CGFloat(maxY - minY + 1) / CGFloat(height))
	}

	var card: CardRepresentation {
		return cardInstance!.representation
	}
	
	var cardInstance: CardInstance! {
		didSet {
			updateCard()
		}
	}
	
	/// Whether the last `updateCard` drew a Saga, Class or Case as its full card image.
	private var showsFullCardImage = false

	private func updateCard() {
		bag = DisposeBag()
		showsFullCardImage = card.drawsFullCardImage && !cardInstance.isPowerToughnessVisible.value
		
		let isUndecidedFace: Bool = {
			var representation = self.card
			
			while case .tokenCopy(let rep) = representation {
				representation = rep
			}
      
      // Sagas, Classes and Cases show their full card image on the battlefield, unless they've
      // become creatures: then they're normal mini cards with power and toughness.
      if representation.drawsFullCardImage, !cardInstance.isPowerToughnessVisible.value {
        return true
      }
			
			if case .alternateFace(_, _) = representation {
				return false
			} else if let faces = representation.card.cardFaces, faces.count > 1 {
				return true
			} else {
				return false
			}
		}()
		
		let isAltFace: Bool = {
			if case .alternateFace(let card, let face) = self.card, let index = card.cardFaces?.firstIndex(of: face) {
				return index >= 1
			}
//			let isAltFace: Bool = {
//				if card.layout == "meld" {
//					return card.card.allParts?.contains(where: {
//						$0.component == .meldResult && $0.scryfallID == card.card.scryfallID
//					}) == true
//				}
//
//				return (faceIndex ?? 0) >= 1
//			}()
			
			if case .card(let mTGCard) = card, mTGCard.layout == "meld" {
				return mTGCard.allParts?.contains(where: {
					$0.component == .meldResult && $0.scryfallID == card.card.scryfallID
				}) == true
			}
			
			return false
		}()
		
		/*if card.layout == "saga" {
			cardView.properties = nil
			cardView.cardImage = nil
			
			DispatchQueue.global(qos: .userInteractive).async { [weak self, card] in
				let image = card.image(type: .normal)
				DispatchQueue.main.async { [weak self] in
					guard let self = self, let image = image, card == self.card else { return }
					UIView.transition(with: self.cardView.cardImageView,
									  duration: 0.2,
									  options: .transitionCrossDissolve,
									  animations: { self.cardView.cardImage = image },
									  completion: nil)
				}
			}
		} else */if case .faceDown(_) = card {
			UIView.transition(with: self.cardView,
								  duration: 0.2,
								  options: .transitionCrossDissolve,
								  animations: { self.contents = .backFace },
								  completion: nil)
		} else if isUndecidedFace {
			
			DispatchQueue.global(qos: .userInteractive).async { [weak self, card] in
				// Scryfall's images have square corners; round them like every other card.
				var image = card.image(type: .normal).map(Self.roundingCorners(of:))
				// A Room lies sideways on the battlefield, its two doors side by side.
				if card.isRoom, let source = image, let cgImage = source.cgImage {
					image = UIImage(cgImage: cgImage, scale: source.scale, orientation: .right)
				}
				DispatchQueue.main.async { [weak self] in
					guard let self = self, let image = image, card == self.card else { return }
					UIView.transition(with: self.cardView,
									  duration: 0.2,
									  options: .transitionCrossDissolve,
									  animations: { self.cardImage = image },
									  completion: { _ in self.updateDoorLocks() })
				}
			}
		} else {
			var properties = MTGCardView.properties(
				includedIcons: .permanent,
				name: card.name,
				manaCost: card.manaCost,
				typeLine: card.typeLine,
				oracleText: card.oracleText,
        colorInitials: cardInstance.colors.value.map { $0.initial },
				fullArt: card.fullArt,
				borderColor: card.borderColor.rawValue,
        frame: card.card.frame,
        frameEffects: card.frameEffects,
				power: card.power,
				toughness: card.toughness,
				loyalty: card.loyalty,
				layout: card.layout,
				flavorName: card.flavorName,
				isAltFace: isAltFace,
        keywords: card.keywords,
        securityStamp: card.card.securityStamp,
        isCommander: cardInstance.isCommander.value
      )
			// Planets and Spacecraft are printed like colorless cards (large art inside pinlines),
			// keeping their colored border.
			if let type = card.typeLine, type.contains("Planet") || type.contains("Spacecraft") { properties.isPinlineFrame = true }
			defaultFrameColors = properties.colors
			properties.applyFrameColors(cardInstance.colors.value, isLand: card.isLand, defaults: defaultFrameColors)
			properties.art = card.imageIfLoaded(type: .art)
			self.properties = properties
			
			DispatchQueue.global(qos: .userInteractive).async { [weak self, card] in
				let image = card.image(type: .art)
				DispatchQueue.main.async { [weak self] in
					guard let self = self, let image = image, card == self.card else { return }
					UIView.transition(with: self.cardView,
									  duration: 0.2,
									  options: .transitionCrossDissolve,
									  animations: {
									guard var current = self.properties else { return }
									current.art = image
									self.properties = current
					},
									  completion: nil)
				}
			}
		}
		
		updateTransform(controllerIdentifier: cardInstance.controllerIdentifier.value, isTapped: cardInstance.isTapped.value, animated: false)
		
		bind()
	}
	
	private var shouldAlwaysHideTextBox: Bool {
		return card.isBasicLand || ((card.oracleText == nil || card.oracleText == "") && (card.flavorText == nil || card.flavorText == ""))
	}
	
	private func bind() {
		guard let cardInstance = cardInstance else { return }
		
		cardInstance.representedCardDidChange
			.subscribe(onNext: { [weak self] _ in
				self?.updateCard()
			}).disposed(by: bag)
    
    cardInstance.isCommander
      .subscribe(onNext: { [weak self] isCommander in
        
        if let index = self?.properties?.icons.firstIndex(of: .commander) {
          self?.properties?.icons.remove(at: index)
        } else if isCommander && self?.properties?.icons.contains(.commander) != true {
          self?.properties?.icons.insert(.commander, at: 0)
        }
      }).disposed(by: bag)
    
    cardInstance.colors
      .subscribe(onNext: { [weak self] colors in
        guard let self, var properties = self.properties else { return }
        properties.applyFrameColors(colors, isLand: self.card.isLand, defaults: self.defaultFrameColors)
        self.properties = properties
      }).disposed(by: bag)
		
    Observable.combineLatest(cardInstance.power, cardInstance.toughness, cardInstance.counters, cardInstance.isPowerToughnessVisible, cardInstance.markedDamage)
      .subscribe(onNext: { [weak self] power, toughness, counters, isPowerToughnessVisible, _ in
        let powerToughnessString: NSAttributedString? = {
          guard isPowerToughnessVisible else { return nil }
          guard let self = self else { return nil }
          return self.powerToughnessLabelText(power: power, toughness: toughness, counters: counters)
        }()
        
        let loyaltyString: NSAttributedString? = {
          guard let self = self else { return nil }
          guard self.card.typeLine?.lowercased().contains("planeswalker") == true else { return nil }
          
          let loyaltyCounterCount = counters.reduce(into: 0) { (result, counter) in
            if counter == .loyalty {
              result += 1
            }
          }
          
          if loyaltyCounterCount > 0 {
            return NSAttributedString(string: "\(loyaltyCounterCount)")
          } else if let loyalty = self.card.loyalty {
            if Int(loyalty) == nil {
              return NSAttributedString(string: loyalty)
            } else {
              return NSAttributedString(string: "0")
            }
          }
          return nil
          
        }()
        
        guard var properties = self?.properties else { return }
        
        properties.value = powerToughnessString ?? loyaltyString
        
        if let frame = self?.card.card.frame, frame == "1993" || frame == "1997" {
          properties.borderStyle = .retro
        } else if powerToughnessString != nil {
					properties.borderStyle = self?.card.typeLine?.lowercased().contains("legendary") == true ? .legendary : nil
				} else if loyaltyString != nil {
					properties.borderStyle = .planeswalker
				}
				
				self?.properties = properties
		}).disposed(by: bag)
		
		cardInstance.isPowerToughnessVisible
			.subscribe(onNext: { [weak self] isPowerToughnessVisible in
				// A Saga, Class or Case that becomes (or stops being) a creature switches between
				// its full card image and a mini card.
				if let self, self.card.drawsFullCardImage, self.showsFullCardImage == isPowerToughnessVisible {
					self.updateCard()
					return
				}
				self?.updateTransform(controllerIdentifier: cardInstance.controllerIdentifier.value, isTapped: cardInstance.isTapped.value, animated: true)
			}).disposed(by: bag)
		
//		cardInstance.isSummoningSick
//			.subscribe(onNext: { [weak self] isSummoningSick in
//				if isSummoningSick {
//					self?.oracleBox.startGlowingWithColor(color: .black, fromIntensity: 0.1, toIntensity: 0.5, duration: 1.6, repeat: true)
//				} else {
//					self?.oracleBox.stopGlowing()
//				}
//			}).disposed(by: bag)
		
    // A phased-out permanent is drawn faded (it's treated as though it doesn't exist).
    cardInstance.counters
      .map { $0.contains(.phasedOut) }
      .distinctUntilChanged()
      .observeOn(MainScheduler.instance)
      .subscribe(onNext: { [weak self] phased in
        UIView.animate(withDuration: 0.2) { self?.cardView?.alpha = phased ? 0.3 : 1 }
        self?.accessibilityHint = phased ? "Phased out" : nil
      })
      .disposed(by: bag)

    // A Room's locked doors are darkened, with a lock, on the card itself.
    cardInstance.counters
      .map { $0.filter(\.isDoorLock) }
      .distinctUntilChanged()
      .observeOn(MainScheduler.instance)
      .subscribe(onNext: { [weak self] _ in self?.updateDoorLocks() })
      .disposed(by: bag)

    // Re-apply keyword counter tiles when counters change.
    cardInstance.counters
      .map { $0.filter(\.isKeyword) }
      .distinctUntilChanged()
      .subscribe(onNext: { [weak self] _ in
        guard let self, let properties = self.properties else { return }
        self.properties = properties
      }).disposed(by: bag)

    Observable.combineLatest(cardInstance.isFlying, cardInstance.isPowerToughnessVisible, cardInstance.counters.map { $0.contains(.flying) })
      .subscribe (onNext: { [weak self] (baseFlying, isPowerToughnessVisible, flyingCounter) in
				guard let self = self else { return }
				// A flying counter flies the card just like the Flying ability.
				let isFlying = baseFlying || flyingCounter
				
        // Don't show flying if it's not a creature
        if isFlying && isPowerToughnessVisible {
					self.cardView.startWiggle(durationModifier: 24, varianceModifier: 1.2, angleModifier: 2, bounceModifier: 1)
					self.cardView.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
					self.layer.shadowOpacity = 0.75
					self.layer.shadowRadius = 50
					self.layer.shadowOffset = .zero
					//			self.layer.allowsEdgeAntialiasing = true
					//			self.layer.shadowOffset = CGSize(width: 0, height: 50)
					self.layer.zPosition = 1
				} else {
					self.cardView.stopWiggle()
					self.cardView.transform = .identity
					self.layer.shadowOpacity = 0.5
					self.layer.shadowRadius = 5
					self.layer.shadowOffset = .zero
					self.layer.zPosition = 0
					//				self.layer.allowsEdgeAntialiasing = false
					return
				}
			}).disposed(by: bag)
		
		Observable.combineLatest(cardInstance.counters, cardInstance.isPowerToughnessVisible)
			.map { [weak self] (counters, isPowerToughnessVisible) -> [CounterAndCount] in
				var countersAndCounts: [CounterAndCount] = []
				
				for counter in counters where !counter.isCardState {
					// Keyword counters already show as ability tiles on the card; no round counter for them.
					if counter.isKeyword { continue }
					if (counter == .loyalty && self?.card.typeLine?.lowercased().contains("planeswalker") == true && !isPowerToughnessVisible) { continue }
					
					if let index = countersAndCounts.firstIndex(where: { $0.counter == counter }) {
						countersAndCounts[index].count += 1
					} else {
						countersAndCounts.append(CounterAndCount(counter: counter, count: 1))
					}
				}
				
				if self?.card.typeLine?.lowercased().contains("planeswalker") == true && isPowerToughnessVisible && !counters.contains(.loyalty) {
					countersAndCounts.insert(CounterAndCount(counter: .loyalty, count: 0), at: 0)
				}
				
				return countersAndCounts
			}
			.subscribe(onNext: { [weak self] countersAndCounts in
				guard let self = self else { return }
				
				for subview in self.countersStackView.arrangedSubviews {
					subview.removeFromSuperview()
				}
				
				for counterAndCount in countersAndCounts {
					let (counter, count) = (counterAndCount.counter, counterAndCount.count)
//					let view = UIView()
					let image: UIImage? = {
						switch counter {
						case .loyalty: return UIImage.resource(named: "Loyalty")!
						default: return UIImage(systemName: "circle.fill")
						}
					}()
					let view = UIImageView(image: image)
					view.contentMode = .scaleAspectFit
					view.translatesAutoresizingMaskIntoConstraints = false
					let width: CGFloat = {
						switch counter {
						case .loyalty:
							return 100
						default:
							return 90
						}
					}()
					view.heightAnchor.constraint(equalToConstant: width).isActive = true
					view.widthAnchor.constraint(equalToConstant: width).isActive = true
					view.tintColor = counter.color
					
					view.layer.shadowColor = UIColor.black.cgColor
					view.layer.shadowRadius = 3.0
					view.layer.shadowOpacity = 0.8
					view.layer.shadowOffset = CGSize(width: 0, height: 3)
					view.layer.masksToBounds = false
					
					let label = UILabel()
					label.translatesAutoresizingMaskIntoConstraints = false
					view.addSubview(label)
					label.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
					label.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
					label.font = UIFont(name: "Beleren2016-Bold", size: 45)
					
					if let symbol = counter.symbolImage {
						// Stun and finality show their icon; a count only when there's more than one.
						let icon = UIImageView(image: symbol)
						icon.tintColor = .white
						icon.contentMode = .scaleAspectFit
						icon.translatesAutoresizingMaskIntoConstraints = false
						view.addSubview(icon)
						NSLayoutConstraint.activate([
							icon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
							icon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
							icon.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.66),
							icon.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.66)
						])
						label.isHidden = true
						if count > 1 {
							let badge = UILabel()
							badge.translatesAutoresizingMaskIntoConstraints = false
							badge.font = UIFont(name: "Beleren2016-Bold", size: 30)
							badge.textColor = .white
							badge.textAlignment = .center
							badge.text = String(count)
							badge.backgroundColor = UIColor.black.withAlphaComponent(0.75)
							badge.layer.cornerRadius = 18
							badge.layer.masksToBounds = true
							view.addSubview(badge)
							NSLayoutConstraint.activate([
								badge.trailingAnchor.constraint(equalTo: view.trailingAnchor),
								badge.bottomAnchor.constraint(equalTo: view.bottomAnchor),
								badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
								badge.heightAnchor.constraint(equalToConstant: 36)
							])
						}
						view.accessibilityLabel = "\(counter.name) counter\(count > 1 ? "s, \(count)" : "")"
					} else if counter == .lore {
						label.textColor = .black
						
						label.text = romanNumeralFor(count) ?? String(count)
					} else {
						label.textColor = .white
						label.text = String(count)
					}
					
					self.countersStackView.addArrangedSubview(view)
				}
			}).disposed(by: bag)
		
		Observable.combineLatest(cardInstance.controllerIdentifier, cardInstance.isTapped)
			.observeOn(MainScheduler.instance)
			.subscribe(onNext: { [weak self] controllerIdentifier, isTapped in
				self?.updateTransform(controllerIdentifier: controllerIdentifier, isTapped: isTapped, animated: true)
			}).disposed(by: bag)
		
		Observable.combineLatest(cardInstance.doesNotUntapNextTurn, cardInstance.doesNotUntapAutomatically)
//			.do(onNext: { (doesNotUntapNextTurn, doesNotUntapAutomatically) in
//				if doesNotUntapAutomatically {
//					self.chainsImageView.image = UIImage.resource(named: "chains")!
//				} else if doesNotUntapNextTurn {
//					self.chainsImageView.image = UIImage.resource(named: "bluechains")!
//				}
//			})
			.map { !($0 || $1) }
			.subscribe(onNext: { [weak self] chainIsHidden in
				self?.properties?.isChained = !chainIsHidden
			}).disposed(by: bag)
	}
  
  override func accessibilityActivate() -> Bool {
    guard usesPlayerPerspective, let cardInstance else { return super.accessibilityActivate() }
    #if !BOARD_CONNECT
    if let session = AppDelegate.shared.phoneSession, session.mode == .rules {
      session.send(.tap(cardInstance.uuid))
      return true
    }
    #endif
    cardInstance.isTapped.mutate { $0.toggle() }
    try? GameState.current.save()
    return true
  }

  private var doorLockViews: [UIView] = []

  override func layoutSubviews() {
    super.layoutSubviews()
    if !doorLockViews.isEmpty { updateDoorLocks() }
    layoutCountersOnCard()
    updateFullImageTapShade()
    layoutSummoningSicknessMark()
  }

  /// Arena uses a white spiral for summoning sickness. Keep it on the art, clear of
  /// the name, counters and power/toughness, and outside the editable counter model.
  private func layoutSummoningSicknessMark() {
    guard showsRulesSummoningSickness, let cardView, let drawn = drawnImageRect else {
      summoningSicknessMark?.removeFromSuperview()
      summoningSicknessMark = nil
      return
    }
    let mark: UIImageView
    if let existing = summoningSicknessMark { mark = existing }
    else {
      mark = UIImageView(image: UIImage(systemName: "hurricane"))
      mark.tintColor = .white
      mark.backgroundColor = UIColor(white: 0.08, alpha: 0.85)
      mark.contentMode = .scaleAspectFit
      mark.isUserInteractionEnabled = false
      mark.accessibilityIdentifier = "rules-summoning-sickness"
      cardView.addSubview(mark)
      summoningSicknessMark = mark
    }
    let fraction = renderedCardFraction ?? CGRect(x: 0, y: 0, width: 1, height: 1)
    let face = CGRect(x: drawn.minX + drawn.width * fraction.minX,
                      y: drawn.minY + drawn.height * fraction.minY,
                      width: drawn.width * fraction.width, height: drawn.height * fraction.height)
    // MiniCardView can use a large logical canvas scaled down by its board transform.
    // Proportion to the card face rather than capping logical points, so the marker stays legible.
    let size = face.width * 0.16
    mark.frame = CGRect(x: face.maxX - size - face.width * 0.06,
                        y: face.minY + face.height * 0.2, width: size, height: size)
    mark.layer.cornerRadius = size / 2
    mark.layer.masksToBounds = true
    cardView.bringSubviewToFront(mark)
  }

  /// Where the card image is actually drawn inside `cardView` (it's aspect-fit in a square).
  private var drawnImageRect: CGRect? {
    guard let image = cardView?.image, image.size.width > 0, image.size.height > 0 else { return nil }
    let bounds = cardView.bounds
    let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
    return CGRect(x: bounds.midX - image.size.width * scale / 2, y: bounds.midY - image.size.height * scale / 2,
                  width: image.size.width * scale, height: image.size.height * scale)
  }

  /// The counters column straddles the card's right edge. Full upright card images (sagas,
  /// classes, cases) are narrower than the square, so pull it in to sit on the drawn card.
  private lazy var countersTrailingConstraint: NSLayoutConstraint? = contentView.constraints.first {
    ($0.firstItem === countersStackView && $0.firstAttribute == .trailing) ||
    ($0.secondItem === countersStackView && $0.secondAttribute == .trailing)
  }
  private lazy var countersTrailingDefault: CGFloat = countersTrailingConstraint?.constant ?? 0

  private func layoutCountersOnCard() {
    guard let constraint = countersTrailingConstraint else { return }
    var inset: CGFloat = 0
    if case .image = contents, let drawn = drawnImageRect {
      inset = cardView.bounds.maxX - drawn.maxX
    }
    let sign: CGFloat = constraint.firstItem === countersStackView ? 1 : -1
    let constant = countersTrailingDefault - sign * inset
    if abs(constraint.constant - constant) > 0.5 { constraint.constant = constant }
  }

  /// Rendered mini cards darken themselves when tapped; plain card images get this shade.
  private lazy var fullImageTapShade: UIView = {
    let shade = UIView()
    shade.backgroundColor = UIColor.black.withAlphaComponent(0.4)
    shade.isUserInteractionEnabled = false
    shade.layer.cornerCurve = .continuous
    shade.isHidden = true
    return shade
  }()

  private func updateFullImageTapShade() {
    guard let cardView else { return }
    let isFaceUpImage: Bool = {
      guard case .image = contents, let cardInstance else { return false }
      if case .faceDown = cardInstance.representation { return false }
      return true
    }()
    guard isFaceUpImage, cardInstance?.isTapped.value == true, let drawn = drawnImageRect else {
      fullImageTapShade.isHidden = true
      return
    }
    if fullImageTapShade.superview !== cardView { cardView.addSubview(fullImageTapShade) }
    fullImageTapShade.frame = drawn
    fullImageTapShade.layer.cornerRadius = min(drawn.width, drawn.height) * Self.cornerFraction
    fullImageTapShade.isHidden = false
    // Door locks draw their own shade; keep them above this one.
    doorLockViews.forEach { cardView.bringSubviewToFront($0) }
  }

  /// A card's corner radius as a fraction of its short side.
  private static let cornerFraction: CGFloat = 0.0455

  /// The image clipped to a card's rounded corners.
  static func roundingCorners(of image: UIImage) -> UIImage {
    let size = image.size
    guard size.width > 0, size.height > 0 else { return image }
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      let radius = min(size.width, size.height) * cornerFraction
      UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius).addClip()
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }

  /// Darkens each locked door of a sideways Room and marks it with a lock.
  fileprivate func updateDoorLocks() {
    doorLockViews.forEach { $0.removeFromSuperview() }
    doorLockViews = []
    guard let cardInstance, cardInstance.representation.isRoom, let image = cardView?.image,
          image.size.width > 0, image.size.height > 0 else { return }
    let bounds = cardView.bounds
    let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
    let drawn = CGRect(x: bounds.midX - image.size.width * scale / 2, y: bounds.midY - image.size.height * scale / 2,
                       width: image.size.width * scale, height: image.size.height * scale)
    for (index, counter) in [Counter.lockedDoorLeft, .lockedDoorRight].enumerated() where cardInstance.counters.value.contains(counter) {
      let half = CGRect(x: drawn.minX + CGFloat(index) * drawn.width / 2, y: drawn.minY, width: drawn.width / 2, height: drawn.height)
      let shade = UIView(frame: half.insetBy(dx: 1, dy: 1))
      shade.backgroundColor = UIColor.black.withAlphaComponent(0.5)
      shade.isUserInteractionEnabled = false
      let lock = UIImageView(image: Counter.lockedDoorImage)
      lock.tintColor = .white
      lock.contentMode = .scaleAspectFit
      let side = min(half.width, half.height) * 0.5
      lock.frame = CGRect(x: (shade.bounds.width - side) / 2, y: (shade.bounds.height - side) / 2, width: side, height: side)
      lock.layer.shadowColor = UIColor.black.cgColor
      lock.layer.shadowOpacity = 0.8
      lock.layer.shadowRadius = side * 0.1
      lock.layer.shadowOffset = .zero
      shade.addSubview(lock)
      shade.isAccessibilityElement = true
      shade.accessibilityIdentifier = "phone-door-locked"
      shade.accessibilityLabel = "\(cardInstance.representation.card.cardFaces?[index].name ?? "Door") locked"
      cardView.addSubview(shade)
      doorLockViews.append(shade)
    }
  }

  var updatesTransform = true
  var usesPlayerPerspective = false {
    didSet {
      guard oldValue != usesPlayerPerspective else { return }
      if let cardInstance {
        updateTransform(controllerIdentifier: cardInstance.controllerIdentifier.value, isTapped: cardInstance.isTapped.value, animated: false)
        if case .cardProperties(let properties) = contents {
          cardView.image = image(for: properties, size: cardView.bounds.size)
        }
      }
    }
  }
	
  private lazy var phoneTapArrow: UIImageView = {
    let arrow = UIImageView(image: UIImage.resource(named: "tap")?.withRenderingMode(.alwaysTemplate))
    arrow.tintColor = .white
    arrow.alpha = 0.65
    arrow.contentMode = .scaleAspectFit
    arrow.isUserInteractionEnabled = false
    addSubview(arrow)
    return arrow
  }()

  /// Phone Play: a size for this card on top of the board's zoom (back-row permanents are drawn
  /// at land size, as on Arena).
  var layoutScale: CGFloat = 1 {
    didSet {
      guard abs(oldValue - layoutScale) > 0.001 else { return }
      updateTransform(controllerIdentifier: cardInstance.controllerIdentifier.value, isTapped: cardInstance.isTapped.value, animated: false)
    }
  }

  /// Noncreature artifacts, enchantments, lands and emblems are drawn a little smaller than creatures.
  var typeScale: CGFloat {
    if let typeLine = card.typeLine?.lowercased(), !cardInstance.isPowerToughnessVisible.value,
       typeLine.contains("artifact") || typeLine.contains("enchantment") || typeLine.contains("land") || typeLine.contains("emblem") {
      return 0.85
    }
    return 1
  }

  /// Phone Play: the `layoutScale` that draws this card at the same size as `host`, so an
  /// attachment (Equipment, an Aura) tucked behind its card is never smaller and hidden by it.
  func layoutScale(matching host: MiniCardView) -> CGFloat {
    host.typeScale * host.layoutScale / max(0.01, typeScale)
  }

  private func updateTransform(controllerIdentifier: Player.Identifier, isTapped: Bool, animated: Bool) {
    guard updatesTransform else { return }
    if usesPlayerPerspective {
      phoneTapArrow.isHidden = !isTapped
      phoneTapArrow.frame = bounds.insetBy(dx: bounds.width * 0.27, dy: bounds.height * 0.27)
      bringSubviewToFront(phoneTapArrow)
    } else { phoneTapArrow.isHidden = true }
    
    UIView.transition(
      with: self.cardView,
      duration: animated ? 0.3 : 0,
      options: .transitionCrossDissolve,
      animations: { [weak self] in
        guard let self = self else { return }
        var transform: CGAffineTransform = .identity
        
        if controllerIdentifier == .b && !self.usesPlayerPerspective {
          transform = transform.rotated(by: .pi)
        }
        
        if isTapped {
          transform = transform.rotated(by: .pi/15)
        }
        
        
        self.properties?.isTapped = isTapped
        self.updateFullImageTapShade()
        
        let scale = self.typeScale * self.layoutScale
        if scale != 1 { transform = transform.scaledBy(x: scale, y: scale) }
        
        self.transform = transform
      },
      completion: nil)
  }
  
	private func powerToughnessLabelText(power: String, toughness: String, counters: [Counter]) -> NSAttributedString {
		
		func string(for power: String) -> String {
            #if !BOARD_CONNECT
            // XMage's effective stats already include counters and continuous effects.
            if AppDelegate.shared.phoneSession?.mode == .rules { return power }
            #endif
			var string = power
			
			if let value = Int(string) {
				let counterModifier: Int = counters.reduce(into: 0) { (result, counter) in
					if counter == .plusOnePlusOne {
						result += 1
					} else if counter == .minusOneMinusOne {
						result -= 1
					}
				}
				string = "\(value+counterModifier)"
			}
			
			return string
		}
		
		let powerString: String = string(for: power)
		let toughnessString = string(for: toughness)
		
		guard let properties = properties else { return NSAttributedString() }
		
		let modifiedColor = properties.isInverted || properties.backgroundStyle == .vehicle ? #colorLiteral(red: 0.2392156869, green: 0.6745098233, blue: 0.9686274529, alpha: 1) : #colorLiteral(red: 0.03035263158, green: 0.3804000616, blue: 1, alpha: 1)
        return Self.powerToughnessText(power: powerString, toughness: toughnessString,
            printedPower: cardInstance.representation.power, printedToughness: cardInstance.representation.toughness,
            damage: cardInstance.markedDamage.value, modifiedColor: modifiedColor)
    }

    /// Only the displayed toughness loses marked damage. Rules, detail pages and combat still
    /// use the effective toughness; clearing the engine's damage restores the usual stat color.
    static func powerToughnessText(power: String, toughness: String, printedPower: String?, printedToughness: String?,
                                   damage: Int, modifiedColor: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let modified: [NSAttributedString.Key: Any] = [.foregroundColor: modifiedColor]
        result.append(NSAttributedString(string: power, attributes: power == printedPower ? [:] : modified))
        result.append(NSAttributedString(string: "/"))
        let marked = max(0, damage)
        if marked > 0, let effective = Int(toughness) {
            result.append(NSAttributedString(string: String(effective - marked), attributes: [.foregroundColor: UIColor.systemRed]))
        } else {
            result.append(NSAttributedString(string: toughness, attributes: toughness == printedToughness ? [:] : modified))
        }
        return result
    }

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}
	
	private func commonInit() {
		Bundle.main.loadNibNamed("MiniCardView", owner: self, options: nil)
		addSubview(contentView)
		contentView.frame = self.bounds
		contentView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
		
//		cardView.layer.allowsEdgeAntialiasing = true
		
//		let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapUnTapGestureRecognized))
//		cardView.addGestureRecognizer(gestureRecognizer)
		
//		let rotateGestureRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(rotated(_:)))
//		cardView.addGestureRecognizer(rotateGestureRecognizer)
	}
	
	@objc private func rotated(_ gestureRecognizer: UIRotationGestureRecognizer) {
		// user's two fingers. This creates a more natural looking rotation.
		guard gestureRecognizer.view != nil else { return }
		
		print(gestureRecognizer.rotation / .pi)
		if gestureRecognizer.state == .began || gestureRecognizer.state == .changed {
			if gestureRecognizer.rotation >= .pi / 4 {
				cardInstance.isTapped.accept(true)
				gestureRecognizer.rotation = 0
			} else if gestureRecognizer.rotation <= .pi / -4 {
				cardInstance.isTapped.accept(false)
				gestureRecognizer.rotation = 0
			}
		}
	}
	
//	@objc private func tapUnTapGestureRecognized(_ gestureRecognizer: UIGestureRecognizer) {
//		tapUnTap()
//	}
//	
//	private func tapUnTap() {
//		cardInstance.isTapped.toggle()
//		try? GameState.current.save()
//	}
	
	override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
		return cardView.point(inside: point, with: event)
	}

}

extension MiniCardView: UIGestureRecognizerDelegate {
//	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
//		if let otherGestureRecognizer = otherGestureRecognizer as? UITapGestureRecognizer, otherGestureRecognizer.numberOfTapsRequired == 2 {
//			return true
//		}
//		return false
//	}
}


// MARK: SwiftUI

struct SwiftUICardView: View {
  let card: CardInstance
  let isRotationEnabled: Bool
  /// Phone Play: the opponent is looking at this card (a thin white outline around it).
  var isInspected = false
  
  @ObservedObject private var isTapped: ObservableBridge<Bool>
  @ObservedObject private var representation: ObservableBridge<CardRepresentation>
  @ObservedObject private var colors: ObservableBridge<[MTGColor]>
  @State private var art: UIImage?
  
  private static let backFace: UIImage = UIImage.resource(named: "mtg-card-back-png-1")!
  
  let bag = DisposeBag()
  
  init(card: CardInstance, isRotationEnabled: Bool = true, isInspected: Bool = false) {
    self.card = card
    self.isInspected = isInspected
    self._art = State(initialValue: card.representation.imageIfLoaded(type: .art))
    self.isTapped = ObservableBridge(card.isTapped)
    self.colors = ObservableBridge(card.colors)
    self.isRotationEnabled = isRotationEnabled
    
    let cardDidChangeObservable = card.representedCardDidChange
      .map { card.representation }
    self.representation = ObservableBridge(cardDidChangeObservable, initialValue: card.representation)
  }
  
  private var isUndecidedFace: Bool {
    var representation = self.representation.value
    
    while case .tokenCopy(let rep) = representation {
      representation = rep
    }
    
    // Sagas, Classes and Cases show their full card image on the battlefield, unless they've
    // become creatures.
    if representation.drawsFullCardImage { return !card.isPowerToughnessVisible.value }
    
    if case .alternateFace(_, _) = representation {
      return false
    } else if let faces = representation.card.cardFaces, faces.count > 1 {
      return true
    } else {
      return false
    }
  }
  
  private var isAltFace: Bool {
    if case .alternateFace(let card, let face) = self.representation.value, let index = card.cardFaces?.firstIndex(of: face) {
      return index >= 1
    }
//      let isAltFace: Bool = {
//        if card.layout == "meld" {
//          return card.card.allParts?.contains(where: {
//            $0.component == .meldResult && $0.scryfallID == card.card.scryfallID
//          }) == true
//        }
//
//        return (faceIndex ?? 0) >= 1
//      }()
    
    if case .card(let mTGCard) = representation.value, mTGCard.layout == "meld" {
      return mTGCard.allParts?.contains(where: {
        $0.component == .meldResult && $0.scryfallID == representation.value.card.scryfallID
      }) == true
    }
    
    return false
  }
  
  @ViewBuilder
  private var contents: some View {
    if case .faceDown(_) = representation.value {
      Image(uiImage: Self.backFace)
        .resizable()
        .aspectRatio(63/88, contentMode: .fit)
    } else if isUndecidedFace {
      AsyncImage(
        card: representation.value.card,
        type: .normal,
        placeholder: Image(uiImage: Self.backFace).opacity(0.5),
        configuration: {
          $0.resizable()
          .aspectRatio(63/88, contentMode: .fit)
          .clipShape(CardCornerShape())
        }
      )
    } else {
        BattlefieldCardThumbnail(properties: properties, usesLargeText: AppDelegate.shared.usesPhoneSession,
                                 topAlignsArt: representation.value.drawsFullCardImage)
        .aspectRatio(480/420, contentMode: .fit)
        .task {
          let image = card.representation.image(type: .art)
          await MainActor.run {
            self.art = image
          }
        }
    }
  }
  
  private var properties: MTGCardView.CardProperties {
    var properties = MTGCardView.properties(
      includedIcons: .permanent,
      name: representation.value.name,
      manaCost: representation.value.manaCost,
      typeLine: representation.value.typeLine,
      oracleText: representation.value.oracleText,
      colorInitials: card.colors.value.map { $0.initial },
      fullArt: representation.value.fullArt,
      borderColor: representation.value.borderColor.rawValue,
      frame: representation.value.card.frame,
      frameEffects: representation.value.frameEffects,
      power: representation.value.power,
      toughness: representation.value.toughness,
      loyalty: representation.value.loyalty,
      layout: representation.value.layout,
      flavorName: representation.value.flavorName,
      isAltFace: isAltFace,
      keywords: representation.value.keywords,
      securityStamp: representation.value.card.securityStamp,
      isCommander: card.isCommander.value
    )
    if let type = representation.value.typeLine, type.contains("Planet") || type.contains("Spacecraft") { properties.isPinlineFrame = true }
    properties.applyFrameColors(colors.value, isLand: representation.value.isLand, defaults: properties.colors)
    
    properties.art = self.art
    
    return properties
  }
  
  var body: some View {
//    MiniCardViewWrapper(cardInstance: card, updatesTransform: false)
//    Text(String(describing: representation.value))
    contents
      .drag(card: AppDelegate.shared.usesPhoneSession ? nil : card)
      .overlay {
        if isTapped.value {
          CardCornerShape().fill(Color.black.opacity(0.4))
          if AppDelegate.shared.usesPhoneSession {
            GeometryReader { proxy in
              Image(resource: "tap").resizable().renderingMode(.template).scaledToFit()
                .foregroundColor(.white.opacity(0.65))
                .frame(width: proxy.size.width * 0.46, height: proxy.size.height * 0.46)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }.allowsHitTesting(false)
          }
        }
      }
      .overlay {
        // Every face here fills its frame with the card (thumbnails are cropped to the card
        // body), so the outline hugs the card; it sits inside the tap rotation below.
        if isInspected {
          GeometryReader { proxy in
            RoundedRectangle(cornerRadius: proxy.size.width * 0.0455 + 1.5, style: .continuous)
              .strokeBorder(Color.white, lineWidth: 1.5)
              .padding(-1.5)
          }
          .allowsHitTesting(false)
          .accessibilityIdentifier("phone-opponent-inspecting")
        }
      }
      .rotationEffect(isRotationEnabled && isTapped.value ? .init(radians: .pi/15) : .zero)
      .animation(.default, value: isTapped.value)
      .animation(.default, value: representation.value)
      
  }
}


/// A card's rounded corners, sized from its width.
private struct CardCornerShape: Shape {
  func path(in rect: CGRect) -> Path {
    Path(roundedRect: rect, cornerRadius: rect.width * 0.0455, style: .continuous)
  }
}


/// Keep UIKit rasterization out of SwiftUI body evaluation. Rebuilding the XIB
/// while evaluating a body can continually invalidate the hosting view's layout.
private struct BattlefieldCardThumbnail: UIViewRepresentable {
    let properties: MTGCardView.CardProperties
    let usesLargeText: Bool
    var topAlignsArt = false

    final class Coordinator {
        var properties: MTGCardView.CardProperties?
        var usesLargeText: Bool?
        lazy var renderer = MTGCardView(frame: CGRect(x: 0, y: 0, width: 480, height: 480))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        let cache = context.coordinator
        guard cache.properties != properties || cache.usesLargeText != usesLargeText else { return }
        cache.properties = properties
        cache.usesLargeText = usesLargeText
        let renderer = cache.renderer
        renderer.prefersLargeBattlefieldText = usesLargeText
        renderer.backgroundColor = .clear
        renderer.properties = properties
        renderer.layoutIfNeeded()
        if topAlignsArt { renderer.topAlignArt() }

        // The XIB lays out in a square canvas. Crop only after rendering to
        // preserve the original title, artwork, and power/toughness positions.
        UIGraphicsBeginImageContextWithOptions(renderer.bounds.size, false, 2)
        defer { UIGraphicsEndImageContext() }
        guard let graphics = UIGraphicsGetCurrentContext() else { return }
        renderer.layer.render(in: graphics)
        guard let square = UIGraphicsGetImageFromCurrentImageContext(), let pixels = square.cgImage else { return }
        let crop = CGRect(x: 0, y: 30 * square.scale, width: 480 * square.scale, height: 420 * square.scale)
        guard let cropped = pixels.cropping(to: crop) else { return }
        imageView.image = UIImage(cgImage: cropped, scale: square.scale, orientation: square.imageOrientation)
    }
}


extension MTGCardView {
    /// Crops the art to the art box from its top instead of its middle. Sagas, Classes and Cases
    /// have tall art whose subject sits at the top; as creature mini cards they show that part.
    func topAlignArt() {
        let box = artImageView.bounds.size
        guard box.width > 0, box.height > 0, let art = artImageView.image, let source = art.cgImage else { return }
        let width = CGFloat(source.width), height = CGFloat(source.height)
        let cropHeight = min(height, (width * box.height / box.width).rounded())
        guard cropHeight < height,
              let cropped = source.cropping(to: CGRect(x: 0, y: 0, width: width, height: cropHeight)) else { return }
        artImageView.image = UIImage(cgImage: cropped, scale: art.scale, orientation: art.imageOrientation)
    }
}


extension MTGCardView.CardProperties {
    /// Colors set on a card instance override its frame colors. A land with no colors set keeps
    /// its default frame (from the mana it makes); other cards use their instance colors as before.
    mutating func applyFrameColors(_ colors: [MTGColor], isLand: Bool, defaults: [MTGCardView.Color]) {
        let set = colors.compactMap { MTGCardView.Color(initial: $0.initial) }
        self.colors = isLand && set.isEmpty ? defaults : set
    }
}
