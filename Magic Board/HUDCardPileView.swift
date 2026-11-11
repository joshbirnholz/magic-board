//
//  HUDCardPileView.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/24/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa

class HUDCardPileView: UIView {
	
	private let bag = DisposeBag()
	
	@IBOutlet weak var numberLabel: UILabel!
	@IBOutlet weak var topCardImageView: UIImageView!
	@IBOutlet weak var titleLabel: UILabel!
	
	@IBOutlet var contentView: UIView!
	
	var pile: Pile! {
		didSet {
			self.titleLabel.text = pile.location.rawValue
			
			bind()
		}
	}
	
	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}
	
	private func commonInit() {
		Bundle.main.loadNibNamed("HUDCardPileView", owner: self, options: nil)
		addSubview(contentView)
		contentView.frame = self.bounds
		contentView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
		
		numberLabel.layer.shadowColor = UIColor.black.cgColor
		numberLabel.layer.shadowRadius = 3
		numberLabel.layer.shadowOpacity = 1.0
		numberLabel.layer.shadowOffset = CGSize(width: 0, height: 0)
		numberLabel.layer.masksToBounds = false
		
		topCardImageView.layer.cornerRadius = 3.5
		topCardImageView.layer.masksToBounds = true
	}
	
	private func bind() {
		pile.cards
			.observeOn(MainScheduler.instance)
			.subscribe(onNext: { [weak self] (cards) in
			guard let self = self else { return }
			self.numberLabel.text = String(cards.count)
			
			DispatchQueue.global(qos: .userInteractive).async {
				let image = self.pile.topCardImage
				DispatchQueue.main.async { [weak self] in
					self?.topCardImageView.image = image
				}
			}
		}).disposed(by: bag)
    
    pile.isTopCardRevealed
      .observeOn(MainScheduler.instance)
      .subscribe(onNext: { [weak self] (cards) in
      guard let self = self else { return }      
      DispatchQueue.global(qos: .userInteractive).async {
        let image = self.pile.topCardImage
        DispatchQueue.main.async { [weak self] in
          self?.topCardImageView.image = image
        }
      }
    }).disposed(by: bag)
	}
	
}


