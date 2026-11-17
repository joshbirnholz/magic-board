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

struct CardManualAction {
    let title: String
    /// Closes the card inspector afterwards (actions whose result shows on the battlefield).
    var dismisses = false
    let perform: () -> Void
}

struct CardControlView: View {
    @State private var phoneActionRevision = 0
	let card: CardInstance
	let dismiss: () -> Void
	
	@State var doesNotAutoUntapChecked: Bool
	@State var doesNotUntapNextTurnChecked: Bool
	@State var isPreparedChecked: Bool
	@State var lockedDoors: Set<Counter>
	@State var isPhasedOut: Bool
  @State var isCommanderChecked: Bool
  @State var commanderCasts: Int
  @State var colors: [MTGColor]
  
	@State var creationCount: Int = 1
	
	init(card: CardInstance, dismiss: @escaping () -> Void) {
		self.card = card
		self.doesNotAutoUntapChecked = card.doesNotUntapAutomatically.value
		self.doesNotUntapNextTurnChecked = card.doesNotUntapNextTurn.value
		self.isPreparedChecked = card.counters.value.contains(.prepared)
		self.lockedDoors = Set(card.counters.value.filter(\.isDoorLock))
		self.isPhasedOut = card.counters.value.contains(.phasedOut)
    self.isCommanderChecked = card.isCommander.value
    self.commanderCasts = card.commanderCasts.value
		self.dismiss = dismiss
    self.colors = card.colors.value
	}
	
	// MARK: Quick actions grid

	private struct Tile: Identifiable {
		let id: String
		let title: String
		let icon: String
		var isOn: Bool? = nil
		var destructive = false
		let action: () -> Void
	}

	private static func icon(for title: String) -> String {
		switch title {
		case "Attack": return "arrow.up.forward.circle"
		case "Remove from Combat": return "xmark.shield"
		case "Stop Blocking": return "shield.slash"
		case "Tap": return "arrow.turn.down.right"
		case "Untap": return "arrow.turn.up.left"
		case "Unattach": return "paperclip"
		case "Move to Command Zone": return "crown"
		case "Resolve from Stack": return "checkmark.circle"
		case "Copy": return "plus.square.on.square"
		default: return title.hasPrefix("Counter") ? "xmark.bin" : "circle.grid.2x2"
		}
	}

	private var isOnBattlefield: Bool {
		if let onField = PhonePlayBridge.battlefieldContains(card) { return onField }
		return GameState.current.battlefield.value.contains(card)
	}

	private var tiles: [Tile] {
		var tiles: [Tile] = AppDelegate.shared.phoneCardActions(card).map { action in
			Tile(id: "action-\(action.title)", title: action.title, icon: Self.icon(for: action.title)) {
				action.perform()
				if action.dismisses { dismiss() }
			}
		}
		if PhonePlayBridge.isRulesMode { return tiles }
		tiles.append(Tile(id: "control", title: "Switch Control", icon: "arrow.left.arrow.right") {
			card.controllerIdentifier.accept(card.controllerIdentifier.value == .a ? .b : .a)
			try? GameState.current.save()
		})
		let type = card.representation.typeLine ?? ""
		if !(card.representation.isEmblem || type == "Vanguard" || type == "Phenomenon" || type.contains("Conspiracy") || type.contains("Scheme")) {
			tiles.append(Tile(id: "token-copy", title: "Token Copy", icon: "doc.on.doc") {
				card.createCards.onNext { () -> [(Player.Identifier, CardRepresentation)] in
					Array(repeating: (card.controllerIdentifier.value, .tokenCopy(card.representation)), count: creationCount)
				}
				dismiss()
			})
		}
		if card.representation.layout == "transform", case .alternateFace(let mtgCard, _) = card.representation, let faces = mtgCard.cardFaces, !faces.isEmpty {
			tiles.append(Tile(id: "transform", title: "Transform", icon: "arrow.triangle.2.circlepath") {
				if let otherSide = faces.first(where: { $0.name != card.representation.name }) {
					card.representation = .alternateFace(mtgCard, otherSide)
					try? GameState.current.save()
				}
			})
		}
		switch card.representation {
		case .faceDown(let inner):
			tiles.append(Tile(id: "face-up", title: "Face-Up", icon: "eye") { card.representation = inner; try? GameState.current.save(); dismiss() })
		case .morph(let inner), .manifest(let inner), .mysterious(let inner), .foretold(let inner):
			tiles.append(Tile(id: "face-up", title: "Face-Up", icon: "eye") { card.representation = .card(inner); try? GameState.current.save(); dismiss() })
		default:
			tiles.append(Tile(id: "face-down", title: "Face-Down", icon: "eye.slash") {
				card.representation = .faceDown(card.representation); try? GameState.current.save(); dismiss()
			})
		}
		if isOnBattlefield {
			tiles.append(Tile(id: "phased", title: "Phased Out", icon: "circle.dashed", isOn: isPhasedOut) { togglePhasing() })
		}
		tiles.append(Tile(id: "auto-untap", title: "Doesn't Auto-Untap", icon: "lock", isOn: doesNotAutoUntapChecked) {
			card.doesNotUntapAutomatically.accept(!card.doesNotUntapAutomatically.value)
			doesNotAutoUntapChecked.toggle()
			try? GameState.current.save()
		})
		tiles.append(Tile(id: "untap-next", title: "Doesn't Untap Next Turn", icon: "lock.rotation", isOn: doesNotUntapNextTurnChecked) {
			card.doesNotUntapNextTurn.accept(!card.doesNotUntapNextTurn.value)
			doesNotUntapNextTurnChecked.toggle()
			try? GameState.current.save()
		})
		if !card.representation.isToken {
			tiles.append(Tile(id: "commander", title: "Commander", icon: "crown.fill", isOn: isCommanderChecked) {
				card.isCommander.mutate { $0.toggle() }
				isCommanderChecked.toggle()
				try? GameState.current.save()
			})
		}
		tiles.append(Tile(id: "remove", title: "Remove", icon: "trash", destructive: true) {
			card.remove.onNext(())
			try? GameState.current.save()
		})
		return tiles
	}

	/// Every quick action at a glance: compact tiles instead of a long list. Toggles light up when on.
	@ViewBuilder var actionGrid: some View {
		LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
			ForEach(tiles) { tile in
				Button(action: tile.action) {
					VStack(spacing: 5) {
						Image(systemName: tile.icon)
							.font(.system(size: 17, weight: .semibold))
							.frame(height: 20)
						Text(tile.title)
							.font(.caption2.weight(.medium))
							.multilineTextAlignment(.center)
							.lineLimit(2)
							.minimumScaleFactor(0.8)
					}
					.frame(maxWidth: .infinity, minHeight: 52)
					.padding(.horizontal, 4)
					.foregroundStyle(tile.destructive ? Color.red : tile.isOn == true ? Color.accentColor : Color.primary)
					.background(RoundedRectangle(cornerRadius: 12, style: .continuous)
						.fill(tile.isOn == true ? Color.accentColor.opacity(0.22) : Color(uiColor: .tertiarySystemFill)))
					.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
						.strokeBorder(tile.isOn == true ? Color.accentColor : .clear, lineWidth: 1.5))
					.contentShape(RoundedRectangle(cornerRadius: 12))
				}
				.buttonStyle(.plain)
				.accessibilityLabel(tile.title)
				.accessibilityAddTraits(tile.isOn == true ? [.isSelected, .isButton] : .isButton)
				.accessibilityIdentifier("card-tile-\(tile.id)")
			}
		}
		.id(phoneActionRevision)
	}

	/// Card-specific rows: a prepare card's marker and spell, a Room's door locks.
	@ViewBuilder var mainSection: some View {
		// Prepare cards (layout "prepare") show a Prepared marker where Transform would be.
		if card.representation.card.layout == "prepare" {
			Button {
				let prepared = !isPreparedChecked
				if !PhonePlayBridge.sendCounter(card.uuid, .prepared, prepared ? 1 : -1) {
					card.counters.mutate { counters in
						if prepared { counters.append(.prepared) }
						else if let index = counters.firstIndex(of: .prepared) { counters.remove(at: index) }
					}
					try? GameState.current.save()
				}
				isPreparedChecked = prepared
			} label: {
				HStack {
					if let symbol = Counter.prepared.symbolImage {
						Image(uiImage: symbol).renderingMode(.template).resizable().scaledToFit().frame(width: 18, height: 18)
					}
					Text("Prepared")
					if isPreparedChecked {
						Spacer()
						Image(systemName: "checkmark")
					}
				}
			}
			.accessibilityIdentifier("card-prepared")
			.accessibilityAddTraits(isPreparedChecked ? .isSelected : [])
			// While prepared, its spell can be cast (as a copy); that unprepares the creature.
			if isPreparedChecked, PhonePlayBridge.controlsCard(card),
			   let spell = card.representation.card.cardFaces?.dropFirst().first {
				Button("Cast \(spell.name ?? "Prepared Spell")") {
					PhonePlayBridge.castPrepared(card.uuid)
					isPreparedChecked = false
					dismiss()
				}
				.accessibilityIdentifier("card-cast-prepared")
			}
		}

		if card.representation.isRoom, let faces = card.representation.card.cardFaces {
			// A Room isn't two faces: each door is locked or unlocked (where Transform would be).
			ForEach(Array(faces.prefix(2).enumerated()), id: \.offset) { index, face in
				let lock = Counter.doorLock(index)
				Button {
					toggleDoor(lock)
				} label: {
					HStack {
						if lockedDoors.contains(lock), let door = Counter.lockedDoorImage {
							Image(uiImage: door).renderingMode(.template).resizable().scaledToFit().frame(width: 18, height: 18)
						} else {
							Image(systemName: "door.left.hand.open")
						}
						Text("\(face.name ?? "Door") Locked")
						if lockedDoors.contains(lock) {
							Spacer()
							Image(systemName: "checkmark")
						}
					}
				}
				.accessibilityIdentifier("card-door-lock-\(index)")
			}
		}
	}

	private func togglePhasing() {
		let phased = !isPhasedOut
		if !PhonePlayBridge.sendCounter(card.uuid, .phasedOut, phased ? 1 : -1) {
			card.counters.mutate { counters in
				if phased { counters.append(.phasedOut) } else if let index = counters.firstIndex(of: .phasedOut) { counters.remove(at: index) }
			}
			try? GameState.current.save()
		}
		isPhasedOut = phased
	}

	private func toggleDoor(_ lock: Counter) {
		let locked = !lockedDoors.contains(lock)
		if !PhonePlayBridge.sendCounter(card.uuid, lock, locked ? 1 : -1) {
			card.counters.mutate { counters in
				if locked { counters.append(lock) } else if let index = counters.firstIndex(of: lock) { counters.remove(at: index) }
			}
			try? GameState.current.save()
		}
		if locked { lockedDoors.insert(lock) } else { lockedDoors.remove(lock) }
	}

	/// A face's own flavor name when it's printed with one (e.g. "Hawkins National Laboratory"
	/// for Havengul Laboratory), else its name.
	static func displayName(of face: MTGCard.Face, in card: MTGCard) -> String {
		face.flavorName ?? face.name ?? ""
	}

	/// Switching faces (split halves, double-faced sides, prototype). Face-up/down are tiles.
	@ViewBuilder var cardFaceSection: some View {
		switch card.representation {
		case .card(let card), .alternateFace(let card, _), .prototyped(let card):
			if card.layout == "split" {
				Button(card.flavorName ?? card.name ?? "") {
					self.card.representation = .card(card)
					try? GameState.current.save()
				}
			}
			if let faces = card.cardFaces, !faces.isEmpty {
				ForEach(faces, id: \.self) { face in
					Button(Self.displayName(of: face, in: card)) {
						self.card.representation = .alternateFace(card, face)
						try? GameState.current.save()
					}
				}
			}
			if card.prototype != nil {
				Toggle(isOn: .init(get: {
					if case .prototyped = self.card.representation { return true } else { return false }
				}, set: { newValue in
					self.card.representation = newValue ? .prototyped(card) : .card(card)
					try? GameState.current.save()
					dismiss()
				}), label: { Text("Prototyped") })
			}
		default:
			EmptyView()
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
					return [(self.card.controllerIdentifier.value, CardRepresentation.tokenCopy(rep))]
				}
				dismiss()
			}
		}
		if let parts = card.representation.card.allParts?.filter({ $0.name != card.representation.name && $0.isCreatable }), !parts.isEmpty {
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
	
  /// Whether the Create… section has anything beyond the Token Copy tile.
  private var hasCreateOptions: Bool {
    card.representation.card.language != .english
      || card.representation.name == "Factory of Momir Vig" || card.representation.name == "Momir Vig, Simic Visionary Avatar"
      || card.representation.card.allParts?.contains(where: { $0.name != card.representation.name && $0.isCreatable }) == true
  }

  /// Whether the card has faces to switch between (Rooms lock doors instead).
  private var hasFaceChoices: Bool {
    guard !card.representation.isRoom else { return false }
    let mtgCard = card.representation.card
    return mtgCard.layout == "split" || (mtgCard.cardFaces?.isEmpty == false) || mtgCard.prototype != nil
  }

  var body: some View {
    List {
      if PhonePlayBridge.isRulesMode {
        Section { actionGrid }
      } else {
      // Card-specific rows (Prepared, Room doors) come first: they're why the menu was opened.
      if card.representation.card.layout == "prepare" || card.representation.isRoom {
        Section {
          mainSection
        }
      }

      Section {
        actionGrid
          .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
          .listRowBackground(Color.clear)
      }

      if card.representation.card.set.lowercased() == "hbg" {
        Section(header: Text("Specialize…")) {
          specializeSection
        }
      } else {
        if hasFaceChoices {
          Section(header: Text("Card Face")) {
            cardFaceSection
          }
        }
        if hasCreateOptions {
          Section(header: Text("Create…")) {
            createSection
          }
        }
      }

      if isCommanderChecked {
        Section {
          Stepper(value: $commanderCasts, in: 0...(Int.max)) {
            HStack {
              Text("Commander Tax")
              Spacer()
              addSymbols(string: "{\(commanderCasts * 2)}", symbolLength: 16)
            }
          }
        }
      }

      Section(header: Text("Colors")) {
        HStack {
          ForEach(MTGCardView.Color.allCases, id: \.self) { color in
            Button(action: {
              let color = MTGColor(rawValue: color.initial.uppercased())!
              var set = Set(self.colors)
              if self.colors.contains(color) { set.remove(color) } else { set.insert(color) }
              self.colors = Array(set)
            }, label: {
              Image(resource: "{\(color.initial)}")
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .opacity(self.colors.contains(MTGColor(rawValue: color.initial.uppercased())!) ? 1 : 0.1)
            }).buttonStyle(.plain)
            .accessibilityIdentifier("card-color-\(color.initial.lowercased())")
          }
        }
      }
    }
    }
    .listStyle(.insetGrouped)
//    .listStyle(.insetGrouped)
    .navigationTitle(card.representation.name ?? "")
    .navigationBarTitleDisplayMode(.inline)
    .onReceive(NotificationCenter.default.publisher(for: .phoneGameDidChange)) { _ in phoneActionRevision &+= 1 }
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
      try? GameState.current.save()
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
				return UIImage.resource(named: "Creature_symbol")!
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
            guard !AppDelegate.shared.usesPhoneSession else { break }
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
			
			if let parts = cardInstance.representation.card.allParts?.filter({ $0.name != cardInstance.representation.name && $0.isCreatable }), !parts.isEmpty {
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
				case .morph(let card), .manifest(let card), .mysterious(let card), .foretold(let card):
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


extension MTGCard.RelatedCard {
	/// Only tokens (and emblems) can be created from a card; related cards such as the cards that
	/// make a token, meld pieces or combo pieces aren't offered.
	var isCreatable: Bool {
		component == .token || typeLine.contains("Token") || typeLine.contains("Emblem")
	}
}


/// The card menu's Phone Play hooks. Board Connect compiles this file too but has no Phone Play,
/// so there they do nothing (and the menu edits the card directly, as on the iPad board).
private enum PhonePlayBridge {
#if BOARD_CONNECT
	static var isRulesMode: Bool { false }
	static func battlefieldContains(_ card: CardInstance) -> Bool? { nil }
	static func sendCounter(_ id: UUID, _ counter: Counter, _ delta: Int) -> Bool { false }
	static func controlsCard(_ card: CardInstance) -> Bool { false }
	static func castPrepared(_ id: UUID) {}
#else
	static var isRulesMode: Bool { AppDelegate.shared.phoneSession?.mode == .rules }
	/// Whether the card is on Phone Play's battlefield (nil outside Phone Play).
	static func battlefieldContains(_ card: CardInstance) -> Bool? {
		AppDelegate.shared.phoneSession.map { $0.game.state.battlefield.value.contains(card) }
	}
	/// Sends a counter change through Phone Play; false outside Phone Play.
	static func sendCounter(_ id: UUID, _ counter: Counter, _ delta: Int) -> Bool {
		guard let session = AppDelegate.shared.phoneSession else { return false }
		session.send(.counter(id, counter, delta))
		return true
	}
	/// Whether this phone's player controls the card in Phone Play.
	static func controlsCard(_ card: CardInstance) -> Bool {
		AppDelegate.shared.phoneSession.map { card.controllerIdentifier.value == $0.player } ?? false
	}
	static func castPrepared(_ id: UUID) { AppDelegate.shared.phoneSession?.send(.castPrepared(id)) }
#endif
}
