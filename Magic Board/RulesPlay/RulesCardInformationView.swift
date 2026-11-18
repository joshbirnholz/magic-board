import SwiftUI

/// Arena-style inspection of information the engine allows this seat to see.
/// Closing this view changes local presentation only; it never answers a rules prompt.
struct RulesCardInformationView: View {
    let group: RulesSnapshot.CardGroup
    let viewBattlefield: () -> Void
    let dismiss: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let cardHeight = max(96, min(230, geometry.size.height - 120))
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    Text(RulesText.plain(group.name))
                        .font(.custom("Beleren2016-Bold", size: 22, relativeTo: .title2))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .accessibilityIdentifier("rules-information-title")
                    Spacer(minLength: 8)
                    Button("View Battlefield", action: viewBattlefield)
                        .buttonStyle(RulesPillButtonStyle(primary: false))
                        .accessibilityIdentifier("rules-information-battlefield")
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 12) {
                        ForEach(group.cards) { card in
                            RulesChoiceCardFace(card: card, height: cardHeight)
                                .accessibilityRemoveTraits(.isButton)
                                .accessibilityIdentifier("rules-information-card-\(card.id)")
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(minWidth: geometry.size.width)
                }
                .frame(height: cardHeight + 8)
                Spacer(minLength: 0)
                Button("Done", action: dismiss)
                    .buttonStyle(RulesPillButtonStyle())
                    .accessibilityIdentifier("rules-information-done")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
