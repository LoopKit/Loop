//
//  RadioSelectionTableViewController.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/26/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import MinimedKit

protocol RadioSelectionTableViewControllerDelegate: class {
    func radioSelectionTableViewControllerDidChangeSelectedIndex(_ controller: RadioSelectionTableViewController)
}


class RadioSelectionTableViewController: UITableViewController, IdentifiableClass {

    var options = [String]()

    var selectedIndex: Int? {
        didSet {
            if let oldValue = oldValue, oldValue != selectedIndex {
                tableView.cellForRow(at: IndexPath(row: oldValue, section: 0))?.accessoryType = .none
            }

            if let selectedIndex = selectedIndex, oldValue != selectedIndex {
                tableView.cellForRow(at: IndexPath(row: selectedIndex, section: 0))?.accessoryType = .checkmark

                delegate?.radioSelectionTableViewControllerDidChangeSelectedIndex(self)
            }
        }
    }

    var contextHelp: String?

    weak var delegate: RadioSelectionTableViewControllerDelegate?

    convenience init() {
        self.init(style: .grouped)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return options.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") ?? UITableViewCell(style: .default, reuseIdentifier: "Cell")

        cell.textLabel?.text = options[indexPath.row]
        cell.accessoryType = selectedIndex == indexPath.row ? .checkmark : .none

        return cell
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return contextHelp
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedIndex = indexPath.row

        tableView.deselectRow(at: indexPath, animated: true)
    }
}


extension RadioSelectionTableViewController {
    typealias T = RadioSelectionTableViewController

    static func insulinDataSource(_ value: InsulinDataSource) -> T {
        let vc = T()

        vc.selectedIndex = value.rawValue
        vc.options = (0..<2).flatMap({ InsulinDataSource(rawValue: $0) }).map { String(describing: $0) }
        vc.contextHelp = NSLocalizedString("Insulin delivery can be determined from the pump by either interpreting the event history or comparing the reservoir volume over time. Reading event history allows for a more accurate status graph and uploading up-to-date treatment data to Nightscout, at the cost of faster pump battery drain and the possibility of a higher radio error rate compared to reading only reservoir volume. If the selected source cannot be used for any reason, the system will attempt to fall back to the other option.", comment: "Instructions on selecting an insulin data source")

        return vc
    }

    static func batteryChemistryType(_ value: BatteryChemistryType) -> T {
        let vc = T()

        vc.selectedIndex = value.rawValue
        vc.options = (0..<2).flatMap({ BatteryChemistryType(rawValue: $0) }).map { String(describing: $0) }
        vc.contextHelp = NSLocalizedString("Alkaline and Lithium batteries decay at differing rates. Alkaline tend to have a linear voltage drop over time whereas lithium cell batteries tend to maintain voltage until halfway through their lifespan. Under normal usage in a Non-MySentry compatible Minimed (x22/x15) insulin pump running Loop, Alkaline batteries last approximately 4 to 5 days. Lithium batteries last between 1-2 weeks. This selection will use different battery voltage decay rates for each of the battery chemistry types and alert the user when a battery is approximately 8 to 10 hours from failure.", comment: "Instructions on selecting battery chemistry type")

        return vc
    }

}
