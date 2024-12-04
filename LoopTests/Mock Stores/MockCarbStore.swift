//
//  MockCarbStore.swift
//  LoopTests
//
//  Created by Anna Quinlan on 8/7/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopCore
@testable import Loop

class MockCarbStore: CarbStoreProtocol {
    var defaultAbsorptionTimes = LoopCoreConstants.defaultCarbAbsorptionTimes

    var carbHistory: [StoredCarbEntry] = []

    func getCarbEntries(start: Date?, end: Date?, dateAscending: Bool, fetchLimit: Int?, with favoriteFoodID: String?) async throws -> [StoredCarbEntry] {
        return carbHistory.filterDateRange(start, end)
    }

    func replaceCarbEntry(_ oldEntry: StoredCarbEntry, withEntry newEntry: NewCarbEntry) async throws -> StoredCarbEntry {
        let stored = newEntry.asStoredCarbEntry
        carbHistory = carbHistory.map({ entry in
            if entry.syncIdentifier == oldEntry.syncIdentifier {
                return stored
            } else {
                return entry
            }
        })
        return stored
    }

    func addCarbEntry(_ entry: NewCarbEntry) async throws -> StoredCarbEntry {
        let stored = entry.asStoredCarbEntry
        carbHistory.append(stored)
        return stored
    }

    func deleteCarbEntry(_ oldEntry: StoredCarbEntry) async throws -> Bool {
        carbHistory = carbHistory.filter { $0.syncIdentifier == oldEntry.syncIdentifier }
        return true
    }
}
