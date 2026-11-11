//
//  CommandZoneViewController.swift
//  Magic Board
//
//  Created by Josh Birnholz on 10/7/23.
//  Copyright © 2023 Josh Birnholz. All rights reserved.
//

import UIKit
import RxSwift
import SwiftUI
import RxRelay
import CardView
import CardService

private struct CardView: UIViewRepresentable {
  typealias UIViewType = MTGCardView
  
  let card: CardRepresentation
  
  init(card: CardRepresentation) {
    self.card = card
    updateArt()
  }
  
  private let cardView = MTGCardView()
  
  private static func properties(for card: CardInstance) -> MTGCardView.CardProperties {
    return MTGCardView.properties(
      includedIcons: .all,
      name: card.name,
      manaCost: card.manaCost,
      typeLine: card.typeLine,
      oracleText: card.oracleText,
      colors: card.colors?.map { $0.rawValue },
      fullArt: card.fullArt,
      borderColor: card.borderColor.rawValue,
      frameEffects: card.frameEffects,
      power: card.power,
      toughness: card.toughness,
      loyalty: card.loyalty,
      layout: card.layout,
      flavorName: card.flavorName,
      isAltFace: false,
      keywords: card.keywords,
      securityStamp: card.card.securityStamp,
      isCommander: isCommander
    )
  }
  
  func makeUIView(context: Context) -> MTGCardView {
    cardView.backgroundColor = .clear
    cardView.properties = Self.properties(for: card)
    cardView.layoutIfNeeded()
    
    return cardView
  }
  
  func updateUIView(_ uiView: MTGCardView, context: Context) {
    uiView.properties = Self.properties(for: card)
  }
  
  private func updateArt() {
    DispatchQueue.global(qos: .userInteractive).async {
      let image = card.image(type: .art)
      
      DispatchQueue.main.async {
        guard let image = image, card == self.card else { return }
        
        UIView.transition(
          with: self.cardView,
          duration: 0.2,
          options: .transitionCrossDissolve,
          animations: {
            cardView.properties.art = image
          },
          completion: nil)
      }
    }
  }
}

struct CommandZoneView: View {
  
  @ObservedObject var cards: ObservableBridge<OrderedSet<CardInstance>>
  
  var body: some View {
    VStack {
      ForEach(cards.value, id: \.uuid) { card in
        CardView(card: card.representation)
//          .background(.blue)
          .drag(card: card)
      }
    }.padding()
//    .frame(width: 150, height: 100)
  }
}

class CommandZoneViewController: UIHostingController<CommandZoneView> {
  
  private let bag = DisposeBag()
  
  var commandZone: Pile {
    return player.commandZone
  }
  
  var player: Player! {
    didSet {
      bindHandCards()
    }
  }
  
  func bindHandCards() {
    let bridge = ObservableBridge(commandZone.cards)
    rootView = CommandZoneView(cards: bridge)
    view.backgroundColor = .clear
    
    let dropInteraction = UIDropInteraction(delegate: self)
    view.addInteraction(dropInteraction)
  }
  
  @objc required dynamic init?(coder aDecoder: NSCoder) {
    let handView = CommandZoneView(cards: ObservableBridge(BehaviorRelay(value: [])))
    super.init(coder: aDecoder, rootView: handView)
  }
}

extension CommandZoneViewController: UIDropInteractionDelegate {
  
  func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
//    guard let context = session.localDragSession?.localContext as? HandViewController, context == self else { return false }
    return session.canLoadObjects(ofClass: CardInstance.self)
  }
  
  func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
    let cardInstances = session.items.compactMap { $0.cardInstance }
    let destinationPile = commandZone
    let allSourcesAndDestinationPilesAreEqual = cardInstances.allSatisfy({ (cardInstance) -> Bool in
      return cardInstance.pile == destinationPile
    })
    guard !allSourcesAndDestinationPilesAreEqual else {
      return UIDropProposal(operation: .cancel)
    }
    
    return UIDropProposal(operation: .move)
  }
  
  func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
    let destinationPile = commandZone

    let dropItems = session.items
      .sorted { (first, second) -> Bool in
        if let firstIndex = (first.cardInstance)?.indexInPile, let secondIndex = (second.cardInstance)?.indexInPile {
          return firstIndex > secondIndex
        }

        return false
    }

    for dropItem in dropItems {
      guard let cardInstance = dropItem.cardInstance else { continue }

      if cardInstance.pile == commandZone {
        print("Moving from same")
        
        commandZone.cards.mutate { cards in
          if let card = cards.remove(cardInstance) {
            cards.append(card)
          }
        }
        
        try? GameState.current.save()
      } else {
        GameState.current.move(cardInstances: [cardInstance], to: destinationPile)
      }
    }
  }
  
}
