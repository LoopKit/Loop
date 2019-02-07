//
//  LoopSettings.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit


struct LoopSettings: Equatable {
    var dosingEnabled = false

    let dynamicCarbAbsorptionEnabled = true

    var glucoseTargetRangeSchedule: GlucoseRangeSchedule?

    var preMealTargetRange: DoubleRange?

    var overridePresets: [TemporaryScheduleOverridePreset] = []

    var scheduleOverride: TemporaryScheduleOverride?

    var maximumBasalRatePerHour: Double?

    var maximumBolus: Double?

    var suspendThreshold: GlucoseThreshold? = nil

    var retrospectiveCorrectionEnabled = true

    /// The interval over which to aggregate changes in glucose for retrospective correction
    let retrospectiveCorrectionGroupingInterval = TimeInterval(minutes: 30)

    /// The maximum duration over which to integrate retrospective correction changes
    let retrospectiveCorrectionIntegrationInterval = TimeInterval(minutes: 30)

    /// The amount of time since a given date that data should be considered valid
    let recencyInterval = TimeInterval(minutes: 15)

    // MARK - Display settings

    let minimumChartWidthPerHour: CGFloat = 50

    let statusChartMinimumHistoryDisplay: TimeInterval = .hours(1)
}

extension LoopSettings {
    var glucoseTargetRangeScheduleApplyingOverrideIfActive: GlucoseRangeSchedule? {
        if let override = scheduleOverride, override.isActive() {
            return glucoseTargetRangeSchedule?.applyingOverride(override)
        } else {
            return glucoseTargetRangeSchedule
        }
    }

    func scheduleOverrideEnabled(at date: Date = Date()) -> Bool {
        guard let override = scheduleOverride else { return false }
        return override.isActive(at: date)
    }

    func nonPreMealOverrideEnabled(at date: Date = Date()) -> Bool {
        guard let override = scheduleOverride else { return false }
        return override.context != .preMeal && override.isActive(at: date)
    }

    func preMealTargetEnabled(at date: Date = Date()) -> Bool {
        guard let override = scheduleOverride else { return false }
        return override.context == .preMeal && override.isActive(at: date)
    }

    func futureOverrideEnabled(relativeTo date: Date = Date()) -> Bool {
        guard let override = scheduleOverride else { return false }
        return override.startDate > date
    }

    mutating func enablePreMealOverride(at date: Date = Date(), for duration: TimeInterval) {
        scheduleOverride = preMealOverride(beginningAt: date, for: duration)
    }

    func preMealOverride(beginningAt date: Date = Date(), for duration: TimeInterval) -> TemporaryScheduleOverride? {
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

    mutating func clearOverride(matching context: TemporaryScheduleOverride.Context? = nil) {
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
    typealias RawValue = [String: Any]
    private static let version = 1

    init?(rawValue: RawValue) {
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

        if let retrospectiveCorrectionEnabled = rawValue["retrospectiveCorrectionEnabled"] as? Bool {
            self.retrospectiveCorrectionEnabled = retrospectiveCorrectionEnabled
        }
    }

    var rawValue: RawValue {
        var raw: RawValue = [
            "version": LoopSettings.version,
            "dosingEnabled": dosingEnabled,
            "retrospectiveCorrectionEnabled": retrospectiveCorrectionEnabled,
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
