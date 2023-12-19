//
//  LoopSettings.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit

public extension AutomaticDosingStrategy {
    var title: String {
        switch self {
        case .tempBasalOnly:
            return LocalizedString("Temp Basal Only", comment: "Title string for temp basal only dosing strategy")
        case .automaticBolus:
            return LocalizedString("Automatic Bolus", comment: "Title string for automatic bolus dosing strategy")
        }
    }
}

public struct LoopSettings: Equatable {
    public var dosingEnabled = false

    public var glucoseTargetRangeSchedule: GlucoseRangeSchedule?

    public var insulinSensitivitySchedule: InsulinSensitivitySchedule?

    public var basalRateSchedule: BasalRateSchedule?

    public var carbRatioSchedule: CarbRatioSchedule?

    public var preMealTargetRange: ClosedRange<HKQuantity>?

    public var legacyWorkoutTargetRange: ClosedRange<HKQuantity>?

    public var overridePresets: [TemporaryScheduleOverridePreset] = []

    public var maximumBasalRatePerHour: Double?

    public var maximumBolus: Double?

    public var suspendThreshold: GlucoseThreshold? = nil
    
    public var automaticDosingStrategy: AutomaticDosingStrategy = .tempBasalOnly

    public var defaultRapidActingModel: ExponentialInsulinModelPreset?
    
    public var glucoseUnit: HKUnit? {
        return glucoseTargetRangeSchedule?.unit
    }

    public init(
        dosingEnabled: Bool = false,
        glucoseTargetRangeSchedule: GlucoseRangeSchedule? = nil,
        insulinSensitivitySchedule: InsulinSensitivitySchedule? = nil,
        basalRateSchedule: BasalRateSchedule? = nil,
        carbRatioSchedule: CarbRatioSchedule? = nil,
        preMealTargetRange: ClosedRange<HKQuantity>? = nil,
        legacyWorkoutTargetRange: ClosedRange<HKQuantity>? = nil,
        overridePresets: [TemporaryScheduleOverridePreset]? = nil,
        maximumBasalRatePerHour: Double? = nil,
        maximumBolus: Double? = nil,
        suspendThreshold: GlucoseThreshold? = nil,
        automaticDosingStrategy: AutomaticDosingStrategy = .tempBasalOnly,
        defaultRapidActingModel: ExponentialInsulinModelPreset? = nil
    ) {
        self.dosingEnabled = dosingEnabled
        self.glucoseTargetRangeSchedule = glucoseTargetRangeSchedule
        self.insulinSensitivitySchedule = insulinSensitivitySchedule
        self.basalRateSchedule = basalRateSchedule
        self.carbRatioSchedule = carbRatioSchedule
        self.preMealTargetRange = preMealTargetRange
        self.legacyWorkoutTargetRange = legacyWorkoutTargetRange
        self.overridePresets = overridePresets ?? []
        self.maximumBasalRatePerHour = maximumBasalRatePerHour
        self.maximumBolus = maximumBolus
        self.suspendThreshold = suspendThreshold
        self.automaticDosingStrategy = automaticDosingStrategy
        self.defaultRapidActingModel = defaultRapidActingModel
    }
}

extension LoopSettings: RawRepresentable {
    public typealias RawValue = [String: Any]
    private static let version = 1
    fileprivate static let codingGlucoseUnit = HKUnit.milligramsPerDeciliter

    public init?(rawValue: RawValue) {
        guard
            let version = rawValue["version"] as? Int,
            version == LoopSettings.version
        else {
            return nil
        }

        if let dosingEnabled = rawValue["dosingEnabled"] as? Bool {
            self.dosingEnabled = dosingEnabled
        }

        if let glucoseRangeScheduleRawValue = rawValue["glucoseTargetRangeSchedule"] as? GlucoseRangeSchedule.RawValue {
            self.glucoseTargetRangeSchedule = GlucoseRangeSchedule(rawValue: glucoseRangeScheduleRawValue)

            // Migrate the glucose range schedule override targets
            if let overrideRangesRawValue = glucoseRangeScheduleRawValue["overrideRanges"] as? [String: DoubleRange.RawValue] {
                if let preMealTargetRawValue = overrideRangesRawValue["preMeal"] {
                    self.preMealTargetRange = DoubleRange(rawValue: preMealTargetRawValue)?.quantityRange(for: LoopSettings.codingGlucoseUnit)
                }
                if let legacyWorkoutTargetRawValue = overrideRangesRawValue["workout"] {
                    self.legacyWorkoutTargetRange = DoubleRange(rawValue: legacyWorkoutTargetRawValue)?.quantityRange(for: LoopSettings.codingGlucoseUnit)
                }
            }
        }

        if let rawPreMealTargetRange = rawValue["preMealTargetRange"] as? DoubleRange.RawValue {
            self.preMealTargetRange = DoubleRange(rawValue: rawPreMealTargetRange)?.quantityRange(for: LoopSettings.codingGlucoseUnit)
        }

        if let rawLegacyWorkoutTargetRange = rawValue["legacyWorkoutTargetRange"] as? DoubleRange.RawValue {
            self.legacyWorkoutTargetRange = DoubleRange(rawValue: rawLegacyWorkoutTargetRange)?.quantityRange(for: LoopSettings.codingGlucoseUnit)
        }

        if let rawPresets = rawValue["overridePresets"] as? [TemporaryScheduleOverridePreset.RawValue] {
            self.overridePresets = rawPresets.compactMap(TemporaryScheduleOverridePreset.init(rawValue:))
        }

        self.maximumBasalRatePerHour = rawValue["maximumBasalRatePerHour"] as? Double

        self.maximumBolus = rawValue["maximumBolus"] as? Double

        if let rawThreshold = rawValue["minimumBGGuard"] as? GlucoseThreshold.RawValue {
            self.suspendThreshold = GlucoseThreshold(rawValue: rawThreshold)
        }
        
        if let rawDosingStrategy = rawValue["dosingStrategy"] as? AutomaticDosingStrategy.RawValue,
            let automaticDosingStrategy = AutomaticDosingStrategy(rawValue: rawDosingStrategy)
        {
            self.automaticDosingStrategy = automaticDosingStrategy
        }
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "version": LoopSettings.version,
            "dosingEnabled": dosingEnabled,
            "overridePresets": overridePresets.map { $0.rawValue }
        ]

        raw["glucoseTargetRangeSchedule"] = glucoseTargetRangeSchedule?.rawValue
        raw["preMealTargetRange"] = preMealTargetRange?.doubleRange(for: LoopSettings.codingGlucoseUnit).rawValue
        raw["legacyWorkoutTargetRange"] = legacyWorkoutTargetRange?.doubleRange(for: LoopSettings.codingGlucoseUnit).rawValue
        raw["maximumBasalRatePerHour"] = maximumBasalRatePerHour
        raw["maximumBolus"] = maximumBolus
        raw["minimumBGGuard"] = suspendThreshold?.rawValue
        raw["dosingStrategy"] = automaticDosingStrategy.rawValue
        
        return raw
    }
}
