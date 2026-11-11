//
//  PlayerSelectViewController.swift
//  MagicBoardConnect
//
//  Created by Josh Birnholz on 3/9/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa

class PlayerSelectViewController: UIViewController {
	
	private let bag = DisposeBag()

	@IBOutlet weak var player1Button: UIButton!
	@IBOutlet weak var player2Button: UIButton!
	
	override func viewDidLoad() {
        super.viewDidLoad()

		GameState.current.player1.name
			.bind(to: player1Button.rx.title(for: .normal))
			.disposed(by: bag)
		
		GameState.current.player2.name
			.bind(to: player2Button.rx.title(for: .normal))
		.disposed(by: bag)
    }
    
	@IBAction func player1ButtonPressed(_ sender: Any) {
		AppDelegate.shared.role = .player1
		showHand()
	}
	
	@IBAction func player2ButtonPressed(_ sender: Any) {
		AppDelegate.shared.role = .player2
		showHand()
	}
	
	func showHand() {
		guard let viewController = storyboard?.instantiateViewController(identifier: "ContainerViewController") else { return }
		
		viewController.modalPresentationStyle = .fullScreen
		
//		navigationController?.setViewControllers([pileViewController], animated: true)
		present(viewController, animated: true, completion: nil)
	}
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
