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
    static func glucoseFormatter(for unit: HKUnit) -> NumberFormatter {
        let numberFormatter = NumberFormatter()
        
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = unit.preferredFractionDigits
        numberFormatter.maximumFractionDigits = unit.preferredFractionDigits
        return numberFormatter
    }

    func describingGlucose(_ value: Double, for unit: HKUnit) -> String? {
        guard let stringValue = string(from: NSNumber(value: value)) else {
            return nil
        }

        return String(
            format: NSLocalizedString("GLUCOSE_VALUE_AND_UNIT",
                                      value: "%1$@ %2$@",
                                      comment: "Format string for combining localized glucose value and unit. (1: glucose value)(2: unit)"
            ),
            stringValue,
            unit.glucoseUnitDisplayString
        )
    }

    @nonobjc func describingGlucose(_ value: HKQuantity, for unit: HKUnit) -> String? {
        return describingGlucose(value.doubleValue(for: unit), for: unit)
    }

}
