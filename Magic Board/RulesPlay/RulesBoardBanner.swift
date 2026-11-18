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
