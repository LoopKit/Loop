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

    private let dateEntry: DateEntry

    private let weeksEntry: NumberEntry

    private let rangeEntry: QuantityRangeEntry

    init(dataManager: DataManager) {
        self.dataManager = dataManager
        self.glucoseUnit = dataManager.glucoseStore.preferredUnit ?? .milligramsPerDeciliter

        let twoWeeksAgo = Calendar.current.date(byAdding: DateComponents(weekOfYear: -2), to: Date())!

        glucoseFormatter.setPreferredNumberFormatter(for: glucoseUnit)

        // TODO: Add a date components picker cell, and combine into a "DateIntervalEntry" section
        dateEntry = DateEntry(
            date: Calendar.current.startOfDay(for: twoWeeksAgo),
            title: NSLocalizedString("Start Date", comment: "Title of config entry"),
            mode: .date
        )
        weeksEntry = NumberEntry.integerEntry(
            value: 2,
            unitString: NSLocalizedString("Weeks", comment: "Unit string for a count of calendar weeks")
        )

        rangeEntry = QuantityRangeEntry.glucoseRange(quantityFormatter: glucoseFormatter, unit: glucoseUnit)

        self.configurationSections = [
            LessonSection(headerTitle: nil, footerTitle: nil, cells: [dateEntry, weeksEntry]),
            rangeEntry
        ]
    }

    func execute(completion: @escaping ([LessonSectionProviding]) -> Void) {
        guard let weeks = weeksEntry.number?.intValue, let closedRange = rangeEntry.closedRange else {
            // TODO: Cleaner error presentation
            completion([LessonSection(headerTitle: "Error: Please fill out all fields", footerTitle: nil, cells: [])])
            return
        }

        let start = dateEntry.date
        let calculator = TimeInRangeCalculator(dataManager: dataManager, start: start, duration: DateComponents(weekOfYear: weeks), range: closedRange)

        calculator.perform { result in
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
                        ranges: aggregator.dictionary,
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


private extension QuantityRangeEntry {
    class func glucoseRange(quantityFormatter: QuantityFormatter, unit: HKUnit) -> QuantityRangeEntry {
        return QuantityRangeEntry(
            headerTitle: NSLocalizedString("Range", comment: "Section title for glucose range"),
            minValue: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 80),
            maxValue: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 160),
            quantityFormatter: quantityFormatter,
            unit: unit,
            keyboardType: unit == .milligramsPerDeciliter ? .numberPad : .decimalPad
        )
    }
}


class TimesInRangeSection: LessonSectionProviding {
    let headerTitle: String? = nil
    let footerTitle: String? = nil

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

    var dictionary: [DateInterval: Double] {
        guard let allDates = allDates, let averagePercentInRange = averagePercentInRange else {
            return [:]
        }

        return [allDates: averagePercentInRange]
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
    let dataManager: DataManager
    let start: Date
    let duration: DateComponents
    let range: ClosedRange<HKQuantity>

    init(dataManager: DataManager, start: Date, duration: DateComponents, range: ClosedRange<HKQuantity>) {
        self.dataManager = dataManager
        self.start = start
        self.duration = duration
        self.range = range

        log = OSLog(subsystem: "com.loopkit.Learn", category: String(describing: type(of: self)))
    }

    private let log: OSLog

    private let unit = HKUnit.milligramsPerDeciliter

    func perform(completion: @escaping (_ result: Result<[DateInterval: Double]>) -> Void) {
        // Compute the end date
        guard let end = Calendar.current.date(byAdding: duration, to: start) else {
            fatalError("Unable to resolve duration: \(duration)")
        }

        os_log(.default, "Computing Time in range from %{public}@ for %{public}@ between %{public}@", String(describing: start), String(describing: end), String(describing: range))

        // Paginate into 24-hour blocks
        let lockedResults = Locked([DateInterval: Double]())
        var anyError: Error?

        let group = DispatchGroup()

        var segmentStart = start

        Calendar.current.enumerateDates(startingAfter: start, matching: DateComponents(hour: 0), matchingPolicy: .nextTime) { (date, _, stop) in
            guard let date = date else {
                stop = true
                return
            }

            let interval = DateInterval(start: segmentStart, end: min(end, date))

            guard interval.duration > 0 else {
                stop = true
                return
            }

            os_log(.default, "Fetching samples in %{public}@", String(describing: interval))

            group.enter()
            dataManager.glucoseStore.getGlucoseSamples(start: interval.start, end: interval.end) { (result) in
                switch result {
                case .failure(let error):
                    os_log(.error, log: self.log, "Failed to fetch samples: %{public}@", String(describing: error))
                    anyError = error
                case .success(let samples):
                    var inRangeCount = 0
                    var totalCount = 0

                    for sample in samples {
                        if self.range.contains(sample.quantity) {
                            inRangeCount += 1
                        }
                        totalCount += 1
                    }

                    if totalCount > 0 {
                        _ = lockedResults.mutate({ (results) in
                            results[interval] = Double(inRangeCount) / Double(totalCount)
                        })
                    }
                }

                group.leave()
            }

            segmentStart = interval.end
        }

        group.notify(queue: DispatchQueue.main) {
            if let error = anyError {
                completion(.failure(error))
            } else {
                completion(.success(lockedResults.value))
            }
        }
    }
}
