//
//  LoadDeckView.swift
//  Magic Board
//
//  Created by Josh Birnholz on 9/3/22.
//  Copyright © 2022 Josh Birnholz. All rights reserved.
//

import CardService
import SwiftUI

struct JumpstartSet: Codable, Identifiable {
  let name: String
  let code: String
  
  var id: String {
    name
  }
}

struct LoadDeckView: View {
	let playerIdentifier: Player.Identifier
	let chooseListFile: () -> ()
	let dismiss: () -> ()
	
	struct RemoteDeck: Codable, Identifiable {
		let id = UUID()
		
		let url: URL
		let ids: [String]
		let front: URL
		let back: URL?
		let comment: String
		let ci: String
		let type: String?
	}
	
	@State private var remoteDecks: [RemoteDeck] = []
  @State private var jumpstartSets: [JumpstartSet] = []
	@State private var deckLink: String = ""
	
	var body: some View {
		List {
			Section {
				Button("Choose deck list file…") {
					chooseListFile()
				}
			}
			
			Section {
				TextField("Enter a deck link…", text: $deckLink, onCommit: {
					guard let url = URL(string: deckLink) else { return }
					
					let command = Command.loadDeck(Command.LoadDeckParameters(playerIdentifier: playerIdentifier, deckList: url.absoluteString, source: .remoteURL))
					AppDelegate.shared.transceiver.broadcast(command)
					dismiss()
				})
			}
			
			Section {
        ForEach(jumpstartSets) { set in
          NavigationLink {
            JumpStartView(set: set.code, previous: nil, playerIdentifier: playerIdentifier, dismiss: dismiss)
              .navigationTitle(set.name)
          } label: {
            Text(set.name)
          }
        }
        NavigationLink {
          JumpInView(playerIdentifier: playerIdentifier, dismiss: dismiss)
        } label: {
          Text("Jump In!")
        }
			}
			
			if !remoteDecks.isEmpty {
				NavigationLink {
					List(remoteDecks) { deck in
						Button {
							let command = Command.loadDeck(Command.LoadDeckParameters(playerIdentifier: playerIdentifier, deckList: deck.url.absoluteString, source: .remoteURL))
							AppDelegate.shared.transceiver.broadcast(command)
							dismiss()
						} label: {
							let scale: CGFloat = 2
							if #available(iOS 15.0, *) {
								HStack {
									SwiftUI.AsyncImage(url: deck.front) { image in
										image.resizable()
									} placeholder: {
										ProgressView()
									}
									.frame(width: 63*scale, height: 88*scale)
									.cornerRadius(6)
									
									if let back = deck.back {
										SwiftUI.AsyncImage(url: back) { image in
											image.resizable()
										} placeholder: {
											ProgressView()
										}
										.frame(width: 63*scale, height: 88*scale)
										.cornerRadius(6)
									}
								}
							} else {
								EmptyView()
							}
						}
					}.listStyle(.insetGrouped)
						.navigationTitle("Decks")
				} label: {
					Text("Choose a deck…")
				}
			}
      
      Section {
        NavigationLink {
          TextListEditor(playerIdentifier: playerIdentifier, dismiss: dismiss)
        } label: {
          Text("Enter text…")
        }

      }
		}
		.listStyle(.insetGrouped)
		.toolbar {
			ToolbarItem {
				Button("Cancel") {
					dismiss()
				}
			}
		}
		.task {
      await loadRemoteDecks()
    }.task {
      await loadJumpStartSets()
    }
	}
  
  private struct TextListEditor: View {
    let playerIdentifier: Player.Identifier
    
    let dismiss: () -> Void
    
    @State private var text = ""
    
    var body: some View {
      TextEditor(text: $text)
        .navigationTitle("Deck List")
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button {
              let command = Command.loadDeck(Command.LoadDeckParameters(playerIdentifier: playerIdentifier, deckList: text, source: .decklist))
              AppDelegate.shared.transceiver.broadcast(command)
              dismiss()
            } label: {
              Label("Done", systemImage: "checkmark")
            }
          }
          
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              if let text = UIPasteboard.general.string {
                self.text = text
              }
            } label: {
              Image(systemName: "document.on.clipboard").resizable()
            }
          }
        }
      
//      TextField("Enter text…", text: $deckLink, onCommit: {
//        guard let url = URL(string: deckLink) else { return }
//        
//        let command = Command.loadDeck(Command.LoadDeckParameters(playerIdentifier: playerIdentifier, deckList: url.absoluteString, source: .remoteURL))
//        AppDelegate.shared.transceiver.broadcast(command)
//        dismiss()
//      })
    }
  }
	
	private func loadRemoteDecks() async {
		do {
			let url = URL(string: "https://tts-magic-booster.fly.dev/decks")!
			let data = try await URLSession.shared.data(from: url).0
			let decoder = JSONDecoder()
			self.remoteDecks = try decoder.decode([RemoteDeck].self, from: data)
		} catch {
			print(error)
		}
	}
  
  private func loadJumpStartSets() async {
    do {
      let url = URL(string: "https://tts-magic-booster.fly.dev/jumpstartsets")!
      let data = try await URLSession.shared.data(from: url).0
      let decoder = JSONDecoder()
      self.jumpstartSets = try decoder.decode([JumpstartSet].self, from: data)
    } catch {
      print(error)
    }
  }
}
