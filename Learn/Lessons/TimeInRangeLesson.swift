//
//  LessonPlayground.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopCore
import LoopKit
import LoopKitUI
import LoopUI
import HealthKit
import os.log


final class TimeInRangeLesson: Lesson {
    let title = NSLocalizedString("Time in Range", comment: "Lesson title")

    let subtitle = NSLocalizedString("Computes the percentage of glucose measurements within a specified range", comment: "Lesson subtitle")

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

        let calculator = TimeInRangeCalculator(dataManager: dataManager, dates: dates, range: closedRange)

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

class TimesInRangeSection: LessonSectionProviding {

    let cells: [LessonCellProviding]

    init(ranges: [DateInterval: Double], dateFormatter: DateIntervalFormatter, numberFormatter: NumberFormatter) {
        cells = ranges.sorted(by: { $0.0 < $1.0 }).map { pair -> LessonCellProviding in
            DatesAndNumberCell(date: pair.key, value: NSNumber(value: pair.value), dateFormatter: dateFormatter, numberFormatter: numberFormatter)
        }
    }
}


struct TimeInRangeAggregator {
    private var count = 0
    private var sum: Double = 0
    var allDates: DateInterval?

    var averagePercentInRange: Double? {
        guard count > 0 else {
            return nil
        }

        return sum / Double(count)
    }

    var results: (range: DateInterval, value: Double)? {
        guard let allDates = allDates, let averagePercentInRange = averagePercentInRange else {
            return nil
        }

        return (range: allDates, value: averagePercentInRange)
    }

    mutating func add(percentInRange: Double, for dates: DateInterval) {
        sum += percentInRange
        count += 1

        if let allDates = self.allDates {
            self.allDates = DateInterval(start: min(allDates.start, dates.start), end: max(allDates.end, dates.end))
        } else {
            self.allDates = dates
        }
    }
}


/// Time-in-range, e.g. "2 weeks starting on March 5"
private class TimeInRangeCalculator {
    let calculator: DayCalculator<[DateInterval: Double]>
    let range: ClosedRange<HKQuantity>

    private let log: OSLog

    private let unit = HKUnit.milligramsPerDeciliter

    init(dataManager: DataManager, dates: DateInterval, range: ClosedRange<HKQuantity>) {
        self.calculator = DayCalculator(dataManager: dataManager, dates: dates, initial: [:])
        self.range = range

        log = OSLog(category: String(describing: type(of: self)))
    }

    func execute(completion: @escaping (_ result: Result<[DateInterval: Double]>) -> Void) {
        os_log(.default, log: log, "Computing Time in range from %{public}@ between %{public}@", String(describing: calculator.dates), String(describing: range))

        calculator.execute(calculator: { (dataManager, day, results, completion) in
            os_log(.default, log: self.log, "Fetching samples in %{public}@", String(describing: day))

            dataManager.glucoseStore.getGlucoseSamples(start: day.start, end: day.end) { (result) in
                switch result {
                case .failure(let error):
                    os_log(.error, log: self.log, "Failed to fetch samples: %{public}@", String(describing: error))
                    completion(error)
                case .success(let samples):
                    if let timeInRange = samples.proportion(where: { self.range.contains($0.quantity) }) {
                        _ = results.mutate({ (results) in
                            results[day] = timeInRange
                        })
                    }
                    completion(nil)
                }
            }
        }, completion: completion)
    }
}
