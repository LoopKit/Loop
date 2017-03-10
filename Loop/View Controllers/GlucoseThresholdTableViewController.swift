//
//  GlucoseThresholdTableViewController.swift
//  Loop
//
//  Created by Pete Schwamb on 1/1/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation

import UIKit
import LoopKit
import HealthKit


final class GlucoseThresholdTableViewController: TextFieldTableViewController {
    
    public let glucoseUnit: HKUnit
    
    init(threshold: Double?, glucoseUnit: HKUnit) {
        self.glucoseUnit = glucoseUnit
        
        super.init(style: .grouped)
        
        placeholder = NSLocalizedString("Enter minimum BG guard", comment: "The placeholder text instructing users to enter a minimum BG guard")
        keyboardType = .decimalPad
        contextHelp = NSLocalizedString("When current or forecasted BG is below miminum BG guard, Loop will not recommend a bolus, and will issue temporary basal rates of 0U/hr.", comment: "Instructions on entering minimum BG threshold")
        
        unit = glucoseUnit.glucoseUnitDisplayString

        if let threshold = threshold {
            value = NumberFormatter.glucoseFormatter(for: glucoseUnit).string(from: NSNumber(value: threshold))
        }

    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
