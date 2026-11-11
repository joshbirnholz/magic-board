//
//  TextBoxTest.swift
//  Magic Board
//
//  Created by Josh Birnholz on 9/19/23.
//  Copyright © 2023 Josh Birnholz. All rights reserved.
//

import SwiftUI
import CardView
import CardService

struct TextBox: View {
  @State var colors: [MTGCardView.Color]
  @State var backgroundStyle: MTGCardView.BackgroundStyle?
  
  var body: some View {
    Group {
      if let image = Self.textBoxImage(colors: colors, backgroundStyle: backgroundStyle) {
        Image(uiImage: image)
          .resizable()
        //          Text("Image")
      } else {
        Text("Nil")
      }
    }
  }
  
  
  
  static func textBoxImage(colors: [MTGCardView.Color], backgroundStyle: MTGCardView.BackgroundStyle?) -> UIImage? {
    let suffix: String = {
      if backgroundStyle?.isSnow == true {
        return "-snow"
      } else if backgroundStyle?.isUniversesBeyond == true {
        return "-ub"
      } else {
        return ""
      }
    }()
    
    if colors.isEmpty && (backgroundStyle?.isLand == true) {
      return UIImage(named: "textbox-land\(suffix)")
    } else if colors.count == 1 && (backgroundStyle?.isLand == true), let color = colors.first {
      return UIImage(named: "textbox-\(color.rawValue)-land\(suffix)")
    } else if colors.isEmpty && (backgroundStyle?.isArtifact == true) {
      return UIImage(named: "textbox-artifact\(suffix)")
    } else if colors.count == 1, let color = colors.first {
      return UIImage(named: "textbox-\(color.rawValue)\(suffix)")
    } else if colors.count > 2 {
      return UIImage(named: "textbox-gold\(suffix)")
    } else if colors.count == 2 {
      let left = textBoxImage(colors: [colors[0]], backgroundStyle: backgroundStyle)
      let right = textBoxImage(colors: [colors[1]], backgroundStyle: backgroundStyle)
      return mergeImages(left: left, right: right)
    } else {
      return UIImage(named: "textbox-colorless")
    }
  }
  
  private static func maskImage(_ image: UIImage?, withMask maskImage: UIImage?) -> UIImage? {
    guard let maskRef = maskImage?.cgImage, let provider = maskRef.dataProvider else {
      return nil
    }
    
    let mask = CGImage(
      maskWidth: maskRef.width,
         height: maskRef.height,
         bitsPerComponent: maskRef.bitsPerComponent,
         bitsPerPixel: maskRef.bitsPerPixel,
         bytesPerRow: maskRef.bytesPerRow,
         provider: provider,
         decode: nil,
         shouldInterpolate: false)
    
    if let mask = mask, let maskedImageRef = image?.cgImage?.masking(mask) {
      return UIImage(cgImage: maskedImageRef)
    }
    
    return nil
  }
  
  private static func mergeImages(left: UIImage?, right: UIImage?, maskName: String = "textbox-mask-right") -> UIImage? {
    guard
      let left = left,
      let right = right,
      let mask = UIImage(named: maskName),
      let rightMasked = maskImage(right, withMask: mask) else {
      return left ?? right
    }
    
    UIGraphicsBeginImageContext(mask.size)
    
    let areaSize = CGRect(x: 0, y: 0, width: mask.size.width, height: mask.size.height)
    left.draw(in: areaSize)
    
    rightMasked.draw(in: areaSize)
    
    let mergedImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    return mergedImage
  }
  
//  private func mergedImage(left: String, right: String, maskName: String = "textbox-mask") -> UIImage? {
//    let left = UIImage(named: left)
//    let right = UIImage(named: right)
//    
//    return mergeImages(left: left, right: right, maskName: maskName)
//  }
}

#Preview {
  TextBox(
    colors: [],
    backgroundStyle: .universesBeyondVehicle
  ).background(.white)
}
