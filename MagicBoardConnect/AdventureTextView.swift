//
//  AdventureTextView.swift
//  Magic Board
//
//  Created by Josh Birnholz on 9/12/23.
//  Copyright © 2023 Josh Birnholz. All rights reserved.
//

import SwiftUI
import CardService

class AdventureViewModel: ObservableObject {
  @Published var oracleText: String?
  @Published var flavorText: String?
  @Published var adventureTitle: String = ""
  @Published var adventureText: String = ""
  @Published var adventureCost: String = ""
  @Published var adventureType: String = ""
  
  @Published var color: MTGColor = .colorless
  @Published var adventureColor: MTGColor = .colorless
  
  var viewType: String {
    if adventureType.contains("Omen") {
      return "omen"
    } else {
      return "adventure"
    }
  }
}

struct AdventureTextView: View {
  @ObservedObject var viewModel: AdventureViewModel
  
  var body: some View {
    HStack(spacing: 0) {
      GeometryReader { proxy in
        Image("textbox-\(viewModel.adventureColor.name)-\(viewModel.viewType)-left").resizable()
          .overlay {
            if viewModel.adventureColor != viewModel.color {
              Image("textbox-\(viewModel.color.name)-\(viewModel.viewType)-left").resizable()
                .mask(
                  Image("\(viewModel.viewType)-left-mask").resizable()
                )
            }
          }
          .overlay {
            VStack(alignment: .leading, spacing: 0) {
              HStack {
                Text(viewModel.adventureTitle)
                  .font(.custom("Beleren2016-Bold", size: proxy.size.width*0.09))
                  .foregroundColor(.white)
                  .lineLimit(1)
                  .minimumScaleFactor(0.1)
                Spacer()
                addSymbols(string: viewModel.adventureCost, symbolLength: proxy.size.width*0.09)
                  .fixedSize()
                  .shadow(
                    color: .black,
                    radius: 0,
                    x: -proxy.size.width*0.006,
                    y: proxy.size.width*0.006
                  )
              }
              .frame(height: proxy.size.height*0.155)
              
              Text(viewModel.adventureType)
                .font(.custom("Beleren2016-Bold", size: proxy.size.width*0.09))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.1)
                .frame(height: proxy.size.height*0.14)
              
              OracleTextView(viewModel: {
                let vm = OracleTextViewModel()
                vm.oracleText = viewModel.adventureText
                vm.textAlignment = .leading
                return vm
              }())
              .frame(maxHeight: .infinity)
              .padding(.top, proxy.size.width*0.01)
              .padding(.bottom, proxy.size.width*0.03)
            }
            .padding(.leading, proxy.size.width*0.06)
            .padding(.trailing, proxy.size.width*0.04)
            .padding(.top, proxy.size.width*0.017)
          }
      }
      
      GeometryReader { proxy in
        Image("textbox-\(viewModel.color.name)-\(viewModel.viewType)-right").resizable()
          .overlay {
            OracleTextView(viewModel: {
              let vm = OracleTextViewModel()
              vm.oracleText = viewModel.oracleText
              vm.flavorText = viewModel.flavorText
              vm.textAlignment = .leading
              return vm
            }())
            .padding(proxy.size.width*0.05)
          }
      }
    }.aspectRatio((335*2)/319, contentMode: .fit)
  }
}

//#Preview {
//  AdventureTextView(viewModel: {
//    let vm = AdventureViewModel()
//    vm.oracleText = "Flying, haste"
//    vm.flavorText = "“At least it’s a beautiful way to die.”\n—Erinis, gloom stalker"
//    vm.adventureTitle = "Burn Together"
//    vm.adventureText = "Return target nonland permanent an opponent controls to its owner’s hand."
//    vm.adventureCost = "{R}"
//    vm.adventureType = "Sorcery – Adventure"
//    vm.color = .red
//    vm.adventureColor = .black
//    
//    return vm
//  }())
//}
//
