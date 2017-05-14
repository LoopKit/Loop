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

    func string(from number: Double, unit: String) -> String? {
        guard let stringValue = string(from: NSNumber(value: number)) else {
            return nil
        }

        return String(
            format: NSLocalizedString(
                "QUANTITY_VALUE_AND_UNIT",
                value: "%1$@ %2$@",
                comment: "Format string for combining localized numeric value and unit. (1: numeric value)(2: unit)"
            ),
            stringValue,
            unit
        )
    }

    func describingGlucose(_ value: Double, for unit: HKUnit) -> String? {
        return string(from: value, unit: unit.glucoseUnitDisplayString)
    }

    @nonobjc func describingGlucose(_ value: HKQuantity, for unit: HKUnit) -> String? {
        return describingGlucose(value.doubleValue(for: unit), for: unit)
    }

}
