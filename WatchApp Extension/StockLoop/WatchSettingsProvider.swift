//
//  WatchSettingsProvider.swift
//  WatchApp
//
//  `SettingsProvider` on the wrist: one settings snapshot from the grant, fixed for the loan,
//  with the phone's settings history before the grant. No settings history to publish.
//

import Foundation
import LoopKit
import LoopAlgorithm
import LoopCore
import Observation

/// Serves the grant's settings to `WatchLoopManager.fetchData` and the dose store's basal history.
@Observable
final class WatchSettingsProvider {
    /// The granted snapshot, in the shape the rest of the settings machinery expects.
    private(set) var storedSettings: StoredSettings

    /// The phone's timelines up to the grant; nil (an older phone) projects the snapshot back.
    var history: LoanSettingsHistory?

    init(settings: LoopSettings = LoopSettings()) {
        self.storedSettings = Self.stored(from: settings)
    }

    /// Whole-snapshot replacement, never a mix of two grants.
    func update(with settings: LoopSettings) {
        storedSettings = Self.stored(from: settings)
    }

    /// The insulin model is not carried; `WatchLoopManager.insulinModel(for:)` reads LoopSettings.
    private static func stored(from s: LoopSettings) -> StoredSettings {
        StoredSettings(
            dosingEnabled: s.dosingEnabled,
            glucoseTargetRangeSchedule: s.glucoseTargetRangeSchedule,
            preMealTargetRange: s.preMealTargetRange,
            overridePresets: s.overridePresets,
            maximumBasalRatePerHour: s.maximumBasalRatePerHour,
            maximumBolus: s.maximumBolus,
            suspendThreshold: s.suspendThreshold,
            basalRateSchedule: s.basalRateSchedule,
            insulinSensitivitySchedule: s.insulinSensitivitySchedule,
            carbRatioSchedule: s.carbRatioSchedule,
            automaticDosingStrategy: s.automaticDosingStrategy
        )
    }
}

// MARK: - SettingsProvider

extension WatchSettingsProvider: SettingsProvider {
    var settings: StoredSettings { storedSettings }

    /// The phone's flag; the wrist gates on its own loop switch, `WatchLoopManager._closedLoopEnabled`.
    var dosingEnabled: Bool { storedSettings.dosingEnabled }

    /// Splits at midnight as stock does; `WatchLoopManager.fetchData` collapses same-rate runs.
    func getBasalHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        guard let schedule = storedSettings.basalRateSchedule else { return [] }
        return Self.stitch(history?.basal, startDate, endDate) { start, end in
            BasalRateSchedule.generateTimeline(schedules: [(date: .distantPast, schedule: schedule)], startDate: start, endDate: end)
        }
    }

    /// Already projected by `between`.
    func getCarbRatioHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        guard let schedule = storedSettings.carbRatioSchedule else { return [] }
        return Self.stitch(history?.carbRatio, startDate, endDate) { schedule.between(start: $0, end: $1) }
    }

    func getInsulinSensitivityHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<LoopQuantity>] {
        guard let schedule = storedSettings.insulinSensitivitySchedule else { return [] }
        let past = history?.sensitivity.map {
            AbsoluteScheduleValue(startDate: $0.startDate, endDate: $0.endDate,
                                  value: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: $0.value))
        }
        return Self.stitch(past, startDate, endDate) { schedule.quantitiesBetween(start: $0, end: $1) }
    }

    /// In the schedule's own unit; overrides are applied in `WatchLoopManager.fetchData`.
    func getTargetRangeHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<ClosedRange<LoopQuantity>>] {
        guard let schedule = storedSettings.glucoseTargetRangeSchedule else { return [] }
        let past = history?.targetRange.map {
            AbsoluteScheduleValue(startDate: $0.startDate, endDate: $0.endDate,
                                  value: $0.value.quantityRange(for: .milligramsPerDeciliter))
        }
        return Self.stitch(past, startDate, endDate) { start, end in
            schedule.between(start: start, end: end).map {
                AbsoluteScheduleValue(
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    value: $0.value.quantityRange(for: schedule.unit)
                )
            }
        }
    }

    /// The phone's timeline where it covers the window, the snapshot elsewhere; without one,
    /// the snapshot unchanged.
    private static func stitch<T>(_ history: [AbsoluteScheduleValue<T>]?, _ start: Date, _ end: Date,
                                  snapshot: (Date, Date) -> [AbsoluteScheduleValue<T>]) -> [AbsoluteScheduleValue<T>] {
        guard let history, let first = history.first?.startDate, let last = history.last?.endDate else {
            return snapshot(start, end)
        }
        func clipped(_ values: [AbsoluteScheduleValue<T>], _ from: Date, _ to: Date) -> [AbsoluteScheduleValue<T>] {
            values.compactMap {
                let s = max($0.startDate, from), e = min($0.endDate, to)
                return s < e ? AbsoluteScheduleValue(startDate: s, endDate: e, value: $0.value) : nil
            }
        }
        var result: [AbsoluteScheduleValue<T>] = []
        if start < first { result += clipped(snapshot(start, min(end, first)), start, min(end, first)) }
        result += clipped(history, max(start, first), min(end, last))
        if end > last { result += clipped(snapshot(max(start, last), end), max(start, last), end) }
        return result
    }

    /// The grant's limits only; nil becomes a refusal to dose, not a default.
    func getDosingLimits(at date: Date) async throws -> DosingLimits {
        DosingLimits(
            suspendThreshold: storedSettings.suspendThreshold?.quantity,
            maxBolus: storedSettings.maximumBolus,
            maxBasalRate: storedSettings.maximumBasalRatePerHour
        )
    }

    /// The wrist authors no settings: empty.
    func executeSettingsQuery(fromQueryAnchor queryAnchor: SettingsStore.QueryAnchor?,
                              limit: Int,
                              completion: @escaping (SettingsStore.SettingsQueryResult) -> Void) {
        completion(.success(queryAnchor ?? SettingsStore.QueryAnchor(), []))
    }
}
