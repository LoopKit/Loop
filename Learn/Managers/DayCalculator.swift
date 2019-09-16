//
//  DayCalculator.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopCore
import LoopKit

class DayCalculator<ResultType> {
    typealias Calculator = (_ dataManager: DataManager, _ day: DateInterval, _ results: Locked<ResultType>, _ completion: @escaping (_ error: Error?) -> Void) -> Void

    let dataManager: DataManager
    let dates: DateInterval
    private var lockedResults: Locked<ResultType>

    init(dataManager: DataManager, dates: DateInterval, initial: ResultType) {
        self.dataManager = dataManager
        self.dates = dates
        self.lockedResults = Locked(initial)
    }

    func execute(calculator: @escaping Calculator, completion: @escaping (_ result: Result<ResultType>) -> Void) {
        var anyError: Error?

        let group = DispatchGroup()

        var segmentStart = dates.start

        Calendar.current.enumerateDates(startingAfter: dates.start, matching: DateComponents(hour: 0), matchingPolicy: .nextTime) { (date, exactMatch, stop) in
            guard let date = date else {
                stop = true
                return
            }

            let interval = DateInterval(start: segmentStart, end: min(dates.end, date))

            guard interval.duration > 0 else {
                stop = true
                return
            }

            group.enter()
            calculator(dataManager, interval, lockedResults) { error in
                if let error = error {
                    anyError = error
                }

                group.leave()
            }
            segmentStart = interval.end
        }

        group.notify(queue: .main) {
            if let error = anyError {
                completion(.failure(error))
            } else {
                completion(.success(self.lockedResults.value))
            }
        }
    }
}
