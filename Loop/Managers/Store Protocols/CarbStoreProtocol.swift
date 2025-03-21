//
//  CarbStoreProtocol.swift
//  Loop
//
//  Created by Anna Quinlan on 8/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit

protocol CarbStoreProtocol: AnyObject {

    func getCarbEntries(start: Date?, end: Date?, dateAscending: Bool, fetchLimit: Int?, with favoriteFoodID: String?) async throws -> [StoredCarbEntry]

    func replaceCarbEntry(_ oldEntry: StoredCarbEntry, withEntry newEntry: NewCarbEntry) async throws -> StoredCarbEntry

    func addCarbEntry(_ entry: NewCarbEntry) async throws -> StoredCarbEntry

    func deleteCarbEntry(_ oldEntry: StoredCarbEntry) async throws -> Bool

}

extension CarbStoreProtocol {
    func getCarbEntries(start: Date?, end: Date?) async throws -> [StoredCarbEntry] {
        try await getCarbEntries(start: start, end: end, dateAscending: true, fetchLimit: nil, with: nil)
    }
}

extension CarbStore: CarbStoreProtocol { }
