//
//  LoopSettings.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit

public struct LoopSettings: Equatable {
    public var dosingEnabled = false

    public let dynamicCarbAbsorptionEnabled = true

    public static let defaultCarbAbsorptionTimes: CarbStore.DefaultAbsorptionTimes = (fast: .hours(2), medium: .hours(3), slow: .hours(4))

    public var glucoseTargetRangeSchedule: GlucoseRangeSchedule?

    public var preMealTargetRange: DoubleRange?

    public var legacyWorkoutTargetRange: DoubleRange?

    public var overridePresets: [TemporaryScheduleOverridePreset] = []

    public var scheduleOverride: TemporaryScheduleOverride? {
        didSet {
            if let newValue = scheduleOverride, newValue.context == .preMeal {
                preconditionFailure("The `scheduleOverride` field should not be used for a pre-meal target range override; use `preMealOverride` instead")
            }
        }
    }

    public var preMealOverride: TemporaryScheduleOverride? {
        didSet {
            if let newValue = preMealOverride, newValue.context != .preMeal || newValue.settings.insulinNeedsScaleFactor != nil {
                preconditionFailure("The `preMealOverride` field should be used only for a pre-meal target range override")
            }
        }
    }

    public var maximumBasalRatePerHour: Double?

    public var maximumBolus: Double?

    public var suspendThreshold: GlucoseThreshold? = nil

    public let retrospectiveCorrectionEnabled = true

    /// The interval over which to aggregate changes in glucose for retrospective correction
    public let retrospectiveCorrectionGroupingInterval = TimeInterval(minutes: 30)

    /// The amount of time since a given date that input data should be considered valid
    public let inputDataRecencyInterval = TimeInterval(minutes: 15)
    
    /// Loop completion aging category limits
    public let completionFreshLimit = TimeInterval(minutes: 6)
    public let completionAgingLimit = TimeInterval(minutes: 16)
    public let completionStaleLimit = TimeInterval(hours: 12)

    public let batteryReplacementDetectionThreshold = 0.5

    public let defaultWatchCarbPickerValue = 15 // grams

    public let defaultWatchBolusPickerValue = 1.0 // %

    // MARK - Display settings

    public let minimumChartWidthPerHour: CGFloat = 50

    public let statusChartMinimumHistoryDisplay: TimeInterval = .hours(1)
    
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
    public var glucoseTargetRangeScheduleApplyingOverrideIfActive: GlucoseRangeSchedule? {
        let currentEffectiveOverride: TemporaryScheduleOverride?
        switch (preMealOverride, scheduleOverride) {
        case (let preMealOverride?, nil):
            currentEffectiveOverride = preMealOverride
        case (nil, let scheduleOverride?):
            currentEffectiveOverride = scheduleOverride
        case (let preMealOverride?, let scheduleOverride?):
            currentEffectiveOverride = preMealOverride.endDate > Date()
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
        guard let override = scheduleOverride else { return false }
        return override.startDate > date
    }

    public mutating func enablePreMealOverride(at date: Date = Date(), for duration: TimeInterval) {
        preMealOverride = makePreMealOverride(beginningAt: date, for: duration)
    }

    private func makePreMealOverride(beginningAt date: Date = Date(), for duration: TimeInterval) -> TemporaryScheduleOverride? {
        guard let preMealTargetRange = preMealTargetRange, let unit = glucoseUnit else {
            return nil
        }
        return TemporaryScheduleOverride(
            context: .preMeal,
            settings: TemporaryScheduleOverrideSettings(unit: unit, targetRange: preMealTargetRange),
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

    public func legacyWorkoutOverride(beginningAt date: Date = Date(), for duration: TimeInterval) -> TemporaryScheduleOverride? {
        guard let legacyWorkoutTargetRange = legacyWorkoutTargetRange, let unit = glucoseUnit else {
            return nil
        }
        return TemporaryScheduleOverride(
            context: .legacyWorkout,
            settings: TemporaryScheduleOverrideSettings(unit: unit, targetRange: legacyWorkoutTargetRange),
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

        guard let override = scheduleOverride else { return }
        if let context = context {
            if override.context == context {
                scheduleOverride = nil
            }
        } else {
            scheduleOverride = nil
        }
    }
}

extension LoopSettings: RawRepresentable {
    public typealias RawValue = [String: Any]
    private static let version = 1

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
                    self.preMealTargetRange = DoubleRange(rawValue: preMealTargetRawValue)
                }
                if let legacyWorkoutTargetRawValue = overrideRangesRawValue["workout"] {
                    self.legacyWorkoutTargetRange = DoubleRange(rawValue: legacyWorkoutTargetRawValue)
                }
            }
        }

        if let rawPreMealTargetRange = rawValue["preMealTargetRange"] as? DoubleRange.RawValue {
            self.preMealTargetRange = DoubleRange(rawValue: rawPreMealTargetRange)
        }

        if let rawLegacyWorkoutTargetRange = rawValue["legacyWorkoutTargetRange"] as? DoubleRange.RawValue {
            self.legacyWorkoutTargetRange = DoubleRange(rawValue: rawLegacyWorkoutTargetRange)
        }

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
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "version": LoopSettings.version,
            "dosingEnabled": dosingEnabled,
            "overridePresets": overridePresets.map { $0.rawValue }
        ]

        raw["glucoseTargetRangeSchedule"] = glucoseTargetRangeSchedule?.rawValue
        raw["preMealTargetRange"] = preMealTargetRange?.rawValue
        raw["legacyWorkoutTargetRange"] = legacyWorkoutTargetRange?.rawValue
        raw["preMealOverride"] = preMealOverride?.rawValue
        raw["scheduleOverride"] = scheduleOverride?.rawValue
        raw["maximumBasalRatePerHour"] = maximumBasalRatePerHour
        raw["maximumBolus"] = maximumBolus
        raw["minimumBGGuard"] = suspendThreshold?.rawValue

        return raw
    }
}
