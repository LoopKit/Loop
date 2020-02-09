//
//  ForecastErrorLesson.swift
//  Learn
//
//  Created by Pete Schwamb on 1/31/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopCore
import LoopKit
import LoopKitUI
import LoopUI
import HealthKit
import os.log

final class ForecastErrorLesson: Lesson {
    let title = NSLocalizedString("Forecast Error", comment: "Lesson title")

    let subtitle = NSLocalizedString("Visualizes Loop's forecast error", comment: "Lesson subtitle")

    let configurationSections: [LessonSectionProviding]

    private let dataManager: DataManager

    private let glucoseUnit: HKUnit

    private let glucoseFormatter = QuantityFormatter()

    private let dateIntervalEntry: DateIntervalEntry

    private let rangeEntry: QuantityRangeEntry

    init(dataManager: DataManager) {
        self.dataManager = dataManager
        self.glucoseUnit = dataManager.glucoseStore.preferredUnit ?? .milligramsPerDeciliter

        glucoseFormatter.setPreferredNumberFormatter(for: glucoseUnit)

        dateIntervalEntry = DateIntervalEntry(
            end: Date(),
            weeks: 2
        )

        rangeEntry = QuantityRangeEntry.glucoseRange(
            minValue: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 80),
            maxValue: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 160),
            quantityFormatter: glucoseFormatter,
            unit: glucoseUnit)

        self.configurationSections = [
            dateIntervalEntry,
            rangeEntry
        ]
    }

    func execute(completion: @escaping ([LessonSectionProviding]) -> Void) {
        guard let dates = dateIntervalEntry.dateInterval, let closedRange = rangeEntry.closedRange else {
            // TODO: Cleaner error presentation
            completion([LessonSection(headerTitle: "Error: Please fill out all fields", footerTitle: nil, cells: [])])
            return
        }
        
        guard
            let basalRateSchedule = dataManager.basalRateSchedule,
            let carbRatioSchedule = dataManager.carbRatioSchedule,
            let insulinModelSettings = dataManager.insulinModelSettings,
            let insulinSensitivitySchedule = dataManager.insulinSensitivitySchedule
            else
        {
            completion([LessonSection(headerTitle: "Error: Loop not fully configured", footerTitle: nil, cells: [])])
            return
        }
        
        
        let calculator = ForecastErrorCalculator(
            dataManager: dataManager,
            dates: dates,
            range: closedRange,
            basalRateSchedule: basalRateSchedule,
            carbRatioSchedule: carbRatioSchedule,
            insulinModelSettings: insulinModelSettings,
            insulinSensitivitySchedule: insulinSensitivitySchedule,
            settings: dataManager.settings)

        calculator.execute { result in
            switch result {
            case .failure(let error):
                completion([
                    LessonSection(cells: [TextCell(text: String(describing: error))])
                ])
            case .success(let resultsByDay):
                guard resultsByDay.count > 0 else {
                    completion([
                        LessonSection(cells: [TextCell(text: NSLocalizedString("No data available", comment: "Lesson result text for no data"))])
                        ])
                    return
                }

                let dateFormatter = DateIntervalFormatter(dateStyle: .short, timeStyle: .none)
                let numberFormatter = NumberFormatter()
                numberFormatter.numberStyle = .percent

                var aggregator = TimeInRangeAggregator()
                resultsByDay.forEach({ (pair) in
                    aggregator.add(percentInRange: pair.value, for: pair.key)
                })

                completion([
                    TimesInRangeSection(
                        ranges: aggregator.results.map { [$0.range:$0.value] } ?? [:],
                        dateFormatter: dateFormatter,
                        numberFormatter: numberFormatter
                    ),
                    TimesInRangeSection(
                        ranges: resultsByDay,
                        dateFormatter: dateFormatter,
                        numberFormatter: numberFormatter
                    )
                ])
            }
        }
    }
}




/// Time-in-range, e.g. "2 weeks starting on March 5"
private class ForecastErrorCalculator {
    let calculator: DayCalculator<[DateInterval: Double]>
    let range: ClosedRange<HKQuantity>
    let dataManager: DataManager
    let retrospectiveCorrection: RetrospectiveCorrection
    let basalRateSchedule: BasalRateSchedule
    let carbRatioSchedule: CarbRatioSchedule
    let insulinModelSettings: InsulinModelSettings
    let insulinSensitivitySchedule: InsulinSensitivitySchedule
    let settings: LoopSettings

    private let log: OSLog

    private let unit = HKUnit.milligramsPerDeciliter

    init(dataManager: DataManager,
         dates: DateInterval,
         range: ClosedRange<HKQuantity>,
         basalRateSchedule: BasalRateSchedule,
         carbRatioSchedule: CarbRatioSchedule,
         insulinModelSettings: InsulinModelSettings,
         insulinSensitivitySchedule: InsulinSensitivitySchedule,
         settings: LoopSettings
    ) {
        self.dataManager = dataManager
        self.range = range
        self.calculator = DayCalculator(dataManager: dataManager, dates: dates, initial: [:])
        self.basalRateSchedule = basalRateSchedule
        self.carbRatioSchedule = carbRatioSchedule
        self.insulinModelSettings = insulinModelSettings
        self.insulinSensitivitySchedule = insulinSensitivitySchedule
        self.settings = settings
        
        let retrospectiveCorrectionEffectDuration = TimeInterval(hours: 1)
        retrospectiveCorrection = StandardRetrospectiveCorrection(effectDuration: retrospectiveCorrectionEffectDuration)

        log = OSLog(category: String(describing: type(of: self)))
    }

    func execute(completion: @escaping (_ result: Result<[DateInterval: Double]>) -> Void) {
        os_log(.default, log: log, "Computing Time in range from %{public}@ between %{public}@", String(describing: calculator.dates), String(describing: range))
        
        calculator.execute(calculator: { (dataManager, day, results, completion) in
            os_log(.default, log: self.log, "Fetching samples in %{public}@", String(describing: day))
        
            let result = dataManager.fetchEffects(for: day, retrospectiveCorrection: self.retrospectiveCorrection)
            
            switch result {
            case .failure(let error):
                completion(error)
            case .success(let effects):                
                _ = results.mutate({ (results) in
                    if effects.glucose.count > 0 {
                        let glucoseInterpolated = effects.glucose.interpolatedToSimulationTimeline(start: day.start, end: day.end)
                        results[day] = self.forecastError(effects: effects,
                                                          targetGlucose: glucoseInterpolated,
                                                          momentumDataInterval: dataManager.glucoseStore.momentumDataInterval,
                                                          delta: dataManager.carbStore.delta)
                    } else {
                        results[day] = 0
                    }
                })
                completion(nil)
            }
            
        }, completion: completion)
    }
    
    fileprivate func forecastError(effects: GlucoseEffects, targetGlucose: [GlucoseValue], momentumDataInterval: TimeInterval, delta: TimeInterval) -> Double {
        var momentumWindowStart = 0
        
        for (index, glucose) in effects.glucose.enumerated() {
            
            while glucose.startDate.timeIntervalSince(effects.glucose[momentumWindowStart].startDate) > momentumDataInterval {
                momentumWindowStart += 1
            }
            let momentumWindow = effects.glucose[momentumWindowStart...index]
            let glucoseMomentumEffect = momentumWindow.linearMomentumEffect(
                duration: momentumDataInterval,
                delta: TimeInterval(minutes: 5)
                
            )
            
            // Calculate retrospective correction
            let retrospectiveGlucoseEffect = retrospectiveCorrection.computeEffect(
                startingAt: glucose,
                retrospectiveGlucoseDiscrepanciesSummed: effects.retrospectiveGlucoseDiscrepanciesSummed,
                recencyInterval: settings.recencyInterval,
                insulinSensitivitySchedule: insulinSensitivitySchedule,
                basalRateSchedule: basalRateSchedule,
                glucoseCorrectionRangeSchedule: settings.glucoseTargetRangeSchedule,
                retrospectiveCorrectionGroupingInterval: settings.retrospectiveCorrectionGroupingInterval
            )
            let effectsUsed = [
                effects.carbEffects,
                effects.insulinEffects,
                retrospectiveGlucoseEffect
            ]
            
            let forecast = LoopMath.predictGlucose(startingAt: glucose, momentum: glucoseMomentumEffect, effects: effectsUsed)
            
            // Map predicted and target to nearest forecast point
            let startDate = targetGlucose[0].startDate
            let unit = HKUnit.milligramsPerDeciliter
            var residuals = [GlucoseEffect]()
            var targetGlucoseIter = targetGlucose.makeIterator()
            var targetGlucoseValue = targetGlucoseIter.next()
            for value in forecast {
                let index = Int(round(value.startDate.timeIntervalSince(startDate) / delta))
                while
                    let target = targetGlucoseValue,
                    Int(round(target.startDate.timeIntervalSince(startDate) / delta)) < index
                {
                    targetGlucoseValue = targetGlucoseIter.next()
                }
                if let target = targetGlucoseValue, abs(target.startDate.timeIntervalSince(value.startDate)) < delta / 2 {
                    let residual = value.quantity.doubleValue(for: unit) - target.quantity.doubleValue(for: unit)
                    residuals.append(GlucoseEffect(startDate: value.startDate, quantity: HKQuantity(unit: unit, doubleValue: residual)))
                }
                print("residuals: \(residuals)")
            }
            
        }
        return 1.0
    }
}

extension BidirectionalCollection where Element: GlucoseSampleValue, Index == Int {
    public func interpolatedToSimulationTimeline(start: Date, end: Date, delta: TimeInterval = .init(5 * 60)) -> [GlucoseEffect] {
        guard
            self.count > 1  // Cannot interpolate without 2 or more entries.
        else {
            return []
        }
        let unit = HKUnit.milligramsPerDeciliter
        var values = [GlucoseEffect]()
        
        var iter = makeIterator()
        
        var l = iter.next()!
        var r = iter.next()!
        
        guard let (start, end) = LoopMath.simulationDateRangeForSamples(self, from: start, to: end, duration: 0, delta: delta) else {
            return []
        }
        
        var t = start

        done: repeat {
            while t > r.startDate {
                if let n = iter.next() {
                    l = r
                    r = n
                } else {
                    break done
                }
            }
            if t.timeIntervalSince(l.startDate) < delta && r.startDate.timeIntervalSince(t) < delta {
                let leftValue = l.quantity.doubleValue(for: unit)
                let rightValue = r.quantity.doubleValue(for: unit)
                let value = (t.timeIntervalSince(l.startDate)) * (rightValue - leftValue) / (r.startDate.timeIntervalSince(l.startDate)) + leftValue
                values.append(GlucoseEffect(startDate: t, quantity: HKQuantity(unit: unit, doubleValue: value)))
            }
            t = t.addingTimeInterval(delta)
        } while t < end
        
        return values
    }
}

//class LinearInterpolation {
//    private var n : Int
//    private var x : [Double]
//    private var y : [Double]
//    init (x: [Double], y: [Double]) {
//        assert(x.count == y.count)
//        self.n = x.count-1
//        self.x = x
//        self.y = y
//    }
//
//    func interpolate(t: Double) -> Double {
//        if t <= x[0] { return y[0] }
//        for i in 1...n {
//            if t <= x[i] {
//                let ans = (t-x[i-1]) * (y[i] - y[i-1]) / (x[i]-x[i-1]) + y[i-1]
//                return ans
//            }
//        }
//        return y[n]
//    }
//}

