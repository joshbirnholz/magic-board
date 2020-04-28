//
//  CountersViewController.swift
//  Magic Board
//
//  Created by Josh Birnholz on 3/5/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import UIKit
import RxSwift
import RxCocoa
import CardService

protocol CounterCellDelegate: class {
	func counterCell(_ cell: CounterCell, stepperValueChanged value: Int)
}

class NewCounterCell: UITableViewCell {
	
	@IBOutlet weak var plusOnePlusOneButton: UIButton!
	@IBOutlet weak var minusOneMinusOneButton: UIButton!
	@IBOutlet weak var loyaltyButton: UIButton!
	@IBOutlet weak var counterAButton: UIButton!
	@IBOutlet weak var counterBButton: UIButton!
	@IBOutlet weak var counterCButton: UIButton!
	@IBOutlet weak var counterDButton: UIButton!
	@IBOutlet weak var counterEButton: UIButton!
	
}

class CounterCell: UITableViewCell {
	weak var delegate: CounterCellDelegate?
	
	private var buttons: [UIButton] = [] {
		didSet {
			for subview in stackView.arrangedSubviews.dropFirst() {
				subview.removeFromSuperview()
			}

			for (button, (_, ability)) in zip(buttons, buttonValues) {
				let label = UILabel()
				
				let fontSize: CGFloat = 12
				let textFont = UIFont.systemFont(ofSize: fontSize)
				let italicFont = UIFont.italicSystemFont(ofSize: fontSize)
				
				let text: NSAttributedString = {
					let ability = ability.replacingOccurrences(of: "}{", with: "} {")
					let attributedString = NSMutableAttributedString(string: ability, attributes: [.font: textFont])
					
					let matches = ability.matches(forRegex: "\\((.*?)\\)")
					for match in matches {
						let range = NSRange(match.fullMatch.range, in: ability)
						attributedString.addAttribute(.font, value: italicFont, range: range)
					}
					
					for symbol in MTGSymbolName.allCases {
						let attachment = NSTextAttachment()
						attachment.image = symbol.image
						attachment.setImageHeight(height: fontSize * 0.8)
						let attachmentString = NSAttributedString(attachment: attachment)
						
						while let range = attributedString.string.range(of: symbol.rawValue) {
							attributedString.replaceCharacters(in: NSRange(range, in: attributedString.string), with: attachmentString)
						}
					}
					
					return attributedString
				}()
				
				label.attributedText = text
				label.textColor = .lightText
				label.numberOfLines = 0
				
				let stack = UIStackView(arrangedSubviews: [button, label])
				stack.alignment = .top
				stack.spacing = 8
				stack.axis = .horizontal
				
				stackView.addArrangedSubview(stack)
			}
		}
	}
	
	var buttonValues: [(cost: String, ability: String)] = [] {
		didSet {
			self.buttons = buttonValues.map { (cost, ability) in
				let button = UIButton(frame: CGRect(origin: .zero, size: CGSize(width: 60, height: 32)))
				button.widthAnchor.constraint(equalToConstant: 60).isActive = true
				button.layer.masksToBounds = true
				button.layer.cornerRadius = 8
				button.tintColor = .white
				
				button.backgroundColor = #colorLiteral(red: 0.9148453275, green: 0.9134820997, blue: 1, alpha: 0.1030732044)
				if cost == "0" || Int(cost) == nil {
//					button.backgroundColor = .clear
					button.isEnabled = false
				} else {
					button.backgroundColor = #colorLiteral(red: 0.9148453275, green: 0.9134820997, blue: 1, alpha: 0.1030732044)
				}
				
				button.setTitle(cost, for: .normal)
				button.addTarget(self, action: #selector(buttonPressed(_:)), for: .touchUpInside)
				
				return button
			}
		}
	}
	
	@IBOutlet weak var counterView: UIView!
	@IBOutlet weak var countLabel: UILabel!
	@IBOutlet weak var nameLabel: UILabel!
	@IBOutlet weak var stepper: UIStepper!
	@IBOutlet weak var stackView: UIStackView!
	
	@IBAction func stepperValueChanged(_ sender: UIStepper) {
		delegate?.counterCell(self, stepperValueChanged: Int(sender.value))
	}
	
	@objc private func buttonPressed(_ sender: UIButton) {
		guard let index = buttons.firstIndex(of: sender) else { return }
		
		let value = Int(buttonValues[index].cost) ?? 0
		
		stepper.value += Double(value)
		
		delegate?.counterCell(self, stepperValueChanged: Int(stepper.value))
	}
}

class CountersViewController: UITableViewController {
	
	struct CounterAndCount: Hashable {
		var counter: Counter
		var count: Int
	}
	
	enum SectionModel: Int, CaseIterable {
		case counters
		case newCounter
	}
	
	private let bag = DisposeBag()
	
	@IBOutlet var newCounterButtons: [UIButton]!
	
	var cardInstance: CardInstance! {
		didSet {
			navigationItem.title = cardInstance.representation.name
			tableView.reloadData()
		}
	}
	
	private class DataSource: UITableViewDiffableDataSource<SectionModel, CounterAndCount> {
		override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
			return true
		}
	}
	
	private lazy var dataSource = DataSource(tableView: tableView) { [weak self] (tableView, indexPath, counterAndCount) -> UITableViewCell? in
		guard let self = self else { return nil }
		guard let cell = tableView.dequeueReusableCell(withIdentifier: "CounterCell", for: indexPath) as? CounterCell else { return nil }
	
		cell.counterView.layer.masksToBounds = true
		cell.counterView.layer.cornerRadius = 17
		cell.counterView.backgroundColor = counterAndCount.counter.color
		
		cell.nameLabel.text = counterAndCount.counter.name
		
		cell.stepper.value = Double(counterAndCount.count)
		cell.countLabel.text = String(counterAndCount.count)
		
		if self.cardInstance.representation.typeLine?.lowercased().contains("planeswalker") == true && counterAndCount.counter == .loyalty {
			let regex = #"^([+-]?(?:\d+|X)): (.+)"#
			let matches = (self.cardInstance.representation.oracleText ?? "").replacingOccurrences(of: "−", with: "-").matches(forRegex: regex, options: .anchorsMatchLines)
			cell.buttonValues = matches.compactMap { fullMatch, groups in
				guard groups.count == 2 else { return nil }
				let cost = groups[0].value
				let ability = groups[1].value
				return (cost, ability)
			}
		} else {
			cell.buttonValues = []
		}
		
		cell.delegate = self
		
		return cell
		
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		dataSource.defaultRowAnimation = .fade
		
		cardInstance.counters
			.subscribe(onNext: { [weak self] counters in
				var snapshot = NSDiffableDataSourceSnapshot<SectionModel, CounterAndCount>()
				
				var countersAndCounts: [CounterAndCount] = []
				
				for counter in counters {
					if let index = countersAndCounts.firstIndex(where: { $0.counter == counter }) {
						countersAndCounts[index].count += 1
					} else {
						countersAndCounts.append(CounterAndCount(counter: counter, count: 1))
					}
				}
				
				if self?.cardInstance.representation.typeLine?.lowercased().contains("planeswalker") == true && !countersAndCounts.contains(where: { $0.counter == .loyalty }) {
					countersAndCounts.insert(CounterAndCount(counter: .loyalty, count: 0), at: 0)
				}
				
				if !countersAndCounts.isEmpty {
					snapshot.appendSections([.counters])
					snapshot.appendItems(countersAndCounts)
				}
				
				// Add unused counters to next section
				
//				var unusedCountersAndCounts: [CounterAndCount] = []
//				
//				for counter in Counter.allCases where !countersAndCounts.contains(where: { $0.counter == counter }) {
//					unusedCountersAndCounts.append(CounterAndCount(counter: counter, count: 0))
//				}
//				
//				if !unusedCountersAndCounts.isEmpty {
//					snapshot.appendSections([.newCounter])
//					snapshot.appendItems(unusedCountersAndCounts, toSection: .newCounter)
//				}
				
				self?.dataSource.apply(snapshot, animatingDifferences: false)
			}).disposed(by: bag)
		
		for button in newCounterButtons {
			if button.image(for: .normal) == nil {
				button.layer.cornerRadius = button.frame.width/2
				button.layer.masksToBounds = true
			}
			button.addTarget(self, action: #selector(newCounterButtonPressed(_:)), for: .touchUpInside)
		}
		
		newCounterButtons[0].backgroundColor = Counter.plusOnePlusOne.color
		newCounterButtons[1].backgroundColor = Counter.minusOneMinusOne.color
		
		let genericCounterCount = newCounterButtons.count-3
		for (button, counter) in zip(newCounterButtons.suffix(genericCounterCount), Counter.allCases.suffix(genericCounterCount)) {
			button.backgroundColor = counter.color
		}
	}
	
	@objc private func newCounterButtonPressed(_ sender: UIButton) {
		guard let index = newCounterButtons.firstIndex(of: sender) else { return }
		
		guard let counter = Counter(rawValue: index) else { return }
		
		add(counter)
	}
	
	private func add(_ counter: Counter) {
		cardInstance.counters.mutate { counters in
			counters.append(counter)
		}
		
		try? GameState.current.save()
	}
	
	override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		
		guard let counterAndCount = dataSource.itemIdentifier(for: indexPath) else { return nil }
 
		var actions: [UIContextualAction] = []
		
		let removeAllAction = UIContextualAction(style: .destructive, title: "Remove All") { [weak self] action, view, completionHandler in
			guard let self = self else {
				completionHandler(false)
				return
			}
			self.cardInstance.counters.mutate {
				$0.removeAll(where: { $0 == counterAndCount.counter })
			}
			completionHandler(true)
			try? GameState.current.save()
		}
		actions.append(removeAllAction)
		
		let doubleAction = UIContextualAction(style: .normal, title: "x2") { [weak self] action, view, completionHandler in
			guard let self = self else {
				completionHandler(false)
				return
			}
			self.cardInstance.counters.mutate {
				$0.append(contentsOf: [Counter](repeating: counterAndCount.counter, count: counterAndCount.count))
			}
			completionHandler(true)
			try? GameState.current.save()
		}
		doubleAction.backgroundColor = #colorLiteral(red: 0.3411764801, green: 0.6235294342, blue: 0.1686274558, alpha: 1)
		actions.append(doubleAction)
		
		let config = UISwipeActionsConfiguration(actions: actions)
		config.performsFirstActionWithFullSwipe = false
		return config
	}
	
}

extension CountersViewController: CounterCellDelegate {
	func counterCell(_ cell: CounterCell, stepperValueChanged value: Int) {
		guard let indexPath = tableView.indexPath(for: cell) else { return }
		
		guard let counterAndCount = dataSource.itemIdentifier(for: indexPath) else { return }
		
		cardInstance.counters.mutate { counters in
			counters.removeAll(where: { $0 == counterAndCount.counter })
			counters.append(contentsOf: [Counter](repeating: counterAndCount.counter, count: value))
		}
		
		try? GameState.current.save()
	}
}
