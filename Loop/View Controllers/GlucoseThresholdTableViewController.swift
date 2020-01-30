//
//  GlucoseThresholdTableViewController.swift
//  Loop
//
//  Created by Pete Schwamb on 1/1/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import UIKit

final class GlucoseThresholdTableViewController: TextFieldTableViewController {
    
    public let glucoseUnit: HKUnit
    
    init(threshold: Double?, glucoseUnit: HKUnit) {
        self.glucoseUnit = glucoseUnit
        
        super.init(style: .grouped)
        
        placeholder = NSLocalizedString("Enter suspend threshold", comment: "The placeholder text instructing users to enter a suspend treshold")
        keyboardType = .decimalPad
        contextHelp = NSLocalizedString("When current or forecasted glucose is below the suspend threshold, Loop will not recommend a bolus, and will always recommend a temporary basal rate of 0 units per hour.", comment: "Explanation of suspend threshold")

        let formatter = QuantityFormatter()
        formatter.setPreferredNumberFormatter(for: glucoseUnit)

        unit = formatter.string(from: glucoseUnit)

        if let threshold = threshold {
            value = formatter.numberFormatter.string(from: threshold)
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
