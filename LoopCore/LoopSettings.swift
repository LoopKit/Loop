//
//  LoopSettings.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit

public enum DosingStrategy: Int, CaseIterable {
    case tempBasalOnly
    case automaticBolus
}

public extension DosingStrategy {
    var title: String {
        switch self {
        case .tempBasalOnly:
            return NSLocalizedString("Temp Basal Only", comment: "Title string for temp basal only dosing strategy")
        case .automaticBolus:
            return NSLocalizedString("Automatic Bolus", comment: "Title string for automatic bolus dosing strategy")
        }
    }
}

public struct LoopSettings: Equatable {
    public var isScheduleOverrideInfiniteWorkout: Bool {
        guard let scheduleOverride = scheduleOverride else { return false }
        return scheduleOverride.context == .legacyWorkout && scheduleOverride.duration.isInfinite
    }
    
    public var dosingEnabled = false

    public let dynamicCarbAbsorptionEnabled = true

    public var glucoseTargetRangeSchedule: GlucoseRangeSchedule?

    public var preMealTargetRange: ClosedRange<HKQuantity>?

    public var legacyWorkoutTargetRange: ClosedRange<HKQuantity>?

    public var indefiniteWorkoutOverrideEnabledDate: Date?

    public var overridePresets: [TemporaryScheduleOverridePreset] = []

    public var scheduleOverride: TemporaryScheduleOverride? {
        didSet {
            if let newValue = scheduleOverride, newValue.context == .preMeal {
                preconditionFailure("The `scheduleOverride` field should not be used for a pre-meal target range override; use `preMealOverride` instead")
            }

            if scheduleOverride?.context == .legacyWorkout {
                preMealOverride = nil
            }
        }
    }

    public var preMealOverride: TemporaryScheduleOverride? {
        didSet {
            if let newValue = preMealOverride, newValue.context != .preMeal || newValue.settings.insulinNeedsScaleFactor != nil {
                preconditionFailure("The `preMealOverride` field should be used only for a pre-meal target range override")
            }
            
            if preMealOverride != nil, scheduleOverride?.context == .legacyWorkout {
                scheduleOverride = nil
            }
        }
    }

    public var maximumBasalRatePerHour: Double?

    public var maximumBolus: Double?

    public var suspendThreshold: GlucoseThreshold? = nil
    
    public var dosingStrategy: DosingStrategy = .tempBasalOnly

    public var glucoseUnit: HKUnit? {
        return glucoseTargetRangeSchedule?.unit
    }
    
    // MARK - Push Notifications
    
    public var deviceToken: Data?
    
    // MARK - Guardrails

    public func allowedSensitivityValues(for unit: HKUnit) -> [Double] {
        switch unit {
        case HKUnit.milligramsPerDeciliter:
            return (10...500).map { Double($0) }
        case HKUnit.millimolesPerLiter:
            return (6...270).map { Double($0) / 10.0 }
        default:
            return []
        }
    }

    public func allowedCorrectionRangeValues(for unit: HKUnit) -> [Double] {
        switch unit {
        case HKUnit.milligramsPerDeciliter:
            return (60...180).map { Double($0) }
        case HKUnit.millimolesPerLiter:
            return (33...100).map { Double($0) / 10.0 }
        default:
            return []
        }
    }


    public init(
        dosingEnabled: Bool = false,
        glucoseTargetRangeSchedule: GlucoseRangeSchedule? = nil,
        maximumBasalRatePerHour: Double? = nil,
        maximumBolus: Double? = nil,
        suspendThreshold: GlucoseThreshold? = nil
    ) {
        self.dosingEnabled = dosingEnabled
        self.glucoseTargetRangeSchedule = glucoseTargetRangeSchedule
        self.maximumBasalRatePerHour = maximumBasalRatePerHour
        self.maximumBolus = maximumBolus
        self.suspendThreshold = suspendThreshold
    }
}

extension LoopSettings {
    public func effectiveGlucoseTargetRangeSchedule(presumingMealEntry: Bool = false) -> GlucoseRangeSchedule?  {
        
        let preMealOverride = presumingMealEntry ? nil : self.preMealOverride
        
        let currentEffectiveOverride: TemporaryScheduleOverride?
        switch (preMealOverride, scheduleOverride) {
        case (let preMealOverride?, nil):
            currentEffectiveOverride = preMealOverride
        case (nil, let scheduleOverride?):
            currentEffectiveOverride = scheduleOverride
        case (let preMealOverride?, let scheduleOverride?):
            currentEffectiveOverride = preMealOverride.scheduledEndDate > Date()
                ? preMealOverride
                : scheduleOverride
        case (nil, nil):
            currentEffectiveOverride = nil
        }

        if let effectiveOverride = currentEffectiveOverride {
            return glucoseTargetRangeSchedule?.applyingOverride(effectiveOverride)
        } else {
            return glucoseTargetRangeSchedule
        }
    }

    public func scheduleOverrideEnabled(at date: Date = Date()) -> Bool {
        return scheduleOverride?.isActive(at: date) == true
    }

    public func nonPreMealOverrideEnabled(at date: Date = Date()) -> Bool {
        return scheduleOverride?.isActive(at: date) == true
    }

    public func preMealTargetEnabled(at date: Date = Date()) -> Bool {
        return preMealOverride?.isActive(at: date) == true
    }

    public func futureOverrideEnabled(relativeTo date: Date = Date()) -> Bool {
        guard let scheduleOverride = scheduleOverride else { return false }
        return scheduleOverride.startDate > date
    }

    public mutating func enablePreMealOverride(at date: Date = Date(), for duration: TimeInterval) {
        preMealOverride = makePreMealOverride(beginningAt: date, for: duration)
    }

    private func makePreMealOverride(beginningAt date: Date = Date(), for duration: TimeInterval) -> TemporaryScheduleOverride? {
        guard let preMealTargetRange = preMealTargetRange else {
            return nil
        }
        return TemporaryScheduleOverride(
            context: .preMeal,
            settings: TemporaryScheduleOverrideSettings(targetRange: preMealTargetRange),
            startDate: date,
            duration: .finite(duration),
            enactTrigger: .local,
            syncIdentifier: UUID()
        )
    }

    public mutating func enableLegacyWorkoutOverride(at date: Date = Date(), for duration: TimeInterval) {
        scheduleOverride = legacyWorkoutOverride(beginningAt: date, for: duration)
        preMealOverride = nil
    }

    public mutating func legacyWorkoutOverride(beginningAt date: Date = Date(), for duration: TimeInterval) -> TemporaryScheduleOverride? {
        guard let legacyWorkoutTargetRange = legacyWorkoutTargetRange else {
            return nil
        }

        if duration.isInfinite {
            indefiniteWorkoutOverrideEnabledDate = date
        }
        
        return TemporaryScheduleOverride(
            context: .legacyWorkout,
            settings: TemporaryScheduleOverrideSettings(targetRange: legacyWorkoutTargetRange),
            startDate: date,
            duration: duration.isInfinite ? .indefinite : .finite(duration),
            enactTrigger: .local,
            syncIdentifier: UUID()
        )
    }

    public mutating func clearOverride(matching context: TemporaryScheduleOverride.Context? = nil) {
        if context == .preMeal {
            preMealOverride = nil
            return
        }

        guard let scheduleOverride = scheduleOverride else { return }
        
        if isScheduleOverrideInfiniteWorkout {
            indefiniteWorkoutOverrideEnabledDate = nil
        }

        if let context = context {
            if scheduleOverride.context == context {
                self.scheduleOverride = nil
            }
        } else {
            self.scheduleOverride = nil
        }
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

        self.indefiniteWorkoutOverrideEnabledDate = rawValue["indefiniteWorkoutOverrideEnabledDate"] as? Date

        if let rawPresets = rawValue["overridePresets"] as? [TemporaryScheduleOverridePreset.RawValue] {
            self.overridePresets = rawPresets.compactMap(TemporaryScheduleOverridePreset.init(rawValue:))
        }

        if let rawPreMealOverride = rawValue["preMealOverride"] as? TemporaryScheduleOverride.RawValue {
            self.preMealOverride = TemporaryScheduleOverride(rawValue: rawPreMealOverride)
        }

        if let rawOverride = rawValue["scheduleOverride"] as? TemporaryScheduleOverride.RawValue {
            self.scheduleOverride = TemporaryScheduleOverride(rawValue: rawOverride)
        }

        self.maximumBasalRatePerHour = rawValue["maximumBasalRatePerHour"] as? Double

        self.maximumBolus = rawValue["maximumBolus"] as? Double

        if let rawThreshold = rawValue["minimumBGGuard"] as? GlucoseThreshold.RawValue {
            self.suspendThreshold = GlucoseThreshold(rawValue: rawThreshold)
        }
        
        if let rawDosingStrategy = rawValue["dosingStrategy"] as? DosingStrategy.RawValue,
            let dosingStrategy = DosingStrategy(rawValue: rawDosingStrategy) {
            self.dosingStrategy = dosingStrategy
        }
        
        if let deviceToken = rawValue["deviceToken"] as? Data {
            self.deviceToken = deviceToken
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
        raw["indefiniteWorkoutOverrideEnabledDate"] = indefiniteWorkoutOverrideEnabledDate
        raw["preMealOverride"] = preMealOverride?.rawValue
        raw["scheduleOverride"] = scheduleOverride?.rawValue
        raw["maximumBasalRatePerHour"] = maximumBasalRatePerHour
        raw["maximumBolus"] = maximumBolus
        raw["minimumBGGuard"] = suspendThreshold?.rawValue
        raw["dosingStrategy"] = dosingStrategy.rawValue
        raw["deviceToken"] = deviceToken
        
        return raw
    }
}
