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

    public var preMealTargetRange: ClosedRange<LoopQuantity>?

    public var overridePresets: [TemporaryPreset] = []

    public var maximumBasalRatePerHour: Double?

    public var maximumBolus: Double?

    public var suspendThreshold: GlucoseThreshold? = nil
    
    public var automaticDosingStrategy: AutomaticDosingStrategy = .tempBasalOnly

    public var defaultRapidActingModel: ExponentialInsulinModelPreset?

    /// Every profile with Default first, or empty when Default is the only one.
    public var therapyProfiles: [TherapyProfile] = []

    /// The profile the live schedules belong to; nil means Default.
    public var activeProfileName: String?

    /// The weekly profile starts.
    public var scheduledSwitches: [ScheduledProfileSwitch] = []

    /// Scheduled starts up to this instant are settled: run, superseded or skipped.
    public var scheduledSwitchesSettledAt: Date?

    /// What made the active profile change last.
    public var activeProfileSwitchTrigger: TherapyProfileSwitchTrigger?

    public var glucoseUnit: LoopUnit? {
        return glucoseTargetRangeSchedule?.unit
    }

    public init(
        dosingEnabled: Bool = false,
        glucoseTargetRangeSchedule: GlucoseRangeSchedule? = nil,
        insulinSensitivitySchedule: InsulinSensitivitySchedule? = nil,
        basalRateSchedule: BasalRateSchedule? = nil,
        carbRatioSchedule: CarbRatioSchedule? = nil,
        preMealTargetRange: ClosedRange<LoopQuantity>? = nil,
        overridePresets: [TemporaryPreset]? = nil,
        maximumBasalRatePerHour: Double? = nil,
        maximumBolus: Double? = nil,
        suspendThreshold: GlucoseThreshold? = nil,
        automaticDosingStrategy: AutomaticDosingStrategy = .tempBasalOnly,
        defaultRapidActingModel: ExponentialInsulinModelPreset? = nil,
        therapyProfiles: [TherapyProfile] = [],
        activeProfileName: String? = nil,
        scheduledSwitches: [ScheduledProfileSwitch] = [],
        scheduledSwitchesSettledAt: Date? = nil,
        activeProfileSwitchTrigger: TherapyProfileSwitchTrigger? = nil
    ) {
        self.dosingEnabled = dosingEnabled
        self.glucoseTargetRangeSchedule = glucoseTargetRangeSchedule
        self.insulinSensitivitySchedule = insulinSensitivitySchedule
        self.basalRateSchedule = basalRateSchedule
        self.carbRatioSchedule = carbRatioSchedule
        self.preMealTargetRange = preMealTargetRange
        self.overridePresets = overridePresets ?? []
        self.maximumBasalRatePerHour = maximumBasalRatePerHour
        self.maximumBolus = maximumBolus
        self.suspendThreshold = suspendThreshold
        self.automaticDosingStrategy = automaticDosingStrategy
        self.defaultRapidActingModel = defaultRapidActingModel
        self.therapyProfiles = therapyProfiles
        self.activeProfileName = activeProfileName
        self.scheduledSwitches = scheduledSwitches
        self.scheduledSwitchesSettledAt = scheduledSwitchesSettledAt
        self.activeProfileSwitchTrigger = activeProfileSwitchTrigger
    }

    /// The live schedules as a profile named after the active profile, or nil when any schedule is missing.
    public var liveTherapyProfile: TherapyProfile? {
        TherapyProfile(name: TherapyProfiles.activeName(activeProfileName),
                       glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
                       carbRatioSchedule: carbRatioSchedule,
                       basalRateSchedule: basalRateSchedule,
                       insulinSensitivitySchedule: insulinSensitivitySchedule)
    }

    /// Every profile with Default first. Before any other profile exists this is Default alone.
    public var resolvedTherapyProfiles: [TherapyProfile] {
        TherapyProfiles.resolved(therapyProfiles, live: TherapyProfiles.activeName(activeProfileName) == TherapyProfile.defaultName ? liveTherapyProfile : nil)
    }

    /// Writes the live schedules to the active profile, stores Default as nil and drops a list holding Default alone,
    /// so the stored profiles always agree with the schedules Loop doses with. An active name that is not stored is
    /// treated as Default and returned.
    @discardableResult
    public mutating func synchronizeTherapyProfiles() -> String? {
        var unknownName: String?
        if let name = activeProfileName, name != TherapyProfile.defaultName, !therapyProfiles.contains(where: { $0.name == name }) {
            unknownName = name
            activeProfileName = nil
        }
        if activeProfileName == TherapyProfile.defaultName {
            activeProfileName = nil
        }
        var profiles = TherapyProfiles.synchronizingActive(therapyProfiles, activeProfileName: activeProfileName, live: liveTherapyProfile)
        if profiles.count == 1, profiles[0].isDefault, activeProfileName == nil {
            profiles = []
        }
        therapyProfiles = profiles
        return unknownName
    }

    /// Sets the live schedules to `profile`'s values, keeping the live glucose unit and time zone.
    public mutating func applyTherapyProfileSchedules(_ profile: TherapyProfile) {
        var applied = profile.withGlucoseUnit(glucoseTargetRangeSchedule?.unit ?? profile.glucoseTargetRangeSchedule.unit)
        if let timeZone = basalRateSchedule?.timeZone {
            applied = applied.withTimeZone(timeZone)
        }
        glucoseTargetRangeSchedule = applied.glucoseTargetRangeSchedule
        carbRatioSchedule = applied.carbRatioSchedule
        basalRateSchedule = applied.basalRateSchedule
        insulinSensitivitySchedule = applied.insulinSensitivitySchedule
    }
}

extension LoopSettings: RawRepresentable {
    public typealias RawValue = [String: Any]
    private static let version = 1
    fileprivate static let codingGlucoseUnit = LoopUnit.milligramsPerDeciliter

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
            }
        }

        if let rawPreMealTargetRange = rawValue["preMealTargetRange"] as? DoubleRange.RawValue {
            self.preMealTargetRange = DoubleRange(rawValue: rawPreMealTargetRange)?.quantityRange(for: LoopSettings.codingGlucoseUnit)
        }
        
        if let rawPresets = rawValue["overridePresets"] as? [TemporaryPreset.RawValue] {
            self.overridePresets = rawPresets.compactMap(TemporaryPreset.init(rawValue:))
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
        raw["maximumBasalRatePerHour"] = maximumBasalRatePerHour
        raw["maximumBolus"] = maximumBolus
        raw["minimumBGGuard"] = suspendThreshold?.rawValue
        raw["dosingStrategy"] = automaticDosingStrategy.rawValue
        
        return raw
    }
}
