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

	@IBOutlet var contentView: UIView!
	@IBOutlet weak var countersStackView: UIStackView!
	@IBOutlet weak var cardView: RMShapedImageView!
	
	private enum Contents: Equatable {
		case image(UIImage)
		case cardProperties(MTGCardView.CardProperties)
		
		static let backFace: Contents = .image(#imageLiteral(resourceName: "mtg-card-back-png-1"))
	}
	
	private var contents: Contents = .backFace {
		didSet {
      guard contents != oldValue else { return }
      
      switch self.contents {
      case .image(let image):
        self.cardView.image = image
      case .cardProperties(let properties):
        self.cardView.image = self.image(for: properties, size: self.cardView.bounds.size)
      }
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
			if let properties = newValue {
				contents = .cardProperties(properties)
			} else {
				contents = .backFace
			}
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
		cardView.backgroundColor = .clear
		cardView.properties = properties
		cardView.layoutIfNeeded()
		
		UIGraphicsBeginImageContextWithOptions(cardView.bounds.size, false, 2)
		defer { UIGraphicsEndImageContext() }
		guard let context = UIGraphicsGetCurrentContext() else { return nil }
		cardView.layer.render(in: context)
		return UIGraphicsGetImageFromCurrentImageContext()
	}
	
	var card: CardRepresentation {
		return cardInstance!.representation
	}
	
	var cardInstance: CardInstance! {
		didSet {
			updateCard()
		}
	}
	
	private func updateCard() {
		bag = DisposeBag()
		
		let isUndecidedFace: Bool = {
			var representation = self.card
			
			while case .tokenCopy(let rep) = representation {
				representation = rep
			}
      
//      if representation.card.typeLine?.contains("Saga") == true {
//        return true
//      }
			
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
				let image = card.image(type: .normal)
				DispatchQueue.main.async { [weak self] in
					guard let self = self, let image = image, card == self.card else { return }
					UIView.transition(with: self.cardView,
									  duration: 0.2,
									  options: .transitionCrossDissolve,
									  animations: { self.cardImage = image },
									  completion: nil)
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
			self.properties = properties
			
			DispatchQueue.global(qos: .userInteractive).async { [weak self, card] in
				let image = card.image(type: .art)
				DispatchQueue.main.async { [weak self] in
					guard let self = self, let image = image, card == self.card else { return }
					UIView.transition(with: self.cardView,
									  duration: 0.2,
									  options: .transitionCrossDissolve,
									  animations: {
										properties.art = image
										self.properties = properties
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
        self?.properties?.colors = colors.compactMap { MTGCardView.Color.init(initial: $0.initial) }
      }).disposed(by: bag)
		
    Observable.combineLatest(cardInstance.power, cardInstance.toughness, cardInstance.counters, cardInstance.isPowerToughnessVisible)
      .subscribe(onNext: { [weak self] power, toughness, counters, isPowerToughnessVisible in
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
		
    Observable.combineLatest(cardInstance.isFlying, cardInstance.isPowerToughnessVisible)
      .subscribe (onNext: { [weak self] (isFlying, isPowerToughnessVisible) in
				guard let self = self else { return }
				
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
				
				for counter in counters {
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
						case .loyalty: return #imageLiteral(resourceName: "Loyalty")
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
					
					if counter == .lore {
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
//					self.chainsImageView.image = #imageLiteral(resourceName: "chains")
//				} else if doesNotUntapNextTurn {
//					self.chainsImageView.image = #imageLiteral(resourceName: "bluechains")
//				}
//			})
			.map { !($0 || $1) }
			.subscribe(onNext: { [weak self] chainIsHidden in
				self?.properties?.isChained = !chainIsHidden
			}).disposed(by: bag)
	}
  
  var updatesTransform = true
	
  private func updateTransform(controllerIdentifier: Player.Identifier, isTapped: Bool, animated: Bool) {
    guard updatesTransform else { return }
    
    UIView.transition(
      with: self.cardView,
      duration: animated ? 0.3 : 0,
      options: .transitionCrossDissolve,
      animations: { [weak self] in
        guard let self = self else { return }
        var transform: CGAffineTransform = .identity
        
        if controllerIdentifier == .b {
          transform = transform.rotated(by: .pi)
        }
        
        if isTapped {
          transform = transform.rotated(by: .pi/15)
        }
        
        
        self.properties?.isTapped = isTapped
        
        
        if let typeLine = self.card.typeLine?.lowercased(), !self.cardInstance.isPowerToughnessVisible.value && (typeLine.contains("artifact") || typeLine.contains("enchantment") || typeLine.contains("land") || typeLine.contains("emblem")) {
          let scale: CGFloat = 0.85
          transform = transform.scaledBy(x: scale, y: scale)
        }
        
        self.transform = transform
      },
      completion: nil)
  }
  
	private func powerToughnessLabelText(power: String, toughness: String, counters: [Counter]) -> NSAttributedString {
		let attributedString = NSMutableAttributedString()
		
		func string(for power: String) -> String {
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
		let modifiedAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: modifiedColor]

		let powerAttributedString = NSAttributedString(string: powerString, attributes: (powerString == self.cardInstance.representation.power) ? [:] : modifiedAttributes)
		attributedString.append(powerAttributedString)

		attributedString.append(NSAttributedString(string: "/"))

		let toughnessAttributedString = NSAttributedString(string: toughnessString, attributes: (toughnessString == self.cardInstance.representation.toughness) ? [:] : modifiedAttributes)
		attributedString.append(toughnessAttributedString)

		return attributedString
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
  
  @ObservedObject private var isTapped: ObservableBridge<Bool>
  @ObservedObject private var representation: ObservableBridge<CardRepresentation>
  @State private var art: UIImage?
  
  private static let backFace: UIImage = #imageLiteral(resourceName: "mtg-card-back-png-1")
  
  let bag = DisposeBag()
  
  init(card: CardInstance, isRotationEnabled: Bool = true) {
    self.card = card
    self.isTapped = ObservableBridge(card.isTapped)
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
        }
      )
    } else {
        Image(uiImage: self.cardImage(for: properties))
        .resizable()
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
    
    properties.art = self.art
    
    return properties
  }
  
  /// Renders the card the same way `MiniCardView` does, then crops away the padding.
  ///
  /// `MTGCardView` only lays out correctly when the 8:7 card is letterboxed in a square
  /// canvas (its xib is designed at 480×480). Rendering straight at 480×420 shifts the
  /// name below the title bar, so render square and crop to the card itself.
  private func cardImage(for properties: MTGCardView.CardProperties) -> UIImage {
    let canvas = CGSize(width: 480, height: 480)
    let cardRect = CGRect(x: 0, y: (canvas.height - 420) / 2, width: 480, height: 420)

    guard let squareImage = image(for: properties, size: canvas) else { return UIImage() }
    guard let cgImage = squareImage.cgImage else { return squareImage }

    let scale = squareImage.scale
    let pixelRect = CGRect(x: cardRect.minX * scale, y: cardRect.minY * scale,
                           width: cardRect.width * scale, height: cardRect.height * scale)
    guard let cropped = cgImage.cropping(to: pixelRect) else { return squareImage }
    return UIImage(cgImage: cropped, scale: scale, orientation: squareImage.imageOrientation)
  }

  private func image(for properties: MTGCardView.CardProperties, size: CGSize) -> UIImage! {
    let frame = CGRect(origin: .zero, size: size)
    let cardView = MTGCardView(frame: frame)
    cardView.backgroundColor = .clear
    cardView.properties = properties
    cardView.layoutIfNeeded()
    
    UIGraphicsBeginImageContextWithOptions(cardView.bounds.size, false, 2)
    defer { UIGraphicsEndImageContext() }
    guard let context = UIGraphicsGetCurrentContext() else { return nil }
    cardView.layer.render(in: context)
    return UIGraphicsGetImageFromCurrentImageContext()
  }
  
  var body: some View {
//    MiniCardViewWrapper(cardInstance: card, updatesTransform: false)
//    Text(String(describing: representation.value))
    contents
      .drag(card: card)
      .overlay {
        if isTapped.value {
          Color.black.opacity(0.4)
        }
      }
      .rotationEffect(isRotationEnabled && isTapped.value ? .init(radians: .pi/15) : .zero)
      .animation(.default, value: isTapped.value)
      .animation(.default, value: representation.value)
      
  }
}
