//
//  WebServer.swift
//  Magic Board
//
//  Created by Josh Birnholz on 10/28/23.
//  Copyright © 2023 Josh Birnholz. All rights reserved.
//

import Foundation
import Vapor
import Leaf
import UIKit
import CardView
import SDWebImage

class WebServer {
  var app: Application
  let port: Int
  
  init(port: Int) {
    self.port = port
    app = Application(.development)
    configure(app)
  }
  
  private func configure(_ app: Application) {
    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = port

    app.views.use(.leaf)
    app.leaf.cache.isEnabled = app.environment.isRelease
    app.leaf.configuration.rootDirectory = Bundle.main.bundlePath
    app.routes.defaultMaxBodySize = "50MB"
  }
  
  func start() {
    Task(priority: .background) {
      do {
        try app.register(collection: WebRouteCollection())
        try app.start()
      } catch {
        fatalError(error.localizedDescription)
      }
    }
  }
  
  var handleCommand: ((Command) -> Void)?
  
}

// MARK: Routes

fileprivate struct CardInstanceResponse: Codable, Content {
  
  let id: UUID
  let title: String?
  let owner: Player.Identifier?
  let pileLocation: Pile.Location?
  let indexInPile: Int?
  let frontURL: URL?
  let backURL: URL?
  let frontMiniURL: URL?
  let backMiniURL: URL?
  
  init(cardInstance: CardInstance) {
    self.id = cardInstance.uuid
    self.title = cardInstance.representation.name
    self.owner = cardInstance.pile?.playerIdentifier
    self.pileLocation = cardInstance.pile?.location
    self.indexInPile = cardInstance.indexInPile
    
    guard let ip = Self.getIPAddress() else {
      self.frontURL = nil
      self.backURL = nil
      self.frontMiniURL = nil
      self.backMiniURL = nil
      return
    }
    self.frontURL = URL(string: "http://\(ip):8080/image/\(cardInstance.uuid)")
    self.backURL = URL(string: "http://\(ip):8080/image/\(cardInstance.uuid)?face=back")
    self.frontMiniURL = URL(string: "http://\(ip):8080/minicard/\(cardInstance.uuid)")
    self.backMiniURL = URL(string: "http://\(ip):8080/minicard/\(cardInstance.uuid)?face=back")
  }
  
  private static func getIPAddress() -> String? {
    
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
    if getifaddrs(&ifaddr) == 0 {
      
      var ptr = ifaddr
      while ptr != nil {
        defer { ptr = ptr?.pointee.ifa_next } // memory has been renamed to pointee in swift 3 so changed memory to pointee
        
        let interface = ptr?.pointee
        let addrFamily = interface?.ifa_addr.pointee.sa_family
        if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
          let name: String = String(cString: (interface?.ifa_name)!)
          
          if name == "en0" {  // String.fromCString() is deprecated in Swift 3. So use the following code inorder to get the exact IP Address.
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface?.ifa_addr, socklen_t((interface?.ifa_addr.pointee.sa_len)!), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
            address = String(cString: hostname)
          }
          
        }
      }
      freeifaddrs(ifaddr)
    }
    
    return address
  }

}

fileprivate struct WebRouteCollection: RouteCollection {
  func boot(routes: Vapor.RoutesBuilder) throws {
    routes.get("gamestate", use: gamestateHandler(_:))
    routes.get("battlefield", use: battlefieldHandler(_:))
    routes.get("pile", ":pile", ":player", use: pileHandler(_:))
    routes.get("pileIDs", ":pile", ":player", use: pileUUIDsHandler(_:))
    routes.get("card", ":id", use: cardHandler(_:))
    routes.get("minicard", ":id", use: miniCardHandler(_:))
    routes.get("image", ":id", use: imageHandler(_:))
    routes.post("command", use: commandHandler(_:))
    routes.post("playcard", ":id", use: playCardHandler(_:))
  }
  
  func commandHandler(_ req: Request) async throws -> Response {
    
    let command = try req.content.decode(Command.self)
    
    await MainActor.run {
      AppDelegate.shared.webServer.handleCommand?(command)
    }
    
    return .init(status: .ok)
  }
  
  func playCardHandler(_ req: Request) async throws -> Response {
    do {
      let id = try req.parameters.require("id", as: UUID.self)
    
    
    let mode: Command.PlayCardParameters.Mode = req.query["mode"] ?? .default
    let faceIndex: Int? = req.query["faceIndex"]
    let increaseTax: Bool = req.query["increaseTax"] ?? false
    let tapped: Bool = req.query["tapped"] ?? false
    
    print(id, mode, faceIndex, increaseTax, tapped)
    
    await MainActor.run {
      AppDelegate.shared.webServer.handleCommand?(.moveCardsToBattlefield([
        .init(cardInstanceID: id, faceIndex: faceIndex, mode: mode, increaseTax: increaseTax, tapped: tapped)
      ]))
    }
    
    return .init(status: .ok)
    } catch {
      print(error)
      throw error
    }
  }
  
  func gamestateHandler(_ req: Request) async throws -> GameState {
    return GameState.current
  }
  
  func battlefieldHandler(_ req: Request) async throws -> [CardInstance] {
    return GameState.current.battlefield.value.contents
  }
  
  func pileHandler(_ req: Request) async throws -> [CardInstanceResponse] {
    let identifier = try req.parameters.require("player", as: Player.Identifier.self)
    let location = try req.parameters.require("pile", as: Pile.Location.self)
    
    return GameState.current[player: identifier][location].cards.value.contents.map(CardInstanceResponse.init(cardInstance:))
  }
  
  func pileUUIDsHandler(_ req: Request) async throws -> [UUID] {
    let identifier = try req.parameters.require("player", as: Player.Identifier.self)
    let location = try req.parameters.require("pile", as: Pile.Location.self)
    
    let cards = GameState.current[player: identifier][location].cards.value
    return cards.map(\.uuid)
  }
  
  func cardHandler(_ req: Request) async throws -> CardInstance {
    let id = try req.parameters.require("id", as: UUID.self)
    guard let instance = GameState.current.cardInstance(with: id) else {
      throw WebServerError.invalidId
    }
    
    return instance
  }
  
  func miniCardHandler(_ req: Request) async throws -> Response {
    let id = try req.parameters.require("id", as: UUID.self)
    let isBack = req.query["face"] == "back"
    
    guard let instance = GameState.current.cardInstance(with: id) else {
      throw WebServerError.invalidId
    }
    
    let card = instance.representation.card
    
    let availableRepresentations: [CardRepresentation] = if let faces = card.cardFaces, faces.count > 1 {
      faces.map {
        .alternateFace(card, $0)
      }
    } else {
      [.card(card)]
    }
    
    guard let representation = isBack ? availableRepresentations.last : availableRepresentations.first else {
      throw Abort(.internalServerError)
    }
    
    let art = representation.image(type: .art)
    
    guard let image = await self.image(for: representation, isCommander: instance.isCommander.value, art: art), let data = image.pngData() else {
      throw WebServerError.imageCreationError
    }
    
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "image/png")
    return Response.init(status: .ok, headers: headers, body: .init(data: data))
  }
  
  func imageHandler(_ req: Request) async throws -> Response {
    let id = try req.parameters.require("id", as: UUID.self)
    let isBack = req.query["face"] == "back"
    
    guard let instance = GameState.current.cardInstance(with: id) else {
      throw WebServerError.invalidId
    }
    
    let card = instance.representation.card
    
    let availableRepresentations: [CardRepresentation] = if let faces = card.cardFaces, faces.count > 1 {
      faces.map {
        .alternateFace(card, $0)
      }
    } else {
      [.card(card)]
    }
    
    guard let representation = isBack ? availableRepresentations.last : availableRepresentations.first else {
      throw Abort(.internalServerError)
    }
    
    guard let url = representation.card.imageURL(type: .normal) else {
      throw Abort(.internalServerError)
    }
    
    if SDImageCache.shared.diskImageDataExists(withKey: url.absoluteString), let data = SDImageCache.shared.diskImageData(forKey: url.absoluteString) {
      var headers = HTTPHeaders()
      headers.add(name: .contentType, value: "image/jpg")
      return Response.init(status: .ok, headers: headers, body: .init(data: data))
    } else {
      return req.redirect(to: url.absoluteString)
    }
  }
  
  @MainActor
  private func image(for representation: CardRepresentation, isCommander: Bool, art: UIImage?, size: CGSize = CGSize(width: 480, height: 420)) -> UIImage? {
    let scale = UIScreen.main.scale
    let size = CGSize(width: size.width/scale, height: size.height/scale)
    
    var isAltFace: Bool {
      if case .alternateFace(let card, let face) = representation, let index = card.cardFaces?.firstIndex(of: face) {
        return index >= 1
      }
  //      let isAltFace: Bool = {
  //        if card.layout == "meld" {
  //          return card.card.allParts?.contains(where: {
  //            $0.component == .meldResult && $0.scryfallID == card.card.scryfallID
  //          }) == true
  //        }
  //
  //        return (faceIndex ?? 0) >= 1
  //      }()
      
      if case .card(let mTGCard) = representation, mTGCard.layout == "meld" {
        return mTGCard.allParts?.contains(where: {
          $0.component == .meldResult && $0.scryfallID == representation.card.scryfallID
        }) == true
      }
      
      return false
    }
    
    var properties = MTGCardView.properties(
      includedIcons: .permanent,
      name: representation.name,
      manaCost: representation.manaCost,
      typeLine: representation.typeLine,
      oracleText: representation.oracleText,
      colorInitials: representation.colors?.compactMap { $0.rawValue },
      fullArt: representation.fullArt,
      borderColor: representation.borderColor.rawValue,
      frame: representation.card.frame,
      frameEffects: representation.frameEffects,
      power: representation.power,
      toughness: representation.toughness,
      loyalty: representation.loyalty,
      layout: representation.layout,
      flavorName: representation.flavorName,
      isAltFace: isAltFace,
      keywords: representation.keywords,
      securityStamp: representation.card.securityStamp,
      isCommander: isCommander
    )
    
    properties.art = art
    
    let frame = CGRect(origin: .zero, size: size)
    let cardView = MTGCardView(frame: frame)
    cardView.backgroundColor = .clear
    cardView.properties = properties
    cardView.layoutIfNeeded()
    
    UIGraphicsBeginImageContextWithOptions(cardView.bounds.size, false, 2)
    defer { UIGraphicsEndImageContext() }
    guard let context = UIGraphicsGetCurrentContext() else { return nil }
    cardView.layer.render(in: context)
    return UIGraphicsGetImageFromCurrentImageContext()
  }
  
  
}

extension GameState: Content {
  
}

extension CardInstance: Content {
  
}

extension UUID: Content {
  
}

extension Player.Identifier: LosslessStringConvertible {
  init?(_ description: String) {
    self.init(rawValue: description.lowercased())
  }
  
  var description: String {
    return rawValue
  }
}

extension Pile.Location: LosslessStringConvertible {
  init?(_ description: String) {
    self.init(rawValue: description.lowercased().capitalized)
  }
  
  var description: String {
    return rawValue
  }
}

enum WebServerError: Error {
  case invalidId
  case imageCreationError
}
