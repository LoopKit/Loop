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

protocol PresetActivationObserver: AnyObject {
    func presetActivated(context: TemporaryScheduleOverride.Context, duration: TemporaryScheduleOverride.Duration)
    func presetDeactivated(context: TemporaryScheduleOverride.Context)
}

@Observable
class TemporaryPresetsManager {

    @ObservationIgnored private let log = OSLog(category: "TemporaryPresetsManager")

    @ObservationIgnored private var settingsProvider: SettingsProvider

    var overrideHistory: TemporaryScheduleOverrideHistory

    @ObservationIgnored private var presetActivationObservers: [PresetActivationObserver] = []

    @ObservationIgnored private var overrideIntentObserver: NSKeyValueObservation? = nil

    @MainActor
    init(settingsProvider: SettingsProvider) {
        self.settingsProvider = settingsProvider
        
        self.overrideHistory = TemporaryScheduleOverrideHistoryContainer.shared.fetch()
        TemporaryScheduleOverrideHistory.relevantTimeWindow = Bundle.main.localCacheDuration

        scheduleOverride = overrideHistory.activeOverride(at: Date())

        if scheduleOverride?.context == .preMeal {
            preMealOverride = scheduleOverride
            scheduleOverride = nil
        }

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

            if scheduleOverride != nil {
                preMealOverride = nil
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
                    
                    scheduleClearOverride(override: newPreset)
                }
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
            
            if preMealOverride != nil {
                scheduleOverride = nil
            }
            
            overrideHistory.recordOverride(preMealOverride)

            if let newPreset = preMealOverride {
                for observer in self.presetActivationObservers {
                    observer.presetActivated(context: newPreset.context, duration: newPreset.duration)
                }
                
                scheduleClearOverride(override: newPreset)
            }
            
            notify(forChange: .preferences)
        }
    }
    
    public var activeOverride: TemporaryScheduleOverride? {
        let override = (preMealOverride ?? scheduleOverride)
        if override?.isActive() == true {
            return override
        } else {
            return nil
        }
    }

    var clearOverrideTimer: Timer?
    public func scheduleClearOverride(override: TemporaryScheduleOverride) {
        clearOverrideTimer?.invalidate()
        clearOverrideTimer = Timer.scheduledTimer(withTimeInterval: override.scheduledEndDate.timeIntervalSince(Date()), repeats: false, block: { [weak self] _ in
            if override == self?.scheduleOverride {
                self?.clearOverride()
            } else if override == self?.preMealOverride {
                self?.clearOverride(matching: .preMeal)
            }
        })
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

    public func isScheduleOverrideActive(at date: Date = Date()) -> Bool {
        return scheduleOverride?.isActive(at: date) == true
    }

    public func isNonPreMealOverrideActive(at date: Date = Date()) -> Bool {
        return isScheduleOverrideActive(at: date) == true && scheduleOverride?.context != .preMeal
    }

    public func isPreMealTargetActive(at date: Date = Date()) -> Bool {
        return isScheduleOverrideActive(at: date) == true && scheduleOverride?.context == .preMeal
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

    public func enableLegacyWorkoutOverride(at date: Date = Date(), for duration: TemporaryScheduleOverride.Duration) {
        scheduleOverride = legacyWorkoutOverride(beginningAt: date, for: duration)
        preMealOverride = nil
    }

    public func legacyWorkoutOverride(beginningAt date: Date = Date(), for duration: TemporaryScheduleOverride.Duration) -> TemporaryScheduleOverride? {
        guard let legacyWorkoutTargetRange = settingsProvider.settings.workoutTargetRange else {
            return nil
        }

        return TemporaryScheduleOverride(
            context: .legacyWorkout,
            settings: TemporaryScheduleOverrideSettings(targetRange: legacyWorkoutTargetRange),
            startDate: date,
            duration: duration,
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
    
    func updateActiveOverrideDuration(newEndDate: Date) {
        if var scheduleOverride {
            if newEndDate > Date() {
                scheduleOverride.scheduledEndDate = newEndDate
            } else {
                scheduleOverride.scheduledEndDate = newEndDate.addingTimeInterval(.days(1))
            }
            
            self.scheduleOverride = scheduleOverride
            self.scheduleClearOverride(override: scheduleOverride)
        }
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
