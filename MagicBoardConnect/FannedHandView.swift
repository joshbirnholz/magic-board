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
  
  @State private var draggedCard: CardInstance?
  
  private struct DropViewDelegate: DropDelegate {
    let item: CardInstance
    @Binding var draggedItem: CardInstance?
    let items: [CardInstance]
    
    let moveItemFromIndexToIndex: (Int, Int) -> Void
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
      return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
      draggedItem = nil
      return true
    }
    
    func dropExited(info: DropInfo) {
    }
    
    func dropEntered(info: DropInfo) {
      update()
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
      HStack(spacing: spacing(totalWidth: proxy.size.width)) {
        ForEach(Array([hand, commandZone].joined().enumerated()), id: \.element.uuid) { (index, card) in
          if !commandZone.isEmpty && !hand.isEmpty && index == hand.count {
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
            totalWidth: proxy.size.width
          ).drag(card: isDragEnabled ? card : nil)
          .applyIf(!isDragEnabled) {
            $0.drag(card: card.pile?.location != .hand ? nil : card, onDrag: {
              self.onTapGesture?(card)
              self.draggedCard = card
            }, preview: {
              EmptyView()
            }).onDrop(of: [CardInstance.typeIdentifier], delegate: DropViewDelegate(
              item: card,
              draggedItem: $draggedCard,
              items: hand,
              moveItemFromIndexToIndex: moveItemFromIndexToIndex
            ))
          }
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .animation(.default, value: hand)
      .animation(.default, value: commandZone)
      .animation(.default, value: selectedCard)
  }
  
  private var displayedCount: Int {
    var result = hand.count + commandZone.count
    if !commandZone.isEmpty && !hand.isEmpty {
      result += 1
    }
    return result
  }
  
  private func spacing(totalWidth: CGFloat) -> CGFloat {
    var spacing = -totalWidth / CGFloat(displayedCount)
    if displayedCount > 3 {
      spacing *= 0.2
    }
    return spacing
  }
}

struct FannedView: View {
  let instance: CardInstance
  let onTapGesture: ((CardInstance) -> Void)?
  let isVisible: Bool
  let isSelected: Bool
  let index: Int
  let totalCards: Int
  let totalWidth: CGFloat
  
  let highlightColor = Color(#colorLiteral(red: 0.0594169274, green: 0.7364455462, blue: 0.7434161305, alpha: 1))
  let commanderHighlightColor = Color(#colorLiteral(red: 0.8982658702, green: 0.850980401, blue: 0.5490196347, alpha: 1))
  
  // The imaginary radius of the circle whose arc the cards follow.
  // Larger = flatter arc; smaller = more dramatic curve.
  private let gripRadius: CGFloat = 700
  
  // Total angular spread of the hand in degrees.
  // Scales up slightly for larger hands so cards don't bunch up.
  private var totalArcDegrees: CGFloat {
    let base: CGFloat = 30
    let perCard: CGFloat = 3
    return min(base + CGFloat(max(totalCards - 5, 0)) * perCard, 55)
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
    var offset = gripRadius * (1 - cos(angleRad))
    
    if isSelected {
      offset -= 20
    }
    
    return offset
  }
  
  var body: some View {
    HandCardView(isVisible: isVisible, card: instance.representation.card)
      .cornerRadius(5)
      .onTapGesture {
        onTapGesture?(instance)
      }
      .overlay {
        if isSelected && instance.pile?.location == .hand {
          RoundedRectangle(cornerRadius: 5)
            .stroke(highlightColor, lineWidth: 3)
        }
      }
      .background {
        if instance.pile?.location == .command {
          RoundedRectangle(cornerRadius: 5)
            .shadow(color: commanderHighlightColor, radius: 3)
            .shadow(color: commanderHighlightColor, radius: 3)
            .shadow(color: commanderHighlightColor, radius: 3)
        }
      }
      .scaledToFit()
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
