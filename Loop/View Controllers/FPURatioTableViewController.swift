//
//  FPURatioTableViewController.swift
//  Loop
//
//  Created by Robert Silvers on 10/17/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//
//  Fat-Protein Unit code by Robert Silvers, 10/2018.

import Foundation

import UIKit
import LoopKitUI
import HealthKit

final class FPURatioTableViewController: TextFieldTableViewController {
    
    init(fpuRatioVal: Double?) {
        
        super.init(style: .grouped)
        
        placeholder = NSLocalizedString("Enter Fat-Protein Ratio", comment: "The placeholder text instructing users to enter an FPU Ratio")
        keyboardType = .decimalPad
        contextHelp = NSLocalizedString("Fat-Protein Units are normally based on Fat + Protein calories / 100. The nominal value is 100, and Loop will provide fewer equivilant carbohydrates and insulin for fat and protein if this value is larger, or more if this value is smaller.", comment: "Explanation of FPU Ratio")
        
        if let fpuRatioVal = fpuRatioVal {
            value = String(Int(fpuRatioVal)) // Don't show decimal.
        }
        
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
