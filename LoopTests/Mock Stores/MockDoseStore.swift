//
//  MockDoseStore.swift
//  LoopTests
//
//  Created by Anna Quinlan on 8/7/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import LoopAlgorithm
@testable import Loop

class MockDoseStore: DoseStoreProtocol {
    func getDoses(start: Date?, end: Date?) async throws -> [LoopKit.DoseEntry] {
        return doseHistory ?? [] + addedDoses
    }

    var addedDoses: [DoseEntry] = []

    func addDoses(_ doses: [DoseEntry], from device: HKDevice?) async throws {
        addedDoses = doses
    }
    
    var lastReservoirValue: LoopKit.ReservoirValue?

    func getTotalUnitsDelivered(since startDate: Date) async throws -> InsulinValue {
        return InsulinValue(startDate: lastAddedPumpData, value: 0)
    }
    
    var lastAddedPumpData = Date.distantPast

    var doseHistory: [DoseEntry]?

    static let dateFormatter = ISO8601DateFormatter.localTimeDate()
    
}
