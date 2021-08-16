//
//  LoopSettings.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit

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
    
    var subtitle: String {
        switch self {
        case .tempBasalOnly:
            return NSLocalizedString("Loop will dose via temp basals, limited by your max temp basal setting.", comment: "Description string for temp basal only dosing strategy")
        case .automaticBolus:
            return NSLocalizedString("Loop will automatically bolus when bg is predicted to be higher than target range, and will use temp basals when bg is predicted to be lower than target range.", comment: "Description string for automatic bolus dosing strategy")
        }
    }
}

public struct LoopSettings: Equatable {
    public var dosingEnabled = false

    public let dynamicCarbAbsorptionEnabled = true

    public static let defaultCarbAbsorptionTimes: CarbStore.DefaultAbsorptionTimes = (fast: .hours(2), medium: .hours(3), slow: .hours(4))

    public var glucoseTargetRangeSchedule: GlucoseRangeSchedule?

    public var preMealTargetRange: DoubleRange?

    public var legacyWorkoutTargetRange: DoubleRange?

    public var overridePresets: [TemporaryScheduleOverridePreset] = []

    public var scheduleOverride: TemporaryScheduleOverride?

    public var maximumBasalRatePerHour: Double?

    public var maximumBolus: Double?

    public var suspendThreshold: GlucoseThreshold? = nil

    public let retrospectiveCorrectionEnabled = true
    
    public var dosingStrategy: DosingStrategy = .tempBasalOnly

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
    
    public let bolusPartialApplicationFactor = 0.4 // %

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
        if let override = scheduleOverride, override.isActive() {
            return glucoseTargetRangeSchedule?.applyingOverride(override)
        } else {
            return glucoseTargetRangeSchedule
        }
    }

    public func scheduleOverrideEnabled(at date: Date = Date()) -> Bool {
        guard let override = scheduleOverride else { return false }
        return override.isActive(at: date)
    }

    public func nonPreMealOverrideEnabled(at date: Date = Date()) -> Bool {
        guard let override = scheduleOverride else { return false }
        return override.context != .preMeal && override.isActive(at: date)
    }

    public func preMealTargetEnabled(at date: Date = Date()) -> Bool {
        guard let override = scheduleOverride else { return false }
        return override.context == .preMeal && override.isActive(at: date)
    }

    public func futureOverrideEnabled(relativeTo date: Date = Date()) -> Bool {
        guard let override = scheduleOverride else { return false }
        return override.startDate > date
    }

    public mutating func enablePreMealOverride(at date: Date = Date(), for duration: TimeInterval) {
        scheduleOverride = preMealOverride(beginningAt: date, for: duration)
    }

    public func preMealOverride(beginningAt date: Date = Date(), for duration: TimeInterval) -> TemporaryScheduleOverride? {
        guard let premealTargetRange = preMealTargetRange, let unit = glucoseUnit else {
            return nil
        }
        return TemporaryScheduleOverride(
            context: .preMeal,
            settings: TemporaryScheduleOverrideSettings(unit: unit, targetRange: premealTargetRange),
            startDate: date,
            duration: .finite(duration),
            enactTrigger: .local,
            syncIdentifier: UUID()
        )
    }

    public mutating func enableLegacyWorkoutOverride(at date: Date = Date(), for duration: TimeInterval) {
        scheduleOverride = legacyWorkoutOverride(beginningAt: date, for: duration)
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
        raw["scheduleOverride"] = scheduleOverride?.rawValue
        raw["maximumBasalRatePerHour"] = maximumBasalRatePerHour
        raw["maximumBolus"] = maximumBolus
        raw["minimumBGGuard"] = suspendThreshold?.rawValue
        raw["dosingStrategy"] = dosingStrategy.rawValue

        return raw
    }
}
