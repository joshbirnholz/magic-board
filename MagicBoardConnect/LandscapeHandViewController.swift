//
//  LandscapeHandViewController.swift
//  MagicBoardConnect
//
//  Created by Josh Birnholz on 5/14/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import CardView
import CardService
import SwiftUI

fileprivate let fontSize: CGFloat = 20

extension Array {
	subscript(safe index: Int) -> Element? {
		guard indices.contains(index) else { return nil }
		return self[index]
	}
}

extension String {
	func ranges(of substring: String, options: CompareOptions = [], locale: Locale? = nil) -> [Range<Index>] {
		var ranges: [Range<Index>] = []
		while let range = range(of: substring, options: options, range: (ranges.last?.upperBound ?? self.startIndex)..<self.endIndex, locale: locale) {
			ranges.append(range)
		}
		return ranges
	}
}

extension UIImage {
	func scaled(length: CGFloat) -> UIImage {
		scaled(toFit: CGSize(width: length, height: length))
	}
	
	func scaled(toFit newSize: CGSize) -> UIImage {
		let renderer = UIGraphicsImageRenderer(size: newSize)
		let image = renderer.image { _ in
			self.draw(in: CGRect.init(origin: CGPoint.zero, size: newSize))
		}

		return image.withRenderingMode(self.renderingMode)
	}
}

func addSymbols(string: String, symbolLength: CGFloat = 13, forTextStyle textStyle: UIFont.TextStyle = .body) -> Text {
	let symbolLength: CGFloat = {
		let metrics = UIFontMetrics(forTextStyle: textStyle)
		return metrics.scaledValue(for: symbolLength)
	}()
	
	var text: Text = Text("")
	
	let matches: [EnumeratedSequence<[Match]>.Element] = {
		var matches: [Match] = []
		
		for symbol in MTGSymbolName.allCases {
			let symbolMatches: [Match] = string.ranges(of: symbol.rawValue).map {
				return (range: $0, value: String(string[$0]))
			}
			matches.append(contentsOf: symbolMatches)
		}
		
		matches.sort { $0.range.lowerBound < $1.range.lowerBound }
		
		return Array(matches.enumerated())
	}()
	
	for (index, match) in matches {
		
		let fromPreviousStart: String.Index = {
			guard index > 0 else { return string.startIndex }
			return matches[index-1].element.range.upperBound
		}()
		
		guard match.range.lowerBound >= fromPreviousStart else {
			print("match range incorrect for \(match.value)")
			continue
		}
		
		let nonItalic = string[fromPreviousStart..<match.range.lowerBound]
		
		let imageName = match.value.replacingOccurrences(of: "/", with: "-")
		guard let uiImage = UIImage(named: imageName)?.scaled(length: symbolLength) else {
			text = text + Text(match.value)
			print("No image for \(match.value)")
			continue
		}
		let image = Image(uiImage: uiImage).resizable()
		text = text + Text(nonItalic) + Text(image)
	}
	
	if let match = matches.last?.element {
		let lowerBound = match.range.upperBound
		let upperBound = string.endIndex
		let finalText = string[lowerBound..<upperBound]
		
		text = text + Text(finalText)
	}
	
	if matches.isEmpty {
		text = Text(string)
	}
	
	return text
}

fileprivate struct OracleText: View {
	var oracleText: String
//	var flavorText: String?
	var symbolSpacingEnabled: Bool = false
	var symbolLength: CGFloat = 13
	
	var body: some View {
		content
	}
	
	var content: Text {
		let lines: [String] = oracleText.components(separatedBy: .newlines)
		var texts = lines.map { self.text(for: $0) }
		texts = texts.enumerated().map { offset, text in
			return [text, Text("\n​").baselineOffset(lines[safe: offset+1]?.hasPrefix("•") == true ? 0 : 5)]
			
		}.joined().dropLast()
		let start = texts.removeFirst()
		return texts.reduce(start, +)
	}
	
	func text(for line: String) -> Text {
		var oracleText = line
			.replacingOccurrences(of: "−", with: "-")
			.replacingOccurrences(of: "//", with: "\n")
		if symbolSpacingEnabled {
			oracleText = oracleText.replacingOccurrences(of: "}{", with: "} {")
		}
		
		var text: Text = Text("")
		
		let italicExemptions: [String] = {
			var italicExemptions: [String] = ["Companion", "Boast", "Cycling", "I", "II", "III", "IV", "I, II", "II, III", "III, IV", "I, II, III", "II, III, IV", "Visit", "Prize", "villainous choice"]
			italicExemptions = italicExemptions.map { $0 + " — " }
			return italicExemptions
		}()

    let matches = Array(oracleText.matches(forRegex: #"(?:\((.*?)\)|[^"]+ — )"#, options: .anchorsMatchLines).filter { match in
      !italicExemptions.contains(where: { match.fullMatch.value.hasSuffix($0) })
    }.enumerated())

		for (index, match) in matches {
			let fromPreviousStart: String.Index = {
				guard index > 0 else { return oracleText.startIndex }
				return matches[index-1].element.fullMatch.range.upperBound
			}()

			let nonItalic = oracleText[fromPreviousStart..<match.fullMatch.range.lowerBound]
			
			text = text + addSymbols(string: String(nonItalic), symbolLength: symbolLength).font(Font.custom("MPlantin", size: fontSize)) + addSymbols(string: String(oracleText[match.fullMatch.range]), symbolLength: symbolLength).font(Font.custom("MPlantin-Italic", size: fontSize))
		}

		if let match = matches.last?.element {
			let finalText = oracleText[match.fullMatch.range.upperBound...]

			text = text + addSymbols(string: String(finalText), symbolLength: symbolLength).font(Font.custom("MPlantin", size: fontSize))
		}

		if matches.isEmpty {
			text = addSymbols(string: oracleText, symbolLength: symbolLength).font(Font.custom("MPlantin", size: fontSize))
		}
		
		return text
	}
}

fileprivate func italicizeFlavorText(string: String) -> Text {
	let regex = "\\*([^*]+)\\*"
	
	guard #available(iOS 14.0, *) else {
		return Text(string)
	}
	
	let matches = Array(string.matches(forRegex: regex).enumerated())
	
	guard !matches.isEmpty else {
		return Text(string).font(Font.custom("MPlantin-Italic", size: fontSize))
	}
	
	var text: Text = Text("")
	
	for (index, match) in matches {
		let fromPreviousStart: String.Index = {
			guard index > 0 else { return string.startIndex }
			return matches[index-1].element.fullMatch.range.upperBound
		}()
		
		guard match.fullMatch.range.lowerBound >= fromPreviousStart else {
			print("match range incorrect for \(match.fullMatch.value)")
			continue
		}
		
		let italic = string[fromPreviousStart..<match.fullMatch.range.lowerBound]
		
		text = text + Text(italic).font(Font.custom("MPlantin-Italic", size: fontSize)) + Text(match.groups[0].value).font(Font.custom("MPlantin", size: fontSize))
		
		if index == matches.count-1 {
			let end = string[match.fullMatch.range.upperBound...]
			text = text + Text(end).font(Font.custom("MPlantin-Italic", size: fontSize))
		}
	}
	
	return text
}

class OracleTextViewModel: ObservableObject {
	@Published var oracleText: String?
	@Published var flavorText: String?
	@Published var textAlignment: TextAlignment = .leading
  @Published var adventureViewModel: AdventureViewModel?
  @Published var padding: CGFloat = 0
}

struct OracleTextView: View {
	@ObservedObject var viewModel: OracleTextViewModel
	
  private func finalText(width: CGFloat) -> Text? {
		var texts: [Text] = []
		
		if let oracleText = viewModel.oracleText {
			texts.append(OracleText(oracleText: oracleText, symbolSpacingEnabled: false, symbolLength: 13).content)
				
		}
    if let text = viewModel.oracleText, let flavorText = viewModel.flavorText, !text.isEmpty && !flavorText.isEmpty, let uiImage = UIImage(named: "separator") {
      let width = width * 0.95
      let size = CGSize(width: width, height: (16/583)*width)
      let scaled = uiImage.scaled(toFit: size)
			let image = Image(uiImage: scaled)
			texts.append(Text(image))
		}
		if let flavorText = viewModel.flavorText {
			texts.append(italicizeFlavorText(string: flavorText))
		}
		
		guard !texts.isEmpty else { return nil }
		
		let first = texts.removeFirst()
		return texts.reduce(first, +)
	}
  
  var body: some View {
    GeometryReader { proxy in
      if let adventureViewModel = viewModel.adventureViewModel {
        AdventureTextView(viewModel: adventureViewModel)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      } else {
        finalText(width: proxy.size.width)
          .minimumScaleFactor(0.1)
          .foregroundColor(.black)
          .multilineTextAlignment(viewModel.textAlignment)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .padding(viewModel.padding)
      }
    }
  }
}

class OracleTextViewController: UIHostingController<AnyView> {
	var viewModel: OracleTextViewModel
	
	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .clear
	}

	@objc required dynamic init?(coder aDecoder: NSCoder) {
		let viewModel = OracleTextViewModel()
    let view = AnyView(OracleTextView(viewModel: viewModel))
		self.viewModel = viewModel
		super.init(coder: aDecoder, rootView: view)
	}
}


class LandscapeHandViewController: UIViewController, PileDisplaying {
	
	var pile: Pile!
	private let bag = DisposeBag()
	private let cardInstances = BehaviorRelay<OrderedSet<CardInstance>>(value: [])
	private var handViewController: HandViewController!
	@IBOutlet weak var cardView: MTGCardView!
	@IBOutlet weak var typeLineLabel: UILabel!
	weak var oracleTextViewController: OracleTextViewController!
	@IBOutlet weak var collectorNumberLabel: UILabel!
	@IBOutlet weak var setLanguageLabel: UILabel!
	@IBOutlet weak var rarityLabel: UILabel!
	@IBOutlet weak var artistLabel: UILabel!
	@IBOutlet weak var symbolImageView: UIImageView!
	@IBOutlet weak var textBoxImageView: UIImageView!
	@IBOutlet weak var watermarkImageView: UIImageView!
	@IBOutlet weak var flipButton: UIButton?
	@IBOutlet weak var copyrightLabel: UILabel!
	@IBOutlet weak var illustrationIcon: UIImageView!
	@IBOutlet weak var colorIndicatorImageView: UIImageView!
	@IBOutlet weak var typeLineStackView: UIStackView!

  @IBOutlet weak var rightButton: UIButton!
  @IBOutlet weak var leftButton: UIButton!
  @IBOutlet weak var moreButton: UIButton!
  
  @IBOutlet weak var moveButtonStack: UIStackView!
  
  @IBOutlet weak var taxButton: UIButton!
  
  @IBOutlet weak var playButton: UIButton!
  
//  var sizes: [Int:CGRect] = [:]
	
	private var availableRepresentations: [CardRepresentation] = [] {
		didSet {
			flipButton?.isHidden = !(availableRepresentations.count > 1 && layout != "adventure")
			
			selectedCard = availableRepresentations.first
		}
	}
	private var layout: String?
//	private var associatedIndex: Int?
  private var associatedCardInstance: CardInstance?
	
	private var shouldAnimateNextChange: Bool = false
	
	fileprivate func clear() {
		oracleTextViewController.viewModel.oracleText = nil
		oracleTextViewController.viewModel.flavorText = nil
    oracleTextViewController.viewModel.adventureViewModel = nil
		
		cardView.isHidden = true
		symbolImageView.image = nil
		watermarkImageView.image = nil
		
		rarityLabel.text = nil
		artistLabel.text = nil
		setLanguageLabel.text = nil
		copyrightLabel.text = nil
		illustrationIcon.isHidden = true
		textBoxImageView.image = nil
		typeLineLabel.text = nil
		collectorNumberLabel.text = nil
		
		updateMenu()
    updateButtons()
	}
	
	var faceIndex: Int? {
		if case .alternateFace(let card, let face) = selectedCard, let index = card.cardFaces?.firstIndex(of: face) {
			return index
		}
		return nil
	}
	
	var selectedCard: CardRepresentation? {
    didSet {
      guard let associatedCardInstance else { return }
      
      defer {
        shouldAnimateNextChange = false
      }
      
      guard selectedCard != oldValue else {
        return
      }
      
      guard let card = selectedCard else {
        clear()
        return
      }
      
      let manaCost: String? = {
        if associatedCardInstance.isCommander.value == true && associatedCardInstance.pile?.location == .command {
          let tax = associatedCardInstance.commanderCasts.value * 2
          
          if card.typeLine?.contains("Adventure") == true || card.typeLine?.contains("Omen") == true || card.layout == "prepare" {
            if tax == 0 {
              return card.manaCost
            } else {
              return "{\(tax)}+\(card.manaCost ?? "")"
            }
          } else if tax == 0 {
            return card.manaCost
          } else {
            return "{\(tax)}   +   \(card.manaCost ?? "")"
          }
        } else {
          return card.manaCost
        }
      }()
      
      illustrationIcon.isHidden = card.artist == nil
      
      let isAltFace: Bool = {
        if card.layout == "meld" {
          return card.card.allParts?.contains(where: {
            $0.component == .meldResult && $0.scryfallID == card.card.scryfallID
          }) == true
        }
        
        return (faceIndex ?? 0) >= 1
      }()
			
			let properties = MTGCardView.properties(
				includedIcons: .all,
				showManaCost: true,
				name: card.name,
				manaCost: manaCost,
				typeLine: card.typeLine,
				oracleText: card.oracleText,
        colorInitials: card.colors?.map { $0.initial },
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
        isCommander: associatedCardInstance.isCommander.value
      )
			
			cardView.isHidden = false
			
			if shouldAnimateNextChange {
				UIView.transition(with: cardView, duration: 0.5, options: faceIndex == 0 ? .transitionFlipFromLeft : .transitionFlipFromRight, animations: { [weak self] in
					guard let self = self else { return }
					self.cardView.properties = properties
					self.cardView.layoutSubviews()
				}, completion: nil)
			} else {
				cardView.properties = properties
				cardView.layoutSubviews()
			}
      
      let typeToSearchFor = card.layout == "adventure" ? (card.card.typeLine?.contains("Adventure") == true ? "adventure" : "omen") : nil
			
      if let typeToSearchFor, let adventure = availableRepresentations.first(where: { $0.typeLine?.lowercased().contains(typeToSearchFor) == true }), let permanent = availableRepresentations.first(where: { $0.typeLine?.lowercased().contains(typeToSearchFor) == false }) {
        
        oracleTextViewController.viewModel.textAlignment = .leading
        oracleTextViewController.viewModel.flavorText = nil
        oracleTextViewController.viewModel.oracleText = nil
        
        let vm = AdventureViewModel()
        vm.oracleText = permanent.oracleText
        vm.flavorText = permanent.flavorText
        vm.adventureTitle = adventure.name ?? ""
        vm.adventureText = adventure.oracleText ?? ""
        vm.adventureCost = adventure.manaCost ?? ""
        vm.adventureType = adventure.typeLine ?? ""
        
        func singleColor(from colors: [MTGColor]?) -> MTGColor {
          guard let colors else {
            return .colorless
          }
          
          guard colors.count == 1 else {
            return .multicolor
          }
          
          return colors.first ?? .colorless
        }
        
        vm.color = singleColor(from: permanent.colors)
        vm.adventureColor = singleColor(from: adventure.colors)
        
        oracleTextViewController.viewModel.adventureViewModel = vm
        
        oracleTextViewController.viewModel.padding = 0
        
        textBoxImageView.image = nil
        textBoxImageView.isHidden = true
        watermarkImageView.isHidden = true
			} else {
        oracleTextViewController.viewModel.adventureViewModel = nil
				
				let isBasic = card.typeLine?.lowercased().contains("basic") == true
				let isNormalBasic = isBasic && card.flavorText == nil
				
				oracleTextViewController.viewModel.textAlignment = .leading
				
				if isNormalBasic {
					(oracleTextViewController.viewModel.oracleText, oracleTextViewController.viewModel.flavorText) = (nil, nil)
				} else if isBasic {
					(oracleTextViewController.viewModel.oracleText, oracleTextViewController.viewModel.flavorText) = (nil, card.flavorText)
					oracleTextViewController.viewModel.textAlignment = .center
				} else {
					(oracleTextViewController.viewModel.oracleText, oracleTextViewController.viewModel.flavorText) = (card.oracleText, card.flavorText)
				}
				
				watermarkImageView.image = watermarkImage
        textBoxImageView.image = TextBox.textBoxImage(colors: cardView.properties.colors, backgroundStyle: cardView.properties.backgroundStyle)
				textBoxImageView.isHidden = false
				watermarkImageView.isHidden = false
        
        if isNormalBasic {
          watermarkImageView.alpha = 1
        } else {
          watermarkImageView.alpha = 0.125
        }
        
        oracleTextViewController.viewModel.padding = 9
			}
			
			if let indicator = card.colorIndicator?.ordered, !indicator.isEmpty {
				colorIndicatorImageView.image = UIImage(named: "CI_\(indicator.map(\.initial).joined())")
				colorIndicatorImageView.isHidden = false
			} else {
				colorIndicatorImageView.isHidden = true
			}
			
			typeLineLabel.text = card.typeLine
			
			collectorNumberLabel.text = { () -> String in
				if let num = Int(card.card.collectorNumber) {
					return String(format: "%03d", num)
				} else {
					return card.card.collectorNumber
				}
				}().uppercased()
			artistLabel.text = card.card.artist
			
			var set = card.card.set
			
			if set.count > 3 && set.lowercased().hasPrefix("p") {
				set = String(set.dropFirst())
			}
			
			setLanguageLabel.text = set.uppercased()
			rarityLabel.text = card.isEmblem ? "E" : card.isToken ? "T" : card.isBasicLand ? "L" : card.card.rarity.rawValue.first.map(String.init)?.uppercased()
			
			symbolImageView.image = nil
			
			var copyrightText = "™ & © "
			if let releaseDate = card.card.releaseDate {
				let year = Calendar.current.component(.year, from: releaseDate)
				copyrightText += "\(year) "
			}
			copyrightText += "Wizards of the Coast"
			copyrightLabel.text = copyrightText
			
			DispatchQueue.global(qos: .userInteractive).async { [weak self, card] in
				let image = card.card.symbolImage(size: .large)
				DispatchQueue.main.async { [weak self] in
					guard let self = self, card == self.selectedCard else { return }
					self.symbolImageView.image = image
				}
			}
			
			DispatchQueue.global(qos: .userInteractive).async { [weak self, card] in
				let image = card.image(type: .art)
				DispatchQueue.main.async { [weak self] in
					guard let self = self, let image = image, card == self.selectedCard else { return }
					self.cardView.properties.art = image
				}
			}
		}
	}
	
	var player: Player {
		return GameState.current[player: pile.playerIdentifier]
	}
	
	func setPile(_ pile: Pile) {
		self.pile = pile
		
		handViewController.player = player
    
    let combinedCards = Observable.combineLatest(pile.cards, GameState.current[player: pile.playerIdentifier].commandZone.cards)
      .map { hand, commandZone in
        hand.contents + commandZone.contents
      }
      .share()
		
    combinedCards
      .map {
        OrderedSet($0)
      }
			.bind(to: self.cardInstances)
			.disposed(by: bag)
		
    combinedCards
		.withPrevious(startWith: [])
		.subscribe(onNext: { [weak self] oldCards, newCards in
			guard let self = self else { return }
			
      if (newCards.count == oldCards.count + 1 || (!newCards.isEmpty && oldCards.isEmpty)), let newIndex = newCards.lastIndex(where: { card in !oldCards.contains(where: { $0.uuid == card.uuid }) }) {
        self.setAvailableRepresentations(from: newCards[newIndex], index: newIndex)
				self.handViewController.selectedCard.accept(newCards[newIndex])
			} else if newCards.isEmpty {
				self.setAvailableRepresentations(from: nil, index: nil)
				self.handViewController.selectedCard.accept(nil)
			} else if newCards.count < oldCards.count {
				let difference = newCards.difference(from: oldCards)
				let lastRemovedIndex: Int = difference.compactMap { change -> Int? in
					if case .remove(offset: let offset, element: _, associatedWith: _) = change {
						return offset
					} else {
						return nil
					}
				}.max() ?? 0
				
				var cardToSelect: CardInstance?
				var index: Int?
				
				if oldCards.indices.contains(lastRemovedIndex+1), let newIndex = newCards.firstIndex(of: oldCards[lastRemovedIndex+1]) {
					cardToSelect = oldCards[lastRemovedIndex+1]
					index = newIndex
				} else {
					cardToSelect = newCards.last
					index = oldCards.indices.last
				}
        
//        if cardToSelect?.pile?.location == .command, !pile.cards.value.isEmpty, let last = pile.cards.value.last {
//          cardToSelect = last
//          index = pile.cards.value.count-1
//        }
				
//				let lastRemovedCard = oldCards.last(where: { difference.contains($0) })
				
				self.setAvailableRepresentations(from: cardToSelect, index: index)
				self.handViewController.selectedCard.accept(cardToSelect)
				// TODO: Update to pick new card.
      } else if newCards.count == oldCards.count {
        
        if let selectedCard = handViewController.selectedCard.value, let newIndex = newCards.firstIndex(of: selectedCard), let oldIndex = oldCards.firstIndex(of: selectedCard), newIndex != oldIndex {
          // Card position in hand moved
//          self.selectedCard = selectedCard
          self.handViewController.generator.selectionChanged()
        }
      } else if newCards.count > oldCards.count, let newIndex = newCards.lastIndex(where: { card in !oldCards.contains(where: { $0.uuid == card.uuid }) }) {
        self.setAvailableRepresentations(from: newCards[newIndex], index: newIndex)
        self.handViewController.selectedCard.accept(newCards[newIndex])
      }
			
			self.updateMenu()
      self.updateButtons()
		}).disposed(by: bag)
	}
	
	var contentType: DisplayedContent {
		return .pile(pile.location)
	}
	
	var pileLocation: Pile.Location? {
		return pile.location
	}
	
	var ownerIdentifier: Player.Identifier {
		return pile.playerIdentifier
	}
	
	func pushImageViewController(for cardInstance: CardInstance) {
		
	}

    override func viewDidLoad() {
        super.viewDidLoad()
		
//		watermarkImageView.layer.compositingFilter = "overlayBlendMode"
		
		let monospacedFont = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
		collectorNumberLabel.font = monospacedFont
//		setLanguageLabel.font = monospacedFont
//		rarityLabel.font = monospacedFont
		
		let copyrightFont = UIFont(name: "MPlantin", size: copyrightLabel.font.pointSize)!
		copyrightLabel.font = copyrightFont

		clear()
		
		moreButton.showsMenuAsPrimaryAction = true
	}
	
	private func updateMenu() {
		guard pile != nil else {
			moreButton.menu = nil
			moreButton.isEnabled = false
			return
		}
		
		moreButton.isEnabled = true
		moreButton.menu = makePlayCardUIMenu()
	}
  
  private var shouldIncreaseCommanderTax = true
  private var shouldPlayTapped = false
  
  private func updateButtons() {
    if let associatedCardInstance {
      // Commander
      leftButton.isEnabled = false
      rightButton.isEnabled = false
      taxButton.isEnabled = true
      
      var actions: [UIAction] = [
        UIAction(title: "Play") { _ in
          if associatedCardInstance.pile?.location == .command {
            self.shouldIncreaseCommanderTax = true
          }
          self.playButtonPressed(self.playButton!)
        }
      ]
      
      if associatedCardInstance.pile?.location == .command {
        actions.append(.init(title: "Play without increasing commander tax") { _ in
          self.shouldIncreaseCommanderTax = false
          self.playButtonPressed(self.playButton!)
        })
      }
      
      actions.append(.init(title: "Play Tapped") { _ in
        self.shouldPlayTapped = true
        self.playButtonPressed(self.playButton!)
      })
      
      if actions.count > 1 {
        playButton.menu = UIMenu(children: actions)
      } else {
        playButton.menu = nil
      }
      
    } else {
      // Normal
      leftButton.isEnabled = true
      rightButton.isEnabled = true
      taxButton.isEnabled = false
      
      playButton.menu = nil
    }
  }
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
	}
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "EmbedHandViewController", let destination = segue.destination as? HandViewController {
			self.handViewController = destination
			destination.isCardSelectionEnabled = true
			
			destination.selectedCard
				.subscribe(onNext: { [weak self] selectedCardInstance in
					guard let selectedCardInstance = selectedCardInstance else {
						self?.setAvailableRepresentations(from: nil, index: nil)
						return
					}
          
          guard let self else { return }
					
          let allDisplayedCards = self.pile.cards.value.contents + GameState.current[player: self.pile.playerIdentifier].commandZone.cards.value.contents
          
					guard let index = allDisplayedCards.firstIndex(of: selectedCardInstance) else { return }
					self.setAvailableRepresentations(from: selectedCardInstance, index: index)
				}).disposed(by: bag)
		} else if segue.identifier == "embedOracleTextViewController", let destination = segue.destination as? OracleTextViewController {
			self.oracleTextViewController = destination
		}
	}
	
	private func setAvailableRepresentations(from cardInstance: CardInstance?, index: Int?) {
    guard let cardInstance else {
      availableRepresentations = []
      layout = nil
      associatedCardInstance = nil
      return
    }
    let card = cardInstance.representation.card
		
		layout = card.layout
    
    associatedCardInstance = cardInstance
		
		if let faces = card.cardFaces, faces.count > 1 {
			availableRepresentations = faces.map {
				.alternateFace(card, $0)
			}
		} else {
			availableRepresentations = [.card(card)]
		}
		
		updateMenu()
    updateButtons()
	}
	
	@IBAction private func flipButtonPressed(sender: UIButton) {
		guard let selectedCard = selectedCard, let index = availableRepresentations.firstIndex(of: selectedCard) else {
			return
		}
		
		let nextIndex = index + 1
		
		if selectedCard.layout == "transform" || selectedCard.layout == "modal_dfc" {
			shouldAnimateNextChange = true
		}
		
		if availableRepresentations.indices.contains(nextIndex) {
			self.selectedCard = availableRepresentations[nextIndex]
		} else if index != 0 {
			self.selectedCard = availableRepresentations.first
		}
		
	}
	
  @IBAction func leftButtonPressed(_ sender: Any) {
    guard let cardInstance = associatedCardInstance, let index = self.pile.cards.value.firstIndex(of: cardInstance) else { return }
    
    guard cardInstance.pile?.location == .hand else { return }
    
    let command = Command.moveCards(Command.MoveCommandParameters(
      cardInstanceIDs: [cardInstance.uuid],
      destination: .init(
        location: pile.location,
        playerIdentifier: pile.playerIdentifier
      ),
      insertionIndex: index-1
    ))
    
    AppDelegate.shared.transceiver.broadcast(command)
  }
  
  @IBAction func rightButtonPressed(_ sender: Any) {
    guard let cardInstance = associatedCardInstance, let index = self.pile.cards.value.firstIndex(of: cardInstance) else { return }
    
    guard cardInstance.pile?.location == .hand else { return }
    
    let command = Command.moveCards(Command.MoveCommandParameters(
      cardInstanceIDs: [cardInstance.uuid],
      destination: .init(
        location: pile.location,
        playerIdentifier: pile.playerIdentifier
      ),
      insertionIndex: index+1
    ))
    
    AppDelegate.shared.transceiver.broadcast(command)
  }
  
  @IBAction func taxButtonPressed(_ sender: Any) {
    
  }
  
  
	@IBAction func facesValueChanged(_ sender: UISegmentedControl) {
		self.selectedCard = availableRepresentations[sender.selectedSegmentIndex]
	}
	
//	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
//		super.viewWillTransition(to: size, with: coordinator)
//
//		coordinator.animate(alongsideTransition: { [weak self] context in
//			guard let self = self else { return }
//			let orientation = self.view.window!.windowScene!.interfaceOrientation
//			if orientation == .landscapeLeft || orientation == .landscapeRight {
////				 activate landscape changes
//			} else {
//				self.dismiss(animated: true, completion: nil)
//			}
//		})
//	}
	
	
	private func attributedOracleText(_ oracleText: String, symbolSpacingEnabled: Bool = true) -> NSMutableAttributedString {
		let textFont = UIFont(name: "MPlantin", size: fontSize)!
		
		var oracleText = oracleText
			.replacingOccurrences(of: "\n", with: "\n\n")
			.replacingOccurrences(of: "−", with: "-")
		
		if symbolSpacingEnabled {
			oracleText = oracleText.replacingOccurrences(of: "}{", with: "} {")
		}
		
		let italicFont = UIFont(name: "MPlantin-Italic", size: fontSize)!
		
		let attributedString = NSMutableAttributedString(string: oracleText, attributes: [.font: textFont])
		
		let matches = oracleText.matches(forRegex: #"(?:\((.*?)\)|^(.+) — )"#, options: .anchorsMatchLines)
		for match in matches {
			guard match.fullMatch.value != "Companion — " else { continue }
			let range = NSRange(match.fullMatch.range, in: oracleText)
			attributedString.addAttribute(.font, value: italicFont, range: range)
		}
		
		for symbol in MTGSymbolName.allCases {
			let attachment = NSTextAttachment()
			attachment.image = symbol.image
			attachment.setImageHeight(height: fontSize * 0.8)
			let attachmentString = NSAttributedString(attachment: attachment)
			
			while let range = attributedString.string.range(of: symbol.rawValue) {
				attributedString.replaceCharacters(in: NSRange(range, in: attributedString.string), with: attachmentString)
			}
		}
		
		return attributedString
	}
	
	func attributedFlavorText(_ flavorText: String) -> NSMutableAttributedString {
		let textFont = UIFont(name: "MPlantin", size: fontSize)!
		let italicFont = UIFont(name: "MPlantin-Italic", size: fontSize)!
		
		let attributedString = NSMutableAttributedString(string: flavorText, attributes: [.font: italicFont])
		
		let matches = flavorText.matches(forRegex: "\\*([^*]+)\\*")
//		for (fullMatch, groups) in matches {
//			guard groups.first != nil else { continue }
//			let range = NSRange(fullMatch.range, in: attributedString.string)
//			attributedString.addAttribute(.font, value: textFont, range: range)
//			// TODO: Remove the asterisks -- repalce the range of the full match in the attributed string with just the text of the capture group.
//		}
		
		for (fullMatch, groups) in matches.sorted(by: { $0.fullMatch.range.lowerBound > $1.fullMatch.range.lowerBound }) {
			guard let group = groups.first else { continue }
			let fullRange = NSRange(fullMatch.range, in: attributedString.string)
			
			let newString = NSAttributedString(string: group.value, attributes: [.font: textFont])
			attributedString.replaceCharacters(in: fullRange, with: newString)
			
		}
		
		return attributedString
	}
	
	private var watermarkImage: UIImage! {
		guard let selectedCard = selectedCard else { return nil }
		
		if selectedCard.typeLine?.lowercased().contains("basic") == true {
			for landName in MTGColor.allCases.compactMap(\.land) {
				if selectedCard.typeLine?.lowercased().contains(landName) == true {
					if selectedCard.flavorText != nil {
						return UIImage(named: "watermark-\(landName.lowercased())")
					} else if selectedCard.typeLine?.lowercased().contains("snow") == true {
						return UIImage(named: landName.capitalized + "-snow")
					} else {
						return UIImage(named: landName.capitalized)
					}
				}
			}
			return UIImage(named: "Wastes")
		} else if let watermark = selectedCard.watermark {
			return UIImage(named: "watermark-\(watermark)")
		}
		
		return nil
	}
	
	// Handle buttons
	
	@IBAction func playButtonPressed(_ sender: Any) {
    guard let cardInstance = associatedCardInstance else { return }
		
		let isAftermath: Bool = {
			if cardInstance.representation.layout == "split", let faces = cardInstance.representation.card.cardFaces, faces.count == 2, faces[1].oracleText?.hasPrefix("Aftermath") == true {
				return true
			}
			return false
		}()
		
		if let faces = cardInstance.representation.card.cardFaces, faces.count >= 1 {
			if cardInstance.representation.layout == "transform" || isAftermath {
				castSplitFace(faceIndex: 0, cardInstance: cardInstance)
			} else {
				let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
				let options = (cardInstance.representation.layout == "adventure" ? Array(faces.enumerated().reversed()) : Array(faces.enumerated()))
				
				for (index, face) in options {
					let action = UIAlertAction(title: face.name, style: .default) { (_) in
						self.castSplitFace(faceIndex: index, cardInstance: cardInstance)
					}
					alert.addAction(action)
				}
				
				if cardInstance.representation.keywords.contains("Fuse") {
					let action = UIAlertAction(title: "Fuse", style: .default) { (_) in
						self.castCard(cardInstance: cardInstance)
					}
					alert.addAction(action)
				}
				
				let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
				alert.addAction(cancelAction)
				
				self.present(alert, animated: true, completion: nil)
			}
		} else if cardInstance.representation.keywords.contains("Morph") || cardInstance.representation.keywords.contains("Megamorph") {
			
			let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
			
			let castAction = UIAlertAction(title: cardInstance.representation.name, style: .default) { (_) in
				self.castCard(cardInstance: cardInstance)
			}
			alert.addAction(castAction)
			
			let morphAction = UIAlertAction(title: "Morph", style: .default) { (_) in
				self.castMorphFace(cardInstance: cardInstance)
			}
			alert.addAction(morphAction)
			
			let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
			alert.addAction(cancelAction)
			
			self.present(alert, animated: true, completion: nil)
    } else if cardInstance.representation.card.prototype != nil {
      let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
      
      let castAction = UIAlertAction(title: "Cast", style: .default) { (_) in
        self.castCard(cardInstance: cardInstance)
      }
      alert.addAction(castAction)
      
      if cardInstance.representation.keywords.contains("Prototype") {
        let action = UIAlertAction(title: "Prototype", style: .default) { (_) in
          let command = Command.moveCardsToBattlefield([Command.PlayCardParameters(
            cardInstanceID: cardInstance.uuid,
            mode: .prototype,
            increaseTax: self.shouldIncreaseCommanderTax,
            tapped: self.shouldPlayTapped
          )])
          AppDelegate.shared.transceiver.broadcast(command)
          self.shouldIncreaseCommanderTax = true
          self.shouldPlayTapped = false
        }
        alert.addAction(action)
      }
      
      let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
      alert.addAction(cancelAction)
      
      self.present(alert, animated: true, completion: nil)
      
    } else {
//			let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
//
//			let castAction = UIAlertAction(title: cardInstance.representation.typeLine?.lowercased().contains("land") == true ? "Play" : "Cast", style: .default) { (_) in
//				self.castCard(cardInstance: cardInstance)
//			}
//			alert.addAction(castAction)
//
//			let manifestAction = UIAlertAction(title: "Manifest", style: .default) { (_) in
//				self.manifest(cardInstance: cardInstance)
//			}
//			alert.addAction(manifestAction)
//
//			let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
//			alert.addAction(cancelAction)
//
//			self.present(alert, animated: true, completion: nil)
			
			castCard(cardInstance: cardInstance)
		}
	}
	
	@IBAction func moreButtonPressed(_ sender: Any) {
    guard let associatedCardInstance else { return }
    showPlayCardMenu(for: associatedCardInstance)
	}
	
	func castCard(cardInstance: CardInstance) {
		let command = Command.moveCardsToBattlefield([Command.PlayCardParameters(
      cardInstanceID: cardInstance.uuid,
      faceIndex: nil,
      increaseTax: shouldIncreaseCommanderTax,
      tapped: shouldPlayTapped
    )])
		AppDelegate.shared.transceiver.broadcast(command)
    self.shouldIncreaseCommanderTax = true
    self.shouldPlayTapped = false
	}
	
	func castSplitFace(faceIndex: Int, cardInstance: CardInstance) {
		guard let faces = cardInstance.representation.card.cardFaces, faces.count >= 1 else { return }
		let command = Command.moveCardsToBattlefield([Command.PlayCardParameters(cardInstanceID: cardInstance.uuid, faceIndex: faceIndex, increaseTax: shouldIncreaseCommanderTax, tapped: shouldPlayTapped)])
		AppDelegate.shared.transceiver.broadcast(command)
    self.shouldIncreaseCommanderTax = true
    self.shouldPlayTapped = false
	}
	
	func castMorphFace(cardInstance: CardInstance) {
		let command = Command.moveCardsToBattlefield([Command.PlayCardParameters(cardInstanceID: cardInstance.uuid, faceIndex: faceIndex, mode: .morph, increaseTax: shouldIncreaseCommanderTax, tapped: shouldPlayTapped)])
		AppDelegate.shared.transceiver.broadcast(command)
    self.shouldIncreaseCommanderTax = true
    self.shouldPlayTapped = false
	}
	
	func manifest(cardInstance: CardInstance) {
		let command = Command.moveCardsToBattlefield([Command.PlayCardParameters(cardInstanceID: cardInstance.uuid, faceIndex: faceIndex, mode: .manifest, increaseTax: shouldIncreaseCommanderTax, tapped: shouldPlayTapped)])
		AppDelegate.shared.transceiver.broadcast(command)
    self.shouldIncreaseCommanderTax = true
    self.shouldPlayTapped = false
	}
	
  private func showPlayCardMenu(for cardInstance: CardInstance) {
		
//		let cardInstance = cardInstances.value[index]
		let card = cardInstance.representation.card
		let isSingleFaced = (card.cardFaces?.count ?? 0) == 0
		
		let alert = UIAlertController(title: isSingleFaced ? card.name : nil, message: nil, preferredStyle: .actionSheet)
		alert.title = nil
		
		for action in self.actions(for: cardInstance, includeFaceCasts: false, includeIndividualCast: !isSingleFaced) where action.title != "View Card" && action.title != "Reveal to Opponent" && action.title != "Morph" {
			let alertAction = UIAlertAction(title: action.title, style: action.style) {
				action.handler?($0)
				if action.style != .cancel {
//					self.cardCollectionViewLayout?.revealCardAt(index: indexPath.item)
				}
			}
			alert.addAction(alertAction)
		}
		
//		let frame = self.sizes[index]
//		alert.popoverPresentationController?.sourceView = view
//		alert.popoverPresentationController?.sourceRect = frame ?? .zero
//		alert.view.transform = (navigationController?.view ?? view).transform
		
		self.present(alert, animated: true)
	}
	
	private func makePlayCardUIMenu() -> UIMenu {
		var actions: [UIMenuElement] = []
		
		var moveHandActions: [UIMenuElement] = []
		
    let attributes: UIMenuElement.Attributes = self.pile.cards.value.isEmpty ? .disabled : []
		let playerIdentifier = player.identifier
    let uuids = self.pile.cards.value.map(\.uuid)
		
		func makeMoveAction(title: String, destination: Pile.Location, insertionIndex: Int? = nil) -> UIAction {
			return UIAction(title: title, attributes: attributes) { _ in
				let params = Command.MoveCommandParameters(
					cardInstanceIDs: uuids,
					destination: .init(location: destination, playerIdentifier: playerIdentifier),
					insertionIndex: insertionIndex
				)
				
				let command = Command.moveCards(params)
				AppDelegate.shared.transceiver.broadcast(command)
			}
		}
		
		let discardAction = makeMoveAction(title: "Discard", destination: .graveyard)
		moveHandActions.append(discardAction)
		
		let exileAction = makeMoveAction(title: "Exile", destination: .exile)
		moveHandActions.append(exileAction)
		
		let libraryTopAction = makeMoveAction(title: "Move to Top of Library", destination: .library)
		moveHandActions.append(libraryTopAction)
		
		let libraryBottomAction = makeMoveAction(title: "Move to Bottom of Library", destination: .library, insertionIndex: -1)
		moveHandActions.append(libraryBottomAction)
		
		let moveHandMenu = UIMenu(title: "Hand", children: moveHandActions)
		actions.append(moveHandMenu)
    
    guard let cardInstance = associatedCardInstance, pile.cards.value.contains(cardInstance) else { return UIMenu(title: "", children: actions) }
		
		var cardActions: [UIMenuElement] = []
		
		let card = cardInstance.representation.card
		let isSingleFaced = (card.cardFaces?.count ?? 0) == 0
    
    if cardInstance.isCommander.value && cardInstance.pile?.location == .command {
      let action = UIAction(title: "Play without increasing commander tax") { _ in
        self.shouldIncreaseCommanderTax = false
        self.castCard(cardInstance: cardInstance)
      }
      cardActions.append(action)
    }
		
		for action in self.actions(for: cardInstance, includeFaceCasts: false, includeIndividualCast: !isSingleFaced) where action.title != "View Card" && action.title != "Reveal to Opponent" && action.title != "Morph" && action.style != .cancel {
			let uiAction = Action(title: action.title, style: action.style) { act in
				print("sending command for \(cardInstance.representation.name ?? "")")
				action.handler?(act)
			}
			
			cardActions.append(uiAction.uiAction)
		}
		
		let cardMenu = UIMenu(title: "", options: .displayInline, children: cardActions)
		actions.append(cardMenu)
		
		return UIMenu(title: "", children: actions)
	}
	
	deinit {
		NotificationCenter.default.removeObserver(self)
	}

}
