//
//  SideTableViewController.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/15/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit
import Swiftfall
import RxSwift

class CardCell: UITableViewCell {
	@IBOutlet weak var cardImageView: UIImageView!
}

protocol PowerToughnessCellDelegate: class {
	func updateHeight()
}



class SideTableViewController: UITableViewController, PowerToughnessCellDelegate {

	enum SectionModel: Int {
		case card
		case cardStateOptions
		case control
	}
	
	enum RowModel: Int {
		case card
		case tapUntap
		case summoningSickness
		case powerToughness
		case flying
		case flip
		case remove
		
		var reuseIdentifier: String {
			switch self {
			case .card:
				return "CardCell"
			case .powerToughness:
				return "PickerCell"
			default:
				return "BasicOption"
			}
		}
	}
	
	
	weak var card: CardInstance? {
		didSet {
			if card != oldValue {
				tableView.reloadData()
			}
		}
	}
	
    override func viewDidLoad() {
        super.viewDidLoad()
    }
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		tableView.reloadData()
		tableView.contentOffset = .zero
		
		UIView.animate(withDuration: 0.15) {
			self.splitViewController?.viewControllers.first(where: { $0 != self })?.view.alpha = 0.5
		}
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		
		UIView.animate(withDuration: 0.15) {
			self.splitViewController?.viewControllers.first(where: { $0 != self })?.view.alpha = 1.0
		}
	}

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
		return sections().count
    }
	
	func sections() -> [SectionModel] {
		guard card != nil else {
			return []
		}
		
		return [.card, .cardStateOptions, .control]
	}
	
	func rows(in section: SectionModel) -> [RowModel] {
		switch section {
		case .card:
			return [.card]
		case .cardStateOptions:
			return [.flying, .powerToughness]
		case .control:
			return [.flip, .remove]
		}
	}
	
	func rowModel(for indexPath: IndexPath) -> RowModel? {
		let section = sections()[indexPath.section]
		return rows(in: section)[indexPath.row]
	}

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		guard let section = SectionModel(rawValue: section) else { return 0 }
		
		return rows(in: section).count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		guard let row = rowModel(for: indexPath) else { return UITableViewCell() }
		
		let cell = tableView.dequeueReusableCell(withIdentifier: row.reuseIdentifier, for: indexPath)

		switch row {
		case .card:
			guard let cell = cell as? CardCell else { break }
			guard let card = card else { break }
			
			cell.cardImageView.image = nil
			
			DispatchQueue.global(qos: .userInteractive).async {
				let image = card.card.image(type: .png)
				DispatchQueue.main.async {
					UIView.transition(with: cell.cardImageView,
					duration: 0.2,
					options: .transitionCrossDissolve,
					animations: {
						cell.cardImageView.image = image
					},
					completion: nil)
				}
			}
		case .tapUntap:
			guard let card = card else { break }
			cell.textLabel?.text = "Tapped"
			cell.accessoryType = card.isTapped.value ? .checkmark : .none
		case .flip:
			cell.textLabel?.text = "Flip"
			cell.accessoryType = .none
		case .remove:
			cell.textLabel?.text = "Remove"
			cell.accessoryType = .none
		case .summoningSickness:
			guard let card = card else { break }
			cell.textLabel?.text = "Summoning Sickness"
			cell.accessoryType = card.isSummoningSick.value ? .checkmark : .none
		case .flying:
			guard let card = card else { break }
			cell.textLabel?.text = "Flying"
			cell.accessoryType = card.isFlying.value ? .checkmark : .none
		case .powerToughness:
			guard let card = card else { break }
			guard let cell = cell as? PickerCell else { break }
			
			cell.cardInstance = card
			cell.delegate = self
		}
		
        return cell
    }
	
	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		guard let row = rowModel(for: indexPath) else { return }
		
		switch row {
		case .card:
			tableView.transform = self.tableView.transform.rotated(by: .pi)
		case .tapUntap:
			guard let card = card else { break }
			card.isTapped.toggle()
			tableView.cellForRow(at: indexPath)?.accessoryType = card.isTapped.value ? .checkmark : .none
		case .flip:
			card?.flip.onNext(())
		case .remove:
			card?.remove.onNext(())
			self.card = nil
		case .summoningSickness:
			guard let card = card else { break }
			card.isSummoningSick.toggle()
			tableView.cellForRow(at: indexPath)?.accessoryType = card.isSummoningSick.value ? .checkmark : .none
		case .flying:
			guard let card = card else { break }
			card.isFlying.accept(!card.isFlying.value)
			tableView.cellForRow(at: indexPath)?.accessoryType = card.isFlying.value ? .checkmark : .none
		case .powerToughness:
			break
		}
		
		tableView.deselectRow(at: indexPath, animated: true)
	}
	
	// MARK: PowerToughnessCellDelegate
	
	func updateHeight() {
		tableView.beginUpdates()
		tableView.endUpdates()
	}

    /*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
