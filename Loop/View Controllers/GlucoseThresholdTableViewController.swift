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
        
        placeholder = NSLocalizedString("Enter glucose safety limit", comment: "The placeholder text instructing users to enter a glucose safety limit")
        keyboardType = .decimalPad
        contextHelp = NSLocalizedString("When current or forecasted glucose is below the glucose safety limit, Loop will not recommend a bolus, and will always recommend a temporary basal rate of 0 units per hour.", comment: "Explanation of glucose safety limit")

        let formatter = QuantityFormatter(for: glucoseUnit)

        unit = formatter.localizedUnitStringWithPlurality()

        if let threshold = threshold {
            value = formatter.numberFormatter.string(from: threshold)
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
