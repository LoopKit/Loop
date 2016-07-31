//
//  TextFieldTableViewController.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/31/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import LoopKit


/// Convenience static constructors used to contain common configuration
extension TextFieldTableViewController {
    typealias T = TextFieldTableViewController

    private static let valueNumberFormatter: NSNumberFormatter = {
        let formatter = NSNumberFormatter()

        formatter.numberStyle = .DecimalStyle
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return formatter
    }()

    static func pumpID(value: String?) -> T {
        let vc = T()

        vc.placeholder = NSLocalizedString("Enter the 6-digit pump ID", comment: "The placeholder text instructing users how to enter a pump ID")
        vc.keyboardType = .NumberPad
        vc.value = value

        return vc
    }

    static func transmitterID(value: String?) -> T {
        let vc = T()

        vc.placeholder = NSLocalizedString("Enter the 6-digit transmitter ID", comment: "The placeholder text instructing users how to enter a pump ID")
        vc.value = value

        return vc
    }

    static func insulinActionDuration(value: NSTimeInterval?) -> T {
        let vc = T()

        vc.placeholder = NSLocalizedString("Enter a number of hours", comment: "The placeholder text instructing users how to enter an insulin action duration")
        vc.keyboardType = .DecimalPad

        if let insulinActionDuration = value {
            vc.value = valueNumberFormatter.stringFromNumber(insulinActionDuration.hours)
        }

        return vc
    }

    static func maxBasal(value: Double?) -> T {
        let vc = T()

        vc.placeholder = NSLocalizedString("Enter a rate in units per hour", comment: "The placeholder text instructing users how to enter a maximum basal rate")
        vc.keyboardType = .DecimalPad

        if let maxBasal = value {
            vc.value = valueNumberFormatter.stringFromNumber(maxBasal)
        }

        return vc
    }

    static func maxBolus(value: Double?) -> T {
        let vc = T()

        vc.placeholder = NSLocalizedString("Enter a number of units", comment: "The placeholder text instructing users how to enter a maximum bolus")
        vc.keyboardType = .DecimalPad

        if let maxBolus = value {
            vc.value = valueNumberFormatter.stringFromNumber(maxBolus)
        }

        return vc
    }
}
