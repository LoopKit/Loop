//
//  SettingsProvider.swift
//  Loop
//
//  Extracted from SettingsManager so a watch can serve therapy settings from its grant snapshot.
//

import Foundation
import LoopKit
import LoopAlgorithm
import Observation

protocol SettingsProvider: Observable {
    var settings: StoredSettings { get }
    var dosingEnabled: Bool { get }

    func getBasalHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>]
    func getCarbRatioHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>]
    func getInsulinSensitivityHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<LoopQuantity>]
    func getTargetRangeHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<ClosedRange<LoopQuantity>>]
    func getDosingLimits(at date: Date) async throws -> DosingLimits
    func executeSettingsQuery(fromQueryAnchor queryAnchor: SettingsStore.QueryAnchor?, limit: Int, completion: @escaping (SettingsStore.SettingsQueryResult) -> Void)
}
