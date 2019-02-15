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

    func string(from number: Double) -> String? {
        return string(from: NSNumber(value: number))
    }

    func string(from quantity: HKQuantity, unit: HKUnit) -> String? {
        return string(from: quantity.doubleValue(for: unit), unit: unit)
    }

    func string(from number: Double, unit: HKUnit) -> String? {
        return string(from: number, unit: unit.localizedShortUnitString)
    }

    func string(from number: Double, unit: String) -> String? {
        guard let stringValue = string(from: number) else {
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

    func decibleString(from decibles: Int?) -> String? {
        if let decibles = decibles {
            return string(from: Double(decibles), unit: NSLocalizedString("dB", comment: "The short unit display string for decibles"))
        } else {
            return nil
        }
    }
}
