//
//  QuantityRangeEntry.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import UIKit


class QuantityRangeEntry: LessonSectionProviding {
    var headerTitle: String? {
        return numberRange.headerTitle
    }

    var footerTitle: String? {
        return numberRange.footerTitle
    }

    var cells: [LessonCellProviding] {
        return numberRange.cells
    }

    var minValue: HKQuantity? {
        if let minValue = numberRange.minValue?.doubleValue {
            return HKQuantity(unit: unit, doubleValue: minValue)
        } else {
            return nil
        }
    }

    var maxValue: HKQuantity? {
        if let maxValue = numberRange.maxValue?.doubleValue {
            return HKQuantity(unit: unit, doubleValue: maxValue)
        } else {
            return nil
        }
    }

    var range: Range<HKQuantity>? {
        guard let minValue = minValue, let maxValue = maxValue else {
            return nil
        }

        return minValue..<maxValue
    }

    var closedRange: ClosedRange<HKQuantity>? {
        guard let minValue = minValue, let maxValue = maxValue else {
            return nil
        }

        return minValue...maxValue
    }

    private let numberRange: NumberRangeEntry

    let quantityFormatter: QuantityFormatter

    let unit: HKUnit

    init(headerTitle: String?, minValue: HKQuantity?, maxValue: HKQuantity?, quantityFormatter: QuantityFormatter, unit: HKUnit, keyboardType: UIKeyboardType) {
        self.quantityFormatter = quantityFormatter
        self.unit = unit

        numberRange = NumberRangeEntry(
            headerTitle: headerTitle,
            minValue: (minValue?.doubleValue(for: unit)).map(NSNumber.init(value:)),
            maxValue: (maxValue?.doubleValue(for: unit)).map(NSNumber.init(value:)),
            formatter: quantityFormatter.numberFormatter,
            unitString: quantityFormatter.string(from: unit),
            keyboardType: keyboardType
        )
    }

    internal class func glucoseRange(minValue: HKQuantity, maxValue: HKQuantity, quantityFormatter: QuantityFormatter, unit: HKUnit) -> QuantityRangeEntry {
        return QuantityRangeEntry(
            headerTitle: NSLocalizedString("Range", comment: "Section title for glucose range"),
            minValue: minValue,
            maxValue: maxValue,
            quantityFormatter: quantityFormatter,
            unit: unit,
            keyboardType: unit == .milligramsPerDeciliter ? .numberPad : .decimalPad
        )
    }
}
