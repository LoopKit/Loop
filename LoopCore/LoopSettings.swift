//
//  LoopSettings.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit


public struct LoopSettings: Equatable {
    public var dosingEnabled = false

    public let dynamicCarbAbsorptionEnabled = true

    public static let defaultCarbAbsorptionTimes: CarbStore.DefaultAbsorptionTimes = (fast: .hours(2), medium: .hours(3), slow: .hours(4))

    public var glucoseTargetRangeSchedule: GlucoseRangeSchedule?

    public var preMealTargetRange: DoubleRange?

    public var overridePresets: [TemporaryScheduleOverridePreset] = []

    public var scheduleOverride: TemporaryScheduleOverride?

    public var maximumBasalRatePerHour: Double?

    public var maximumBolus: Double?

    public var suspendThreshold: GlucoseThreshold? = nil

    public var integralRetrospectiveCorrectionEnabled = false

    /// The interval over which to aggregate changes in glucose for retrospective correction
    public let retrospectiveCorrectionGroupingInterval = TimeInterval(minutes: 30)

    /// The maximum duration over which to integrate retrospective correction changes
    public let retrospectiveCorrectionIntegrationInterval = TimeInterval(minutes: 180)

    /// The amount of time since a given date that data should be considered valid
    public let recencyInterval = TimeInterval(minutes: 15)

    // MARK - Display settings

    public let minimumChartWidthPerHour: CGFloat = 50

    public let statusChartMinimumHistoryDisplay: TimeInterval = .hours(1)

    public init(
        dosingEnabled: Bool = false,
        glucoseTargetRangeSchedule: GlucoseRangeSchedule? = nil,
        maximumBasalRatePerHour: Double? = nil,
        maximumBolus: Double? = nil,
        suspendThreshold: GlucoseThreshold? = nil,
        integralRetrospectiveCorrectionEnabled: Bool = true
    ) {
        self.dosingEnabled = dosingEnabled
        self.glucoseTargetRangeSchedule = glucoseTargetRangeSchedule
        self.maximumBasalRatePerHour = maximumBasalRatePerHour
        self.maximumBolus = maximumBolus
        self.suspendThreshold = suspendThreshold
        self.integralRetrospectiveCorrectionEnabled = integralRetrospectiveCorrectionEnabled
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
        guard let premealTargetRange = preMealTargetRange else {
            return nil
        }
        return TemporaryScheduleOverride(
            context: .preMeal,
            settings: TemporaryScheduleOverrideSettings(targetRange: premealTargetRange),
            startDate: date,
            duration: .finite(duration)
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

            // Migrate the pre-meal target
            if let overrideRangesRawValue = glucoseRangeScheduleRawValue["overrideRanges"] as? [String: DoubleRange.RawValue],
                let preMealTargetRawValue = overrideRangesRawValue["preMeal"] {
                self.preMealTargetRange = DoubleRange(rawValue: preMealTargetRawValue)
            }
        }

        if let rawPreMealTargetRange = rawValue["preMealTargetRange"] as? DoubleRange.RawValue {
            self.preMealTargetRange = DoubleRange(rawValue: rawPreMealTargetRange)
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

        if let integralRetrospectiveCorrectionEnabled = rawValue["integralRetrospectiveCorrectionEnabled"] as? Bool {
            self.integralRetrospectiveCorrectionEnabled = integralRetrospectiveCorrectionEnabled
        }
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "version": LoopSettings.version,
            "dosingEnabled": dosingEnabled,
            "integralRetrospectiveCorrectionEnabled": integralRetrospectiveCorrectionEnabled,
            "overridePresets": overridePresets.map { $0.rawValue }
        ]

        raw["glucoseTargetRangeSchedule"] = glucoseTargetRangeSchedule?.rawValue
        raw["preMealTargetRange"] = preMealTargetRange?.rawValue
        raw["scheduleOverride"] = scheduleOverride?.rawValue
        raw["maximumBasalRatePerHour"] = maximumBasalRatePerHour
        raw["maximumBolus"] = maximumBolus
        raw["minimumBGGuard"] = suspendThreshold?.rawValue

        return raw
    }
}
