import SwiftUI

fileprivate struct HoldButtonStyle: ButtonStyle {
  let color: Color
  
  func makeBody(configuration: Self.Configuration) -> some View {
    configuration.label
      .foregroundColor(color)
      .overlay {
        if configuration.isPressed {
          Rectangle()
            .foregroundColor(Color(UIColor.secondarySystemFill))
        }
      }
  }
}

struct HoldButton: View {
  let color: Color
  let action: () -> Void
  
  let delay: TimeInterval = 0.3
  let rate: TimeInterval = 0.1
  
  @State private var timer: Timer?
    @State var isLongPressing = false
    
  var body: some View {
    VStack {
      Button(action: {
        if isLongPressing {
          isLongPressing.toggle()
          timer?.invalidate()
          timer = nil
        } else {
          action()
        }
      }, label: {
        Rectangle().background(color)
      })
      .simultaneousGesture(LongPressGesture(minimumDuration: delay).onEnded { _ in
        isLongPressing = true
        //or fastforward has started to start the timer
        timer = Timer.scheduledTimer(withTimeInterval: rate, repeats: true, block: { _ in
          action()
        })
      })
      .buttonStyle(HoldButtonStyle(color: color))
    }
  }
}

struct LifeTracker: View {
  
//  @Binding var life: Int
  @ObservedObject var life: ObservableBridge<Int>
  
  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        HoldButton(color: Color(white: 0.2)) { life.value += 1 }
        HoldButton(color: Color(white: 0.2)) { life.value -= 1 }
      }
      
      GeometryReader { proxy in
        Text("\(life.value)")
          .font(.custom("Beleren2016-Bold", size: proxy.size.width * 0.5))
          .minimumScaleFactor(0.01)
          .lineLimit(1)
//          .padding()
          .foregroundColor(.white)
          .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
      }
    }
//    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    
    .cornerRadius(15)
    .ignoresSafeArea()
  }
}

struct HoldButtonPreviews: PreviewProvider {
  struct Preview: View {
    let bridge = ObservableBridge(.init(value: 40))
    
    var body: some View {
      LifeTracker(life: bridge)
        .padding()
        .background(.black)
    }
  }
  
  static var previews: some View {
    Preview()
  }
}
