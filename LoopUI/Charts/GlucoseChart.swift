//
//  GlucoseChart.swift
//  LoopUI
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import SwiftCharts


public class GlucoseChart {
    public init() {
    }

    public var glucoseUnit: HKUnit = .milligramsPerDeciliter {
        didSet {
            if glucoseUnit != oldValue {
                // Regenerate the glucose display points
                let oldRange = glucoseDisplayRange
                glucoseDisplayRange = oldRange
            }
        }
    }

    public var glucoseDisplayRange: ClosedRange<HKQuantity>? {
        didSet {
            if let range = glucoseDisplayRange {
                glucoseDisplayRangePoints = [
                    ChartPoint(x: ChartAxisValue(scalar: 0), y: ChartAxisValueDouble(range.lowerBound.doubleValue(for: glucoseUnit))),
                    ChartPoint(x: ChartAxisValue(scalar: 0), y: ChartAxisValueDouble(range.upperBound.doubleValue(for: glucoseUnit)))
                ]
            } else {
                glucoseDisplayRangePoints = []
            }
        }
    }

    public private(set) var glucoseDisplayRangePoints: [ChartPoint] = []

    func glucosePointsFromValues(_ glucoseValues: [GlucoseValue]) -> [ChartPoint] {
        let unitFormatter = QuantityFormatter()
        unitFormatter.unitStyle = .short
        unitFormatter.setPreferredNumberFormatter(for: glucoseUnit)
        let unitString = unitFormatter.string(from: glucoseUnit)
        let dateFormatter = DateFormatter(timeStyle: .short)

        return glucoseValues.map {
            return ChartPoint(
                x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                y: ChartAxisValueDoubleUnit($0.quantity.doubleValue(for: glucoseUnit), unitString: unitString, formatter: unitFormatter.numberFormatter)
            )
        }
    }
}
