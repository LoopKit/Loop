//
//  AlgorithmBridge.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopAlgorithm
import LoopKitUI

// LoopKit's stored values, given to LoopAlgorithm in its fixed units.

extension StoredCarbEntry: @retroactive LoopAlgorithm.CarbEntry {
    public var grams: Double { quantity.doubleValue(for: .gram) }
    public var endDate: Date { startDate }
}

extension StoredGlucoseSample: @retroactive LoopAlgorithm.GlucoseSampleValue {
    public var mgdl: Double { quantity.doubleValue(for: .milligramsPerDeciliter) }
    public var endDate: Date { startDate }
}

// These types conform to both modules' TimelineValue, so the protocols' shared helpers are
// ambiguous on them; these concrete versions take precedence.
extension Array where Element == StoredGlucoseSample {
    func filterDateRange(_ startDate: Date?, _ endDate: Date?) -> [StoredGlucoseSample] {
        filter { (startDate == nil || $0.endDate >= startDate!) && (endDate == nil || $0.startDate <= endDate!) }
    }
}

extension Array where Element == StoredCarbEntry {
    func filterDateRange(_ startDate: Date?, _ endDate: Date?) -> [StoredCarbEntry] {
        filter { (startDate == nil || $0.endDate >= startDate!) && (endDate == nil || $0.startDate <= endDate!) }
    }
}

struct AlgorithmInsulinModel: LoopAlgorithm.InsulinModel {
    let model: LoopKit.InsulinModel

    init(_ model: LoopKit.InsulinModel) {
        self.model = model
    }

    func percentEffectRemaining(at time: TimeInterval) -> Double {
        model.percentEffectRemaining(at: time)
    }

    var effectDuration: TimeInterval { model.effectDuration }

    var delay: TimeInterval { model.delay }
}

extension Array {
    func algorithmSchedule<T>() -> [LoopAlgorithm.AbsoluteScheduleValue<T>] where Element == LoopKit.AbsoluteScheduleValue<T> {
        map { LoopAlgorithm.AbsoluteScheduleValue(startDate: $0.startDate, endDate: $0.endDate, value: $0.value) }
    }

    /// Glucose quantities (or sensitivities) in mg/dL
    func algorithmMgdlSchedule() -> [LoopAlgorithm.AbsoluteScheduleValue<Double>] where Element == LoopKit.AbsoluteScheduleValue<LoopQuantity> {
        map { LoopAlgorithm.AbsoluteScheduleValue(startDate: $0.startDate, endDate: $0.endDate, value: $0.value.doubleValue(for: .milligramsPerDeciliter)) }
    }

    func algorithmMgdlRanges() -> LoopAlgorithm.GlucoseRangeTimeline where Element == LoopKit.AbsoluteScheduleValue<ClosedRange<LoopQuantity>> {
        map {
            LoopAlgorithm.AbsoluteScheduleValue(startDate: $0.startDate, endDate: $0.endDate,
                                                value: $0.value.lowerBound.doubleValue(for: .milligramsPerDeciliter)...$0.value.upperBound.doubleValue(for: .milligramsPerDeciliter))
        }
    }
}

// LoopAlgorithm's results, as LoopKit values for storage and charts.

extension LoopAlgorithm.GlucoseEffect {
    var loopKit: LoopKit.GlucoseEffect {
        LoopKit.GlucoseEffect(startDate: startDate, quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl))
    }
}

extension LoopAlgorithm.PredictedGlucoseValue {
    var loopKit: LoopKit.PredictedGlucoseValue {
        LoopKit.PredictedGlucoseValue(startDate: startDate, quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl))
    }
}

extension LoopAlgorithm.GlucoseEffectVelocity {
    var loopKit: LoopKit.GlucoseEffectVelocity {
        LoopKit.GlucoseEffectVelocity(startDate: startDate, endDate: endDate,
                                      quantity: LoopQuantity(unit: .milligramsPerDeciliterPerSecond, doubleValue: mgdlPerSecond))
    }
}

extension LoopAlgorithm.CarbValue {
    var loopKit: LoopKit.CarbValue {
        LoopKit.CarbValue(startDate: startDate, endDate: endDate, value: value)
    }
}

extension LoopAlgorithm.InsulinValue {
    var loopKit: LoopKit.InsulinValue {
        LoopKit.InsulinValue(startDate: startDate, value: value)
    }
}

extension LoopAlgorithm.BasalRelativeDose {
    var chartedDose: ChartedDose {
        let type: ChartedDose.DoseType
        switch self.type {
        case .bolus: type = .bolus
        case .basal: type = .basal
        }
        return ChartedDose(type: type, startDate: startDate, endDate: endDate, volume: volume, netBasalUnits: netBasalUnits)
    }
}

extension LoopAlgorithm.GlucoseChange {
    var loopKit: LoopKit.GlucoseChange {
        LoopKit.GlucoseChange(startDate: startDate, endDate: endDate, quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl))
    }
}

extension LoopAlgorithm.SimpleGlucoseValue {
    var loopKit: LoopKit.SimpleGlucoseValue {
        LoopKit.SimpleGlucoseValue(startDate: startDate, endDate: endDate, quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl))
    }
}

extension LoopAlgorithm.TempBasalRecommendation {
    var loopKit: LoopKit.TempBasalRecommendation {
        LoopKit.TempBasalRecommendation(unitsPerHour: unitsPerHour, duration: duration)
    }
}

extension LoopAlgorithm.AutomaticDoseRecommendation.Direction {
    var loopKit: LoopKit.AutomaticDoseRecommendation.Direction {
        switch self {
        case .decrease: .decrease
        case .neutral: .neutral
        case .increase: .increase
        }
    }
}

extension LoopAlgorithm.AutomaticDoseRecommendation {
    var loopKit: LoopKit.AutomaticDoseRecommendation {
        LoopKit.AutomaticDoseRecommendation(basalAdjustment: basalAdjustment.loopKit, direction: direction.loopKit, bolusUnits: bolusUnits)
    }
}

extension LoopAlgorithm.BolusRecommendationNotice {
    var loopKit: LoopKit.BolusRecommendationNotice {
        switch self {
        case .glucoseBelowSuspendThreshold(let minGlucose):
            return .glucoseBelowSuspendThreshold(minGlucose: minGlucose.loopKit)
        case .currentGlucoseBelowTarget(let glucose):
            return .currentGlucoseBelowTarget(glucose: glucose.loopKit)
        case .predictedGlucoseBelowTarget(let minGlucose):
            return .predictedGlucoseBelowTarget(minGlucose: minGlucose.loopKit)
        case .predictedGlucoseInRange:
            return .predictedGlucoseInRange
        case .allGlucoseBelowTarget(let minGlucose):
            return .allGlucoseBelowTarget(minGlucose: minGlucose.loopKit)
        }
    }
}

extension LoopAlgorithm.ManualBolusRecommendation {
    var loopKit: LoopKit.ManualBolusRecommendation {
        LoopKit.ManualBolusRecommendation(amount: amount, notice: notice?.loopKit)
    }
}

extension Array {
    func loopKitSchedule<T>() -> [LoopKit.AbsoluteScheduleValue<T>] where Element == LoopAlgorithm.AbsoluteScheduleValue<T> {
        map { LoopKit.AbsoluteScheduleValue(startDate: $0.startDate, endDate: $0.endDate, value: $0.value) }
    }
}

extension LoopKit.TempBasalRecommendation {
    var algorithm: LoopAlgorithm.TempBasalRecommendation {
        LoopAlgorithm.TempBasalRecommendation(unitsPerHour: unitsPerHour, duration: duration)
    }
}
