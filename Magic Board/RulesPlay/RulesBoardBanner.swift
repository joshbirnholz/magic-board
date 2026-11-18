import SwiftUI

extension RulesPrompt {
    /// Only decisions made directly on the battlefield belong in Arena's centre banner.
    /// Keep target restrictions from the engine; a card picker or mana payment has its own UI.
    var boardBannerText: String? {
        switch method {
        case "GAME_SELECT":
            let message = plainMessage.lowercased()
            if message.contains("select attackers") { return "Choose attackers." }
            if message.contains("select blockers") { return "Choose blockers." }
            return nil
        case "GAME_TARGET" where style == .compact && !isStartingPlayer && !isLondonBottom:
            let text = plainMessage.replacingOccurrences(of: "Select ", with: "Choose ", options: .anchored)
            let instruction = text.isEmpty ? "Choose a target." : text
            // XMage sends the asking ability's source separately from its target restriction.
            let sourceName = (source?.name ?? subMessage).map(RulesText.plain)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return sourceName.isEmpty ? instruction : "\(sourceName): \(instruction)"
        default:
            return nil
        }
    }
}

/// A read-only overlay: battlefield gestures pass through the entire hosting view.
struct RulesBoardBanner: View {
    @ObservedObject var session: RulesGameSession

    var body: some View {
        ZStack {
            instruction
            RulesTurnBanner(session: session)
        }
        .allowsHitTesting(false)
    }

    private var instruction: some View {
        Group {
            if session.status == .connected, session.result == nil,
               let text = session.prompt?.boardBannerText {
                Text(text)
                    .font(.system(.headline, design: .default).weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
                    // Phone Play leaves a narrow gap between the two creature rows.
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity)
                    .background {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.72), location: 0.25),
                            .init(color: .black.opacity(0.72), location: 0.75),
                            .init(color: .clear, location: 1)
                        ], startPoint: .leading, endPoint: .trailing)
                    }
                    .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                    .accessibilityIdentifier("rules-board-banner")
            }
        }
        .allowsHitTesting(false)
    }
}

/// Arena's turn announcement: fades and scales up in the middle of the board, holds briefly, then
/// shrinks and drifts toward the new active player's hand as it fades.
struct RulesTurnBanner: View {
    @ObservedObject var session: RulesGameSession
    private enum Stage { case hidden, entering, shown, leaving }
    @State private var stage = Stage.hidden
    @State private var lastKey: String?
    @State private var isMine = true
    @State private var generation = 0

    var body: some View {
        Text(isMine ? "Your Turn" : "Opponent's Turn")
            .font(.system(size: 34, weight: .heavy))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.8), radius: 4, y: 2)
            .fixedSize()
            .scaleEffect(scale)
            .offset(y: offset)
            .opacity(stage == .entering || stage == .shown ? 1 : 0)
            .accessibilityIdentifier("rules-turn-banner")
            .accessibilityHidden(stage == .hidden)
            .onReceive(session.$snapshot) { snapshot in
                guard let snapshot, let active = snapshot.activePlayerId else { return }
                let key = "\(snapshot.gameId)-\(snapshot.turn)-\(active)"
                guard key != lastKey else { return }
                lastKey = key
                announce(mine: active == snapshot.playerId)
            }
    }

    private var scale: CGFloat {
        switch stage {
        case .hidden: return 0.6
        case .entering, .shown: return 1
        case .leaving: return 0.35
        }
    }

    private var offset: CGFloat {
        guard stage == .leaving else { return 0 }
        // The hands sit at the bottom (ours) and top (the opponent's) of the board.
        let distance = UIScreen.main.bounds.height * 0.38
        return isMine ? distance : -distance
    }

    private func announce(mine: Bool) {
        generation += 1
        let current = generation
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            isMine = mine
            stage = .hidden
        }
        DispatchQueue.main.async {
            guard current == generation else { return }
            withAnimation(.easeOut(duration: 0.25)) { stage = .entering }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard current == generation else { return }
            withAnimation(.easeIn(duration: 0.4)) { stage = .leaving }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            guard current == generation else { return }
            withTransaction(reset) { stage = .hidden }
        }
    }
}
