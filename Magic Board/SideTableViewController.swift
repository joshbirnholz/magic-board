//
//  SideTableViewController.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/15/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import CardService
import RxSwift
import SwiftUI
import RxRelay
import CardView

struct CardControlView: View {
	let card: CardInstance
	let dismiss: () -> Void
	
	@State var doesNotAutoUntapChecked: Bool
	@State var doesNotUntapNextTurnChecked: Bool
  @State var isCommanderChecked: Bool
  @State var commanderCasts: Int
  @State var colors: [MTGColor]
  
	@State var creationCount: Int = 1
	
	init(card: CardInstance, dismiss: @escaping () -> Void) {
		self.card = card
		self.doesNotAutoUntapChecked = card.doesNotUntapAutomatically.value
		self.doesNotUntapNextTurnChecked = card.doesNotUntapNextTurn.value
    self.isCommanderChecked = card.isCommander.value
    self.commanderCasts = card.commanderCasts.value
		self.dismiss = dismiss
    self.colors = card.colors.value
	}
	
	@ViewBuilder var mainSection: some View {
		Button("Switch Control") {
			switch card.controllerIdentifier.value {
			case .a:
				card.controllerIdentifier.accept(.b)
			case .b:
				card.controllerIdentifier.accept(.a)
			}
			try? GameState.current.save()
		}
		
		Button {
			card.doesNotUntapAutomatically.accept(!card.doesNotUntapAutomatically.value)
			doesNotAutoUntapChecked.toggle()
		} label: {
			HStack {
				Text("Doesn't Auto-Untap")
				if doesNotAutoUntapChecked {
					Spacer()
					Image(systemName: "checkmark")
				}
			}
		}
		
		Button {
			card.doesNotUntapNextTurn.accept(!card.doesNotUntapNextTurn.value)
			doesNotUntapNextTurnChecked.toggle()
		} label: {
			HStack {
				Text("Doesn't Untap Next Turn")
				if doesNotUntapNextTurnChecked {
					Spacer()
					Image(systemName: "checkmark")
				}
			}
		}
		
		if card.representation.layout == "transform", case .alternateFace(let mtgCard, _) = card.representation, let faces = mtgCard.cardFaces, !faces.isEmpty {
			Button("Transform") {
				if let otherSide = faces.first(where: { $0.name != card.representation.name }) {
					card.representation = .alternateFace(mtgCard, otherSide)
					try? GameState.current.save()
				}
			}
		}
	}
	
	@ViewBuilder var removeSection: some View {
		Button("Remove") {
			card.remove.onNext(())
			try? GameState.current.save()
		}.foregroundColor(.red)
	}
	
	@ViewBuilder var cardFaceSection: some View {
		switch card.representation {
		case .faceDown(let card):
			// For face-down cards, don't give any information about what other faces it may have. Just give the option to turn it face up.
			Button("Face-Up") {
				self.card.representation = card
				
				try? GameState.current.save()
				dismiss()
			}
		case .morph(let card), .manifest(let card), .foretold(let card):
			// For morph cards, don't give any information about what other faces it may have. Just give the option to turn it face up.
			Button("Face-Up") {
				self.card.representation = .card(card)
				
				try? GameState.current.save()
				dismiss()
			}
    case .card(let card), .alternateFace(let card, _), .prototyped(let card):
			if card.layout == "split" {
				Button(card.name ?? "") {
					self.card.representation = .card(card)
					try? GameState.current.save()
				}
			}
			
			if let faces = card.cardFaces, !faces.isEmpty {
				ForEach(faces, id: \.self) { face in
					Button(face.name ?? "") {
						self.card.representation = .alternateFace(card, face)
						try? GameState.current.save()
					}
				}
			}
      
      if card.prototype != nil {
        Toggle(isOn: .init(get: {
          if case .prototyped(_) = self.card.representation {
            return true
          } else {
            return false
          }
        }, set: { newValue in
          if newValue {
            self.card.representation = .prototyped(card)
          } else {
            self.card.representation = .card(card)
          }
          
          try? GameState.current.save()
          dismiss()
        }), label: {
          Text("Prototyped")
        })
      }
			
			Button("Face-Down") {
				self.card.representation = .faceDown(self.card.representation)
				try? GameState.current.save()
				dismiss()
			}
		case .tokenCopy(let representedCard):
			Button("Face-Down") {
				self.card.representation = .faceDown(.tokenCopy(representedCard))
				try? GameState.current.save()
				dismiss()
			}
		}
	}
	
	@ViewBuilder var createSection: some View {
		HStack {
			Text(String(creationCount))
			Spacer()
			Stepper("", value: $creationCount, in: 1...20)
		}
		if card.representation.card.language != .english {
			Button("English Version") {
				guard let card = try? CardService.shared.getCard(code: card.representation.card.set, number: card.representation.card.collectorNumber) else { return }
				DispatchQueue.main.async {
					self.card.createCards.onNext { () -> [(Player.Identifier, CardRepresentation)] in
						[(self.card.controllerIdentifier.value, .card(card))]
					}
					dismiss()
				}
			}
		}
		
		if card.representation.name == "Factory of Momir Vig" || card.representation.name == "Momir Vig, Simic Visionary Avatar" {
			Button("Random Creature (X = \(creationCount))") {
				card.createCards.onNext { () -> [(Player.Identifier, CardRepresentation)] in
					let card = try CardService.shared.getMomirCard(convertedManaCost: creationCount)
					
					let rep: CardRepresentation = {
						if let faces = card.cardFaces, faces.count > 1, let firstFace = faces.first {
							return .alternateFace(card, firstFace)
						} else {
							return .card(card)
						}
					}()
					
					let copy = CardRepresentation.tokenCopy(rep)
					return [(self.card.controllerIdentifier.value, copy)]
				}
				dismiss()
			}
		}
		
		if let parts = card.representation.card.allParts?.filter({ $0.name != card.representation.name }), !parts.isEmpty {
			ForEach(parts, id: \.self) { part in
				Button(part.name) {
					DispatchQueue.global(qos: .userInteractive).async {
						guard let card = try? CardService.shared.getCard(scryfallID: part.scryfallID) else { return }
						DispatchQueue.main.async {
							self.card.createCards.onNext { () -> [(Player.Identifier, CardRepresentation)] in
								if let faces = card.cardFaces, faces.count > 1, let front = faces.first {
									return Array(repeating: (self.card.controllerIdentifier.value, .alternateFace(card, front)), count: creationCount)
								} else {
									return Array(repeating: (self.card.controllerIdentifier.value, .card(card)), count: creationCount)
								}
							}
							dismiss()
						}
					}
				}
			}
		}
		
		if !(card.representation.isEmblem || card.representation.typeLine == "Vanguard" || card.representation.typeLine == "Phenomenon" || card.representation.typeLine?.contains("Conspiracy") == true || card.representation.typeLine?.contains("Scheme") == true || card.representation.typeLine?.hasPrefix("Plane") == true) {
			Button("Token Copy") {
				card.createCards.onNext { () -> [(Player.Identifier, CardRepresentation)] in
					Array(repeating: (card.controllerIdentifier.value, .tokenCopy(card.representation)), count: creationCount)
				}
				dismiss()
			}
		}
		
	}
	
	@ViewBuilder var specializeSection: some View {
    if let parts = card.representation.card.allParts?.compactMap({ try? CardService.shared.getCard(scryfallID: $0.scryfallID) }), !parts.isEmpty {
      let sorted = parts.sorted { first, second in
        return (specializedColor(for: first, from: parts)?.orderNumber ?? -1) < (specializedColor(for: second, from: parts)?.orderNumber ?? -1)
      }
			ForEach(sorted, id: \.scryfallID) { part in
        Button(action: {
          self.card.representation = .card(part)
          try? GameState.current.save()
        }, label: {
          HStack {
            Text(part.name ?? "")
            Spacer()
            if let color = specializedColor(for: part, from: parts) {
              addSymbols(string: "{\(color.initial.uppercased())}")
            }
          }
        })
			}
		}
	}
	
  var body: some View {
    List {
      Section {
        mainSection
      }
      
      if card.representation.card.set.lowercased() == "hbg" {
        Section(header: Text("Specialize…")) {
          specializeSection
        }
      } else {
        switch card.representation {
        case .faceDown, .morph, .manifest, .foretold:
          EmptyView()
        default:
          Section(header: Text("Create…")) {
            createSection
          }
        }
        
        Section(header: Text("Card Face")) {
          cardFaceSection
        }
      }
      
      if !card.representation.isToken {
        Section {
          Button(action: {
            self.card.isCommander.mutate {
              $0.toggle()
            }
            
            withAnimation {
              isCommanderChecked.toggle()
            }
            
            try? GameState.current.save()
          }, label: {
            HStack {
              Text("Commander")
              Spacer()
              if isCommanderChecked {
                Image(systemName: "checkmark")
              }
            }
          })
          
          if card.isCommander.value {
            Stepper(value: $commanderCasts, in: 0...(Int.max)) {
              HStack {
                Text("Commander Tax")
                Spacer()
                addSymbols(string: "{\(commanderCasts * 2)}", symbolLength: 16)
                
              }
            }
          }
        }
      }
      
      Section(header: Text("Properties")) {
        HStack {
          ForEach(MTGCardView.Color.allCases, id: \.self) { color in
            Button(action: {
              let color = MTGColor(rawValue: color.initial.uppercased())!
              
              var set = Set(self.colors)
              
              if self.colors.contains(color) {
                set.remove(color)
              } else {
                set.insert(color)
              }
              
              self.colors = Array(set)
            }, label: {
              Image("{\(color.initial)}")
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .opacity(self.colors.contains(MTGColor(rawValue: color.initial.uppercased())!) ? 1 : 0.1)
            }).buttonStyle(.plain)
          }
        }
      }
      
      Section {
        removeSection
      }
    }
    .listStyle(SidebarListStyle())
//    .listStyle(.insetGrouped)
    .navigationTitle(card.representation.name ?? "")
    .navigationBarTitleDisplayMode(.inline)
    .bind(commanderCasts, to: card.commanderCasts)
    .bind(colors, to: card.colors)
  }
}

extension View {
  @ViewBuilder
  func bind<V>(
      _ value: V,
      to relay: BehaviorRelay<V>
  ) -> some View where V : Equatable {
    onChange(of: value) { newValue in
      relay.accept(newValue)
    }
  }
}

class CardCell: UITableViewCell {
	@IBOutlet weak var cardImageView: UIImageView!
}

protocol PowerToughnessCellDelegate: AnyObject {
	func updateHeight()
}

class SideTableViewController: UITableViewController, PowerToughnessCellDelegate {
	
	enum SectionModel: Int, CaseIterable {
		case card
		case control
		case creature
		case game
		
		static var viewControllerCombinations: [[SectionModel]] {
			return [
//				[.control],
				[.creature]
			]
		}
		
		var title: String? {
			switch self {
			case .card:
				return nil
			case .creature:
				return "Creature"
			case .control:
				return "Control"
			case .game:
				return "Game"
			}
		}
		
		var rows: [RowModel] {
			switch self {
			case .card:
				return [.card]
			case .creature:
				return [
          .flying,
//						.summoningSickness,
						.powerToughness]
			case .control:
				return [.flip,
						.createTokens,
						.cardFaces,
						.chain,
						.chainOneTurn,
						.remove]
			case .game:
				return [.removeAll]
			}
		}
		
		var isEnabled: Bool {
			switch self {
			case .card, .game:
				return false
			default:
				return true
			}
		}
		
		var tabBarImage: UIImage? {
			switch self {
			case .card:
				return nil
			case .creature:
				return #imageLiteral(resourceName: "Creature_symbol")
			case .control:
				return nil
			case .game:
				return nil
			}
		}
	}
	
	enum RowModel: Int {
		case card
		case tapUntap
		case summoningSickness
		case powerToughness
		case flying
    case commander
		case flip
		case remove
		case removeAll
//		case move
		case chain
		case chainOneTurn
		case createTokens
		case cardFaces
		
		var reuseIdentifier: String {
			switch self {
			case .card:
				return "CardCell"
			case .powerToughness:
				return "PickerCell"
			default:
				return "BasicOption"
			}
		}
	}
	
	
	weak var card: CardInstance? {
		didSet {
			navigationItem.title = card?.representation.name
			if card != oldValue {
				tableView.reloadData()
			}
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		tableView.clipsToBounds = false
		
//		tableView.contentInset.top -= 20
	}

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
		return sectionModel?.count ?? 0
    }
	
	var sectionModel: [SectionModel]!
	
	func rowModel(for indexPath: IndexPath) -> RowModel? {
		return sectionModel?[indexPath.section].rows[indexPath.row]
	}
	
	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
//		return sections()[section].title
		return nil
	}

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return self.sectionModel?[section].rows.count ?? 0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		guard let row = rowModel(for: indexPath) else { return UITableViewCell() }
		
		let cell = tableView.dequeueReusableCell(withIdentifier: row.reuseIdentifier, for: indexPath)

		switch row {
		case .card:
			guard let cell = cell as? CardCell else { break }
			guard let card = card else { break }
			
			cell.cardImageView.image = nil
			cell.clipsToBounds = false
			cell.cardImageView.clipsToBounds = false
			
			DispatchQueue.global(qos: .userInteractive).async {
				let image = card.representation.image(type: .large)
				DispatchQueue.main.async {
					UIView.transition(with: cell.cardImageView,
					duration: 0.2,
					options: .transitionCrossDissolve,
					animations: {
						cell.cardImageView.image = image
					},
					completion: nil)
				}
			}
		case .tapUntap:
			guard let card = card else { break }
			cell.textLabel?.text = "Tapped"
			cell.accessoryType = card.isTapped.value ? .checkmark : .none
		case .flip:
			cell.textLabel?.text = "Switch Control"
			cell.accessoryType = .none
		case .remove:
			cell.textLabel?.text = "Remove"
			cell.accessoryType = .none
//		case .move:
//			cell.textLabel?.text = "Move to…"
//			cell.accessoryType = .disclosureIndicator
		case .summoningSickness:
			guard let card = card else { break }
			cell.textLabel?.text = "Summoning Sickness"
			cell.accessoryType = card.isSummoningSick.value ? .checkmark : .none
		case .flying:
			guard let card = card else { break }
			cell.textLabel?.text = "Flying"
			cell.accessoryType = card.isFlying.value ? .checkmark : .none
    case .commander:
      guard let card = card else { break }
      cell.textLabel?.text = "Commander"
      cell.accessoryType = card.isCommander.value ? .checkmark : .none
		case .chain:
			guard let card = card else { break }
			cell.textLabel?.text = "Doesn't Auto-Untap"
			cell.accessoryType = card.doesNotUntapAutomatically.value ? .checkmark : .none
		case .chainOneTurn:
			guard let card = card else { break }
			cell.textLabel?.text = "Doesn't Untap Next Turn"
			cell.accessoryType = card.doesNotUntapNextTurn.value ? .checkmark : .none
		case .powerToughness:
			guard let card = card else { break }
			guard let cell = cell as? PickerCell else { break }
			
			cell.cardInstance = card
			cell.delegate = self
		case .removeAll:
			cell.textLabel?.text = "Remove All Cards"
			cell.accessoryType = .none
		case .createTokens:
			cell.textLabel?.text = "Create…"
			cell.accessoryType = .disclosureIndicator
		case .cardFaces:
			cell.textLabel?.text = "Card Face"
			cell.accessoryType = .disclosureIndicator
		}
		
        return cell
    }
	
	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		guard let row = rowModel(for: indexPath) else { return }
		
		switch row {
		case .card:
			UIView.animate(withDuration: 0.2) {
				let cell = tableView.cellForRow(at: indexPath) as? CardCell
				cell?.cardImageView.transform = cell!.cardImageView.transform.rotated(by: .pi)
			}
//			tableView.transform = self.tableView.transform.rotated(by: .pi)
		case .tapUntap:
			guard let card = card else { break }
			card.isTapped.toggle()
			tableView.cellForRow(at: indexPath)?.accessoryType = card.isTapped.value ? .checkmark : .none
			try? GameState.current.save()
		case .flip:
			guard let card = card else { break }
			switch card.controllerIdentifier.value {
			case .a:
				card.controllerIdentifier.accept(.b)
			case .b:
				card.controllerIdentifier.accept(.a)
			}
			try? GameState.current.save()
		case .remove:
			card?.remove.onNext(())
			self.card = nil
			try? GameState.current.save()
			dismiss(animated: true, completion: nil)
		case .summoningSickness:
			guard let card = card else { break }
			card.isSummoningSick.toggle()
			tableView.cellForRow(at: indexPath)?.accessoryType = card.isSummoningSick.value ? .checkmark : .none
			try? GameState.current.save()
		case .flying:
			guard let card = card else { break }
			card.isFlying.accept(!card.isFlying.value)
			tableView.cellForRow(at: indexPath)?.accessoryType = card.isFlying.value ? .checkmark : .none
			try? GameState.current.save()
    case .commander:
      guard let card = card else { break }
      card.isCommander.accept(!card.isCommander.value)
      
      tableView.cellForRow(at: indexPath)?.accessoryType = card.isCommander.value ? .checkmark : .none
      try? GameState.current.save()
		case .chain:
			guard let card = card else { break }
			card.doesNotUntapAutomatically.accept(!card.doesNotUntapAutomatically.value)
			tableView.cellForRow(at: indexPath)?.accessoryType = card.doesNotUntapAutomatically.value ? .checkmark : .none
			try? GameState.current.save()
		case .chainOneTurn:
			guard let card = card else { break }
			card.doesNotUntapNextTurn.accept(!card.doesNotUntapNextTurn.value)
			tableView.cellForRow(at: indexPath)?.accessoryType = card.doesNotUntapNextTurn.value ? .checkmark : .none
			try? GameState.current.save()
		case .powerToughness:
			break
		case .removeAll:
			let alert = UIAlertController(title: "Are you sure you want to reset the game?", message: nil, preferredStyle: .alert)
			let removeAction = UIAlertAction(title: "Reset Game", style: .destructive) { (_) in
				for card in GameState.current.battlefield.value {
					card.remove.onNext(())
				}
				self.card = nil
				
				let player1Name = GameState.current.player1.name.value
				let player2Name = GameState.current.player2.name.value
				GameState.current = GameState(player1Name: player1Name, player2Name: player2Name)
			}
			alert.addAction(removeAction)
			let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
			alert.addAction(cancelAction)
			self.present(alert, animated: true, completion: nil)
//		case .move:
//			guard let cardInstance = card else { break }
//			let card = cardInstance.card.card
//
//			struct Location {
//				enum Position {
//					case top
//					case bottom
//					case shuffle
//				}
//				var position: Position = .top
//				var pile: Pile
//				var title: String
//			}
//			let owners = cardInstance.controllerIdentifier.value != cardInstance.ownerIdentifier ? "Owner's " : ""
//
//			let owner = GameState.current[player: cardInstance.ownerIdentifier]
//			var locations: [Location] = [
//				Location(position: .top, pile: owner.graveyard, title: "\(owners)Graveyard"),
//				Location(position: .top, pile: owner.library, title: "Top of \(owners)Library"),
//				Location(position: .bottom, pile: owner.library, title: "Bottom of \(owners)Library"),
//				Location(position: .shuffle, pile: owner.library, title: "Shuffle into \(owners)Library"),
//				Location(position: .top, pile: owner.hand, title: "\(owners)Hand"),
//				Location(position: .top, pile: owner.exile, title: "\(owners)Exile")
//			]
//
//			if cardInstance.controllerIdentifier.value != cardInstance.ownerIdentifier {
//				for player in GameState.current.allPlayers where player.identifier != owner.identifier {
//					locations.append(Location(position: .top, pile: player.exile, title: "Exile"))
//				}
//			}
//
//			let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
//			for location in locations {
//				let action = UIAlertAction(title: location.title, style: .default) { (_) in
//
//					switch location.position {
//					case .top:
//						location.pile.cards.mutate { cards in
//							cards.append(card)
//						}
//					case .bottom:
//						location.pile.cards.mutate { cards in
//							cards.insert(card, at: 0)
//						}
//					case .shuffle:
//						location.pile.cards.mutate { cards in
//							cards.append(card)
//							cards.shuffle()
//						}
//					}
//					cardInstance.remove.onNext(())
//					self.card = nil
//					try? GameState.current.save()
//					self.dismiss(animated: true, completion: nil)
//				}
//				alert.addAction(action)
//			}
//
//			let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
//			alert.addAction(cancelAction)
//
//			alert.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
//			alert.popoverPresentationController?.permittedArrowDirections = [.left, .right]
//			alert.view.transform = view.transform
//			if let navigationController = navigationController, alert.view.transform == .identity {
//				alert.view.transform = navigationController.view.transform
//			}
//			self.present(alert, animated: true, completion: nil)
		case .createTokens:
			guard let cardInstance = card else { break }
			
			let alert = UIAlertController(title: "Create…", message: nil, preferredStyle: .actionSheet)
			
			if cardInstance.representation.card.language != .english {
				let action = UIAlertAction(title: "English Version", style: .default) { [weak self] _ in
					guard let card = try? CardService.shared.getCard(code: cardInstance.representation.card.set, number: cardInstance.representation.card.collectorNumber) else { return }
					DispatchQueue.main.async { [weak self] in
						cardInstance.createCards.onNext { () -> [(Player.Identifier, CardRepresentation)] in
							[(cardInstance.controllerIdentifier.value, .card(card))]
						}
						self?.dismiss(animated: true, completion: nil)
					}
				}
				alert.addAction(action)
			}
			
			if cardInstance.representation.name == "Factory of Momir Vig" || cardInstance.representation.name == "Momir Vig, Simic Visionary Avatar" {
				for i in 0...16 {
					let tokenCopyAction = UIAlertAction(title: "Random Creature (X = \(i))", style: .default) { [weak self] _ in
						cardInstance.createCards.onNext { () -> [(Player.Identifier, CardRepresentation)] in
							let card = try CardService.shared.getMomirCard(convertedManaCost: i)
							
							let rep: CardRepresentation = {
								if let faces = card.cardFaces, faces.count > 1, let firstFace = faces.first {
									return .alternateFace(card, firstFace)
								} else {
									return .card(card)
								}
							}()
							
							let copy = CardRepresentation.tokenCopy(rep)
							return [(cardInstance.controllerIdentifier.value, copy)]
						}
						self?.dismiss(animated: true, completion: nil)
					}
					alert.addAction(tokenCopyAction)
				}
			}
			
			if !(cardInstance.representation.isEmblem || cardInstance.representation.typeLine == "Vanguard" || cardInstance.representation.typeLine == "Phenomenon" || cardInstance.representation.typeLine?.contains("Conspiracy") == true || cardInstance.representation.typeLine?.contains("Scheme") == true || cardInstance.representation.typeLine?.hasPrefix("Plane") == true) {
				let tokenCopyAction = UIAlertAction(title: "Token Copy\(cardInstance.representation.name.map { " of \($0)" } ?? "")", style: .default) { [weak self] _ in
					cardInstance.createCards.onNext { () -> [(Player.Identifier, CardRepresentation)] in
						[(cardInstance.controllerIdentifier.value, .tokenCopy(cardInstance.representation))]
					}
					self?.dismiss(animated: true, completion: nil)
				}
				alert.addAction(tokenCopyAction)
			}
			
			if let parts = cardInstance.representation.card.allParts?.filter({ $0.name != cardInstance.representation.name }), !parts.isEmpty {
				for part in parts {
					let action = UIAlertAction(title: part.name, style: .default) { _ in
						DispatchQueue.global(qos: .userInteractive).async {
							guard let card = try? CardService.shared.getCard(scryfallID: part.scryfallID) else { return }
							DispatchQueue.main.async { [weak self] in
								cardInstance.createCards.onNext { () -> [(Player.Identifier, CardRepresentation)] in
									if let faces = card.cardFaces, faces.count > 1, let front = faces.first {
										return [(cardInstance.controllerIdentifier.value, .alternateFace(card, front))]
									} else {
										return [(cardInstance.controllerIdentifier.value, .card(card))]
									}
								}
								self?.dismiss(animated: true, completion: nil)
							}
						}
					}
					alert.addAction(action)
				}
			}
			
			let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
			alert.addAction(cancelAction)
			
			alert.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
			alert.popoverPresentationController?.permittedArrowDirections = [.left, .right]
			alert.view.transform = view.transform
			if let navigationController = navigationController, alert.view.transform == .identity {
				alert.view.transform = navigationController.view.transform
			}
			self.present(alert, animated: true, completion: nil)
		case .cardFaces:
			guard let cardInstance = card else { return }
			
			let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
			
			func addActions(for card: CardRepresentation) {
				switch cardInstance.representation {
				case .faceDown(let card):
					// For face-down cards, don't give any information about what other faces it may have. Just give the option to turn it face up.
					let faceUpAction = UIAlertAction(title: "Face-Up", style: .default) { _ in
						cardInstance.representation = card
						
						try? GameState.current.save()
					}
					alert.addAction(faceUpAction)
				case .morph(let card), .manifest(let card), .foretold(let card):
					// For morph cards, don't give any information about what other faces it may have. Just give the option to turn it face up.
					let faceUpAction = UIAlertAction(title: "Face-Up", style: .default) { _ in
						cardInstance.representation = .card(card)
						
						try? GameState.current.save()
					}
					alert.addAction(faceUpAction)
        case .prototyped(let card):
          break
				case .card(let card), .alternateFace(let card, _):
					if card.layout == "split" {
						let splitFaceAction = UIAlertAction(title: card.name, style: .default) { _ in
							cardInstance.representation = .card(card)
							try? GameState.current.save()
						}
						alert.addAction(splitFaceAction)
					}
					
					if let faces = card.cardFaces, !faces.isEmpty {
						for face in faces {
							let action = UIAlertAction(title: face.name, style: .default) { _ in
								cardInstance.representation = .alternateFace(card, face)
								try? GameState.current.save()
							}
							alert.addAction(action)
						}
					}
					
					let faceDownAction = UIAlertAction(title: "Face-Down", style: .default) { _ in
						cardInstance.representation = .faceDown(cardInstance.representation)
						try? GameState.current.save()
					}
					alert.addAction(faceDownAction)
				case .tokenCopy(let representedCard):
					let faceDownAction = UIAlertAction(title: "Face-Down", style: .default) { _ in
						cardInstance.representation = .faceDown(.tokenCopy(representedCard))
						try? GameState.current.save()
					}
					alert.addAction(faceDownAction)
				}
			}
			
			addActions(for: cardInstance.representation)
			
//			let card = cardInstance.card.card
//
//
//			let defaultAction = UIAlertAction(title: card.name, style: .default) { _ in
//				self.card?.card = .card(card)
//			}
//			alert.addAction(defaultAction)
//
//			swit
//
//			if let faces = card.cardFaces, !faces.isEmpty {
//				for face in faces {
//					let action = UIAlertAction(title: face.name, style: .default) { _ in
//						self.card?.card = .alternateFace(card, face)
//						try? GameState.current.save()
//					}
//					alert.addAction(action)
//				}
//			}
			
			let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
			alert.addAction(cancelAction)
			
			alert.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
			alert.popoverPresentationController?.permittedArrowDirections = [.left, .right]
			
			alert.view.transform = view.transform
			if let navigationController = navigationController, view.transform == .identity {
				alert.view.transform = navigationController.view.transform
			}
			self.present(alert, animated: true, completion: nil)
		}
		
		tableView.deselectRow(at: indexPath, animated: true)
	}
	
	// MARK: PowerToughnessCellDelegate
	
	func updateHeight() {
		tableView.beginUpdates()
		tableView.endUpdates()
	}

    /*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}

public func specializedColor(for card: MTGCard, from cards: [MTGCard]) -> MTGColor? {
  if card.keywords?.contains("Specialize") == true {
    return nil
  }
  
  guard let sharedColor = [MTGColor.white, .blue, .black, .red, .green].first(where: { color in
    cards.contains { otherCard in
      (otherCard.manaCost ?? "").lowercased().contains("{\(color.initial.lowercased())}{\(color.initial.lowercased())}")
    }
  }) else { return nil }
  
  guard let colors = card.colors else { return nil }
  
  if colors.count == 1 {
    return colors.first
  }
  
  var set = Set(colors)
  set.remove(sharedColor)
  return set.first
}
