//
//  SettingsProvider.swift
//  Loop
//
//  Extracted from SettingsManager so that platforms other than the phone can serve therapy
//  settings without pulling in the phone's settings store. The phone answers this from Core
//  Data (settings change over time, so the history queries are real queries); a watch running
//  a loan answers the same protocol from the single settings snapshot it was granted.
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
