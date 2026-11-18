//
//  JumpInSetGrid.swift
//  Magic Board
//
//  The Jump-In set picker: a grid of buttons showing each set's Scryfall
//  symbol and name. Set names and symbols are downloaded once and cached on
//  disk, so the grid still shows them offline after the first visit.
//

import CryptoKit
import SwiftDraw
import SwiftUI

/// Scryfall set names and SVG symbols, cached in memory and on disk.
actor ScryfallSetSymbolStore {
  static let shared = ScryfallSetSymbolStore()

  struct SetInfo: Codable, Sendable {
    let code: String
    let name: String
    let iconSvgUri: URL?
  }

  private struct SetListResponse: Decodable {
    let data: [SetInfo]
    let hasMore: Bool?
    let nextPage: URL?
  }

  private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("SetSymbols", isDirectory: true)
  private var sets: [String: SetInfo]?
  private var setsTask: Task<[String: SetInfo], Error>?
  private var symbols: [URL: SVG] = [:]
  private var symbolTasks: [URL: Task<SVG, Error>] = [:]

  private var setListFile: URL { directory.appendingPathComponent("sets.json") }

  /// The set's Scryfall entry, or nil when Scryfall has no such set.
  func info(for code: String) async throws -> SetInfo? {
    let key = code.lowercased()
    var all = try await allSets()
    if all[key] == nil, isCacheStale(maxAge: 60 * 60) {
      // A set newer than the cached list: refresh once (at most hourly).
      sets = nil
      all = try await allSets(forceRefresh: true)
    }
    return all[key]
  }

  func symbol(for code: String) async throws -> SVG? {
    guard let url = try await info(for: code)?.iconSvgUri else { return nil }
    return try await svg(at: url)
  }

  private func isCacheStale(maxAge: TimeInterval) -> Bool {
    let modified = (try? FileManager.default.attributesOfItem(atPath: setListFile.path)[.modificationDate]) as? Date
    return modified.map { Date().timeIntervalSince($0) > maxAge } ?? true
  }

  private func allSets(forceRefresh: Bool = false) async throws -> [String: SetInfo] {
    if let sets { return sets }
    if let setsTask { return try await setsTask.value }
    let file = setListFile
    let cached = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([SetInfo].self, from: $0) }
    // Use the disk copy when it's under a week old (or when offline).
    if let cached, !forceRefresh, !isCacheStale(maxAge: 7 * 24 * 60 * 60) {
      let result = Self.index(cached)
      sets = result
      return result
    }
    let directory = directory
    let task = Task<[String: SetInfo], Error> {
      do {
        let list = try await Self.downloadSetList()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: file, options: .atomic) }
        return Self.index(list)
      } catch {
        if let cached { return Self.index(cached) }
        throw error
      }
    }
    setsTask = task
    defer { setsTask = nil }
    let result = try await task.value
    sets = result
    return result
  }

  private static func index(_ list: [SetInfo]) -> [String: SetInfo] {
    Dictionary(list.map { ($0.code.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
  }

  private static func downloadSetList() async throws -> [SetInfo] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    var next: URL? = URL(string: "https://api.scryfall.com/sets")!
    var result: [SetInfo] = []
    while let url = next {
      let page = try decoder.decode(SetListResponse.self, from: try await download(url, accept: "application/json"))
      result += page.data
      next = page.hasMore == true ? page.nextPage : nil
    }
    return result
  }

  private func svg(at url: URL) async throws -> SVG {
    if let symbol = symbols[url] { return symbol }
    if let task = symbolTasks[url] { return try await task.value }
    let file = directory.appendingPathComponent(
      SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    ).appendingPathExtension("svg")
    let directory = directory
    // A cell disappearing must not cancel a download other cells share.
    let task = Task<SVG, Error> {
      if let data = try? Data(contentsOf: file), let symbol = SVG(data: data) { return symbol }
      let data = try await Self.download(url, accept: "image/svg+xml")
      guard let symbol = SVG(data: data) else { throw URLError(.cannotDecodeContentData) }
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try? data.write(to: file, options: .atomic)
      return symbol
    }
    symbolTasks[url] = task
    defer { symbolTasks[url] = nil }
    let symbol = try await task.value
    symbols[url] = symbol
    return symbol
  }

  private static func download(_ url: URL, accept: String) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue("MagicBoard/1.0", forHTTPHeaderField: "User-Agent")
    request.setValue(accept, forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
      throw URLError(.badServerResponse)
    }
    return data
  }
}

/// One set's button face: its symbol above its name.
struct JumpInSetTile: View {
  let code: String
  @State private var name: String?
  @State private var symbol: SVG?

  private var isAllSets: Bool { code.uppercased() == "ALL" }
  private var title: String { isAllSets ? "All Sets" : (name ?? code.uppercased()) }

  var body: some View {
    VStack(spacing: 8) {
      Group {
        if isAllSets {
          Image(systemName: "square.stack.3d.up.fill").resizable().scaledToFit()
        } else if let symbol {
          SVGView(svg: symbol).renderingMode(.template).resizable().scaledToFit()
        } else {
          Text(code.uppercased()).font(.headline.monospaced()).minimumScaleFactor(0.5)
        }
      }
      .frame(width: 56, height: 40)
      .foregroundStyle(.primary)
      Text(title)
        .font(.footnote.weight(.medium))
        .multilineTextAlignment(.center)
        .lineLimit(2, reservesSpace: true)
        .minimumScaleFactor(0.8)
        .foregroundStyle(.primary)
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity)
    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .task(id: code) {
      guard !isAllSets else { return }
      // Keep the set code showing if Scryfall can't be reached.
      let store = ScryfallSetSymbolStore.shared
      if let info = try? await store.info(for: code) { name = info.name }
      if let loaded = try? await store.symbol(for: code) { symbol = loaded }
    }
  }
}

/// A grid of Jump-In sets; `cell` wraps each tile in a button or link.
struct JumpInSetGrid<Cell: View>: View {
  let sets: [String]
  @ViewBuilder let cell: (String) -> Cell

  var body: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
        ForEach(sets, id: \.self) { code in
          cell(code)
            .buttonStyle(.plain)
            .accessibilityIdentifier(code)
        }
      }
      .padding()
    }
    .background(Color(uiColor: .systemGroupedBackground))
  }
}
