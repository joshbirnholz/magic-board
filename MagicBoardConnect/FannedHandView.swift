//
//  FannedHandView.swift
//  MagicBoardConnect
//
//  Created by Josh Birnholz on 9/12/23.
//  Copyright © 2023 Josh Birnholz. All rights reserved.
//

import SwiftUI
import CardService

struct FannedCardHandView: View {
  
  let hand: [CardInstance]
  let commandZone: [CardInstance]
  let onTapGesture: ((CardInstance) -> Void)?
  let isVisible: Bool
  let selectedCard: CardInstance?
  let isDragEnabled: Bool
  let moveItemFromIndexToIndex: (Int, Int) -> Void
  var layoutSize: CGSize? = nil
  var onExternalDrop: (([NSItemProvider]) -> Void)? = nil
  
  @State private var draggedCard: CardInstance?
  
  private struct DropViewDelegate: DropDelegate {
    let item: CardInstance
    @Binding var draggedItem: CardInstance?
    let items: [CardInstance]
    
    let moveItemFromIndexToIndex: (Int, Int) -> Void
    let onExternalDrop: (([NSItemProvider]) -> Void)?
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
      return DropProposal(operation: .move)
    }
    
    private func isReordering(_ info: DropInfo) -> Bool {
      guard let draggedItem, items.contains(draggedItem),
            let data = info.itemProviders(for: [CardInstance.typeIdentifier]).first?.teamData,
            let id = String(data: data, encoding: .utf8) else { return false }
      return id == draggedItem.uuid.uuidString
    }

    func validateDrop(info: DropInfo) -> Bool {
      if isReordering(info) { return true }
      return onExternalDrop != nil && info.hasItemsConforming(to: [CardInstance.typeIdentifier])
    }

    func performDrop(info: DropInfo) -> Bool {
      guard validateDrop(info: info) else { return false }
      if !isReordering(info) {
        onExternalDrop?(info.itemProviders(for: [CardInstance.typeIdentifier]))
      }
      draggedItem = nil
      return true
    }
    
    func dropExited(info: DropInfo) {
    }
    
    func dropEntered(info: DropInfo) {
      if isReordering(info) { update() }
    }
    
    private func update() {
      guard
        let draggedItem,
        let sourceIndex = items.firstIndex(of: draggedItem),
        var destinationIndex = items.firstIndex(of: item),
        sourceIndex != destinationIndex
      else { return }
      
      if destinationIndex > sourceIndex {
        destinationIndex += 1
      }
      
      moveItemFromIndexToIndex(sourceIndex, destinationIndex)
    }
  }
  
  var body: some View {
    GeometryReader { proxy in
      let size = layoutSize ?? proxy.size
      fan(size, manaOnly: false)
        .overlay {
          fan(size, manaOnly: true)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .animation(.default, value: hand)
      .animation(.default, value: commandZone)
      .animation(.default, value: selectedCard)
  }

  // Draw floating costs after every card, so neighboring cards cannot cover them.
  private func fan(_ size: CGSize, manaOnly: Bool) -> some View {
      HStack(spacing: spacing(totalWidth: fanWidth(size), cardWidth: phoneCardWidth(height: size.height))) {
        ForEach(Array([hand, commandZone].joined().enumerated()), id: \.element.uuid) { (index, card) in
          if !commandZone.isEmpty && !hand.isEmpty && index == hand.count && !AppDelegate.shared.usesPhoneSession {
            Image("mtg-card-back-png-1")
              .resizable()
              .scaledToFit()
              .frame(maxWidth: .infinity)
              .opacity(0)
          }
          
          FannedView(
            instance: card,
            onTapGesture: onTapGesture,
            isVisible: card.pile?.location != .hand || isVisible,
            isSelected: selectedCard?.uuid == card.uuid,
            index: !commandZone.isEmpty && !hand.isEmpty && index == hand.count ? index + 1 : index,
            totalCards: displayedCount,
            totalWidth: size.width,
            cardHeight: size.height,
            manaOnly: manaOnly,
            visibleWidth: AppDelegate.shared.usesPhoneSession ? visibleWidth(size, isLast: index == hand.count + commandZone.count - 1 || (hasCommandGap && index == hand.count - 1)) : nil
          ).frame(width: AppDelegate.shared.usesPhoneSession ? phoneCardWidth(height: size.height) : nil)
          // Phone Play: the command zone sits off to the side, a real gap after the last hand card.
          .padding(.leading, AppDelegate.shared.usesPhoneSession && hasCommandGap && index == hand.count
                   ? max(0, commandGap(size) - spacing(totalWidth: fanWidth(size), cardWidth: phoneCardWidth(height: size.height))) : 0)
          .drag(card: !manaOnly && isDragEnabled && (isVisible || !AppDelegate.shared.usesPhoneSession) ? card : nil, onDrag: {
            if card.pile?.location == .hand && isVisible { draggedCard = card }
          })
          .applyIf(!manaOnly && !isDragEnabled && !AppDelegate.shared.usesPhoneSession) {
            $0.drag(card: card.pile?.location != .hand ? nil : card, onDrag: {
              self.onTapGesture?(card)
              self.draggedCard = card
            }, preview: {
              EmptyView()
            })
          }
          // Phone Play: dragging a hand card must not "tap" it (that opened the card sheet mid-drag)
          // and must show the card being dragged (the classic path uses an empty preview).
          .applyIf(!manaOnly && !isDragEnabled && AppDelegate.shared.usesPhoneSession && isVisible) {
            $0.drag(card: card.pile?.location != .hand ? nil : card, onDrag: {
              self.draggedCard = card
            })
          }
          .applyIf(!manaOnly) { $0.onDrop(of: [CardInstance.typeIdentifier], delegate: DropViewDelegate(
              item: card,
              draggedItem: $draggedCard,
              items: hand,
              moveItemFromIndexToIndex: moveItemFromIndexToIndex,
              onExternalDrop: isVisible ? onExternalDrop : nil
            )) }
        }
      }.frame(width: AppDelegate.shared.usesPhoneSession ? fanWidth(size) : nil)
       .frame(width: AppDelegate.shared.usesPhoneSession ? size.width : nil)

  }

  private var displayedCount: Int {
    var result = hand.count + commandZone.count
    if !commandZone.isEmpty && !hand.isEmpty {
      result += 1
    }
    return result
  }
  
  /// Phone Play: the cards' row width, inset by the end cards' rotation overhang so every
  /// rotated card stays inside the hand's area (and on screen).
  private func fanWidth(_ size: CGSize) -> CGFloat {
    guard AppDelegate.shared.usesPhoneSession else { return size.width }
    let overhang = fannedHandRotationOverhang(cardWidth: phoneCardWidth(height: size.height), totalCards: displayedCount, isVisible: isVisible)
    return max(phoneCardWidth(height: size.height), size.width - 2 * overhang)
  }

  /// Width of a card's uncovered strip: later cards overlap the right side of earlier ones.
  private func visibleWidth(_ size: CGSize, isLast: Bool) -> CGFloat {
    let cardWidth = phoneCardWidth(height: size.height)
    let step = spacing(totalWidth: fanWidth(size), cardWidth: cardWidth)
    return isLast || step >= 0 ? cardWidth : max(cardWidth * 0.2, cardWidth + step)
  }

  private func phoneCardWidth(height: CGFloat) -> CGFloat {
    max(32, height * 63 / 88)
  }

  private var hasCommandGap: Bool { !hand.isEmpty && !commandZone.isEmpty }
  private func commandGap(_ size: CGSize) -> CGFloat { phoneCardWidth(height: size.height) * 0.3 }

  private func spacing(totalWidth: CGFloat, cardWidth: CGFloat) -> CGFloat {
    if AppDelegate.shared.usesPhoneSession {
      if !isVisible { return -cardWidth * 0.65 }
      if hasCommandGap {
        // n cards plus a leading pad of (gap - spacing) on the first commander must fill the width.
        let n = CGFloat(hand.count + commandZone.count)
        return min(8, (totalWidth - n * cardWidth - cardWidth * 0.3) / max(1, n - 2))
      }
      return min(8, (totalWidth - CGFloat(displayedCount) * cardWidth) / CGFloat(max(1, displayedCount - 1)))
    }
    var spacing = -totalWidth / CGFloat(displayedCount)
    if displayedCount > 3 {
      spacing *= 0.2
    }
    return spacing
  }
}

/// Total angular spread of a fanned hand in degrees; scales up for larger hands.
func fannedHandArcDegrees(totalCards: Int, isVisible: Bool) -> CGFloat {
  if AppDelegate.shared.usesPhoneSession && !isVisible { return 12 }
  return min(30 + CGFloat(max(totalCards - 5, 0)) * 3, 55)
}

/// Phone Play: how far the most-rotated card's bounding box extends past its unrotated
/// width on each side, so the fan can be inset to keep every card on screen.
func fannedHandRotationOverhang(cardWidth: CGFloat, totalCards: Int, isVisible: Bool) -> CGFloat {
  guard totalCards > 1 else { return 0 }
  let theta = fannedHandArcDegrees(totalCards: totalCards, isVisible: isVisible) / 2 * .pi / 180
  let height = cardWidth * 88 / 63
  return max(0, (cardWidth * cos(theta) + height * sin(theta) - cardWidth) / 2)
}

struct FannedView: View {
  let instance: CardInstance
  let onTapGesture: ((CardInstance) -> Void)?
  let isVisible: Bool
  let isSelected: Bool
  let index: Int
  let totalCards: Int
  let totalWidth: CGFloat
  let cardHeight: CGFloat
  let manaOnly: Bool
  /// Phone Play: uncovered width of this card, so its cost sits over the part you can see.
  var visibleWidth: CGFloat? = nil
  
  let highlightColor = Color(#colorLiteral(red: 0.0594169274, green: 0.7364455462, blue: 0.7434161305, alpha: 1))
  let commanderHighlightColor = Color(#colorLiteral(red: 0.8982658702, green: 0.850980401, blue: 0.5490196347, alpha: 1))
  
  // The imaginary radius of the circle whose arc the cards follow.
  // Larger = flatter arc; smaller = more dramatic curve.
  private let gripRadius: CGFloat = 700
  
  // Total angular spread of the hand in degrees.
  // Scales up slightly for larger hands so cards don't bunch up.
  private var totalArcDegrees: CGFloat {
    fannedHandArcDegrees(totalCards: totalCards, isVisible: isVisible)
  }
  
  // Normalized position of this card across the arc: -0.5 ... +0.5
  private var normalizedPosition: CGFloat {
    guard totalCards > 1 else { return 0 }
    return CGFloat(index) / CGFloat(totalCards - 1) - 0.5
  }
  
  // Angle on the arc for this card, in degrees.
  // Negative = left of center, positive = right of center.
  var rotationAngle: CGFloat {
    normalizedPosition * totalArcDegrees
  }
  
  // Vertical offset derived from the same arc geometry.
  // Cards at the edges of the arc are higher up on the circle,
  // so their y-position is greater (they drop down from center).
  var yOffset: CGFloat {
    let angleRad = rotationAngle * .pi / 180
    // How far up the circle this card sits relative to the bottom of the arc.
    // cos(0) = 1 (center, lowest point), cos(angle) < 1 (edges, higher on circle)
    // Phone Play: the end cards drop at most 12% of a card height, whatever the card size,
    // so they stay on screen (a fixed 700 pt radius dropped small cards by a whole card).
    let maxAngle = totalArcDegrees / 2 * .pi / 180
    let radius = AppDelegate.shared.usesPhoneSession && maxAngle > 0
      ? cardHeight * 0.12 / max(0.0001, 1 - cos(maxAngle)) : gripRadius
    var offset = radius * (1 - cos(angleRad))
    
    if isSelected {
      offset -= 20
    }
    
    return offset
  }
  
  private var cornerRadius: CGFloat {
    AppDelegate.shared.usesPhoneSession ? cardHeight * 63 / 88 * 0.045 : 5
  }

  /// Mana cost, with commander tax added like Board Connect ("{tax}+cost") for commanders in the command zone.
  private var displayedCost: String? {
    let cost = instance.representation.manaCost
    guard instance.isCommander.value, instance.pile?.location == .command else { return cost }
    let tax = instance.commanderCasts.value * 2
    guard tax > 0 else { return cost }
    return "{\(tax)}+" + (cost ?? "")
  }

  private var manaSymbolSize: CGFloat {
    AppDelegate.shared.usesPhoneSession
      ? min(22, max(9, cardHeight * 0.075))
      : min(28, max(11, cardHeight * 0.105))
  }

  var body: some View {
    Group {
      if manaOnly { Color.clear }
      else { HandCardView(isVisible: isVisible, card: instance.representation.card) }
    }
      .aspectRatio(63 / 88, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(isVisible ? instance.representation.name ?? "Card" : "Face-down card")
      .accessibilityIdentifier(isVisible && !manaOnly && AppDelegate.shared.usesPhoneSession ? "phone-hand-\(index)" : "")
      .accessibilityHidden(manaOnly)
      .onTapGesture {
        onTapGesture?(instance)
      }
      .overlay {
        if !manaOnly && isSelected && instance.pile?.location == .hand {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(highlightColor, lineWidth: 3)
        }
      }
      .background {
        if !manaOnly && instance.pile?.location == .command {
          // Yellow commander glow, scaled to the card so it reads on large phone cards too.
          let glow: CGFloat = AppDelegate.shared.usesPhoneSession ? max(3, cardHeight * 0.03) : 3
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .shadow(color: commanderHighlightColor, radius: glow)
            .shadow(color: commanderHighlightColor, radius: glow)
            .shadow(color: commanderHighlightColor, radius: glow)
        }
      }
      .overlay(alignment: .topTrailing) {
        if manaOnly && isVisible, let cost = displayedCost, !cost.isEmpty {
          if visibleWidth != nil {
            // Arena anchors costs to the actual top-right corner, with a dark backing
            // and a small gap above the card. The separate cost pass keeps them visible.
            addSymbols(string: cost, symbolLength: manaSymbolSize)
              .font(.system(size: manaSymbolSize))
              .fixedSize()
              .padding(.horizontal, 3)
              .padding(.vertical, 2)
              .background(Color.black.opacity(0.85), in: Capsule())
              .offset(x: -cardHeight * 0.025, y: -manaSymbolSize - 5)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          } else {
            addSymbols(string: cost, symbolLength: manaSymbolSize)
              .fixedSize()
              .shadow(color: .black, radius: 1, y: 1)
              .offset(y: -manaSymbolSize - 3)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
      }
      .frame(maxWidth: .infinity)
      .zIndex(isSelected ? 1 : 0)
      .rotationEffect(.degrees(rotationAngle))
      .offset(y: yOffset)
  }
}

//private struct FannedHandViewPreview: View {
//  @State var count = 7
//  
//  var body: some View {
//    VStack(alignment: .center, spacing: 50) {
//      FannedCardHandView(count: count)
//        .background(Color(UIColor.systemFill))
//        .padding()
//      Stepper(value: $count, in: 0...Int.max) {
//        HStack {
//          Text(String(describing: count))
//          Button {
//            count = 7
//          } label: {
//            Text("(7)")
//          }
//        }
//      }
//    }
//  }
//}

//#Preview {
//  FannedHandViewPreview()
//}
