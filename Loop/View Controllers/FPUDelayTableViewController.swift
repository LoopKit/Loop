 //
//  FPUDelayTableViewController.swift
//  Loop
//
//  Created by Robert Silvers on 10/17/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//
import Foundation

import UIKit
import LoopKitUI
import HealthKit


final class FPUDelayTableViewController: TextFieldTableViewController {

    init(fpuDelayVal: Double?) {

        super.init(style: .grouped)

        placeholder = NSLocalizedString("Enter Fat-Protein Delay in minutes", comment: "The placeholder text instructing users to enter an FPU Delay")
        keyboardType = .decimalPad
        contextHelp = NSLocalizedString("When fat and/or protein is entered as part of a meal, equivilant carbohydrates will be stored starting at the current time if this delay is set to 0, or starting after the delay specified. Values from 0 to 120 minutes are typical.", comment: "Explanation of delay")

        if let fpuDelayVal = fpuDelayVal {
            value = String(Int(fpuDelayVal)) // Don't show decimal.
        }

    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
