//
//  JumpStartView.swift
//  Magic Board
//
//  Created by Josh Birnholz on 9/3/22.
//  Copyright © 2022 Josh Birnholz. All rights reserved.
//

import SwiftUI
import CardService

struct JumpStartView: View {
	let set: String
	let previous: [RemoteCard]?
	@State var current: [[RemoteCard]]?
	let playerIdentifier: Player.Identifier
	let dismiss: () -> ()
	
    @ViewBuilder private func makeView(_ pack: [RemoteCard]) -> some View {
        if let first = pack.first {
            let name = first.packetName ?? first.name
            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.headline)
                Text(OfflineGameLibrary.shared.packetColorNames(kind: "JumpStart", set: set, name: name))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

	var body: some View {
		List {
			if let current = current {
				Section(header: Text("Choose One")) {
					ForEach(current, id: \.self) { pack in
						if previous != nil {
							Button {
								finalize(with: pack)
							} label: {
								makeView(pack)
							}
						} else {
							NavigationLink {
								JumpStartView(set: set, previous: pack, playerIdentifier: playerIdentifier, dismiss: dismiss)
									.navigationTitle("Choose Second")
							} label: {
								makeView(pack)
							}
						}
					}
				}
			} else {
				ProgressView()
			}
		}
		.listStyle(.insetGrouped)
		.onAppear {
			Task {
                guard current == nil else { return }
                let names = OfflineGameLibrary.shared.jumpStartOffers(set: set, excluding: previous?.first?.packetName)
                if !names.isEmpty {
                    var packs: [[RemoteCard]] = []
                    for name in names { packs.append(try await RemoteCard.loadPack(set: set, packetName: name)) }
                    self.current = packs
                    return
                }
				async let pack0 = try RemoteCard.loadPack(set: set)
				async let pack1 = try RemoteCard.loadPack(set: set)
				async let pack2 = try RemoteCard.loadPack(set: set)
        
        let packs = try await [pack0, pack1, pack2]
				
				DispatchQueue.main.async {
					self.current = packs
				}
			}
		}
	}
	
	func finalize(with pack: [RemoteCard]) {
		var cards = pack
		if let previous = previous {
			cards.append(contentsOf: previous)
		}
		
		cards.removeAll { card in
			card.set.count > 3 && card.set.hasPrefix("f")
		}
		
		let string = cards.map {
			"1 \($0.name) (\($0.set)) \($0.collectorNumber)"
		}.joined(separator: "\n")
		
		let command = Command.loadDeck(Command.LoadDeckParameters(playerIdentifier: playerIdentifier, deckList: string, source: .decklist, handSmoothing: true))
		AppDelegate.shared.sendCommand(command)
		dismiss()
	}
}


