//
//  PickerCell.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/16/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import Foundation
import UIKit
import RxSwift

class PickerCell: UITableViewCell, UIPickerViewDataSource, UIPickerViewDelegate {
	@IBOutlet private weak var picker: UIPickerView!
	@IBOutlet weak var boxEnabledSwitch: UISwitch!
	
	weak var delegate: PowerToughnessCellDelegate?
	
	private let bag = DisposeBag()
	
	weak var cardInstance: CardInstance? {
		didSet {
			guard let cardInstance = cardInstance else {
				boxEnabledSwitch.isEnabled = false
				return
			}
			
			update()
			
			var powerRange = PickerCell.defaultRange.map(String.init)
			var toughnessRange = PickerCell.defaultRange.map(String.init)
			
			if powerRange.contains(where: { $0 == cardInstance.card.power }) {
				// Power is a number that is already in the default range (0...100)
				// Do nothing
			} else if let numPower = cardInstance.card.power.flatMap(Int.init) {
				// Power is a number, not in the default range.
				// Add it in, sorted into the right spot
				var newRange = powerRange.compactMap(Int.init)
				newRange.append(numPower)
				newRange.sort(by: <)
				powerRange = newRange.map(String.init)
			} else if let power = cardInstance.card.power {
				// Power is not a number, like "X" or "*"
				powerRange.append(power)
			}
			
			if toughnessRange.contains(where: { $0 == cardInstance.card.toughness }) {
				// Toughness is a number that is already in the default range (0...100)
				// Do nothing
			} else if let numToughness = cardInstance.card.toughness.flatMap(Int.init) {
				// Toughness is a number, not in the default range.
				// Add it in, sorted into the right spot
				var newRange = powerRange.compactMap(Int.init)
				newRange.append(numToughness)
				newRange.sort(by: <)
				toughnessRange = newRange.map(String.init)
			} else if let toughness = cardInstance.card.toughness {
				// Toughness is not a number, like "X" or "*"
				// Add it in, at the bottom.
				toughnessRange.append(toughness)
			}
			
			self.powerRange = powerRange
			self.toughnessRange = toughnessRange
			
			let powerIndex = powerRange.firstIndex(of: cardInstance.power.value) ?? 0
			let toughnessIndex = toughnessRange.firstIndex(of: cardInstance.toughness.value) ?? 0
			picker.selectRow(powerIndex, inComponent: Component.power.rawValue, animated: false)
			picker.selectRow(toughnessIndex, inComponent: Component.toughness.rawValue, animated: false)
		}
	}
	
	enum Component: Int {
		case power, toughness
	}
	
	@IBAction func switchValueChanged(_ sender: UISwitch) {
		cardInstance?.isPowerToughnessVisible.accept(boxEnabledSwitch.isOn)
		update()
	}
	
	private func update() {
		guard let cardInstance = cardInstance else {
			boxEnabledSwitch.isEnabled = false
			return
		}
		boxEnabledSwitch.isOn = cardInstance.isPowerToughnessVisible.value
		picker.isHidden = !cardInstance.isPowerToughnessVisible.value
		delegate?.updateHeight()
	}
	
	private static let defaultRange = Array((0 ... 100).reversed())
	
	private var powerRange: [String] = [] {
		didSet {
			picker.reloadComponent(Component.power.rawValue)
		}
	}
	
	private var toughnessRange: [String] = [] {
		didSet {
			picker.reloadComponent(Component.toughness.rawValue)
		}
	}
	
	// MARK: UIPickerViewDataSource
	
	func numberOfComponents(in pickerView: UIPickerView) -> Int {
		2
	}
	
	func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
		guard let component = Component(rawValue: component) else { return 0 }
		switch component {
		case .power: return powerRange.count
		case .toughness: return toughnessRange.count
		}
	}
	
	// MARK: UIPickerViewDelegate
	
	func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
		guard let component = Component(rawValue: component) else { return }
		guard let cardInstance = cardInstance else { return }

		switch component {
		case .power:
			cardInstance.power.accept(powerRange[row])
		case .toughness:
			cardInstance.toughness.accept(toughnessRange[row])
		}
	}
	
	func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
		guard let component = Component(rawValue: component) else { return nil }
		
		switch component {
		case .power: return powerRange[row]
		case .toughness: return toughnessRange[row]
		}
	}
}
