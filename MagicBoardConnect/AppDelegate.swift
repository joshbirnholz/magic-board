//
//  AppDelegate.swift
//  MagicBoardConnect
//
//  Created by Josh Birnholz on 3/8/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import MultipeerKit
import CardService

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

	let transceiver = MultipeerTransceiver()
	
	var role: Role = .player1

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		// Override point for customization after application launch.
		
		CardService.shouldInitializeCards = false
		
		transceiver.resume()
		
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

