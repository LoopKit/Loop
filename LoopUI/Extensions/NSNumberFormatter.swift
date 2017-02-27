//
//  NSNumberFormatter.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


extension NumberFormatter {
    public static func glucoseFormatter(for unit: HKUnit) -> NumberFormatter {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = unit.preferredFractionDigits
        numberFormatter.maximumFractionDigits = unit.preferredFractionDigits
        return numberFormatter
    }
}
