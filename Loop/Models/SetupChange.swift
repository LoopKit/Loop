//
//  SetupChange.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopAlgorithm

/// The most recent change to the settings that shape dosing, used to tell how long the current setup has run.
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

    /// Changes this close to the latest one are reported together, as one edit.
    static let groupingInterval = TimeInterval(hours: 1)

    /// Finds the latest change in a settings history, in any order. Without one, the setup is
    /// unchanged since at least the oldest record.
    static func latest(in history: [StoredSettings]) -> SetupChange? {
        let sorted = history.sorted { $0.date < $1.date }
        guard let first = sorted.first else {
            return nil
        }
        let changes = zip(sorted, sorted.dropFirst()).compactMap { previous, current -> SetupChange? in
            let items = differences(from: previous, to: current)
            return items.isEmpty ? nil : SetupChange(date: current.date, isLowerBound: false, items: items)
        }
        guard let last = changes.last else {
            return SetupChange(date: first.date, isLowerBound: true, items: [])
        }
        return changes.reversed().reduce(SetupChange(date: last.date, isLowerBound: false, items: [])) { result, change in
            change.date >= last.date - groupingInterval ? result.merging(change) : result
        }
    }

    /// The later of two changes, with both reported when they're close together.
    static func latest(_ a: SetupChange?, _ b: SetupChange?) -> SetupChange? {
        guard let a else { return b }
        guard let b else { return a }
        let (earlier, later) = a.date <= b.date ? (a, b) : (b, a)
        guard !later.isLowerBound, !earlier.isLowerBound, earlier.date >= later.date - groupingInterval else {
            return later
        }
        return later.merging(earlier)
    }

    private func merging(_ other: SetupChange) -> SetupChange {
        var merged = self
        merged.date = max(date, other.date)
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
        if a.insulinType != b.insulinType {
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
