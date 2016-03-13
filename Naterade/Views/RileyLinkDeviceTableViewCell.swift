//
//  RileyLinkDeviceTableViewCell.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import CoreBluetooth
import UIKit

class RileyLinkDeviceTableViewCell: UITableViewCell {

    @IBOutlet weak var connectSwitch: UISwitch!

    @IBOutlet weak var nameLabel: UILabel!

    @IBOutlet weak var signalLabel: UILabel!

    func configureCellWithName(name: String?, signal: Int?, peripheralState: CBPeripheralState?) {
        nameLabel.text = name
        signalLabel.text = signal != nil ? "\(signal!) dB" : nil

        if let state = peripheralState {
            switch state {
            case .Connected:
                connectSwitch.on = true
                connectSwitch.enabled = true
            case .Connecting:
                connectSwitch.on = true
                connectSwitch.enabled = false
            case .Disconnected:
                connectSwitch.on = false
                connectSwitch.enabled = true
            case .Disconnecting:
                connectSwitch.on = false
                connectSwitch.enabled = false
            }
        } else {
            connectSwitch.hidden = true
        }

    }

    override func prepareForReuse() {
        super.prepareForReuse()

        connectSwitch.removeTarget(nil, action: nil, forControlEvents: .ValueChanged)
    }

}
