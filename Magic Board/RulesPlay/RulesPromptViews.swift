import SwiftUI
import CardService

// Rules mode prompts, styled after MTG Arena:
// - Playing on the board (priority, paying mana, picking targets on the battlefield) keeps the board
//   clear: a small instruction strip sits beside the main phase button, which does the confirming.
// - Decisions that aren't on the board (mulligan, who plays first, modes and choices, numbers,
//   piles, cards to pick from a revealed set, game over) take over the screen over a dimmed board,
//   with large cards and pill buttons.

enum RulesPromptStyle { case compact, modal }

extension RulesPrompt {
    var style: RulesPromptStyle {
        switch method {
        case "GAME_SELECT", "GAME_PLAY_MANA", "GAME_PLAY_XMANA": return .compact
        case "GAME_TARGET": return (cards?.isEmpty == false || isStartingPlayer) ? .modal : .compact
        default: return .modal
        }
    }
    var isStartingPlayer: Bool { message?.localizedCaseInsensitiveContains("starting player") == true }
    var isMulligan: Bool { method == "GAME_ASK" && message?.localizedCaseInsensitiveContains("mulligan") == true }
    /// XMage's message without markup or the object-id suffixes it appends ("Silence [50d]").
    var plainMessage: String {
        RulesText.plain(message ?? "Choose an action")
            .replacingOccurrences(of: #"\s*\[[0-9a-f]{3,}\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Shared pieces

/// Arena's pill buttons: a filled primary action and an outlined secondary one.
struct RulesPillButtonStyle: ButtonStyle {
    var primary = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Beleren2016-Bold", size: 17, relativeTo: .headline))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 22).padding(.vertical, 10)
            .frame(minWidth: 112)
            .foregroundStyle(primary ? Color.black : Color.white)
            .background {
                if primary {
                    Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.74, blue: 0.25), Color(red: 0.98, green: 0.52, blue: 0.08)],
                                                  startPoint: .top, endPoint: .bottom))
                } else {
                    Capsule().fill(Color.white.opacity(0.08)).overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
                }
            }
            .shadow(color: primary ? Color.orange.opacity(0.45) : .clear, radius: 8)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Prompt text with mana and tap symbols drawn as symbols.
private struct RulesSymbolText: View {
    let text: String
    var size: CGFloat = 15
    /// Beleren for titles (Arena's headline face); the system font for body text.
    var beleren = false
    var body: some View {
        addSymbols(string: text, symbolLength: size)
            .font(beleren ? .custom("Beleren2016-Bold", size: size, relativeTo: .title3) : .system(size: size))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Compact strip (beside the main button)

/// The compact prompt beside the phase button. Shows nothing while a full-screen decision is up.
struct RulesPromptBar: View {
    @ObservedObject var session: RulesGameSession
    var exit: (() -> Void)? = nil

    var body: some View {
        Group {
            if session.status == .disconnected {
                strip {
                    Text(session.notice.isEmpty ? "Disconnected from the rules server." : session.notice).font(.callout)
                    Button("Reconnect") {
                        let address = UserDefaults.standard.string(forKey: "rules.bridgeAddress") ?? ""
                        session.connect(address: address, key: session.connectionKey)
                    }.buttonStyle(RulesPillButtonStyle())
                }
            } else if session.result != nil {
                EmptyView() // the game-over screen is full screen
            } else if let prompt = session.prompt {
                if prompt.style == .compact { compact(prompt) }
            } else if let waiting = waitingMessage {
                strip {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text(waiting).font(.callout).foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
        .frame(maxWidth: 320)
        .disabled(session.pendingRequest != nil)
        .animation(.easeInOut(duration: 0.15), value: session.prompt?.id)
    }

    @ViewBuilder private func compact(_ prompt: RulesPrompt) -> some View {
        switch prompt.method {
        case "GAME_PLAY_MANA", "GAME_PLAY_XMANA":
            strip {
                RulesSymbolText(text: prompt.plainMessage, size: 18, beleren: true).foregroundStyle(.white)
                    .accessibilityIdentifier("rules-prompt-message")
                Text("Tap your lands to pay.").font(.caption).foregroundStyle(.white.opacity(0.7))
                    .accessibilityHidden(true)
                HStack {
                    answer("Cancel", .boolean(false), primary: false)
                    if prompt.method == "GAME_PLAY_XMANA" { answer("Done", .boolean(true)) }
                    // With automatic payment turned off, one tap still pays with a fitting basic land.
                    if !RulesPhoneAdapter.autoPaysMana, let land = RulesPhoneAdapter.autoPayLand(prompt, snapshot: session.snapshot) {
                        answer("Auto", .object(land)).accessibilityIdentifier("rules-auto-pay")
                    }
                }
            }
        case "GAME_TARGET":
            strip {
                RulesSymbolText(text: prompt.plainMessage, size: 17, beleren: true).foregroundStyle(.white)
                    .accessibilityIdentifier("rules-prompt-message")
                Text("Tap a highlighted card.").font(.caption).foregroundStyle(.white.opacity(0.7))
                let players = session.snapshot?.players.filter { prompt.targets?.contains($0.id) == true } ?? []
                if !players.isEmpty {
                    HStack { ForEach(players) { player in
                        answer(player.id == session.snapshot?.playerId ? "You" : player.name, .object(player.id), primary: false)
                            .accessibilityIdentifier(player.id == session.snapshot?.playerId ? "rules-target-self" : "rules-target-opponent")
                    } }
                }
                if prompt.required != true { answer("Done", .boolean(false), primary: false) }
            }
        case "GAME_SELECT" where !allAttackers(prompt).isEmpty:
            // Arena's "All Attack": declare every creature that can attack, then confirm with the main button.
            strip {
                Button("All Attack") { attackWithAll(allAttackers(prompt)) }
                    .buttonStyle(RulesPillButtonStyle(primary: false))
                    .disabled(!session.canAnswer || attacking)
                    .accessibilityIdentifier("rules-all-attack")
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel(prompt.plainMessage)
                    .accessibilityIdentifier("rules-prompt-message")
            }
        case "GAME_SELECT" where prompt.specialActionAvailable == true:
            // A special action (turning a face-down creature up, suspend…) is possible: offer it.
            strip {
                Button(prompt.specialActionLabel ?? "Special Action") { Task { await session.answer(.specialAction) } }
                    .buttonStyle(RulesPillButtonStyle(primary: false))
                    .disabled(!session.canAnswer)
                    .accessibilityIdentifier("rules-special-action")
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel(prompt.plainMessage)
                    .accessibilityIdentifier("rules-prompt-message")
            }
        default:
            // GAME_SELECT: like Arena, no instructions. The highlights show what can be played and
            // the main button says what passing does (To Attackers, Resolve, End Turn…). The engine's
            // wording stays available to VoiceOver (and UI tests) without drawing anything.
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel(prompt.plainMessage)
                .accessibilityIdentifier("rules-prompt-message")
        }
    }

    @State private var attacking = false

    /// Our untapped creatures that aren't summoning sick and aren't attacking yet, while XMage asks for attackers.
    private func allAttackers(_ prompt: RulesPrompt) -> [String] {
        guard RulesText.plain(prompt.message ?? "").localizedCaseInsensitiveContains("select attackers"),
              let state = session.snapshot, let mine = state.players.first(where: { $0.id == state.playerId }) else { return [] }
        let declared = Set((state.combat ?? []).flatMap(\.attackers))
        return mine.battlefield.filter { card in
            (card.typeLine ?? "").contains("Creature") && card.tapped != true && card.summoningSick != true && !declared.contains(card.id)
        }.map(\.id)
    }

    /// Selects each attacker in turn; XMage asks "Select attackers" again after each one.
    private func attackWithAll(_ ids: [String]) {
        attacking = true
        Task {
            defer { attacking = false }
            for id in ids {
                let before = session.prompt?.id
                await session.answer(.object(id))
                for _ in 0..<60 where session.prompt?.id == before || session.pendingRequest != nil {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                guard session.prompt?.method == "GAME_SELECT" else { break }
            }
        }
    }

    private func strip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .center, spacing: 6) { content() }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            .environment(\.colorScheme, .dark)
    }

    private var phaseLine: String? {
        guard let state = session.snapshot else { return nil }
        let owner = state.activePlayerId == nil ? nil : state.activePlayerId == state.playerId ? "Your turn" : "Opponent's turn"
        let step = state.step.map { RulesText.plain($0.replacingOccurrences(of: "_", with: " ").capitalized) }
        return [owner, step].compactMap { $0 }.joined(separator: " · ")
    }

    private var waitingMessage: String? {
        guard let state = session.snapshot else { return session.status == .connected ? "Waiting for the game…" : nil }
        let mine = state.players.first { $0.id == state.playerId }?.name
        if let priority = state.priorityPlayer, !priority.isEmpty, priority != mine { return "\(priority) is thinking…" }
        return nil
    }

    private func answer(_ title: String, _ value: RulesAnswer, primary: Bool = true) -> some View {
        Button(title) { Task { await session.answer(value) } }
            .buttonStyle(RulesPillButtonStyle(primary: primary))
            .disabled(!session.canAnswer)
    }
}

// MARK: - Full-screen decisions

/// Decisions that take over the screen (Arena's dimmed browser with large cards and pill buttons).
struct RulesPromptModal: View {
    @ObservedObject var session: RulesGameSession
    var exit: (() -> Void)? = nil
    /// Tells the board whether to show this layer (it would otherwise swallow touches).
    var onVisibilityChange: (Bool) -> Void = { _ in }
    @State private var number = 0
    @State private var amounts: [Int] = []
    @State private var choiceSearch = ""
    @State private var minimized = false

    private var informationGroup: RulesSnapshot.CardGroup? {
        guard session.status == .connected, session.result == nil else { return nil }
        if let prompt = session.prompt {
            guard prompt.method == "GAME_SELECT", prompt.plainMessage.hasPrefix("Play ") else { return nil }
        }
        return session.cardInformation.first
    }

    private var isVisible: Bool {
        if session.result != nil { return true }
        guard session.status == .connected else { return false }
        return session.prompt?.style == .modal || informationGroup != nil
    }

    var body: some View {
        ZStack {
            if isVisible, !minimized {
                Color.black.opacity(0.62).ignoresSafeArea()
                content
                    .padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else if isVisible {
                // Arena lets you hide a decision to look at the board; this brings it back.
                Button { minimized = false } label: {
                    Label(informationGroup == nil ? "Back to choice" : "Revealed Cards",
                          systemImage: informationGroup == nil ? "rectangle.on.rectangle" : "eye")
                }
                    .buttonStyle(RulesPillButtonStyle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 12)
            }
        }
        .environment(\.colorScheme, .dark)
        .disabled(session.pendingRequest != nil)
        .animation(.easeInOut(duration: 0.18), value: isVisible)
        .onAppear { resetInputs(); onVisibilityChange(isVisible) }
        .onChange(of: isVisible) { onVisibilityChange($0) }
        .onChange(of: session.prompt?.id) { _ in resetInputs() }
    }

    @ViewBuilder private var content: some View {
        if let result = session.result {
            gameOver(result)
        } else if let prompt = session.prompt, prompt.style == .modal {
            VStack(spacing: 14) {
                title(prompt)
                body(for: prompt)
            }
        } else if let group = informationGroup {
            RulesCardInformationView(group: group, viewBattlefield: { minimized = true },
                                     dismiss: { session.dismissCardInformation(group.id) })
        }
    }

    private func title(_ prompt: RulesPrompt) -> some View {
        VStack(spacing: 4) {
            // Long engine sentences ("Select up to one card to put on the bottom…") get a smaller size
            // so the cards still fit in landscape.
            let title = prompt.isStartingPlayer ? "Who plays first?" : prompt.isMulligan ? mulliganTitle(prompt) : prompt.plainMessage
            RulesSymbolText(text: title, size: title.count > 48 ? 18 : 24, beleren: true)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("rules-prompt-message")
                .accessibilityLabel(prompt.plainMessage)
            if let sub = prompt.subMessage.map(RulesText.plain), !sub.isEmpty {
                RulesSymbolText(text: sub, size: 15).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
            }
            if prompt.queryType == "PICK_ABILITY" {
                Text("Choose the order: the first one you pick goes on the stack first.")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            if prompt.style == .modal, prompt.method != "GAME_ASK" || prompt.isMulligan {
                Button("View Battlefield") { minimized = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private func mulliganTitle(_ prompt: RulesPrompt) -> String {
        let hand = session.snapshot?.hand.count ?? 7
        return "Your opening hand: \(hand) card\(hand == 1 ? "" : "s")"
    }

    @ViewBuilder private func body(for prompt: RulesPrompt) -> some View {
        switch prompt.method {
        case "GAME_ASK":
            if prompt.isMulligan {
                cardRow(session.snapshot?.hand ?? [], height: 150, selectable: false)
                HStack(spacing: 16) {
                    answer("Mulligan", .boolean(true), primary: false)
                    answer("Keep Hand", .boolean(false))
                }
            } else {
                HStack(spacing: 16) {
                    answer("No", .boolean(false), primary: false)
                    answer("Yes", .boolean(true))
                }
            }
        case "GAME_TARGET":
            if prompt.isStartingPlayer {
                HStack(spacing: 16) {
                    ForEach(session.snapshot?.players.filter { prompt.targets?.contains($0.id) == true } ?? []) { player in
                        answer(player.name, .object(player.id), primary: player.id == session.snapshot?.playerId)
                            .accessibilityLabel(player.name)
                    }
                }
            } else {
                cardRow(prompt.cards ?? [], height: 150, selectable: true)
                // "Up to one…" (scry, optional targets) can be finished without choosing.
                if prompt.required != true || prompt.canCancel == true || (prompt.min ?? 1) == 0 {
                    answer("Done", .boolean(false), primary: false)
                }
            }
        case "GAME_GET_AMOUNT":
            let low = prompt.min ?? 0, high = max(prompt.min ?? 0, prompt.max ?? 0)
            HStack(spacing: 22) {
                stepButton("minus", enabled: number > low) { number -= 1 }
                Text("\(number)").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white).frame(minWidth: 70)
                stepButton("plus", enabled: number < high) { number += 1 }
            }
            answer("Confirm", .number(number))
        case "GAME_CHOOSE_CHOICE", "GAME_CHOOSE_ABILITY":
            if prompt.choices.count > 12 {
                TextField("Search", text: $choiceSearch)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled().frame(maxWidth: 320)
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(prompt.choices.filter { choiceSearch.isEmpty || $0.label.localizedCaseInsensitiveContains(choiceSearch) }) { choice in
                        Button { Task { await session.answer(.choice(choice.id)) } } label: {
                            RulesSymbolText(text: RulesText.plain(choice.label), size: 16)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!session.canAnswer)
                        .accessibilityLabel(RulesText.plain(choice.label))
                        .accessibilityIdentifier("rules-choice")
                    }
                }.frame(maxWidth: 460)
            }.frame(maxHeight: 220)
            if prompt.canCancel == true { answer("Cancel", .cancel, primary: false) }
        case "GAME_CHOOSE_PILE":
            HStack(alignment: .top, spacing: 18) {
                pile("Pile 1", prompt.cards ?? [], answer: true)
                pile("Pile 2", prompt.secondPile ?? [], answer: false)
            }
        case "GAME_GET_MULTI_AMOUNT":
            distribution(prompt)
        default:
            Text("This choice is not supported yet.").foregroundStyle(.white.opacity(0.8))
            if prompt.canCancel == true { answer("Cancel", .boolean(false), primary: false) }
        }
    }

    private func gameOver(_ result: String) -> some View {
        let text = RulesText.plain(result)
        let mine = session.snapshot?.players.first { $0.id == session.snapshot?.playerId }?.name ?? ""
        let won = !mine.isEmpty && text.localizedCaseInsensitiveContains("\(mine) is the winner")
        let lost = text.localizedCaseInsensitiveContains("is the winner") && !won
        return VStack(spacing: 16) {
            Text(won ? "Victory" : lost ? "Defeat" : "Game Over")
                .font(.custom("Beleren2016-Bold", size: 56, relativeTo: .largeTitle))
                .foregroundStyle(won ? Color(red: 1, green: 0.8, blue: 0.3) : .white)
            Text(text).font(.callout).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
            if let exit { Button("Exit Game", action: exit).buttonStyle(RulesPillButtonStyle()) }
        }
    }

    private func pile(_ title: String, _ cards: [RulesCard], answer value: Bool) -> some View {
        VStack(spacing: 8) {
            Text("\(title) · \(cards.count)").font(.custom("Beleren2016-Bold", size: 17, relativeTo: .headline)).foregroundStyle(.white)
            cardRow(cards, height: 120, selectable: false).frame(maxWidth: 320)
            answer("Choose \(title)", .boolean(value))
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2.weight(.bold)).frame(width: 48, height: 48)
                .background(Circle().fill(Color.white.opacity(enabled ? 0.18 : 0.06)))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.3))
        }.buttonStyle(.plain).disabled(!enabled)
    }

    @ViewBuilder private func distribution(_ prompt: RulesPrompt) -> some View {
        let rows = prompt.amounts ?? []
        let values = amounts.count == rows.count ? amounts : rows.map(\.defaultValue)
        let total = values.reduce(0, +)
        let minimum = prompt.min ?? 0, maximum = prompt.max ?? 0
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack {
                        RulesSymbolText(text: RulesText.plain(row.label), size: 15).foregroundStyle(.white)
                        Spacer()
                        stepButton("minus", enabled: values[index] > row.min) { set(index, values[index] - 1, rows) }
                        Text("\(values[index])").font(.title3.bold()).monospacedDigit().foregroundStyle(.white).frame(minWidth: 36)
                        stepButton("plus", enabled: values[index] < max(row.min, row.max)) { set(index, values[index] + 1, rows) }
                    }
                }
            }.frame(maxWidth: 460)
        }.frame(maxHeight: 200)
        Text("Total \(total) · \(minimum == maximum ? "exactly \(minimum)" : "\(minimum)–\(maximum)")")
            .font(.caption).monospacedDigit().foregroundStyle(.white.opacity(0.75))
        HStack(spacing: 16) {
            if prompt.canCancel == true { answer("Cancel", .boolean(false), primary: false) }
            answer("Confirm", .amounts(values)).disabled(total < minimum || total > maximum || !session.canAnswer)
        }
    }

    private func set(_ index: Int, _ value: Int, _ rows: [RulesPrompt.Amount]) {
        if amounts.count != rows.count { amounts = rows.map(\.defaultValue) }
        amounts[index] = value
    }

    private func cardRow(_ cards: [RulesCard], height: CGFloat, selectable: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(cards) { card in
                    if selectable {
                        Button { Task { await session.answer(.object(card.id)) } } label: { RulesChoiceCardFace(card: card, height: height) }
                            .buttonStyle(.plain)
                            .disabled(!session.canAnswer || session.prompt?.isCardSelectable(card.id) == false)
                            .opacity(session.prompt?.isCardSelectable(card.id) == false ? 0.45 : 1)
                            .accessibilityIdentifier("rules-prompt-card-\(card.id)")
                    } else { RulesChoiceCardFace(card: card, height: height) }
                }
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cards.isEmpty ? 0 : height + 24)
    }

    private func resetInputs() {
        number = session.prompt?.min ?? 0
        amounts = session.prompt?.amounts?.map(\.defaultValue) ?? []
        choiceSearch = ""
        minimized = false
    }

    private func answer(_ title: String, _ value: RulesAnswer, primary: Bool = true) -> some View {
        Button(title) { Task { await session.answer(value) } }
            .buttonStyle(RulesPillButtonStyle(primary: primary))
            .disabled(!session.canAnswer)
    }
}

/// Phone Play's Scryfall-backed card face, for engine card and pile choices.
struct RulesChoiceCardFace: View {
    let card: RulesCard
    var height: CGFloat = 128
    @State private var instance: CardInstance?

    var body: some View {
        VStack(spacing: 4) {
            if let instance {
                PhoneHandCardFace(card: instance, height: height, faceDown: card.faceDown)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.25)).frame(width: height * 63 / 88, height: height)
            }
        }
        .frame(width: height * 63 / 88 + 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.faceDown ? "Face-down card" : RulesText.plain(card.name ?? "Card"))
        .accessibilityAddTraits(.isButton)
        .task(id: card.id) {
            let catalog = RulesCardCatalog.shared
            let cached = await catalog.localCard(card)
            if let model = cached ?? (try? RulesPhoneAdapter.placeholder(name: card.name ?? "Card", typeLine: card.typeLine ?? "", rules: card.rules, manaCost: card.manaCost)) {
                instance = CardInstance(card: model, center: nil, ownerIdentifier: .a)
            }
            if cached == nil, let loaded = await catalog.card(card), !Task.isCancelled {
                instance = CardInstance(card: loaded, center: nil, ownerIdentifier: .a)
            }
        }
    }
}
