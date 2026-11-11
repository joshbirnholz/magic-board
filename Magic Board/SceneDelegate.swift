//
//  SceneDelegate.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/12/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import CardService

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

	var window: UIWindow?
	
	/// Floats above the app to show card database loading progress.
	private var loadingProgressWindow: CardLoadingProgressWindow?

	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
		// Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
		// If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
		// This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
		guard let windowScene = (scene as? UIWindowScene) else { return }
		loadingProgressWindow = CardLoadingProgressWindow(windowScene: windowScene)
	}

	func sceneDidDisconnect(_ scene: UIScene) {
		// Called as the scene is being released by the system.
		// This occurs shortly after the scene enters the background, or when its session is discarded.
		// Release any resources associated with this scene that can be re-created the next time the scene connects.
		// The scene may re-connect later, as its session was not neccessarily discarded (see `application:didDiscardSceneSessions` instead).
	}

	func sceneDidBecomeActive(_ scene: UIScene) {
		// Called when the scene has moved from an inactive state to an active state.
		// Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
	}

	func sceneWillResignActive(_ scene: UIScene) {
		// Called when the scene will move from an active state to an inactive state.
		// This may occur due to temporary interruptions (ex. an incoming phone call).
	}

	func sceneWillEnterForeground(_ scene: UIScene) {
		// Called as the scene transitions from the background to the foreground.
		// Use this method to undo the changes made on entering the background.
	}

	func sceneDidEnterBackground(_ scene: UIScene) {
		// Called as the scene transitions from the foreground to the background.
		// Use this method to save data, release shared resources, and store enough scene-specific state information
		// to restore the scene back to its current state.
	}


}

// MARK: - Card loading progress

/// A window above the app's content that shows a progress bar while the card database loads.
/// It never receives touches, so the app stays usable underneath it.
final class CardLoadingProgressWindow: UIWindow {
	
	private let progressViewController = CardLoadingProgressViewController()
	private var observers: [NSObjectProtocol] = []
	private var hideWorkItem: DispatchWorkItem?
	
	override init(windowScene: UIWindowScene) {
		super.init(windowScene: windowScene)
		windowLevel = .alert + 1
		backgroundColor = .clear
		isUserInteractionEnabled = false
		rootViewController = progressViewController
		isHidden = true
		
		let center = NotificationCenter.default
		observers = [
			center.addObserver(forName: .cardServiceInitializationProgressDidChange, object: nil, queue: .main) { [weak self] note in
				guard let progress = note.userInfo?["progress"] as? CardLoadingProgress else { return }
				self?.show(progress)
			},
			center.addObserver(forName: .cardServiceDidEndInitialization, object: nil, queue: .main) { [weak self] _ in
				self?.progressViewController.showFinished()
				self?.hide(after: 1.5)
			},
			center.addObserver(forName: .cardServiceInitializationDidFail, object: nil, queue: .main) { [weak self] note in
				let error = note.userInfo?["error"] as? Error
				self?.progressViewController.showFailure(error)
				self?.hide(after: 6)
			},
		]
		
		// A load may already be underway by the time the scene connects.
		if let progress = CardService.shared.initializationProgress {
			show(progress)
		}
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	deinit {
		observers.forEach(NotificationCenter.default.removeObserver)
	}
	
	override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
		nil
	}
	
	private func show(_ progress: CardLoadingProgress) {
		hideWorkItem?.cancel()
		hideWorkItem = nil
		progressViewController.update(progress)
		if isHidden {
			isHidden = false
			progressViewController.setCardVisible(true, animated: true)
		}
	}
	
	private func hide(after delay: TimeInterval) {
		hideWorkItem?.cancel()
		let workItem = DispatchWorkItem { [weak self] in
			self?.progressViewController.setCardVisible(false, animated: true) {
				self?.isHidden = true
			}
		}
		hideWorkItem = workItem
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
	}
}

private final class CardLoadingProgressViewController: UIViewController {
	
	private let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
	private let messageLabel = UILabel()
	private let percentLabel = UILabel()
	private let progressView = UIProgressView(progressViewStyle: .default)
	
	override func loadView() {
		view = UIView()
		view.backgroundColor = .clear
		view.isUserInteractionEnabled = false
		
		card.layer.cornerRadius = 14
		card.layer.cornerCurve = .continuous
		card.clipsToBounds = true
		card.translatesAutoresizingMaskIntoConstraints = false
		card.alpha = 0
		view.addSubview(card)
		
		messageLabel.font = .preferredFont(forTextStyle: .subheadline)
		messageLabel.adjustsFontForContentSizeCategory = true
		messageLabel.textColor = .label
		messageLabel.numberOfLines = 2
		
		percentLabel.font = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .regular)
		percentLabel.textColor = .secondaryLabel
		percentLabel.setContentHuggingPriority(.required, for: .horizontal)
		percentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
		
		let labels = UIStackView(arrangedSubviews: [messageLabel, percentLabel])
		labels.spacing = 8
		labels.alignment = .firstBaseline
		
		let stack = UIStackView(arrangedSubviews: [labels, progressView])
		stack.axis = .vertical
		stack.spacing = 8
		stack.translatesAutoresizingMaskIntoConstraints = false
		card.contentView.addSubview(stack)
		
		let preferredWidth = card.widthAnchor.constraint(equalToConstant: 360)
		preferredWidth.priority = .defaultHigh
		
		NSLayoutConstraint.activate([
			card.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
			card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			card.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
			preferredWidth,
			
			stack.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 12),
			stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -12),
			stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 16),
			stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -16),
		])
	}
	
	func update(_ progress: CardLoadingProgress) {
		loadViewIfNeeded()
		let fraction = Float(max(0, min(1, progress.fractionCompleted)))
		messageLabel.text = progress.message
		messageLabel.textColor = .label
		percentLabel.text = "\(Int((fraction * 100).rounded(.down)))%"
		percentLabel.isHidden = false
		progressView.isHidden = false
		progressView.progressTintColor = nil
		progressView.setProgress(fraction, animated: fraction > progressView.progress)
		view.accessibilityLabel = "\(progress.message) \(percentLabel.text ?? "")"
	}
	
	func showFinished() {
		loadViewIfNeeded()
		messageLabel.text = "Card database ready"
		percentLabel.isHidden = true
		progressView.setProgress(1, animated: true)
	}
	
	func showFailure(_ error: Error?) {
		loadViewIfNeeded()
		let detail = error.map { ": \($0.localizedDescription)" } ?? ""
		messageLabel.text = "Couldn't load cards\(detail)"
		messageLabel.textColor = .systemRed
		percentLabel.isHidden = true
		progressView.isHidden = true
		// The window may still be hidden if the load failed before reporting any progress.
		view.window?.isHidden = false
		setCardVisible(true, animated: true)
	}
	
	func setCardVisible(_ visible: Bool, animated: Bool, completion: (() -> Void)? = nil) {
		loadViewIfNeeded()
		let changes = {
			self.card.alpha = visible ? 1 : 0
			self.card.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: -12)
		}
		if visible && card.alpha == 0 {
			card.transform = CGAffineTransform(translationX: 0, y: -12)
		}
		guard animated else {
			changes()
			completion?()
			return
		}
		UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: changes) { _ in
			completion?()
		}
	}
}
