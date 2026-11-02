//
//  CarbStore+SimulatedCoreData.swift
//  Loop
//
//  Created by Darin Krauss on 6/4/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

// MARK: - Simulated Core Data

extension CarbStore {
    private var historicalEndDate: Date { Date(timeIntervalSinceNow: -.hours(24)) }

    private var simulatedPerDay: Int { 10 }
    private var simulatedLimit: Int { 10000 }

    func generateSimulatedHistoricalCarbObjects() async throws {
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
                try await addSimulatedHistoricalCarbObjects(entries: simulated)
                simulated = []
            }

            startDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        }

        try await addSimulatedHistoricalCarbObjects(entries: simulated)
    }

    private func addSimulatedHistoricalCarbObjects(entries: [NewCarbEntry]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            addNewCarbEntries(entries: entries) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func purgeHistoricalCarbObjects(completion: @escaping (Error?) -> Void) {
        purgeCachedCarbObjectsUnconditionally(before: historicalEndDate, completion: completion)
    }
}

fileprivate extension NewCarbEntry {
    static func simulated(startDate: Date, grams: Double, absorptionTime: TimeInterval) -> NewCarbEntry {
        return NewCarbEntry(date: startDate,
                            syncIdentifier: UUID().uuidString,
                            quantity: LoopQuantity(unit: .gram, doubleValue: grams),
                            startDate: startDate,
                            foodType: "Simulated",
                            absorptionTime: absorptionTime)
    }
}
