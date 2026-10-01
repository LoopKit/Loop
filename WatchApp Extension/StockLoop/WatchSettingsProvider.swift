//
//  WatchSettingsProvider.swift
//  WatchApp
//
//  The wrist's answer to `SettingsProvider`.
//
//  On the phone that protocol is served by `SettingsManager`, which reads a Core Data
//  history: settings can change at any time, so "what was the basal schedule between
//  T1 and T2" is a genuine query. The wrist's situation is different in a way that
//  makes the same protocol much cheaper to satisfy — it holds exactly ONE settings
//  snapshot, the one handed to it in the loan grant, and that snapshot is fixed for
//  the life of the loan. There is no history to search because there is only ever one
//  entry, in effect for the whole window.
//
//  So each history accessor here answers with the granted schedule projected across
//  the requested window, using the same `generateTimeline` upstream uses. Feeding it a
//  single schedule dated `.distantPast` says precisely what is true: this schedule was
//  already in effect before the window opened and never changed inside it.
//
//  Deliberately NOT supported: `executeSettingsQuery`. That exists so the phone can
//  sync settings history to Nightscout and Tidepool. The wrist is not a settings
//  author — it never edits therapy settings, it only borrows them — so it has no
//  history to publish, and returning an empty page is the honest answer rather than a
//  stub that pretends a store exists.
//

import Foundation
import LoopKit
import LoopAlgorithm
import LoopCore
import Observation

/// Serves the loan grant's therapy settings to everything on the wrist that expects a
/// `SettingsProvider`: `WatchLoopManager.fetchAlgorithmInput`, which builds every schedule the
/// algorithm runs on, and the DoseStore delegate's `scheduledBasalHistory`.
@Observable
final class WatchSettingsProvider {
    /// The granted snapshot, in the shape the rest of the settings machinery expects.
    private(set) var storedSettings: StoredSettings

    init(settings: LoopSettings = LoopSettings()) {
        self.storedSettings = Self.stored(from: settings)
    }

    /// Apply a new grant. Whole-snapshot replacement is the point: a piecemeal update would let
    /// the wrist dose against a mix of two grants.
    func update(with settings: LoopSettings) {
        storedSettings = Self.stored(from: settings)
    }

    /// Carries across exactly the fields the algorithm's history queries and dosing limits need.
    /// `defaultRapidActingModel` is deliberately not among them — the two types differ
    /// (`StoredInsulinModel` here, `ExponentialInsulinModelPreset` in `LoopSettings`), so
    /// `WatchLoopManager.insulinModel(for:)` reads the live `LoopSettings` instead of this
    /// snapshot. Nothing on the wrist reads the model off `storedSettings`; keep it that way.
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

    /// The PHONE's automation flag, relayed inside the grant. It exists to satisfy the protocol
    /// and nothing on the wrist consults it for a dosing decision: once the pod is lent, the
    /// watch is sovereign over loop mode and reads `WatchLoopManager.closedLoopEnabled` instead.
    /// ANDing the two produced a loop control the user could not turn on whenever the phone
    /// happened to be running open loop.
    var dosingEnabled: Bool { storedSettings.dosingEnabled }

    /// `generateTimeline` projects the daily schedule onto absolute time and splits at every
    /// local midnight even when the rate does not change. That is stock's own behaviour, and
    /// `fetchAlgorithmInput` collapses the contiguous same-rate entries afterwards for the same
    /// reason stock does — the IOB integrator does not rejoin sub-doses across those boundaries.
    func getBasalHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        guard let schedule = storedSettings.basalRateSchedule else { return [] }
        return BasalRateSchedule.generateTimeline(
            schedules: [(date: .distantPast, schedule: schedule)],
            startDate: startDate,
            endDate: endDate
        )
    }

    /// `between` already projects the daily schedule across the window, so unlike basal there is
    /// nothing to synthesise here.
    func getCarbRatioHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        guard let schedule = storedSettings.carbRatioSchedule else { return [] }
        return schedule.between(start: startDate, end: endDate)
    }

    func getInsulinSensitivityHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<LoopQuantity>] {
        guard let schedule = storedSettings.insulinSensitivitySchedule else { return [] }
        return schedule.quantitiesBetween(start: startDate, end: endDate)
    }

    /// Returned in the schedule's OWN unit. An override replaces this wholesale for the forecast
    /// — see `fetchAlgorithmInput` — so what comes back here is always the unmodified grant.
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

    /// The grant's limits, and during a loan the ONLY ones in force — the phone cannot raise or
    /// lower them mid-loan, and the wrist will not invent them: a nil here becomes a refusal to
    /// dose in `fetchAlgorithmInput`, not a default.
    func getDosingLimits(at date: Date) async throws -> DosingLimits {
        DosingLimits(
            suspendThreshold: storedSettings.suspendThreshold?.quantity,
            maxBolus: storedSettings.maximumBolus,
            maxBasalRate: storedSettings.maximumBasalRatePerHour
        )
    }

    /// See the file note: the wrist authors no settings, so it has no history to publish. An
    /// empty page is the honest answer; do not grow a stub store behind it.
    func executeSettingsQuery(fromQueryAnchor queryAnchor: SettingsStore.QueryAnchor?,
                              limit: Int,
                              completion: @escaping (SettingsStore.SettingsQueryResult) -> Void) {
        completion(.success(queryAnchor ?? SettingsStore.QueryAnchor(), []))
    }
}
