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
      .onDisappear { timer?.invalidate(); timer = nil; isLongPressing = false }
    }
  }
}

struct LifeTracker: View {
  
//  @Binding var life: Int
  @ObservedObject var life: ObservableBridge<Int>
  /// The − / + marks; off for a tracker that can't be changed (the opponent's, in Phone Play).
  var showsMarks = true
  
  var body: some View {
    ZStack {
      HStack(spacing: 0) {
        HoldButton(color: Color(white: 0.2)) { life.value -= 1 }
          .accessibilityLabel("Decrease life")
        HoldButton(color: Color(white: 0.2)) { life.value += 1 }
          .accessibilityLabel("Increase life")
      }
      
      GeometryReader { proxy in
        Text("\(life.value)")
          .font(.custom("Beleren2016-Bold", size: AppDelegate.shared.usesPhoneSession ? min(proxy.size.height * 0.82, proxy.size.width * 0.46) : proxy.size.width * 0.5))
          .minimumScaleFactor(0.01)
          .lineLimit(1)
//          .padding()
          .allowsHitTesting(false)
          .foregroundColor(.white)
          .frame(width:proxy.size.width,height:proxy.size.height,alignment:.center)
          .transaction { $0.animation = nil }
        // Subtle − / + marks at the ends show that each half is a button.
        if showsMarks {
        let mark = max(7, min(proxy.size.height * 0.2, proxy.size.width * 0.09))
        HStack {
          Image(systemName: "minus")
          Spacer(minLength: 0)
          Image(systemName: "plus")
        }
        .font(.system(size: mark, weight: .semibold))
        .foregroundColor(.white.opacity(0.35))
        .padding(.horizontal, max(4, proxy.size.width * 0.05))
        .frame(width: proxy.size.width, height: proxy.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        }
      }
    }
//    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    
    .cornerRadius(15)
    // Phone Play positions the tracker explicitly; fill that frame exactly on every device.
     .transaction { if AppDelegate.shared.usesPhoneSession { $0.animation = nil } }

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
