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
  /// Arena's life-change feedback (Rules games): the box flashes red or green and the change floats up.
  var showsChanges = false
  /// Compact centered phone HUD; the classic board retains its rectangular tracker.
  var circular = false
  
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
    
    .clipShape(RoundedRectangle(cornerRadius: circular ? 1000 : 15))
    // Phone Play positions the tracker explicitly; fill that frame exactly on every device.
     .transaction { if AppDelegate.shared.usesPhoneSession { $0.animation = nil } }
     // After the transaction above, so its animation-off rule doesn't reach the feedback.
     .overlay { if showsChanges { LifeChangeFeedback(value: life.value, circular: circular) } }

  }
}

/// A brief Arena-style cue when a life total changes: a red (loss) or green (gain) flash around
/// the box and the amount floating up out of it.
struct LifeChangeFeedback: View {
  let value: Int
  var circular = false
  @State private var last: Int?
  @State private var delta = 0
  @State private var shown = false
  @State private var token = 0
  @State private var appeared = Date.distantFuture

  var body: some View {
    GeometryReader { proxy in
      let radius = circular ? min(proxy.size.width, proxy.size.height) / 2 : 15
      let color = delta < 0 ? Color(red: 1, green: 0.3, blue: 0.25) : Color(red: 0.35, green: 0.95, blue: 0.45)
      ZStack {
        RoundedRectangle(cornerRadius: radius)
          .strokeBorder(color, lineWidth: 3)
          .background(RoundedRectangle(cornerRadius: radius).fill(color.opacity(0.25)))
          .shadow(color: color, radius: 6)
          .opacity(shown ? 1 : 0)
        Text(delta > 0 ? "+\(delta)" : "\(delta)")
          .font(.custom("Beleren2016-Bold", size: max(12, min(proxy.size.height * 0.5, 28))))
          .foregroundStyle(color)
          .shadow(color: .black, radius: 2)
          .offset(y: shown ? -proxy.size.height * 0.55 : 0)
          .opacity(shown ? 1 : 0)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .allowsHitTesting(false)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(shown ? "Life changed by \(delta)" : "")
    .accessibilityIdentifier("life-change")
    .onAppear { last = value; appeared = Date() }
    .onChange(of: value) { newValue in
      defer { last = newValue }
      // The first engine snapshot replaces Phone Play's starting life; that isn't a change.
      guard let last, newValue != last, Date().timeIntervalSince(appeared) > 1 else { return }
      // Changes in quick succession (one hit after another) add up while the cue is showing.
      delta = shown ? delta + (newValue - last) : newValue - last
      token += 1
      let current = token
      withAnimation(.easeOut(duration: 0.2)) { shown = true }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
        guard current == token else { return }
        withAnimation(.easeIn(duration: 0.35)) { shown = false }
      }
    }
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
