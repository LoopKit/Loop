//
//  ModalDayLesson.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopCore
import LoopKit
import os.log

final class ModalDayLesson: Lesson {
    let title = NSLocalizedString("Modal Day", comment: "Lesson title")

    let subtitle = NSLocalizedString("Visualizes the most frequent glucose values by time of day", comment: "Lesson subtitle")

    let configurationSections: [LessonSectionProviding]

    private let dataManager: DataManager

    private let dateIntervalEntry: DateIntervalEntry

    private let glucoseUnit: HKUnit

    init(dataManager: DataManager) {
        self.dataManager = dataManager
        self.glucoseUnit = dataManager.glucoseStore.preferredUnit ?? .milligramsPerDeciliter

        dateIntervalEntry = DateIntervalEntry(
            end: Date(),
            weeks: 2
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

        let calendar = Calendar.current

        let calculator = ModalDayCalculator(dataManager: dataManager, dates: dates, bucketSize: .minutes(60), unit: glucoseUnit, calendar: calendar)
        calculator.execute { (result) in
            switch result {
            case .failure(let error):
                completion([
                    LessonSection(cells: [TextCell(text: String(describing: error))])
                ])
            case .success(let buckets):
                guard buckets.count > 0 else {
                    completion([
                        LessonSection(cells: [TextCell(text: NSLocalizedString("No data available", comment: "Lesson result text for no data"))])
                        ])
                    return
                }

                let dateFormatter = DateIntervalFormatter(timeStyle: .short)
                let glucoseFormatter = QuantityFormatter()
                glucoseFormatter.setPreferredNumberFormatter(for: self.glucoseUnit)

                completion([
                    LessonSection(cells: buckets.compactMap({ (bucket) -> TextCell? in
                        guard let start = calendar.date(from: bucket.time.lowerBound.dateComponents),
                            let end = calendar.date(from: bucket.time.upperBound.dateComponents),
                            let time = dateFormatter.string(from: DateInterval(start: start, end: end)),
                            let median = bucket.median,
                            let medianString = glucoseFormatter.string(from: median, for: bucket.unit)
                        else {
                            return nil
                        }

                        return TextCell(text: time, detailText: medianString)
                    }))
                ])
            }
        }
    }
}


fileprivate extension TextCell {

}


fileprivate struct ModalDayBucket {
    let time: Range<TimeComponents>
    let orderedValues: [Double]
    let unit: HKUnit

    init(time: Range<TimeComponents>, unorderedValues: [Double], unit: HKUnit) {
        self.time = time
        self.orderedValues = unorderedValues.sorted()
        self.unit = unit
    }

    var median: HKQuantity? {
        let count = orderedValues.count
        guard count > 0 else {
            return nil
        }

        if count % 2 == 1 {
            return HKQuantity(unit: unit, doubleValue: orderedValues[count / 2])
        } else {
            let mid = count / 2
            let lower = orderedValues[mid - 1]
            let upper = orderedValues[mid]
            return HKQuantity(unit: unit, doubleValue: (lower + upper) / 2)
        }
    }
}


fileprivate struct ModalDayBuilder {
    let calendar: Calendar
    let bucketSize: TimeInterval
    let unit: HKUnit
    private(set) var unorderedValuesByBucket: [Range<TimeComponents>: [Double]]

    init(calendar: Calendar, bucketSize: TimeInterval, unit: HKUnit) {
        self.calendar = calendar
        self.bucketSize = bucketSize
        self.unit = unit
        self.unorderedValuesByBucket = [:]
    }

    mutating func add(_ value: Double, at time: TimeComponents) {
        let bucket = time.bucket(withBucketSize: bucketSize)
        var values = unorderedValuesByBucket[bucket] ?? []
        values.append(value)
        unorderedValuesByBucket[bucket] = values
    }

    mutating func add(_ value: Double, at date: DateComponents) {
        guard let time = TimeComponents(dateComponents: date) else {
            return
        }
        add(value, at: time)
    }

    mutating func add(_ value: Double, at date: Date) {
        add(value, at: calendar.dateComponents([.hour, .minute], from: date))
    }

    mutating func add(_ quantity: HKQuantity, at date: Date) {
        add(quantity.doubleValue(for: unit), at: date)
    }

    var allBuckets: [ModalDayBucket] {
        return unorderedValuesByBucket.sorted(by: { $0.0.lowerBound < $1.0.lowerBound }).map { pair -> ModalDayBucket in
            return ModalDayBucket(time: pair.key, unorderedValues: pair.value, unit: unit)
        }
    }
}


fileprivate class ModalDayCalculator {
    typealias ResultType = ModalDayBuilder
    let calculator: DayCalculator<ResultType>
    let bucketSize: TimeInterval
    let calendar: Calendar
    private let log: OSLog

    init(dataManager: DataManager, dates: DateInterval, bucketSize: TimeInterval, unit: HKUnit, calendar: Calendar) {
        self.calculator = DayCalculator(dataManager: dataManager, dates: dates, initial: ModalDayBuilder(calendar: calendar, bucketSize: bucketSize, unit: unit))
        self.bucketSize = bucketSize
        self.calendar = calendar

        log = OSLog(category: String(describing: type(of: self)))
    }

    func execute(completion: @escaping (_ result: Result<[ModalDayBucket]>) -> Void) {
        os_log(.default, log: log, "Computing Modal day in %{public}@", String(describing: calculator.dates))

        calculator.execute(calculator: { (dataManager, day, mutableResult, completion) in
            os_log(.default, log: self.log, "Fetching samples in %{public}@", String(describing: day))

            dataManager.glucoseStore.getGlucoseSamples(start: day.start, end: day.end, completion: { (result) in
                switch result {
                case .failure(let error):
                    os_log(.error, log: self.log, "Failed to fetch samples: %{public}@", String(describing: error))
                    completion(error)
                case .success(let samples):
                    os_log(.error, log: self.log, "Found %d samples", samples.count)

                    for sample in samples {
                        _ = mutableResult.mutate({ (result) in
                            result.add(sample.quantity, at: sample.startDate)
                        })
                    }
                    completion(nil)
                }
            })
        }, completion: { (result) in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let builder):
                completion(.success(builder.allBuckets))
            }
        })
    }
}
