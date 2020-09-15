//
//  PersistentDeviceLog+SimulatedCoreData.swift
//  Loop
//
//  Created by Darin Krauss on 6/4/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

// MARK: - Simulated Core Data

extension PersistentDeviceLog {
    private var historicalEndDate: Date { Date(timeIntervalSinceNow: -.hours(24)) }

    private var simulatedPerHour: Int { 250 }
    private var simulatedLimit: Int { 10000 }

    func generateSimulatedHistoricalDeviceLogEntries(completion: @escaping (Error?) -> Void) {
        var startDate = Calendar.current.startOfDay(for: earliestLogEntryDate)
        let endDate = Calendar.current.startOfDay(for: historicalEndDate)
        var simulated = [StoredDeviceLogEntry]()

        while startDate < endDate {
            for index in 0..<simulatedPerHour {
                simulated.append(StoredDeviceLogEntry.simulated(timestamp: startDate.addingTimeInterval(.hours(1) * Double(index) / Double(simulatedPerHour))))
            }

            if simulated.count >= simulatedLimit {
                if let error = addStoredDeviceLogEntries(entries: simulated) {
                    completion(error)
                    return
                }
                simulated = []
            }

            startDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate)!
        }

        completion(addStoredDeviceLogEntries(entries: simulated))
    }

    func purgeHistoricalDeviceLogEntries(completion: @escaping (Error?) -> Void) {
        purgeLogEntries(before: historicalEndDate, completion: completion)
    }
}

fileprivate extension StoredDeviceLogEntry {
    static func simulated(timestamp: Date) -> StoredDeviceLogEntry {
        return StoredDeviceLogEntry(type: .connection,
                                    managerIdentifier: "SimulatedMId",
                                    deviceIdentifier: "SimulatedDId",
                                    message: "This is an simulated message for the PersistentDeviceLog. In an analysis performed on June 1, 2020, the current average length of these messages is about 225 characters. This string should also be approximately that length.",
                                    timestamp: timestamp)
    }
}
