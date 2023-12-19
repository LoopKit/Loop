//
//  DoseStoreProtocol.swift
//  Loop
//
//  Created by Anna Quinlan on 8/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit

protocol DoseStoreProtocol: AnyObject {
    func getDoses(start: Date?, end: Date?) async throws -> [DoseEntry]

    func addDoses(_ doses: [DoseEntry], from device: HKDevice?) async throws

    var lastReservoirValue: ReservoirValue? { get }

    func getTotalUnitsDelivered(since startDate: Date) async throws -> InsulinValue

    var lastAddedPumpData: Date { get }
}

extension DoseStore: DoseStoreProtocol {}
