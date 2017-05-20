//
//  StatusChartManager+LoopKit.swift
//  Loop
//
//  Created by Nate Racklyeft on 2/15/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import HealthKit

import CarbKit
import GlucoseKit
import InsulinKit
import LoopKit
import SwiftCharts
import LoopUI

extension StatusChartsManager {

    private var dateFormatter: DateFormatter {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        return timeFormatter
    }

    // MARK: - Glucose

    private func glucosePointsFromValues(_ glucoseValues: [GlucoseValue]) -> [ChartPoint] {
        let unitString = glucoseUnit.glucoseUnitDisplayString
        let formatter = dateFormatter
        let glucoseFormatter = NumberFormatter.glucoseFormatter(for: glucoseUnit)

        return glucoseValues.map {
            return ChartPoint(
                x: ChartAxisValueDate(date: $0.startDate, formatter: formatter),
                y: ChartAxisValueDoubleUnit($0.quantity.doubleValue(for: glucoseUnit), unitString: unitString, formatter: glucoseFormatter)
            )
        }
    }

    func setGlucoseValues(_ glucoseValues: [GlucoseValue]) {
        glucosePoints = glucosePointsFromValues(glucoseValues)
    }

    func setPredictedGlucoseValues(_ glucoseValues: [GlucoseValue]) {
        predictedGlucosePoints = glucosePointsFromValues(glucoseValues)
    }

    func setAlternatePredictedGlucoseValues(_ glucoseValues: [GlucoseValue]) {
        alternatePredictedGlucosePoints = glucosePointsFromValues(glucoseValues)
    }

    // MARK: - Insulin

    private var doseFormatter: NumberFormatter {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2

        return numberFormatter
    }

    func setIOBValues(_ iobValues: [InsulinValue]) {
        let dateFormatter = self.dateFormatter
        let doseFormatter = self.doseFormatter

        iobPoints = iobValues.map {
            return ChartPoint(
                x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                y: ChartAxisValueDoubleUnit($0.value, unitString: "U", formatter: doseFormatter)
            )
        }
    }

    func setDoseEntries(_ doseEntries: [DoseEntry]) {
        let dateFormatter = self.dateFormatter
        let doseFormatter = self.doseFormatter

        var basalDosePoints = [ChartPoint]()
        var bolusDosePoints = [ChartPoint]()
        var allDosePoints = [ChartPoint]()

        for entry in doseEntries {
            switch entry.unit {
            case .unitsPerHour:
                // TODO: Display the DateInterval
                let startX = ChartAxisValueDate(date: entry.startDate, formatter: dateFormatter)
                let endX = ChartAxisValueDate(date: entry.endDate, formatter: dateFormatter)
                let zero = ChartAxisValueInt(0)
                let value = ChartAxisValueDoubleLog(actualDouble: entry.value, unitString: "U/hour", formatter: doseFormatter)

                let valuePoints: [ChartPoint]

                if entry.value != 0 {
                    valuePoints = [
                        ChartPoint(x: startX, y: value),
                        ChartPoint(x: endX, y: value)
                    ]
                } else {
                    valuePoints = []
                }

                basalDosePoints += [
                    ChartPoint(x: startX, y: zero)
                ] + valuePoints + [
                    ChartPoint(x: endX, y: zero)
                ]

                allDosePoints += valuePoints
            case .units:
                let x = ChartAxisValueDate(date: entry.startDate, formatter: dateFormatter)
                let y = ChartAxisValueDoubleLog(actualDouble: entry.value, unitString: "U", formatter: doseFormatter)

                let point = ChartPoint(x: x, y: y)
                bolusDosePoints.append(point)
                allDosePoints.append(point)
            }
        }

        self.basalDosePoints = basalDosePoints
        self.bolusDosePoints = bolusDosePoints
        self.allDosePoints = allDosePoints
    }

    // MARK: - Carbs

    func setCOBValues(_ cobValues: [CarbValue]) {
        let dateFormatter = self.dateFormatter
        let integerFormatter = NumberFormatter()
        integerFormatter.numberStyle = .none
        integerFormatter.maximumFractionDigits = 0

        let unit = HKUnit.gram()
        let unitString = unit.unitString

        cobPoints = cobValues.map {
            ChartPoint(
                x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                y: ChartAxisValueDoubleUnit($0.quantity.doubleValue(for: unit), unitString: unitString, formatter: integerFormatter)
            )
        }
    }
}
