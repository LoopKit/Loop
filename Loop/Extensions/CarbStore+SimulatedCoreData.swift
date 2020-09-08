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

    private var simulatedCachedPerDay: Int { 8 }
    private var simulatedDeletedPerDay: Int { 3 }
    private var simulatedLimit: Int { 10000 }

    func generateSimulatedHistoricalCarbObjects(completion: @escaping (Error?) -> Void) {
        generateSimulatedHistoricalStoredCarbObjects() { error in
            guard error == nil else {
                completion(error)
                return
            }
            self.generateSimulatedHistoricalDeletedCarbObjects(completion: completion)
        }
    }

    private func generateSimulatedHistoricalStoredCarbObjects(completion: @escaping (Error?) -> Void) {
        var startDate = Calendar.current.startOfDay(for: earliestCacheDate)
        let endDate = Calendar.current.startOfDay(for: historicalEndDate)
        var simulated = [StoredCarbEntry]()

        while startDate < endDate {
            for index in 0..<simulatedCachedPerDay {
                simulated.append(StoredCarbEntry.simulated(startDate: startDate.addingTimeInterval(.hours(24) * Double(index) / Double(simulatedCachedPerDay)),
                                                           grams: Double(20 + 10 * (index % 3)),
                                                           absorptionTime: .hours(Double(2 + index % 3))))
            }

            if simulated.count >= simulatedLimit {
                if let error = addSimulatedHistoricalStoredCarbObjects(entries: simulated) {
                    completion(error)
                    return
                }
                simulated = []
            }

            startDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        }

        completion(addSimulatedHistoricalStoredCarbObjects(entries: simulated))
    }

    private func addSimulatedHistoricalStoredCarbObjects(entries: [StoredCarbEntry]) -> Error? {
        var addError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        addStoredCarbEntries(entries: entries) { error in
            addError = error
            semaphore.signal()
        }
        semaphore.wait()
        return addError
    }

    private func generateSimulatedHistoricalDeletedCarbObjects(completion: @escaping (Error?) -> Void) {
        var startDate = Calendar.current.startOfDay(for: earliestCacheDate)
        let endDate = Calendar.current.startOfDay(for: historicalEndDate)
        var simulated = [DeletedCarbEntry]()

        while startDate < endDate {
            for index in 0..<simulatedDeletedPerDay {
                simulated.append(DeletedCarbEntry.simulated(startDate: startDate.addingTimeInterval(.hours(24) * Double(index) / Double(simulatedDeletedPerDay))))
            }

            if simulated.count >= simulatedLimit {
                if let error = addSimulatedHistoricalDeletedCarbObjects(entries: simulated) {
                    completion(error)
                    return
                }
                simulated = []
            }

            startDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        }

        completion(addSimulatedHistoricalDeletedCarbObjects(entries: simulated))
    }

    private func addSimulatedHistoricalDeletedCarbObjects(entries: [DeletedCarbEntry]) -> Error? {
        var addError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        addDeletedCarbEntries(entries: entries) { error in
            addError = error
            semaphore.signal()
        }
        semaphore.wait()
        return addError
    }

    func purgeHistoricalCarbObjects(completion: @escaping (Error?) -> Void) {
        purgeCachedCarbEntries(before: historicalEndDate, completion: completion)
    }
}

fileprivate extension StoredCarbEntry {
    static func simulated(startDate: Date, grams: Double, absorptionTime: TimeInterval) -> StoredCarbEntry {
        return StoredCarbEntry(sampleUUID: UUID(),
                               syncIdentifier: UUID().uuidString,
                               syncVersion: 1,
                               startDate: startDate,
                               unitString: HKUnit.gram().unitString,
                               value: grams,
                               foodType: "Simulated",
                               absorptionTime: absorptionTime,
                               createdByCurrentApp: true,
                               externalID: UUID().uuidString)
    }
}

fileprivate extension DeletedCarbEntry {
    static func simulated(startDate: Date) -> DeletedCarbEntry {
        return DeletedCarbEntry(externalID: UUID().uuidString,
                                startDate: startDate,
                                uuid: UUID(),
                                syncIdentifier: UUID().uuidString,
                                syncVersion: 1)
    }
}
