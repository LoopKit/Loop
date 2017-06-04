//
//  TextFieldTableViewController.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/31/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import LoopKit
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

    static func pumpID(_ value: String?) -> T {
        let vc = T()

        vc.placeholder = NSLocalizedString("Enter the 6-digit pump ID", comment: "The placeholder text instructing users how to enter a pump ID")
        vc.keyboardType = .numberPad
        vc.value = value
        vc.contextHelp = NSLocalizedString("The pump ID can be found printed on the back, or near the bottom of the STATUS/Esc screen. It is the strictly numerical portion of the serial number (shown as SN or S/N).", comment: "Instructions on where to find the pump ID on a Minimed pump")

        return vc
    }

    static func transmitterID(_ value: String?) -> T {
        let vc = T()

        vc.placeholder = NSLocalizedString("Enter the 6-digit transmitter ID", comment: "The placeholder text instructing users how to enter a pump ID")
        vc.value = value
        vc.contextHelp = NSLocalizedString("The transmitter ID can be found printed on the back of the device, on the side of the box it came in, and from within the settings menus of the G5 receiver and mobile app.", comment: "Instructions on where to find the transmitter ID")

        return vc
    }

    static func insulinActionDuration(_ value: TimeInterval?) -> T {
        let vc = T()

        vc.placeholder = NSLocalizedString("Enter a number of hours", comment: "The placeholder text instructing users how to enter an insulin action duration")
        vc.keyboardType = .decimalPad
        vc.unit = NSLocalizedString("hours", comment: "The unit string for hours")

        if let insulinActionDuration = value {
            vc.value = valueNumberFormatter.string(from: NSNumber(value: insulinActionDuration.hours))
        }

        return vc
    }

    static func maxBasal(_ value: Double?) -> T {
        let vc = T()

        vc.placeholder = NSLocalizedString("Enter a rate in units per hour", comment: "The placeholder text instructing users how to enter a maximum basal rate")
        vc.keyboardType = .decimalPad
        vc.unit = NSLocalizedString("U/hour", comment: "The unit string for units per hour")

        if let maxBasal = value {
            vc.value = valueNumberFormatter.string(from: NSNumber(value: maxBasal))
        }

        return vc
    }

    static func maxBolus(_ value: Double?) -> T {
        let vc = T()

        vc.placeholder = NSLocalizedString("Enter a number of units", comment: "The placeholder text instructing users how to enter a maximum bolus")
        vc.keyboardType = .decimalPad
        vc.unit = NSLocalizedString("Units", comment: "The unit string for units")

        if let maxBolus = value {
            vc.value = valueNumberFormatter.string(from: NSNumber(value: maxBolus))
        }

        return vc
    }    
}
