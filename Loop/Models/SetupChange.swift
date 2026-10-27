//
//  SetupChange.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopAlgorithm

/// A change to the settings that shape dosing, used to tell how long a setup ran.
struct SetupChange: Equatable {
    enum Item: Equatable {
        case therapySetting(TherapySetting)
        case insulinType
        case insulinModel
        case dosingStrategy
        case experiment(ExperimentOption, enabled: Bool)
    }

    var date: Date
    /// The setup is known to be unchanged since `date`, but may be older.
    var isLowerBound: Bool
    var items: [Item]
    /// When the setup before this change started, as far as the records show.
    var previousDate: Date? = nil
    /// The therapy settings were first entered, during onboarding.
    var isInitialSetup = false

    /// Changes this close together are reported as one edit.
    static let groupingInterval = TimeInterval(hours: 1)

    /// Changes between consecutive records of a settings history, in any order.
    static func changes(in history: [StoredSettings]) -> [SetupChange] {
        // The insulin type comes from the pump, which has none while it's being replaced
        var insulinType: InsulinType?
        let sorted = history.sorted { $0.date < $1.date }.map { settings in
            var settings = settings
            settings.insulinType = settings.insulinType ?? insulinType
            insulinType = settings.insulinType
            return settings
        }
        return zip(sorted, sorted.dropFirst()).compactMap { previous, current in
            let items = differences(from: previous, to: current)
            let isInitialSetup = previous.basalRateSchedule == nil && previous.insulinSensitivitySchedule == nil && previous.carbRatioSchedule == nil
            return items.isEmpty ? nil : SetupChange(date: current.date, isLowerBound: false, items: items, isInitialSetup: isInitialSetup)
        }
    }

    /// Experiments turned on or off between dosing decisions. Decisions from builds that didn't
    /// record experiments are skipped.
    static func changes(in records: [ExperimentsRecord]) -> [SetupChange] {
        var previous: Set<ExperimentOption>?
        var changes: [SetupChange] = []
        for record in records.sorted(by: { $0.date < $1.date }) {
            guard let recorded = record.algorithmExperiments else {
                continue
            }
            let current = Set(recorded.compactMap { ExperimentOption(rawValue: $0.identifier) })
            if let previous, previous != current {
                let items = ExperimentOption.allCases
                    .filter { previous.contains($0) != current.contains($0) }
                    .map { Item.experiment($0, enabled: current.contains($0)) }
                changes.append(SetupChange(date: record.date, isLowerBound: false, items: items))
            }
            previous = current
        }
        return changes
    }

    /// Adds an earlier change's items after this one's, keeping the later date.
    func merging(_ other: SetupChange) -> SetupChange {
        var merged = self
        merged.date = max(date, other.date)
        merged.isInitialSetup = isInitialSetup || other.isInitialSetup
        for item in other.items where !merged.items.contains(item) {
            merged.items.append(item)
        }
        return merged
    }

    static func differences(from a: StoredSettings, to b: StoredSettings) -> [Item] {
        var items: [Item] = []
        if a.basalRateSchedule?.items != b.basalRateSchedule?.items {
            items.append(.therapySetting(.basalRate))
        }
        if !sameSchedule(a.insulinSensitivitySchedule, b.insulinSensitivitySchedule) {
            items.append(.therapySetting(.insulinSensitivity))
        }
        if !sameSchedule(a.carbRatioSchedule, b.carbRatioSchedule) {
            items.append(.therapySetting(.carbRatio))
        }
        if !sameRanges(a.glucoseTargetRangeSchedule?.quantityRanges.map(\.value), b.glucoseTargetRangeSchedule?.quantityRanges.map(\.value))
            || a.glucoseTargetRangeSchedule?.quantityRanges.map(\.startTime) != b.glucoseTargetRangeSchedule?.quantityRanges.map(\.startTime) {
            items.append(.therapySetting(.glucoseTargetRange))
        }
        if !sameRanges(a.preMealTargetRange.map { [$0] }, b.preMealTargetRange.map { [$0] }) {
            items.append(.therapySetting(.preMealCorrectionRangeOverride))
        }
        if !sameQuantity(a.suspendThreshold?.quantity, b.suspendThreshold?.quantity) {
            items.append(.therapySetting(.suspendThreshold))
        }
        if a.maximumBasalRatePerHour != b.maximumBasalRatePerHour || a.maximumBolus != b.maximumBolus {
            items.append(.therapySetting(.deliveryLimits))
        }
        if let aType = a.insulinType, let bType = b.insulinType, aType != bType {
            items.append(.insulinType)
        }
        if a.defaultRapidActingModel != b.defaultRapidActingModel {
            items.append(.insulinModel)
        }
        if a.automaticDosingStrategy != b.automaticDosingStrategy {
            items.append(.dosingStrategy)
        }
        return items
    }

    private static func sameSchedule(_ a: SingleQuantitySchedule?, _ b: SingleQuantitySchedule?) -> Bool {
        guard let a, let b else {
            return a == nil && b == nil
        }
        let aItems = a.quantities, bItems = b.quantities
        return aItems.count == bItems.count && zip(aItems, bItems).allSatisfy { x, y in
            x.startTime == y.startTime && sameQuantity(x.value, y.value)
        }
    }

    private static func sameRanges(_ a: [ClosedRange<LoopQuantity>]?, _ b: [ClosedRange<LoopQuantity>]?) -> Bool {
        guard let a, let b else {
            return a == nil && b == nil
        }
        return a.count == b.count && zip(a, b).allSatisfy { x, y in
            sameQuantity(x.lowerBound, y.lowerBound) && sameQuantity(x.upperBound, y.upperBound)
        }
    }

    // A value saved in mmol/L is rounded to 0.1, which can be ~2% from the same value in mg/dL
    private static func sameQuantity(_ a: LoopQuantity?, _ b: LoopQuantity?) -> Bool {
        guard let a, let b else {
            return a == nil && b == nil
        }
        let x = a.doubleValue(for: a.unit), y = b.doubleValue(for: a.unit)
        let tolerance = a.unit == b.unit ? 1e-9 : 0.02
        return abs(x - y) <= tolerance * max(abs(x), abs(y))
    }
}

/// The date of a dosing decision and the experiments it ran with, decoded without the rest of the decision.
struct ExperimentsRecord: Codable, Equatable {
    let date: Date
    /// Nil for builds that didn't record experiments.
    let algorithmExperiments: [AlgorithmExperiment]?

    /// The first record with experiments, then each record where they changed.
    static func transitions(_ records: [ExperimentsRecord]) -> [ExperimentsRecord] {
        var kept: [ExperimentsRecord] = []
        var previous: Set<String>?
        for record in records.sorted(by: { $0.date < $1.date }) {
            guard let experiments = record.algorithmExperiments else {
                continue
            }
            let identifiers = Set(experiments.map(\.identifier))
            if identifiers != previous {
                kept.append(ExperimentsRecord(date: record.date, algorithmExperiments: experiments.map { AlgorithmExperiment(identifier: $0.identifier) }))
                previous = identifiers
            }
        }
        return kept
    }
}

/// The experiment transitions read from dosing decisions so far, so each decision is read once.
struct ExperimentsHistoryCache {
    private struct Stored: Codable {
        var records: [ExperimentsRecord]
        var readThrough: Date
    }

    private let defaults: UserDefaults
    private let key = "com.loopkit.Loop.experimentsHistory"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Reads the decisions since the last call with `read(start)` and returns every transition since `start`.
    func records(since start: Date, now: Date, read: (Date) async throws -> [ExperimentsRecord]) async throws -> [ExperimentsRecord] {
        let stored = defaults.data(forKey: key).flatMap { try? PropertyListDecoder().decode(Stored.self, from: $0) }
        let readFrom = max(start, stored?.readThrough ?? start)
        let records = ExperimentsRecord.transitions((stored?.records ?? []) + (try await read(readFrom)))
        // Keep the last record before `start`, which says what was in effect then
        let current = records.filter { $0.date >= start }
        let kept = (records.last { $0.date < start }.map { [$0] } ?? []) + current
        defaults.set(try? PropertyListEncoder().encode(Stored(records: kept, readThrough: now)), forKey: key)
        return kept
    }
}

/// Every setup change in Loop's records, from the settings history and the experiments recorded
/// on dosing decisions.
struct SetupHistory: Equatable {
    /// Oldest first, each with the date of the change before it.
    let changes: [SetupChange]
    /// The oldest record. The setup before the first change is known only since then.
    let start: Date?

    init(settings: [StoredSettings], experiments: [ExperimentsRecord]) {
        let individual = (SetupChange.changes(in: settings) + SetupChange.changes(in: experiments)).sorted { $0.date < $1.date }
        var groups: [SetupChange] = []
        for change in individual {
            if let last = groups.last, change.date <= last.date + SetupChange.groupingInterval {
                groups[groups.count - 1] = change.merging(last)
            } else {
                groups.append(change)
            }
        }
        let start = (settings.map(\.date) + experiments.filter { $0.algorithmExperiments != nil }.map(\.date)).min()
        self.start = start
        changes = groups.indices.map { index in
            var change = groups[index]
            change.previousDate = index > 0 ? groups[index - 1].date : start
            return change
        }
    }

    /// The latest change, or without one, a lower bound at the oldest record.
    var latest: SetupChange? {
        changes.last ?? start.map { SetupChange(date: $0, isLowerBound: true, items: []) }
    }

    /// When the setup that `change` started was replaced, or nil if it's current.
    func end(of change: SetupChange) -> Date? {
        changes.first { $0.date > change.date }?.date
    }
}
