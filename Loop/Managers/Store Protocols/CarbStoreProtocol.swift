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

    func getCarbEntries(start: Date?, end: Date?) async throws -> [StoredCarbEntry]

    func replaceCarbEntry(_ oldEntry: StoredCarbEntry, withEntry newEntry: NewCarbEntry) async throws -> StoredCarbEntry

    func addCarbEntry(_ entry: NewCarbEntry) async throws -> StoredCarbEntry

    func deleteCarbEntry(_ oldEntry: StoredCarbEntry) async throws -> Bool

}

extension CarbStore: CarbStoreProtocol { }
