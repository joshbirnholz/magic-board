//
//  AppDelegate.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/12/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import MultipeerKit
import CardService

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
	
	let transceiver = MultipeerTransceiver()
  let webServer = WebServer(port: 8080)
    var phoneSession: PhoneGameSession?
    weak var boardController: BoardViewController?
    var usesPhoneSession: Bool { phoneSession != nil }
    var supportsEmbeddedCompanion: Bool { true }
    #if DEBUG
    var didPresentCompanionFixture = false
    #endif
    func sendCommand(_ command: Command) {
        if let phoneSession { phoneSession.send(command) }
        else { transceiver.broadcast(command) }
    }
	
	var role: Role = .board
	
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		// Scryfall Tagger lists (e.g. lands that enter tapped): refreshed weekly in the background.
		if NSClassFromString("XCTestCase") == nil, !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--phone-board") }) {
			OracleTags.shared.refreshIfNeeded()
		}
		// Override point for customization after application launch.
		
        #if DEBUG
        // Manual connection tests start with an empty address; recovery tests omit this flag
        // on relaunch to exercise the same saved-server auto-connect used by the app.
        if ProcessInfo.processInfo.arguments.contains("--rules-manual-connect") {
            UserDefaults.standard.removeObject(forKey: "rules.bridgeAddress")
        }
        let isolatedPhoneCheck = ProcessInfo.processInfo.arguments.contains { $0 == "--phone-board-fixture" || $0 == "--phone-companion-fixture" || $0 == "--rules-ui-test" || $0.hasPrefix("--phone-network-") }
        #else
        let isolatedPhoneCheck = false
        #endif
        if !OfflineGameLibrary.shared.games.isEmpty { CardService.shouldInitializeCards = false }
        if isolatedPhoneCheck || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            CardService.shouldInitializeCards = false
        } else { _ = CardService.shared }
		
		transceiver.resume()
    if !isolatedPhoneCheck && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
        webServer.start()
        // Card artwork isn't bundled; fetch whatever is missing as a step of the content-loading process
        // (after the card/rulings import when that also runs). Shown in the same progress window.
        OfflineGameLibrary.shared.downloadMissingArtworkIfNeeded()
    }
		UIApplication.shared.isIdleTimerDisabled = true
		
		return true
	}

	// MARK: UISceneSession Lifecycle

	func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
		// Called when a new scene session is being created.
		// Use this method to select a configuration to create the new scene with.
		return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
	}

	func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
		// Called when the user discards a scene session.
		// If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
		// Use this method to release any resources that were specific to the discarded scenes, as they will not return.
	}

	static var shared: AppDelegate {
		return UIApplication.shared.delegate as! AppDelegate
	}

}


extension AppDelegate {
    func phoneCardActions(_ card: CardInstance) -> [CardManualAction] {
        guard let session = phoneSession else { return [] }
        if session.mode == .rules {
            // Only when the engine would accept it (XMage refuses anything else).
            guard session.rulesAdapter?.canChoose(card.uuid) == true else { return [] }
            return [.init(title: "Choose / Activate", dismisses: true, perform: { session.send(.tap(card.uuid)) })]
        }
        var actions: [CardManualAction] = []
        if let item = session.game.stack.first(where: { $0.card?.uuid == card.uuid }) {
            if session.game.stack.last?.id == item.id { actions.append(.init(title: "Resolve from Stack", perform: { session.send(.resolve(item.id)) })) }
            actions.append(.init(title: "Copy", dismisses: true, perform: { session.send(.copyStackItem(item.id)) }))
            actions.append(.init(title: "Counter / Move to Graveyard", perform: { session.send(.counterStack(item.id)) }))
        } else if session.game.state.battlefield.value.contains(card) {
            if card.isCommander.value, card.ownerIdentifier == session.player {
                actions.append(.init(title: "Move to Command Zone", dismisses: true, perform: {
                    session.send(.moveToPlayer(card.uuid, .command, card.ownerIdentifier, bottom: false))
                }))
            }
            if session.game.attachments[card.uuid] != nil {
                actions.append(.init(title: "Unattach", perform: { session.send(.attach(card.uuid, nil)) }))
            }
            let game = session.game
            let mine = card.controllerIdentifier.value == session.player
            if mine, card.isPhoneCreature, game.attachments[card.uuid] == nil {
                let attacking = game.combat?.attackers.contains(card.uuid) == true
                if attacking {
                    actions.append(.init(title: "Remove from Combat", dismisses: true, perform: {
                        session.send(.attack(card.uuid, tap: !card.hasVigilance))
                    }))
                } else if game.attackingPlayer == nil || game.attackingPlayer == session.player {
                    // Attacking taps the creature unless it has vigilance, and starts combat.
                    actions.append(.init(title: "Attack", dismisses: true, perform: {
                        session.send(.attack(card.uuid, tap: !card.hasVigilance))
                    }))
                }
                if game.combat?.blockers[card.uuid] != nil {
                    actions.append(.init(title: "Stop Blocking", dismisses: true, perform: { session.send(.block(card.uuid, nil)) }))
                }
                if game.attackingPlayer == session.player {
                    // In combat, tapping a creature on the board toggles its attack; this taps it plainly.
                    actions.append(.init(title: card.isTapped.value ? "Untap" : "Tap", dismisses: true, perform: { session.send(.tap(card.uuid)) }))
                }
            }
        } else if session.game.canUse(card, player: session.player) {
            actions.append(.init(title: card.representation.isLand ? "Play Land" : "Play onto Stack", perform: {
                session.send(.play(card.uuid, face: nil, faceDown: false, tapped: false, directly: false))
            }))
        }
        return actions
    }

    private func presentPhoneController(_ alert: UIViewController) {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow),
              var presenter = window.rootViewController else { return }
        while let next = presenter.presentedViewController { presenter = next }
        alert.popoverPresentationController?.sourceView = presenter.view
        alert.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        presenter.present(alert, animated: true)
    }
}
