//
//  OverlayedGeometryProxy.swift
//  Spellbook
//
//  Created by Josh Birnholz on 8/18/23.
//

import SwiftUI

/// A proxy for access to the size and coordinate space (for anchor resolution) of the container view.
public struct OverlayedGeometryProxy {
  fileprivate init(size: CGSize = .zero, safeAreaInsets: EdgeInsets = .init(), frameInSpace: ((CoordinateSpace) -> CGRect)? = nil) {
    /// The size of the container view.
    self.size = size
    /// The safe area inset of the container view.
    self.safeAreaInsets = safeAreaInsets
    /// Returns the container view’s bounds rectangle, converted to a defined coordinate space.
    self.frameInSpace = frameInSpace
  }
  
  public var size: CGSize = .zero
  public var safeAreaInsets: EdgeInsets = .init()
  
  fileprivate var frameInSpace: ((CoordinateSpace) -> CGRect)?
  
  public func frame(in coordinateSpace: CoordinateSpace) -> CGRect {
    return frameInSpace?(coordinateSpace) ?? .zero
  }
}

public struct OverlayedGeometryReader<Content: View>: View {
  
  private let content: (OverlayedGeometryProxy) -> Content
  @State private var proxy = OverlayedGeometryProxy()
  
  public init(@ViewBuilder content: @escaping (OverlayedGeometryProxy) -> Content) {
    self.content = content
  }
  
  public var body: some View {
    content(proxy)
      .overlay {
        GeometryReader { proxy in
          Color.clear
            .onAppear {
              self.proxy = OverlayedGeometryProxy(
                size: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets,
                frameInSpace: proxy.frame(in:)
              )
            }
            .onChange(of: proxy.size, perform: { newValue in
              self.proxy = OverlayedGeometryProxy(
                size: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets,
                frameInSpace: proxy.frame(in:)
              )
            })
            .onChange(of: proxy.safeAreaInsets) { newValue in
              self.proxy = OverlayedGeometryProxy(
                size: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets,
                frameInSpace: proxy.frame(in:)
              )
            }
        }
      }
  }
}
