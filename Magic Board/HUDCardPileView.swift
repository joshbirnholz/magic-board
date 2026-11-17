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
	
	private var bag = DisposeBag()
    private var phonePreviewHeight: NSLayoutConstraint?
    private var phonePreviewCenter: NSLayoutConstraint?
    private var phoneTitleGap: NSLayoutConstraint?
    private var phoneCountInset: NSLayoutConstraint?
	
	@IBOutlet weak var numberLabel: UILabel!
	@IBOutlet weak var topCardImageView: UIImageView!
	@IBOutlet weak var titleLabel: UILabel!
	
	@IBOutlet var contentView: UIView!
	
	var pile: Pile! {
		didSet {
			self.titleLabel.text = pile.location.rawValue
			
            if let previous = oldValue, previous.cards === pile.cards, previous.isTopCardRevealed === pile.isTopCardRevealed { return }
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
	
    /// Give every pile the same preview geometry, independent of image pixels.
    func configurePhoneLayout(previewHeight: CGFloat, scale: CGFloat) {
        if phonePreviewHeight == nil {
            NSLayoutConstraint.deactivate(contentView.constraints)
            if let stack = topCardImageView.superview as? UIStackView {
                let items: [UIView] = [topCardImageView, titleLabel]
                for item in items {
                    stack.removeArrangedSubview(item)
                    item.removeFromSuperview()
                    contentView.addSubview(item)
                }
                stack.removeFromSuperview()
            }
            phonePreviewHeight = topCardImageView.heightAnchor.constraint(equalToConstant: previewHeight)
            phonePreviewCenter = topCardImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
            phoneTitleGap = titleLabel.topAnchor.constraint(equalTo: topCardImageView.bottomAnchor)
            phoneCountInset = numberLabel.bottomAnchor.constraint(equalTo: topCardImageView.bottomAnchor)
            NSLayoutConstraint.activate([
                phonePreviewHeight!, phonePreviewCenter!, phoneTitleGap!, phoneCountInset!,
                topCardImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                titleLabel.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -4),
                numberLabel.centerXAnchor.constraint(equalTo: topCardImageView.centerXAnchor),
                numberLabel.widthAnchor.constraint(equalTo: topCardImageView.widthAnchor)
            ])
            contentView.bringSubviewToFront(numberLabel)
            numberLabel.adjustsFontSizeToFitWidth = true
            numberLabel.minimumScaleFactor = 0.5
        }
        let gap = 2 * scale
        phonePreviewHeight?.constant = previewHeight
        phonePreviewCenter?.constant = -(titleLabel.font.lineHeight + gap) / 2
        phoneTitleGap?.constant = gap
        phoneCountInset?.constant = -1.5 * scale
        topCardImageView.layer.cornerRadius = previewHeight * 63 / 88 * 0.045
    }

	/// Phone Play: whether this phone's player may see the library's top card (kept revealed to
	/// one or both players); nil uses the pile's own flag.
	var revealsTopCardOverride: Bool? {
		didSet { if oldValue != revealsTopCardOverride { refreshTopImage() } }
	}

	private var currentTopImage: UIImage? {
		if revealsTopCardOverride == true, let top = pile.cards.value.last { return top.representation.image(type: .normal) }
		return pile.topCardImage
	}

	private func refreshTopImage() {
		guard pile != nil else { return }
		DispatchQueue.global(qos: .userInteractive).async {
			let image = self.currentTopImage
			DispatchQueue.main.async { [weak self] in self?.topCardImageView.image = image }
		}
	}

	private func bind() {
        bag = DisposeBag()
		pile.cards
			.observeOn(MainScheduler.instance)
			.subscribe(onNext: { [weak self] (cards) in
			guard let self = self else { return }
			self.numberLabel.text = String(cards.count)
			
			DispatchQueue.global(qos: .userInteractive).async {
				let image = self.currentTopImage
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
        let image = self.currentTopImage
        DispatchQueue.main.async { [weak self] in
          self?.topCardImageView.image = image
        }
      }
    }).disposed(by: bag)
	}
	
}


