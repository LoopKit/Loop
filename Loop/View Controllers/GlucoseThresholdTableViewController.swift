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
    
    public let glucoseUnits: HKUnit
    
    private static let valueNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        
        return formatter
    }()

    init(threshold: Double?, glucoseUnits: HKUnit) {
        self.glucoseUnits = glucoseUnits
        
        super.init(style: .grouped)
        
        placeholder = NSLocalizedString("Enter minimum BG guard", comment: "The placeholder text instructing users to enter a minimum BG guard")
        keyboardType = .decimalPad
        contextHelp = NSLocalizedString("When current or forecasted BG is below miminum BG guard, Loop will not recommend a bolus, and will issue temporary basal rates of 0U/hr.", comment: "Instructions on entering minimum BG threshold")
        
        unit = glucoseUnits.glucoseUnitDisplayString
        
        if let threshold = threshold {
            value = GlucoseThresholdTableViewController.valueNumberFormatter.string(from: NSNumber(value: threshold))
        }

    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
