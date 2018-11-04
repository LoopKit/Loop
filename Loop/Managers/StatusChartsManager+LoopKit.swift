//
//  StatusChartManager+LoopKit.swift
//  Loop
//
//  Created by Nate Racklyeft on 2/15/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import HealthKit

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
        let unitString = glucoseUnit.localizedShortUnitString
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
            let time = entry.endDate.timeIntervalSince(entry.startDate)

            if entry.type == .bolus && entry.netBasalUnits > 0 && time < .minutes(10) {
                let x = ChartAxisValueDate(date: entry.startDate, formatter: dateFormatter)
                let y = ChartAxisValueDoubleLog(actualDouble: entry.units, unitString: "U", formatter: doseFormatter)

                let point = ChartPoint(x: x, y: y)
                bolusDosePoints.append(point)
                allDosePoints.append(point)
            } else if time > 0 {
                // TODO: Display the DateInterval
                let startX = ChartAxisValueDate(date: entry.startDate, formatter: dateFormatter)
                let endX = ChartAxisValueDate(date: entry.endDate, formatter: dateFormatter)
                let zero = ChartAxisValueInt(0)
                let rate = entry.netBasalUnitsPerHour
                let value = ChartAxisValueDoubleLog(actualDouble: rate, unitString: "U/hour", formatter: doseFormatter)

                let valuePoints: [ChartPoint]

                if abs(rate) > .ulpOfOne {
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

    /// Convert an array of GlucoseEffects (as glucose values) into glucose effect velocity (glucose/min) for charting
    ///
    /// - Parameter effects: A timeline of glucose values representing glucose change
    func setCarbEffects(_ effects: [GlucoseEffect]) {
        let dateFormatter = self.dateFormatter
        let decimalFormatter = self.doseFormatter
        let unit = glucoseUnit.unitDivided(by: .minute())
        let unitString = unit.unitString

        var lastDate = effects.first?.endDate
        var lastValue = effects.first?.quantity.doubleValue(for: glucoseUnit)
        let minuteInterval = 5.0

        var carbEffectPoints = [ChartPoint]()

        let zero = ChartAxisValueInt(0)

        for effect in effects.dropFirst() {
            let value = effect.quantity.doubleValue(for: glucoseUnit)
            let valuePerMinute = (value - lastValue!) / minuteInterval
            lastValue = value

            let startX = ChartAxisValueDate(date: lastDate!, formatter: dateFormatter)
            let endX = ChartAxisValueDate(date: effect.endDate, formatter: dateFormatter)
            lastDate = effect.endDate

            let valueY = ChartAxisValueDoubleUnit(valuePerMinute, unitString: unitString, formatter: decimalFormatter)

            carbEffectPoints += [
                ChartPoint(x: startX, y: zero),
                ChartPoint(x: startX, y: valueY),
                ChartPoint(x: endX, y: valueY),
                ChartPoint(x: endX, y: zero)
            ]
        }

        self.carbEffectPoints = carbEffectPoints
    }

    /// Charts glucose effect velocity
    ///
    /// - Parameter effects: A timeline of glucose velocity values
    func setInsulinCounteractionEffects(_ effects: [GlucoseEffectVelocity]) {
        let dateFormatter = self.dateFormatter
        let decimalFormatter = self.doseFormatter
        let unit = glucoseUnit.unitDivided(by: .minute())
        let unitString = String(format: NSLocalizedString("%1$@/min", comment: "Format string describing glucose units per minute (1: glucose unit string)"), glucoseUnit.localizedShortUnitString)

        var insulinCounteractionEffectPoints: [ChartPoint] = []
        var allCarbEffectPoints: [ChartPoint] = []

        let zero = ChartAxisValueInt(0)

        for effect in effects {
            let startX = ChartAxisValueDate(date: effect.startDate, formatter: dateFormatter)
            let endX = ChartAxisValueDate(date: effect.endDate, formatter: dateFormatter)
            let value = ChartAxisValueDoubleUnit(effect.quantity.doubleValue(for: unit), unitString: unitString, formatter: decimalFormatter)

            guard value.scalar != 0 else {
                continue
            }

            let valuePoint = ChartPoint(x: endX, y: value)

            insulinCounteractionEffectPoints += [
                ChartPoint(x: startX, y: zero),
                ChartPoint(x: startX, y: value),
                valuePoint,
                ChartPoint(x: endX, y: zero)
            ]

            allCarbEffectPoints.append(valuePoint)
        }

        self.insulinCounteractionEffectPoints = insulinCounteractionEffectPoints
        self.allCarbEffectPoints = allCarbEffectPoints
    }

    // MARK: - Insulin Model Settings

    func setSelectedInsulinModelValues(_ values: [GlucoseValue]) {
        self.selectedInsulinModelChartPoints = glucosePointsFromValues(values)
    }

    func setUnselectedInsulinModelValues(_ values: [[GlucoseValue]]) {
        self.unselectedInsulinModelChartPoints = values.map {
            return glucosePointsFromValues($0)
        }
    }
}
