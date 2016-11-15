//
//  BatteryTypeSelectionTableViewController.swift
//  Loop
//
//  Created by Jerermy Lucas on 11/15/16 pattern derived from Nathan Racklyeft.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import UIKit


protocol BatteryTypeSelectionTableViewControllerDelegate: class {
    func batteryTypeSelectionTableViewControllerDidChangeSelectedIndex(_ controller: BatteryTypeSelectionTableViewController)
}


class BatteryTypeSelectionTableViewController: UITableViewController, IdentifiableClass {
    
    var options = [String]()
    
    var selectedIndex: Int? {
        didSet {
            if let oldValue = oldValue, oldValue != selectedIndex {
                tableView.cellForRow(at: IndexPath(row: oldValue, section: 0))?.accessoryType = .none
            }
            
            if let selectedIndex = selectedIndex, oldValue != selectedIndex {
                tableView.cellForRow(at: IndexPath(row: selectedIndex, section: 0))?.accessoryType = .checkmark
                
                delegate?.batteryTypeSelectionTableViewControllerDidChangeSelectedIndex(self)
            }
        }
    }
    
    var contextHelp: String?
    
    weak var delegate: BatteryTypeSelectionTableViewControllerDelegate?
    
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


extension BatteryTypeSelectionTableViewController {
    typealias T = BatteryTypeSelectionTableViewController
    
    static func insulinDataSource(_ value: BatteryChemistryType) -> T {
        let vc = T()
        
        vc.selectedIndex = value.rawValue
        vc.options = (0..<2).flatMap({ BatteryChemistryType(rawValue: $0) }).map { String(describing: $0) }
        vc.contextHelp = NSLocalizedString("Alkaline and Lithium batteries decay at differing rates.  Alkaline tend to have a linear voltage drop over time whereas lithium cell batteries tend to maintain voltage until the end of their lifespan.  Under normal usage in a Non-MySentry compatible Minimed (x22/x15) insulin pump running Loop, Alkaline batteries last approximately 4 to 5 days.  Lithium batteries last between 7 and 8 days. This selection will use different battery voltage decay rates for each of the battery chemistry types and alert the user when a battery is approximately 8 to 10 hours from failure.", comment: "Instructions on selecting battery chemistry type")
        
        return vc
    }
}
