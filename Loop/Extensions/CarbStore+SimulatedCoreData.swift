//
//  CarbStore+SimulatedCoreData.swift
//  Loop
//
//  Created by Darin Krauss on 6/4/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

// MARK: - Simulated Core Data

extension CarbStore {
    private var historicalEndDate: Date { Date(timeIntervalSinceNow: -.hours(24)) }

    private var simulatedPerDay: Int { 10 }
    private var simulatedLimit: Int { 10000 }

    func generateSimulatedHistoricalCarbObjects(completion: @escaping (Error?) -> Void) {
        var startDate = Calendar.current.startOfDay(for: earliestCacheDate)
        let endDate = Calendar.current.startOfDay(for: historicalEndDate)
        var simulated = [NewCarbEntry]()

        while startDate < endDate {
            for index in 0..<simulatedPerDay {
                simulated.append(NewCarbEntry.simulated(startDate: startDate.addingTimeInterval(.hours(24) * Double(index) / Double(simulatedPerDay)),
                                                        grams: Double(20 + 10 * (index % 3)),
                                                        absorptionTime: .hours(Double(2 + index % 3))))
            }

            if simulated.count >= simulatedLimit {
                if let error = addSimulatedHistoricalCarbObjects(entries: simulated) {
                    completion(error)
                    return
                }
                simulated = []
            }

            startDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        }

        completion(addSimulatedHistoricalCarbObjects(entries: simulated))
    }

    private func addSimulatedHistoricalCarbObjects(entries: [NewCarbEntry]) -> Error? {
        var addError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        addNewCarbEntries(entries: entries) { error in
            addError = error
            semaphore.signal()
        }
        semaphore.wait()
        return addError
    }

    func purgeHistoricalCarbObjects(completion: @escaping (Error?) -> Void) {
        purgeCachedCarbObjectsUnconditionally(before: historicalEndDate, completion: completion)
    }
}

fileprivate extension NewCarbEntry {
    static func simulated(startDate: Date, grams: Double, absorptionTime: TimeInterval) -> NewCarbEntry {
        return NewCarbEntry(date: startDate,
                            quantity: HKQuantity(unit: .gram(), doubleValue: grams),
                            startDate: startDate,
                            foodType: "Simulated",
                            absorptionTime: absorptionTime)
    }
}
