import SwiftUI
import UIKit

/// Where the app goes from the start screen.
enum AppDestination {
    /// The classic shared board (iPad only).
    case board
    /// Host a nearby two-phone game, optionally resuming the saved one.
    case host(resume: Bool)
    /// Join a nearby game hosted on another phone.
    case join
    /// Use this device as a hand for a board running elsewhere (Board Connect screens).
    case hand
}

/// Owns the window's root: the start screen, or the board opened for a destination.
@MainActor
enum AppRouter {
    static weak var window: UIWindow?

    /// UI tests and network fixtures launch straight into the board.
    static var launchesDirectlyIntoBoard: Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--phone-") }
    }

    static var hasSavedHostedGame: Bool {
        FileManager.default.fileExists(atPath: PhoneGameSession.saveURL.path)
    }

    static func showStart(animated: Bool = true) {
        guard let window else { return }
        let host = UIHostingController(rootView: StartMenuView(choose: { open($0) }))
        setRoot(host, in: window, animated: animated)
    }

    static func open(_ destination: AppDestination) {
        guard let window,
              let board = UIStoryboard(name: "Board", bundle: nil).instantiateInitialViewController() as? BoardViewController else { return }
        board.pendingDestination = destination
        setRoot(board, in: window, animated: true)
    }

    private static func setRoot(_ controller: UIViewController, in window: UIWindow, animated: Bool) {
        window.rootViewController?.dismiss(animated: false)
        guard animated else { window.rootViewController = controller; return }
        UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve) {
            UIView.performWithoutAnimation { window.rootViewController = controller }
        }
    }
}

struct StartMenuView: View {
    let choose: (AppDestination) -> Void
    @State private var askResume = false

    var body: some View {
        NavigationStack {
            List {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Section {
                        row("Magic Board", "Play on this iPad's shared board", "rectangle.split.2x1") { choose(.board) }
                    }
                }
                Section {
                    row("Host Game", "Start a game other phones can join nearby", "antenna.radiowaves.left.and.right") {
                        if AppRouter.hasSavedHostedGame { askResume = true } else { choose(.host(resume: false)) }
                    }
                    .accessibilityIdentifier("start-host")
                    row("Join Game", "Join a game hosted on a nearby phone", "person.2") { choose(.join) }
                        .accessibilityIdentifier("start-join")
                }
                Section {
                    row("Connect as Hand", "Use this device as Player 1's or Player 2's hand", "hand.raised") { choose(.hand) }
                        .accessibilityIdentifier("start-hand")
                }
            }
            .navigationTitle("Magic Board")
            .confirmationDialog("Host Game", isPresented: $askResume, titleVisibility: .visible) {
                Button("Resume Saved Game") { choose(.host(resume: true)) }
                Button("New Game") { choose(.host(resume: false)) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A saved game is available.")
            }
        }
    }

    private func row(_ title: String, _ subtitle: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Color(uiColor: .label))
                    Text(subtitle).font(.subheadline).foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            } icon: {
                Image(systemName: symbol)
            }
            .padding(.vertical, 6)
        }
    }
}
