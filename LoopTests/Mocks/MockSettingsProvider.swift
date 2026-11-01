//
//  MockSettingsProvider.swift
//  LoopTests
//
//  Created by Pete Schwamb on 11/28/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
@testable import Loop
@testable import LoopCore

@Observable
class MockSettingsProvider: SettingsProvider {
    var dosingEnabled: Bool = false
    
    var basalHistory: [AbsoluteScheduleValue<Double>]?
    func getBasalHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        return basalHistory ?? settings.basalRateSchedule?.between(start: startDate, end: endDate) ?? []
    }
    
    var carbRatioHistory: [AbsoluteScheduleValue<Double>]?
    func getCarbRatioHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        return carbRatioHistory ?? settings.carbRatioSchedule?.truncatingBetween(start: startDate, end: endDate) ?? []
    }
    
    var insulinSensitivityHistory: [AbsoluteScheduleValue<LoopQuantity>]?
    func getInsulinSensitivityHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<LoopQuantity>] {
        if let insulinSensitivityHistory { return insulinSensitivityHistory }
        guard let schedule = settings.insulinSensitivitySchedule else { return [] }
        // Match SettingsStore: history begins at the requested date, not at the preceding
        // daily schedule boundary (which can accidentally hide missing-history bugs).
        return schedule.truncatingBetween(start: startDate, end: endDate).map {
            AbsoluteScheduleValue(startDate: $0.startDate, endDate: $0.endDate,
                                  value: LoopQuantity(unit: schedule.unit, doubleValue: $0.value))
        }
    }
    
    var targetRangeHistory: [AbsoluteScheduleValue<ClosedRange<LoopQuantity>>]?
    func getTargetRangeHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<ClosedRange<LoopQuantity>>] {
        return targetRangeHistory ?? settings.glucoseTargetRangeSchedule?.quantityBetween(start: startDate, end: endDate) ?? []
    }
    
    func getDosingLimits(at date: Date) async throws -> DosingLimits {
        return DosingLimits(
            suspendThreshold: settings.suspendThreshold?.quantity,
            maxBolus: settings.maximumBolus,
            maxBasalRate: settings.maximumBasalRatePerHour
        )
    }

    func executeSettingsQuery(fromQueryAnchor queryAnchor: SettingsStore.QueryAnchor?, limit: Int, completion: @escaping (SettingsStore.SettingsQueryResult) -> Void) {
        completion(.success(SettingsStore.QueryAnchor(), []))
    }

    var settings: StoredSettings

    init(settings: StoredSettings, dosingEnabled: Bool = true) {
        self.settings = settings
        self.dosingEnabled = dosingEnabled
    }
}
