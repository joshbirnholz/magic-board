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

private struct LandCardFramesKey: PreferenceKey {
  static var defaultValue: [UUID: CGRect] = [:]
  static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

struct LandOrganizer: View {
  
  struct LandStack: View {
    let cardInstances: OrderedSet<CardInstance>
    let onLongPress: (CardInstance) -> Void
    let height: CGFloat
    let draggedCardID: UUID?
    var attachedCards: [CardInstance] = []
    
    private var showsCountTile: Bool {
      cardInstances.count > 3
    }
    
    @ViewBuilder
    private func countTile(height: CGFloat) -> some View {
      Text("x\(cardInstances.count)")
        .font(.custom("Beleren2016-Bold", size: AppDelegate.shared.usesPhoneSession ? max(14, height * 0.22) : 22))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background {
          RoundedRectangle(cornerRadius: 4)
            .foregroundColor(.black.opacity(0.82))
        }

    }
    
    var body: some View {
      // The row supplies height. Measuring this stack to size its own overlap
      // feeds image intrinsic-size changes back into SwiftUI layout.
      HStack(spacing: -height * (showsCountTile ? 1.07 : 0.97)) {
        ForEach(Array((attachedCards + cardInstances.contents).enumerated()), id: \.element.uuid) { (_, card) in
          SwiftUICardView(card: card, isRotationEnabled: true)
            .frame(width: height * 480 / 420, height: height)
            .opacity(card.uuid == draggedCardID ? 0 : 1)
            .shadow(radius: 5)
        }
      }
      .padding(.leading, showsCountTile ? 10 : 0)
      .frame(height: height)
      .overlay {
        if showsCountTile {
          countTile(height: height).position(x: 24, y: max(12, min(40, height - 12)))
        }
      }
    }
  }
  

  @GestureState private var draggedCardID: UUID? = nil
  @ObservedObject var cardInstances: ObservableBridge<OrderedSet<CardInstance>>
  @ObservedObject var tappedIDs: ObservableBridge<[UUID]>
  let onLongPress: (CardInstance) -> Void
  var isOpponentRow = false
  var showsBackground = true
  var onDragChanged: ((CardInstance, CGPoint, CGSize) -> Void)?
  var onDragEnded: ((CardInstance, CGPoint) -> Void)?
  var onDragCancelled: (() -> Void)?
  var attachmentsByLand: [UUID: [CardInstance]] = [:]
  var onLandFramesChanged: (([UUID: CGRect]) -> Void)?
  
  private var stacks: [[CardInstance]] {
    // 1. Group by oracle ID (same card type stacks together)
    let groups: [UUID: [CardInstance]] = .init(
      grouping: cardInstances.value,
      by: { $0.representation.card.oracleID ?? $0.representation.card.scryfallID }
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
  
  @ViewBuilder private func landCards(height: CGFloat) -> some View {
    HStack(spacing: 6) {
      ForEach(stacks, id: \.first?.uuid) { stack in
        LandStack(cardInstances: OrderedSet(stack), onLongPress: onLongPress, height: max(1, height), draggedCardID: draggedCardID,
                  attachedCards: stack.flatMap { attachmentsByLand[$0.uuid] ?? [] })
          .background(GeometryReader { geometry in
            Color.clear.preference(key: LandCardFramesKey.self,
                                   value: stack.last.map { [$0.uuid: geometry.frame(in: .global)] } ?? [:])
          })
          .contentShape(Rectangle())
          .accessibilityElement(children: .combine)
          .accessibilityLabel("\(stack.first?.representation.name ?? "Land"), \(stack.count)\(stack.first?.isTapped.value == true ? ", tapped" : ", untapped")")
          // A hold opens the inspector only if the finger stays put; moving starts a drag instead.
          .simultaneousGesture(LongPressGesture(minimumDuration: 0.65, maximumDistance: 8).onEnded { _ in
            if let card = stack.last { onLongPress(card) }
          })
          .simultaneousGesture(DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($draggedCardID) { _, state, _ in state = stack.last?.uuid }
            .onChanged { value in if let card = stack.last { onDragChanged?(card, value.location, CGSize(width: max(1, height) * 480 / 420, height: max(1, height))) } }
            .onEnded { value in
              if let card = stack.last { onDragEnded?(card, value.location) }
            }, including: AppDelegate.shared.usesPhoneSession ? .all : .subviews)
          .simultaneousGesture(TapGesture().onEnded {
            guard !isOpponentRow else {
              if let card = stack.last { onLongPress(card) }
              return
            }
            stack.last?.isTapped.mutate {
              $0.toggle()
            }
            try? GameState.current.save()
          })
          .padding(.horizontal, 4)
      }
      Spacer()
    }
  }

  var body: some View {
    GeometryReader { proxy in
      landCards(height: proxy.size.height)
    }.padding(.vertical, 4)
      .padding(.horizontal, 4)
      .background {
        if showsBackground {
          RoundedRectangle(cornerRadius: 12)
            .foregroundColor(.white.opacity(0.05))
        }
      }
      .padding(.bottom, 8)
      .padding(.horizontal, 4)
      .onPreferenceChange(LandCardFramesKey.self) { onLandFramesChanged?($0) }
      .onChange(of: draggedCardID) { if $0 == nil { onDragCancelled?() } }
      .animation(.default, value: cardInstances.value)
      .animation(.easeInOut(duration: 0.2), value: tappedIDs.value)
  }
}

// MARK: - UIHostingController

class LandOrganizerViewController: UIHostingController<LandOrganizer> {
  
  var onLongPress: (CardInstance) -> Void = { _ in }
  var onDragChanged: ((CardInstance, CGPoint, CGSize) -> Void)?
  var onDragEnded: ((CardInstance, CGPoint) -> Void)?
  var onDragCancelled: (() -> Void)?
  
  var playerIdentifier: Player.Identifier = .a {
    didSet {
      bindPlayer()
    }
  }
  
  private var bag = DisposeBag()
  private var landCardFrames: [UUID: CGRect] = [:] { didSet { if landCardFrames != oldValue { onLandContentChanged?() } } }
  /// Window-coordinate frames of the land stacks currently drawn (Phone Play lays the battlefield beside them).
  public var landContentFrames: [CGRect] { Array(landCardFrames.values) }
  public var onLandContentChanged: (() -> Void)?
  func card(at windowPoint: CGPoint, excluding ids: Set<UUID>) -> CardInstance? {
    rootView.cardInstances.value.contents.reversed().first {
      !ids.contains($0.uuid) && landCardFrames[$0.uuid]?.contains(windowPoint) == true
    }
  }
  /// Window-coordinate frame of a drawn land, if visible.
  func landFrame(for id: UUID) -> CGRect? { landCardFrames[id] }
  func updateAttachments(_ attachments: [UUID: [CardInstance]]) {
    if rootView.attachmentsByLand != attachments { rootView.attachmentsByLand = attachments }
  }
  var isOpponentRow = false { didSet { bindPlayer() } }

  init(playerIdentifier: Player.Identifier, isOpponentRow: Bool) {
    self.playerIdentifier = playerIdentifier
    self.isOpponentRow = isOpponentRow
    super.init(rootView: LandOrganizer(cardInstances: .init(.init(value: [])), tappedIDs: .init(.init(value: [])), onLongPress: { _ in }))
    bindPlayer()
  }
  
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
    (AppDelegate.shared.usesPhoneSession ? cardInstance.controllerIdentifier.value : cardInstance.ownerIdentifier) == self.playerIdentifier &&
    cardInstance.representation.typeLine?.lowercased().contains("land") == true &&
    !cardInstance.isPowerToughnessVisible.value
  }
  
  func hideOrganizerBackground() {
    if rootView.showsBackground { rootView.showsBackground = false }
    view.backgroundColor = .clear
  }

  private func bindPlayer() {
    bag = DisposeBag()
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
      onLongPress: { [weak self] card in self?.onLongPress(card) },
      isOpponentRow: isOpponentRow,
      showsBackground: !AppDelegate.shared.usesPhoneSession,
      onDragChanged: { [weak self] card, point, size in self?.onDragChanged?(card, point, size) },
      onDragEnded: { [weak self] card, point in self?.onDragEnded?(card, point) },
      onDragCancelled: { [weak self] in self?.onDragCancelled?() },
      onLandFramesChanged: { [weak self] in self?.landCardFrames = $0 }
    )
  }
}
