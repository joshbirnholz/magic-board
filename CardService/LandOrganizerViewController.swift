//
//  LandOrganizerViewController.swift
//  CardService
//
//  Created by Josh Birnholz on 10/17/23.
//  Copyright © 2023 Josh Birnholz. All rights reserved.
//

import Foundation
import CardService
import SwiftUI
import RxSwift
import RxRelay

// MARK: - Oracle Text Mana Parsing

/// Extracts produced MTGColors from a land's oracle text by scanning for mana
/// symbols in "Add ..." lines (e.g. "{T}: Add {W} or {B}.").
///
/// Special cases:
/// - "any color" / "any combination of colors" → all five pip colors
/// - "the chosen color" (Pathway-style) → returns nil so the caller can fall back
/// - {C} and other non-pip symbols → ignored (colorless lands handled separately)
private func parseProducedMana(from oracleText: String) -> [MTGColor]? {
  // "any color" lands (Mana Confluence, Command Tower, etc.) → all five
  let anyColorPhrases = ["any color", "any combination of colors", "any type"]
  if anyColorPhrases.contains(where: { oracleText.lowercased().contains($0) }) {
    return [.white, .blue, .black, .red, .green]
  }

  // "the chosen color" means we can't statically determine the color
  if oracleText.lowercased().contains("the chosen color") {
    return nil
  }

  // Extract all {W}/{U}/{B}/{R}/{G} symbols that appear after "Add"
  // Matches things like: "Add {W}.", "Add {U} or {B}.", "Add {G} or {W}."
  let addLinePattern = try! NSRegularExpression(pattern: #"(?i)\bAdd\b[^.]*"#)
  let pipPattern = try! NSRegularExpression(pattern: #"\{([WUBRG])\}"#)

  let nsText = oracleText as NSString
  let addMatches = addLinePattern.matches(in: oracleText, range: NSRange(location: 0, length: nsText.length))

  var colors: [MTGColor] = []

  for addMatch in addMatches {
    let addClause = nsText.substring(with: addMatch.range)
    let pipMatches = pipPattern.matches(in: addClause, range: NSRange(addClause.startIndex..., in: addClause))
    for pip in pipMatches {
      if let range = Range(pip.range(at: 1), in: addClause),
         let color = MTGColor(rawValue: String(addClause[range])) {
        colors.append(color)
      }
    }
  }

  return colors.isEmpty ? nil : Array(OrderedSet(colors))
}

// MARK: - CardRepresentation: Produced Mana

private extension CardRepresentation {
  /// Returns the mana colors this representation can currently produce,
  /// derived by parsing oracle text rather than relying on colors/manaCost
  /// (which are useless for colorless land permanents).
  ///
  /// For MDFCs like Brightclimb // Grimclimb Pathway, only the active face's
  /// oracle text is consulted, so sorting reflects the face that's actually
  /// in play.
  var producedMana: [MTGColor] {
    switch self {
    case .faceDown, .morph, .manifest, .foretold:
      return []

    case .alternateFace(let card, let face):
      // Parse the active face's oracle text first
      if let faceText = face.oracleText ?? face.printedText,
         let colors = parseProducedMana(from: faceText) {
        return colors
      }
      // "The chosen color" or unparseable — fall back to card-level producedMana
      return card.producedMana ?? []

    default:
      // For single-faced cards, parse oracle text; fall back to producedMana
      if let text = card.oracleText ?? card.printedText,
         let colors = parseProducedMana(from: text) {
        return colors
      }
      return card.producedMana ?? []
    }
  }
}

// MARK: - Color Sorting Helpers

/// WUBRG sort order for MTGColor. Lower = earlier in the display order.
private let mtgColorOrder: [MTGColor: Int] = [
  .white:     0,
  .blue:      1,
  .black:     2,
  .red:       3,
  .green:     4,
  .colorless: 5,
  .artifact:  6,
  .multicolor: 7,
]

/// A sort key for a produced mana set that puts:
///   - duals/multicolor before mono-color (more pip-producing colors = earlier)
///   - within the same count, orders by WUBRG primary then secondary color
///   - colorless/artifact lands sort last
private func colorSortKey(for colors: [MTGColor]) -> (Int, Int, Int) {
  // Only count actual pip colors — ignore .multicolor/.artifact/.colorless for bucketing
  let pipColors = colors.filter { [.white, .blue, .black, .red, .green].contains($0) }
  
  guard !pipColors.isEmpty else {
    // No pip colors: colorless/artifact lands go last
    let fallback = colors.compactMap { mtgColorOrder[$0] }.min() ?? Int.max
    return (2, fallback, Int.max)
  }
  
  let sorted = pipColors.sorted { (mtgColorOrder[$0] ?? .max) < (mtgColorOrder[$1] ?? .max) }
  let primary   = mtgColorOrder[sorted[0]] ?? Int.max
  let secondary = sorted.count > 1 ? (mtgColorOrder[sorted[1]] ?? Int.max) : Int.max
  
  // Negate count so more colors sort first (-2 < -1, duals before monos)
  return (-pipColors.count, primary, secondary)
}

// MARK: - LandOrganizer

struct LandOrganizer: View {
  
  struct LandStack: View {
    let cardInstances: OrderedSet<CardInstance>
    let onLongPress: (CardInstance) -> Void
    
    private var showsCountTile: Bool {
      cardInstances.count > 3
    }
    
    @ViewBuilder
    private var countTile: some View {
      Text("x\(cardInstances.count)")
        .font(.custom("Beleren2016-Bold", size: 22))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background {
          RoundedRectangle(cornerRadius: 4)
            .foregroundColor(.black.opacity(0.82))
        }
        .position(CGPoint(x: 24, y: 40))
    }
    
    var body: some View {
      OverlayedGeometryReader { proxy in
        HStack(spacing: -proxy.size.height * (showsCountTile ? 1.07 : 0.97)) {
          ForEach(Array(cardInstances.enumerated()), id: \.element.uuid) { (index, card) in
            SwiftUICardView(card: card)
              .shadow(radius: 5)
          }
        }.padding(.leading, showsCountTile ? 10 : 0)
          .overlay {
            if showsCountTile {
              countTile
            }
          }
      }
    }
  }
  
  @ObservedObject var cardInstances: ObservableBridge<OrderedSet<CardInstance>>
  @ObservedObject var tappedIDs: ObservableBridge<[UUID]>
  let onLongPress: (CardInstance) -> Void
  
  private var stacks: [[CardInstance]] {
    // 1. Group by oracle ID (same card type stacks together)
    let groups: [UUID: [CardInstance]] = .init(
      grouping: cardInstances.value,
      by: \.representation.card.oracleID!
    )
    
    // 2. Preserve original battlefield order within each oracle group
    let orderedGroups = groups
      .sorted { first, second in
        let firstOrder = cardInstances.value.firstIndex(where: { $0.representation.card.oracleID == first.key }) ?? .max
        let secondOrder = cardInstances.value.firstIndex(where: { $0.representation.card.oracleID == second.key }) ?? .max
        return firstOrder < secondOrder
      }
      .map(\.value)
      .map { group in
        group.sorted { first, second in
          let firstIndex = cardInstances.value.firstIndex(of: first) ?? .max
          let secondIndex = cardInstances.value.firstIndex(of: second) ?? .max
          return firstIndex < secondIndex
        }
      }
    
    // 3. Split each oracle group into untapped / tapped sub-stacks
    let splitGroups: [[CardInstance]] = orderedGroups.flatMap { group -> [[CardInstance]] in
      let untapped = group.filter { !tappedIDs.value.contains($0.uuid) }
      let tapped   = group.filter {  tappedIDs.value.contains($0.uuid) }
      return [untapped, tapped].filter { !$0.isEmpty }
    }
    
    // 4. Sort stacks by color signature: duals first, then mono WUBRG, then colorless
    let sorted = splitGroups.sorted { lhs, rhs in
      guard
        let lhsRep = lhs.first?.representation,
        let rhsRep = rhs.first?.representation
      else { return false }
      
      let lhsKey = colorSortKey(for: lhsRep.producedMana)
      let rhsKey = colorSortKey(for: rhsRep.producedMana)
      
      // Compare tuple elements in order
      if lhsKey.0 != rhsKey.0 { return lhsKey.0 < rhsKey.0 }
      if lhsKey.1 != rhsKey.1 { return lhsKey.1 < rhsKey.1 }
      return lhsKey.2 < rhsKey.2
    }
    
    return sorted
  }
  
  var body: some View {
    HStack(spacing: 6) {
      ForEach(stacks, id: \.first?.uuid) { stack in
        LandStack(cardInstances: OrderedSet(stack), onLongPress: onLongPress)
          .onTapGesture {
            stack.last?.isTapped.mutate {
              $0.toggle()
            }
            try? GameState.current.save()
          }
          .padding(.horizontal, 4)
      }
      Spacer()
    }.padding(.vertical, 4)
      .padding(.horizontal, 4)
      .background {
        RoundedRectangle(cornerRadius: 12)
          .foregroundColor(.white.opacity(0.05))
      }
      .padding(.bottom, 8)
      .padding(.horizontal, 4)
      .animation(.default, value: cardInstances.value)
      .animation(.easeInOut(duration: 0.2), value: tappedIDs.value)
  }
}

// MARK: - UIHostingController

class LandOrganizerViewController: UIHostingController<LandOrganizer> {
  
  var onLongPress: (CardInstance) -> Void = { _ in }
  
  var playerIdentifier: Player.Identifier = .a {
    didSet {
      bindPlayer()
    }
  }
  
  private let bag = DisposeBag()
  
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
  }
  
  @objc required dynamic init?(coder aDecoder: NSCoder) {
    let organizer = LandOrganizer(
      cardInstances: ObservableBridge(BehaviorRelay(value: [])),
      tappedIDs: .init(.init(value: [])),
      onLongPress: { _ in }
    )
    super.init(coder: aDecoder, rootView: organizer)
  }
  
  override func loadView() {
    super.loadView()
    view.translatesAutoresizingMaskIntoConstraints = false
  }
  
  func shouldIncludeCard(_ cardInstance: CardInstance) -> Bool {
    cardInstance.ownerIdentifier == self.playerIdentifier &&
    cardInstance.representation.typeLine?.lowercased().contains("land") == true &&
    !cardInstance.isPowerToughnessVisible.value
  }
  
  private func bindPlayer() {
    let relay: BehaviorRelay<OrderedSet<CardInstance>> = BehaviorRelay(value: [])
    
    GameState.current.battlefield
      .map { [weak self] set in
        guard let self else { return OrderedSet() }
        return OrderedSet(set.filter { self.shouldIncludeCard($0) })
      }
      .bind(to: relay)
      .disposed(by: bag)
    
    let tappedIDsRelay: BehaviorRelay<[UUID]> = .init(value: [])
    let isTapped = relay
      .map { set in set.map(\.isTapped) }
      .flatMap(Observable.combineLatest)
    
    Observable.combineLatest(relay, isTapped)
      .map { cards, isTapped in
        isTapped.enumerated().compactMap { index, isTapped in
          guard isTapped else { return nil }
          guard cards.indices.contains(index) else { return nil }
          return cards[index].uuid
        }
      }
      .bind(to: tappedIDsRelay)
      .disposed(by: bag)
    
    rootView = LandOrganizer(
      cardInstances: ObservableBridge(relay),
      tappedIDs: ObservableBridge(tappedIDsRelay),
      onLongPress: onLongPress
    )
  }
}
