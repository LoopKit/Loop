//
//  DoseStoreProtocol.swift
//  Loop
//
//  Created by Anna Quinlan on 8/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit
import LoopAlgorithm

protocol DoseStoreProtocol: AnyObject {
    func getNormalizedDoseEntries(start: Date, end: Date?) async throws -> [DoseEntry]

    func addDoses(_ doses: [DoseEntry], from device: HKDevice?) async throws

    var lastReservoirValue: ReservoirValue? { get }

    func getTotalUnitsDelivered(since startDate: Date) async throws -> InsulinValue

    var lastAddedPumpData: Date { get }
}

extension DoseStore: DoseStoreProtocol {}
