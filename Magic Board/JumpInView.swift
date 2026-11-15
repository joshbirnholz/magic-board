//
//  JumpInView.swift
//  Magic Board
//
//  Created by Josh Birnholz on 10/1/25.
//  Copyright © 2025 Josh Birnholz. All rights reserved.
//

import SwiftUI
import CardService

private struct Packet: Decodable {
  let colors: [String]
  let name: String
  let setCode: String
}

private final class JumpInClient {
  static let baseURL = URL(string: "https://tts-magic-booster.fly.dev/")!
  
  static let decoder = JSONDecoder()
  
  func getSupportedSets() async throws -> [String] {
    let local = OfflineGameLibrary.shared.jumpInSetOptions
    if !local.isEmpty { return local }
    let url = Self.baseURL.appending(path: "jumpinsets")
    
    let data = try await URLSession.shared.data(from: url).0
    return try Self.decoder.decode([String].self, from: data)
  }
  
  func getPackets(setCode: String, pack1Name: String?) async throws -> [Packet] {
    let local = OfflineGameLibrary.shared.jumpInPackets(set: setCode, first: pack1Name)
    if !local.isEmpty { return local.map { name in Packet(colors: OfflineGameLibrary.shared.jumpInPacket(set: setCode, choice: name)?.colors ?? [], name: name, setCode: setCode) } }
    var url = Self.baseURL.appendingPathComponent("jumpin/\(setCode)")
    
    if let pack1Name {
      url = url.appending(queryItems: [.init(name: "pack1", value: pack1Name)])
    }
    
    let data = try await URLSession.shared.data(from: url).0
    return try Self.decoder.decode([Packet].self, from: data)
  }
  
  func getDeckList(pack1: String, pack2: String, set1: String, set2: String) async throws -> String {
    if set1 == set2, let list = OfflineGameLibrary.shared.jumpInDeck(set: set1, first: pack1, second: pack2) { return list }
    let url = Self.baseURL.appendingPathComponent("jumpin")
      .appending(queryItems: [
        .init(name: "pack1", value: pack1),
        .init(name: "pack2", value: pack2),
        .init(name: "set1", value: set1),
        .init(name: "set2", value: set2),
        .init(name: "format", value: "list")
      ])
    
    let data = try await URLSession.shared.data(from: url).0
    return String(data: data, encoding: .utf8)!
  }
  
}

struct JumpInView: View {
  
  let playerIdentifier: Player.Identifier
  let dismiss: () -> Void
  
  @State private var supportedSets: [String]? = OfflineGameLibrary.shared.jumpInSetOptions.isEmpty ? nil : OfflineGameLibrary.shared.jumpInSetOptions
  @State private var errorMessage: String?
  
  private let client = JumpInClient()
  
  var body: some View {
    Group {
      if let supportedSets {
        List(supportedSets, id: \.self) { setCode in
          NavigationLink {
            JumpInChoosePacketView(playerIdentifier: playerIdentifier, setCode: setCode, pack1Name: nil, dismiss: dismiss)
          } label: {
            Text(setCode == "ALL" ? "All Sets" : setCode)
          }
        }
      } else if let errorMessage { Text(errorMessage).padding() }
      else { ProgressView() }
    }.navigationTitle("Jump-In")
      .task {
        do {
          if supportedSets == nil { self.supportedSets = try await client.getSupportedSets() }
        } catch {
          errorMessage = error.localizedDescription
        }
      }
  }
}

private struct JumpInChoosePacketView: View {
  
  let playerIdentifier: Player.Identifier
  let setCode: String
  let pack1Name: String?
  let dismiss: () -> Void
  
  @State private var packets: [Packet]?
  @State private var errorMessage: String?
  
  private let client = JumpInClient()
  
  @ViewBuilder
  private func makePacketView(packet: Packet) -> some View {
    VStack(alignment: .leading) {
      Text(packet.name)
      Text(packet.colors.joined(separator: ", "))
    }.foregroundStyle(.primary)
  }
  
  var body: some View {
    Group {
      if let packets {
        List(packets, id: \.name) { packet in
          if let pack1Name {
            Button {
              Task {
                do { try await finalize(pack1: pack1Name, pack2: packet.name) } catch { errorMessage = error.localizedDescription }
              }
            } label: {
              makePacketView(packet: packet)
            }
          } else {
            NavigationLink {
              JumpInChoosePacketView(playerIdentifier: playerIdentifier, setCode: setCode, pack1Name: packet.name, dismiss: dismiss)
            } label: {
              makePacketView(packet: packet)
            }
          }
        }
      } else if let errorMessage { Text(errorMessage).padding() }
      else { ProgressView() }
    }.navigationTitle("Choose One")
      .task {
        do {
          if packets == nil { self.packets = try await client.getPackets(setCode: setCode, pack1Name: pack1Name) }
        } catch {
          errorMessage = error.localizedDescription
        }
      }
  }
  
  private func finalize(pack1: String, pack2: String) async throws {
    let list = try await client.getDeckList(pack1: pack1, pack2: pack2, set1: setCode, set2: setCode)
    
    await MainActor.run {
      let command = Command.loadDeck(Command.LoadDeckParameters(playerIdentifier: playerIdentifier, deckList: list, source: .decklist, handSmoothing: true))
      AppDelegate.shared.sendCommand(command)
      dismiss()
    }
  }
}
