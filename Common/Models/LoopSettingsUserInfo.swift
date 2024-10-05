//
//  LoopSettingsUserInfo.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import LoopCore
import LoopKit

struct LoopSettingsUserInfo: Equatable {
    var loopSettings: LoopSettings
    var scheduleOverride: TemporaryScheduleOverride?
    var preMealOverride: TemporaryScheduleOverride?

    public mutating func enablePreMealOverride(at date: Date = Date(), for duration: TimeInterval) {
        preMealOverride = makePreMealOverride(beginningAt: date, for: duration)
    }

    private func makePreMealOverride(beginningAt date: Date = Date(), for duration: TimeInterval) -> TemporaryScheduleOverride? {
        guard let preMealTargetRange = loopSettings.preMealTargetRange else {
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

    public mutating func clearOverride(matching context: TemporaryScheduleOverride.Context? = nil) {
        if context == .preMeal {
            preMealOverride = nil
            return
        }

        guard let scheduleOverride = scheduleOverride else { return }

        if let context = context {
            if scheduleOverride.context == context {
                self.scheduleOverride = nil
            }
        } else {
            self.scheduleOverride = nil
        }
    }

    public func nonPreMealOverrideEnabled(at date: Date = Date()) -> Bool {
        return scheduleOverride?.isActive(at: date) == true
    }

    public mutating func legacyWorkoutOverride(beginningAt date: Date = Date(), for duration: TimeInterval) -> TemporaryScheduleOverride? {
        guard let legacyWorkoutTargetRange = loopSettings.legacyWorkoutTargetRange else {
            return nil
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

}


extension LoopSettingsUserInfo: RawRepresentable {
    typealias RawValue = [String: Any]

    static let name = "LoopSettingsUserInfo"
    static let version = 1

    init?(rawValue: RawValue) {
        guard rawValue["v"] as? Int == LoopSettingsUserInfo.version,
            rawValue["name"] as? String == LoopSettingsUserInfo.name,
            let settingsRaw = rawValue["s"] as? LoopSettings.RawValue,
            let loopSettings = LoopSettings(rawValue: settingsRaw)
        else {
            return nil
        }

        self.loopSettings = loopSettings

        if let rawScheduleOverride = rawValue["o"] as? TemporaryScheduleOverride.RawValue {
            self.scheduleOverride = TemporaryScheduleOverride(rawValue: rawScheduleOverride)
        } else {
            self.scheduleOverride = nil
        }

        if let rawPreMealOverride = rawValue["p"] as? TemporaryScheduleOverride.RawValue {
            self.preMealOverride = TemporaryScheduleOverride(rawValue: rawPreMealOverride)
        } else {
            self.preMealOverride = nil
        }
    }

    var rawValue: RawValue {
        var raw: RawValue = [
            "v": LoopSettingsUserInfo.version,
            "name": LoopSettingsUserInfo.name,
            "s": loopSettings.rawValue
        ]

        raw["o"] = scheduleOverride?.rawValue
        raw["p"] = preMealOverride?.rawValue

        return raw
    }
}
