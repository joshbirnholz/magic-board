import SwiftUI

/// Arena's controls around the main button in a Rules game: the phase row above it (the current
/// step lit), Arena's second button ("No Attacks" / "Cancel Attacks") and the small fast-forward
/// pill for the pass shortcuts. The main button itself is Phone Play's phase button, restyled.
struct RulesActionStack: View {
    @ObservedObject var session: RulesGameSession
    let adapter: RulesPhoneAdapter

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                RulesFastForwardPill(session: session)
                if let state = session.snapshot, state.activePlayerId != nil {
                    RulesPhaseRow(step: state.step ?? "", mine: state.activePlayerId == state.playerId)
                }
            }
            if let title = RulesPhoneAdapter.secondaryButton(prompt: session.prompt, snapshot: session.snapshot) {
                Button(title) { Task { await adapter.pressSecondary() } }
                    .buttonStyle(RulesArenaButtonStyle(kind: title == "No Attacks" ? .blue : .outline))
                    .disabled(!session.canAnswer)
                    .accessibilityIdentifier("rules-secondary-action")
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.15), value: RulesPhoneAdapter.secondaryButton(prompt: session.prompt, snapshot: session.snapshot))
    }
}

/// Arena's small fast-forward pill under the main button: the "Pass Until…" shortcuts.
struct RulesFastForwardPill: View {
    @ObservedObject var session: RulesGameSession

    var body: some View {
        Menu {
            Button { pass(.resolveStack) } label: { Label("Stack Resolves", systemImage: "square.stack.3d.up") }
            Button { pass(.nextMain) } label: { Label("Next Main Phase", systemImage: "arrow.right.to.line") }
            Button { pass(.endStep) } label: { Label("End Step", systemImage: "forward.end") }
            Button { pass(.yourTurn) } label: { Label("My Next Turn", systemImage: "forward.end.alt") }
        } label: {
            Image(systemName: "forward.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 46, height: 26)
                .background(Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.3), Color(red: 0.93, green: 0.4, blue: 0.12)], startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
                .shadow(color: .orange.opacity(0.5), radius: 4)
        }
        .disabled(session.status != .connected)
        .accessibilityLabel("Pass until")
        .accessibilityIdentifier("rules-fast-forward")
    }

    private func pass(_ action: RulesPriorityAction) { Task { await session.controlPriority(action) } }
}

/// Arena's turn structure row: beginning ◆, first main ▮, attackers ⚔, blockers 🛡, damage ★,
/// second main ▮, end ◆. The current step glows (orange on your turn, blue on the opponent's).
struct RulesPhaseRow: View {
    let step: String
    let mine: Bool

    private enum Segment: CaseIterable { case beginning, main1, attackers, blockers, damage, main2, end }

    private var current: Segment {
        switch step {
        case "UNTAP", "UPKEEP", "DRAW": return .beginning
        case "PRECOMBAT_MAIN": return .main1
        case "BEGIN_COMBAT", "DECLARE_ATTACKERS": return .attackers
        case "DECLARE_BLOCKERS": return .blockers
        case "FIRST_COMBAT_DAMAGE", "COMBAT_DAMAGE", "END_COMBAT": return .damage
        case "POSTCOMBAT_MAIN": return .main2
        default: return .end
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Segment.allCases, id: \.self) { segment in
                glyph(segment)
                    .foregroundStyle(segment == current ? (mine ? Color(red: 1, green: 0.66, blue: 0.3) : Color(red: 0.45, green: 0.75, blue: 1)) : Color.black.opacity(0.75))
                    .shadow(color: segment == current ? (mine ? .orange : .blue) : .clear, radius: 5)
                    .shadow(color: .white.opacity(segment == current ? 0 : 0.35), radius: 0.5)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.25)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step: \(step.replacingOccurrences(of: "_", with: " ").capitalized)")
        .accessibilityIdentifier("rules-phase-row")
    }

    @ViewBuilder private func glyph(_ segment: Segment) -> some View {
        switch segment {
        case .beginning, .end: Image(systemName: "diamond.fill").font(.system(size: 7))
        case .main1, .main2: Image(systemName: "rectangle.portrait.fill").font(.system(size: 12))
        case .attackers: Text("⚔︎").font(.system(size: 15, weight: .bold))
        case .blockers: Image(systemName: "shield.fill").font(.system(size: 12))
        case .damage: Image(systemName: "star.fill").font(.system(size: 12))
        }
    }
}

/// Arena's pill buttons around the main button: blue ("No Attacks"), outlined ("Cancel Attacks").
struct RulesArenaButtonStyle: ButtonStyle {
    enum Kind { case orange, blue, red, outline }
    var kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Beleren2016-Bold", size: 16, relativeTo: .headline))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 18).frame(minWidth: 130, minHeight: 34)
            .background {
                switch kind {
                case .outline: Capsule().fill(Color.black.opacity(0.45))
                default: Capsule().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(kind == .outline ? 0.85 : 0.6), lineWidth: kind == .outline ? 2 : 1))
            .shadow(color: glow, radius: 6)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }

    private var colors: [Color] {
        switch kind {
        case .orange: return [Color(red: 1, green: 0.72, blue: 0.45), Color(red: 0.92, green: 0.45, blue: 0.2)]
        case .blue: return [Color(red: 0.5, green: 0.62, blue: 1), Color(red: 0.27, green: 0.35, blue: 0.85)]
        case .red: return [Color(red: 1, green: 0.55, blue: 0.5), Color(red: 0.88, green: 0.3, blue: 0.3)]
        case .outline: return []
        }
    }

    private var glow: Color {
        switch kind {
        case .orange: return .orange.opacity(0.5)
        case .blue: return .blue.opacity(0.5)
        case .red: return .red.opacity(0.5)
        case .outline: return .clear
        }
    }
}
