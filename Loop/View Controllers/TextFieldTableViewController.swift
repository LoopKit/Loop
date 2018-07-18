//
//  TextFieldTableViewController.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/31/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import LoopKitUI
import HealthKit


/// Convenience static constructors used to contain common configuration
extension TextFieldTableViewController {
    typealias T = TextFieldTableViewController
    
    private static let valueNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()

        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return formatter
    }()

    static func transmitterID(_ value: String?) -> T {
        let vc = T()

        vc.placeholder = NSLocalizedString("Enter the 6-digit transmitter ID", comment: "The placeholder text instructing users how to enter a transmitter ID")
        vc.value = value
        vc.contextHelp = NSLocalizedString("The transmitter ID can be found printed on the back of the device, on the side of the box it came in, and from within the settings menus of the receiver and mobile app.", comment: "Instructions on where to find the transmitter ID")

        return vc
    }
}
