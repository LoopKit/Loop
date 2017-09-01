//
//  PumpIDTableViewController.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/30/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import UIKit
import MinimedKit
import LoopKit

protocol PumpIDTableViewControllerDelegate: TextFieldTableViewControllerDelegate {
    func pumpIDTableViewControllerDidChangePumpRegion(_ controller: PumpIDTableViewController)
}


extension PumpRegion {
    static let count = 2
}


final class PumpIDTableViewController: TextFieldTableViewController {

    /// The selected pump region
    var region: PumpRegion? {
        didSet {
            if let oldValue = oldValue, oldValue != region {
                tableView.cellForRow(at: IndexPath(row: oldValue.rawValue, section: Section.region.rawValue))?.accessoryType = .none
            }

            if let region = region, oldValue != region {
                tableView.cellForRow(at: IndexPath(row: region.rawValue, section: Section.region.rawValue))?.accessoryType = .checkmark
            }

            if let delegate = delegate as? PumpIDTableViewControllerDelegate {
                delegate.pumpIDTableViewControllerDidChangePumpRegion(self)
            }
        }
    }

    convenience init(pumpID: String?, region: PumpRegion?) {
        self.init(style: .grouped)

        self.region = region

        placeholder = NSLocalizedString("Enter the 6-digit pump ID", comment: "The placeholder text instructing users how to enter a pump ID")
        keyboardType = .numberPad
        value = pumpID
        contextHelp = NSLocalizedString("The pump ID can be found printed on the back, or near the bottom of the STATUS/Esc screen. It is the strictly numerical portion of the serial number (shown as SN or S/N).", comment: "Instructions on where to find the pump ID on a Minimed pump")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = UITableViewAutomaticDimension
    }

    // MARK: - Table view data source

    private enum Section: Int {
        case id
        case region

        static let count = 2
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .id:
            return super.tableView(tableView, numberOfRowsInSection: section)
        case .region:
            return PumpRegion.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .id:
            return super.tableView(tableView, cellForRowAt: indexPath)
        case .region:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") ?? UITableViewCell(style: .default, reuseIdentifier: "Cell")

            let region = PumpRegion(rawValue: indexPath.row)!

            cell.textLabel?.text = String(describing: region)
            cell.accessoryType = self.region == region ? .checkmark : .none
            
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .id:
            return super.tableView(tableView, titleForFooterInSection: section)
        case .region:
            return NSLocalizedString("The pump regioncan be found printed on the back as part of the model number (REF), for example: MMT-551NAB, or MMT-515LWWS. If the model number contains \"NA\" or \"CA\", then the region is North America. If if contains \"WW\", then the region is World-Wide.", comment: "Instructions on selecting the pump region")
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .id:
            break
        case .region:
            region = PumpRegion(rawValue: indexPath.row)
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }
}
