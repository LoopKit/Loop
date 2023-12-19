//
//  TemporaryPresetsManager.swift
//  Loop
//
//  Created by Pete Schwamb on 11/1/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import os.log
import LoopCore
import HealthKit

protocol PresetActivationObserver: AnyObject {
    func presetActivated(context: TemporaryScheduleOverride.Context, duration: TemporaryScheduleOverride.Duration)
    func presetDeactivated(context: TemporaryScheduleOverride.Context)
}

class TemporaryPresetsManager {

    private let log = OSLog(category: "TemporaryPresetsManager")

    private var settingsProvider: SettingsProvider

    var overrideHistory = UserDefaults.appGroup?.overrideHistory ?? TemporaryScheduleOverrideHistory.init()

    private var presetActivationObservers: [PresetActivationObserver] = []

    private var overrideIntentObserver: NSKeyValueObservation? = nil

    init(settingsProvider: SettingsProvider) {
        self.settingsProvider = settingsProvider

        self.overrideHistory.relevantTimeWindow = LoopCoreConstants.defaultCarbAbsorptionTimes.slow * 2

        scheduleOverride = overrideHistory.activeOverride(at: Date())

        // TODO: Pre-meal is not stored in overrideHistory yet. https://tidepool.atlassian.net/browse/LOOP-4759
        //preMealOverride = overrideHistory.preMealOverride

        overrideIntentObserver = UserDefaults.appGroup?.observe(
            \.intentExtensionOverrideToSet,
             options: [.new],
             changeHandler:
                { [weak self] (defaults, change) in
                    self?.handleIntentOverrideAction(default: defaults, change: change)
                }
        )
    }

    private func handleIntentOverrideAction(default: UserDefaults, change: NSKeyValueObservedChange<String?>) {
        guard let name = change.newValue??.lowercased(),
              let appGroup = UserDefaults.appGroup else 
        {
            return
        }

        guard let preset = settingsProvider.settings.overridePresets.first(where: {$0.name.lowercased() == name}) else
        {
            log.error("Override Intent: Unable to find override named '%s'", String(describing: name))
            return
        }

        log.default("Override Intent: setting override named '%s'", String(describing: name))
        scheduleOverride = preset.createOverride(enactTrigger: .remote("Siri"))

        // Remove the override from UserDefaults so we don't set it multiple times
        appGroup.intentExtensionOverrideToSet = nil
    }

    public func addTemporaryPresetObserver(_ observer: PresetActivationObserver) {
        presetActivationObservers.append(observer)
    }

    public var scheduleOverride: TemporaryScheduleOverride? {
        didSet {
            guard oldValue != scheduleOverride else {
                return
            }

            if let newValue = scheduleOverride, newValue.context == .preMeal {
                preconditionFailure("The `scheduleOverride` field should not be used for a pre-meal target range override; use `preMealOverride` instead")
            }

            if scheduleOverride != oldValue {
                overrideHistory.recordOverride(scheduleOverride)

                if let oldPreset = oldValue {
                    for observer in self.presetActivationObservers {
                        observer.presetDeactivated(context: oldPreset.context)
                    }
                }
                if let newPreset = scheduleOverride {
                    for observer in self.presetActivationObservers {
                        observer.presetActivated(context: newPreset.context, duration: newPreset.duration)
                    }
                }
            }

            if scheduleOverride?.context == .legacyWorkout {
                preMealOverride = nil
            }

            notify(forChange: .preferences)
        }
    }

    public var preMealOverride: TemporaryScheduleOverride? {
        didSet {
            guard oldValue != preMealOverride else {
                return
            }

            if let newValue = preMealOverride, newValue.context != .preMeal || newValue.settings.insulinNeedsScaleFactor != nil {
                preconditionFailure("The `preMealOverride` field should be used only for a pre-meal target range override")
            }

            if preMealOverride != nil, scheduleOverride?.context == .legacyWorkout {
                scheduleOverride = nil
            }

            notify(forChange: .preferences)
        }
    }

    public var isScheduleOverrideInfiniteWorkout: Bool {
        guard let scheduleOverride = scheduleOverride else { return false }
        return scheduleOverride.context == .legacyWorkout && scheduleOverride.duration.isInfinite
    }

    public func effectiveGlucoseTargetRangeSchedule(presumingMealEntry: Bool = false) -> GlucoseRangeSchedule?  {

        guard let glucoseTargetRangeSchedule = settingsProvider.settings.glucoseTargetRangeSchedule else {
            return nil
        }

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
            return glucoseTargetRangeSchedule.applyingOverride(effectiveOverride)
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

    public func enablePreMealOverride(at date: Date = Date(), for duration: TimeInterval) {
        preMealOverride = makePreMealOverride(beginningAt: date, for: duration)
    }

    private func makePreMealOverride(beginningAt date: Date = Date(), for duration: TimeInterval) -> TemporaryScheduleOverride? {
        guard let preMealTargetRange = settingsProvider.settings.preMealTargetRange else {
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

    public func enableLegacyWorkoutOverride(at date: Date = Date(), for duration: TimeInterval) {
        scheduleOverride = legacyWorkoutOverride(beginningAt: date, for: duration)
        preMealOverride = nil
    }

    public func legacyWorkoutOverride(beginningAt date: Date = Date(), for duration: TimeInterval) -> TemporaryScheduleOverride? {
        guard let legacyWorkoutTargetRange = settingsProvider.settings.workoutTargetRange else {
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

    public func clearOverride(matching context: TemporaryScheduleOverride.Context? = nil) {
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

    public var basalRateScheduleApplyingOverrideHistory: BasalRateSchedule? {
        if let basalSchedule = settingsProvider.settings.basalRateSchedule {
            return overrideHistory.resolvingRecentBasalSchedule(basalSchedule)
        } else {
            return nil
        }
    }

    /// The insulin sensitivity schedule, applying recent overrides relative to the current moment in time.
    public var insulinSensitivityScheduleApplyingOverrideHistory: InsulinSensitivitySchedule? {
        if let insulinSensitivitySchedule = settingsProvider.settings.insulinSensitivitySchedule {
            return overrideHistory.resolvingRecentInsulinSensitivitySchedule(insulinSensitivitySchedule)
        } else {
            return nil
        }
    }

    public var carbRatioScheduleApplyingOverrideHistory: CarbRatioSchedule? {
        if let carbRatioSchedule = carbRatioSchedule {
            return overrideHistory.resolvingRecentCarbRatioSchedule(carbRatioSchedule)
        } else {
            return nil
        }
    }

    private func notify(forChange context: LoopUpdateContext) {
        NotificationCenter.default.post(name: .LoopDataUpdated,
            object: self,
            userInfo: [
                LoopDataManager.LoopUpdateContextKey: context.rawValue
            ]
        )
    }

}

public protocol SettingsWithOverridesProvider {
    var insulinSensitivityScheduleApplyingOverrideHistory: InsulinSensitivitySchedule? { get }
    var carbRatioSchedule: CarbRatioSchedule? { get }
    var maximumBolus: Double? { get }
}

extension TemporaryPresetsManager : SettingsWithOverridesProvider {
    var carbRatioSchedule: LoopKit.CarbRatioSchedule? {
        settingsProvider.settings.carbRatioSchedule
    }

    var maximumBolus: Double? {
        settingsProvider.settings.maximumBolus
    }
}
