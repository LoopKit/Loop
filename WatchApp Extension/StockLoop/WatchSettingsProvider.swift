//
//  WatchSettingsProvider.swift
//  WatchApp
//
//  `SettingsProvider` on the wrist: one settings snapshot from the grant, fixed for the loan,
//  projected across any requested window. No settings history to publish.
//

import Foundation
import LoopKit
import LoopAlgorithm
import LoopCore
import Observation

/// Serves the grant's settings to `fetchAlgorithmInput` and the dose store's basal history.
@Observable
final class WatchSettingsProvider {
    /// The granted snapshot, in the shape the rest of the settings machinery expects.
    private(set) var storedSettings: StoredSettings

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

    /// The phone's flag; the wrist uses `WatchLoopManager.closedLoopEnabled`.
    var dosingEnabled: Bool { storedSettings.dosingEnabled }

    /// Splits at midnight as stock does; `fetchAlgorithmInput` collapses same-rate runs.
    func getBasalHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        guard let schedule = storedSettings.basalRateSchedule else { return [] }
        return BasalRateSchedule.generateTimeline(
            schedules: [(date: .distantPast, schedule: schedule)],
            startDate: startDate,
            endDate: endDate
        )
    }

    /// Already projected by `between`.
    func getCarbRatioHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        guard let schedule = storedSettings.carbRatioSchedule else { return [] }
        return schedule.between(start: startDate, end: endDate)
    }

    func getInsulinSensitivityHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<LoopQuantity>] {
        guard let schedule = storedSettings.insulinSensitivitySchedule else { return [] }
        return schedule.quantitiesBetween(start: startDate, end: endDate)
    }

    /// In the schedule's own unit; overrides are applied in `fetchAlgorithmInput`.
    func getTargetRangeHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<ClosedRange<LoopQuantity>>] {
        guard let schedule = storedSettings.glucoseTargetRangeSchedule else { return [] }
        return schedule.between(start: startDate, end: endDate).map {
            AbsoluteScheduleValue(
                startDate: $0.startDate,
                endDate: $0.endDate,
                value: $0.value.quantityRange(for: schedule.unit)
            )
        }
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
