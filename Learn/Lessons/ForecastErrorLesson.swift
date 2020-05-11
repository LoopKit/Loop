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


enum ForecastErrorLessonError: Error {
    case missingProfile
}


class ForecastErrorSection: LessonSectionProviding {

    let cells: [LessonCellProviding]

    init(summaries: [DateInterval: ForecastSummary], glucoseUnit: HKUnit, dateIntervalFormatter: DateIntervalFormatter, dateFormatter: DateFormatter, delta: TimeInterval) {
        var allCells = [LessonCellProviding]()
        summaries.sorted(by: { $0.0 < $1.0 }).forEach { pair in
            if pair.value.forecasts.count > 0 {
                let spotCheckForecast = pair.value.forecasts[pair.value.forecasts.count / 2]
                let cellsForDate: [LessonCellProviding] = [
                    SpotCheckCell(date: pair.key, actualGlucose: pair.value.actualGlucose, forecast: spotCheckForecast, colors: .default, settings: .default, glucoseUnit: glucoseUnit, dateFormatter: dateFormatter),
                    SpotCheckResidualsCell(date: pair.key, actualGlucose: pair.value.actualGlucose, forecast: spotCheckForecast, colors: .default, settings: .default, glucoseUnit: glucoseUnit, dateFormatter: dateFormatter),
                    ResidualsCell(date: pair.key, forecasts: pair.value.forecasts, colors: .default, settings: .default, glucoseUnit: glucoseUnit, dateFormatter: dateIntervalFormatter),
                    ForecastErrorCell(date: pair.key, forecasts: pair.value.forecasts, delta: delta, colors: .default, settings: .default, glucoseUnit: glucoseUnit, dateFormatter: dateIntervalFormatter),
                ]
                allCells.append(contentsOf: cellsForDate)
            }
        }
        cells = allCells
    }
}


final class ForecastErrorLesson: Lesson {
    
    static let title = NSLocalizedString("Forecast Error", comment: "Lesson title")

    static let subtitle = NSLocalizedString("Visualizes Loop's forecast error", comment: "Lesson subtitle")

    let configurationSections: [LessonSectionProviding]

    private let glucoseUnit: HKUnit

    private let glucoseFormatter = QuantityFormatter()

    private let dateIntervalEntry: DateIntervalEntry
    
    private let dataSource: LearnDataSource

    init(dataSource: LearnDataSource, preferredGlucoseUnit: HKUnit) {
        self.dataSource = dataSource
        self.glucoseUnit = preferredGlucoseUnit

        glucoseFormatter.setPreferredNumberFormatter(for: glucoseUnit)

        dateIntervalEntry = DateIntervalEntry(
            end: Date(),
            weeks: 0,
            days: 1
        )

        self.configurationSections = [
            dateIntervalEntry
        ]
    }

    func execute(completion: @escaping ([LessonSectionProviding]) -> Void) {
        guard let dates = dateIntervalEntry.dateInterval else {
            // TODO: Cleaner error presentation
            completion([LessonSection(headerTitle: "Error: Please fill out all fields", footerTitle: nil, cells: [])])
            return
        }
        
        guard let therapySettings = dataSource.fetchTherapySettings() else {
            completion([LessonSection(headerTitle: "Error: Could not get therapy settings from selected data source", footerTitle: nil, cells: [])])
            return
        }
                
        print("starting run for dates: \(dates)")
                
        let calculator = ForecastErrorCalculator(dataSource: dataSource, therapySettings: therapySettings, dates: dates)

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

                let dateIntervalFormatter = DateIntervalFormatter(dateStyle: .short, timeStyle: .none)
                let dateFormatter = DateFormatter(dateStyle: .short, timeStyle: .short)
                let numberFormatter = NumberFormatter()
                numberFormatter.numberStyle = .percent

                completion([
                    ForecastErrorSection(
                        summaries: resultsByDay,
                        glucoseUnit: self.glucoseUnit,
                        dateIntervalFormatter: dateIntervalFormatter,
                        dateFormatter: dateFormatter,
                        delta: therapySettings.delta)
                ])
            }
        }
    }
}

struct Residual {
    let time: TimeInterval
    let quantity: HKQuantity
}

struct Forecast {
    let startTime: Date
    let predictedGlucose: [PredictedGlucoseValue]
    let targetGlucose: [GlucoseValue]
    let residuals: [GlucoseEffect]
}

struct ForecastSummary {
    let date: DateInterval
    let forecasts: [Forecast]
    let actualGlucose: [GlucoseValue]
}

/// Time-in-range, e.g. "2 weeks starting on March 5"
private class ForecastErrorCalculator {
    let calculator: DayCalculator<[DateInterval: ForecastSummary]>
    let dataSource: LearnDataSource
    let therapySettings: LearnTherapySettings

    private let log: OSLog

    init(dataSource: LearnDataSource, therapySettings: LearnTherapySettings, dates: DateInterval) {
        self.dataSource = dataSource
        self.therapySettings = therapySettings
        self.calculator = DayCalculator(dataSource: dataSource, dates: dates, initial: [:])
        
        log = OSLog(category: String(describing: type(of: self)))
    }

    func execute(completion: @escaping (_ result: Result<[DateInterval: ForecastSummary]>) -> Void) {
        os_log(.default, log: log, "Computing forecast error from %{public}@", String(describing: calculator.dates))
        
        calculator.execute(calculator: { (dataManager, day, results, completion) in
            os_log(.default, log: self.log, "Fetching source data for %{public}@", String(describing: day))
            
            guard let therapySettings = self.dataSource.fetchTherapySettings() else {
                completion(ForecastErrorLessonError.missingProfile)
                return
            }
            
            let result = self.dataSource.fetchEffects(for: day, using: therapySettings)

            switch result {
            case .failure(let error):
                completion(error)
            case .success(let effects):
                _ = results.mutate({ (results) in
                    if effects.glucose.count > 0 {
                        let glucoseInterpolated = effects.glucose.interpolatedToSimulationTimeline(start: day.start, end: day.end)
                        let forecasts = self.forecastError(date: day,
                                                           effects: effects,
                                                           targetGlucose: glucoseInterpolated,
                                                           momentumDataInterval: therapySettings.momentumDataInterval,
                                                           delta: therapySettings.delta)
                        results[day] = ForecastSummary(date: day, forecasts: forecasts, actualGlucose: effects.glucose)
                    }
                })
                completion(nil)
            }
            
        }, completion: completion)
    }
    
    fileprivate func forecastError(date: DateInterval, effects: GlucoseEffects, targetGlucose: [GlucoseValue], momentumDataInterval: TimeInterval, delta: TimeInterval) -> [Forecast] {
        var momentumWindowStart = 0
        
        print("Computing error for \(effects.dateInterval.start) to \(effects.dateInterval.end)")
        
        let targetBGByDate = targetGlucose.reduce(into: [Date: GlucoseValue]()) {
            $0[$1.startDate] = $1
        }
        
        var forecasts = [Forecast]()
        
        for (index, glucose) in effects.glucose.enumerated() {
            
            guard glucose.startDate >= date.start else {
                continue
            }
            
            while glucose.startDate.timeIntervalSince(effects.glucose[momentumWindowStart].startDate) >= momentumDataInterval {
                momentumWindowStart += 1
            }
            
            let momentumWindow = effects.glucose[momentumWindowStart...index]
            let glucoseMomentumEffect = momentumWindow.linearMomentumEffect(
                duration: momentumDataInterval,
                delta: TimeInterval(minutes: 5)
            )
            
            let pastRetrospectiveGlucoseDiscrepanciesSummed = effects.retrospectiveGlucoseDiscrepanciesSummed.filter { (change) -> Bool in
                change.startDate < glucose.startDate
            }
            
            // Calculate retrospective correction
            let retrospectiveGlucoseEffect = therapySettings.retrospectiveCorrection.computeEffect(
                startingAt: glucose,
                retrospectiveGlucoseDiscrepanciesSummed: pastRetrospectiveGlucoseDiscrepanciesSummed,
                recencyInterval: therapySettings.inputDataRecencyInterval,
                insulinSensitivitySchedule: therapySettings.sensitivity,
                basalRateSchedule: therapySettings.basalSchedule,
                glucoseCorrectionRangeSchedule: nil, // Not actually used
                retrospectiveCorrectionGroupingInterval: therapySettings.retrospectiveCorrectionGroupingInterval
            )
            
            let forecastStart = glucose.startDate.dateCeiledToTimeInterval(delta)
            let forecastEnd = forecastStart + therapySettings.insulinModel.model.effectDuration
            
            var effectsUsed: [[GlucoseEffect]] = [
                effects.carbEffects,
                effects.insulinEffects,
                retrospectiveGlucoseEffect
                ].map { $0.filter { $0.startDate >= forecastStart && $0.startDate <= forecastEnd } }
            

            // Ensure we have at least one effect value at each point of the forecast
            var zeroEffect = [GlucoseEffect]()
            var forecastDate = forecastStart
            while forecastDate <= forecastEnd {
                zeroEffect.append(GlucoseEffect(startDate: forecastDate, quantity: HKQuantity.init(unit: HKUnit.milligramsPerDeciliter, doubleValue: 0)))
                forecastDate += delta
            }
            effectsUsed.append(zeroEffect)
            
            let forecast = LoopMath.predictGlucose(startingAt: glucose, momentum: glucoseMomentumEffect, effects: effectsUsed)
                        
            let unit = HKUnit.milligramsPerDeciliter // Just used for math, not display
            var residuals = [GlucoseEffect]()
            for value in forecast {
                
                if let target = targetBGByDate[value.startDate] {
                    let residual = target.quantity.doubleValue(for: unit) - value.quantity.doubleValue(for: unit) 
                    residuals.append(GlucoseEffect(startDate: value.startDate, quantity: HKQuantity(unit: unit, doubleValue: residual)))
                }
            }
            
//            let cutoffDate = DateFormatter.descriptionFormatter.date(from: "2020-05-03 02:48:29 +0000")!
//            if glucose.startDate == cutoffDate {
//                print("here")
//            }
//
            
            //if glucose.startDate <= cutoffDate {
                forecasts.append(Forecast(startTime: glucose.startDate, predictedGlucose: forecast, targetGlucose: targetGlucose, residuals: residuals))
            //}
        }
        return forecasts
    }
}

extension BidirectionalCollection where Element: GlucoseSampleValue, Index == Int {
    public func interpolatedToSimulationTimeline(start: Date, end: Date, delta: TimeInterval = .init(5 * 60)) -> [GlucoseEffect] {
        guard
            self.count > 1  // Cannot interpolate without 2 or more entries.
        else {
            return []
        }
        let unit = HKUnit.milligramsPerDeciliter // Just used for math, not display
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

