//
//  SelectablePreset.swift
//  Loop
//
//  Created by Pete Schwamb on 3/19/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import LoopKit
import SwiftUI
import LoopAlgorithm

public enum PresetDuration: Equatable {
    case untilCarbsEntered
    case duration(TimeInterval)
    case indefinite

    public var presetDuration: TemporaryScheduleOverride.Duration {
        switch self {
        case .indefinite: return .indefinite
        case .duration(let duration): return .finite(duration)
        case .untilCarbsEntered: return .indefinite
        }
    }
}

public enum PresetExpectedEndTime {
    case untilCarbsEntered
    case scheduled(Date)
    case indefinite
}

extension TemporaryScheduleOverride.Duration {
    public var presetDurationType: PresetDuration {
        switch self {
        case .finite(let interval):
            return .duration(interval)
        case .indefinite:
            return .indefinite
        }
    }
}

extension TemporaryScheduleOverride {
    public var expectedEndTime: PresetExpectedEndTime? {
        switch context {
        case .preMeal: return .untilCarbsEntered
        case .activity, .custom, .preset:
            switch duration {
            case .indefinite: return .indefinite
            case .finite: return .scheduled(scheduledEndDate)
            }
        }
    }

    public var presetId: String {
        switch context {
        case .preMeal: return "preMeal"
        case .activity(let activity): return activity.presetId
        case .custom: return self.syncIdentifier.uuidString
        case .preset(let preset): return preset.id
        }
    }
}

extension ActivityPreset {
    var presetId: String {
        "activity-\(id)"
    }
}

extension PresetDuration: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .indefinite:
            hasher.combine("indefinite")
        case .untilCarbsEntered:
            hasher.combine("untilCarbsEntered")
        case .duration(let interval):
            hasher.combine("duration")
            hasher.combine(interval)
        }
    }
}

public enum SelectablePreset: Hashable, Identifiable {

    case custom(TemporaryPreset)
    case preMeal(range: ClosedRange<LoopQuantity>)
    case activity(ActivityPreset)

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .custom(let preset):
            hasher.combine(preset)
        case .activity(let activity):
            hasher.combine(activity)
        case .preMeal(let range):
            hasher.combine("preMeal")
            hasher.combine(range)
        }
    }

    public static func == (lhs: SelectablePreset, rhs: SelectablePreset) -> Bool {
        switch (lhs, rhs) {
        case (.custom(let lhsPreset), .custom(let rhsPreset)):
            return lhsPreset == rhsPreset
        case (.activity(let lhsActivity), .activity(let rhsActivity)):
            return lhsActivity == rhsActivity
        case (.preMeal(let lhsRange), .preMeal(let rhsRange)):
            return lhsRange == rhsRange
        default:
            return false
        }
    }

    public var id: String {
        switch self {
        case .custom(let preset): return preset.id
        case .activity(let activity): return activity.presetId
        case .preMeal: return "preMeal"
        }
    }

    public var icon: PresetSymbol? {
        switch self {
        case .custom(let preset): return preset.symbol
        case .preMeal: return .image("Pre-Meal-symbol", tint: .preMeal)
        case .activity(let activity): return activity.activityType.symbol
        }
    }

    public var duration: PresetDuration {
        get {
            switch self {
            case .custom(let preset):
                switch preset.duration {
                case .indefinite:
                    return .indefinite
                case .finite(let duration):
                    return .duration(duration)
                }
            case .activity(let activity):
                switch activity.preset.duration {
                case .indefinite:
                    return .indefinite
                case .finite(let duration):
                    return .duration(duration)
                }
            case .preMeal: return .untilCarbsEntered
            }
        }
        set {
            switch self {
            case .preMeal(let range):
                self = .preMeal(range: range)
            case .activity(var activity):
                activity.preset.settings = TemporaryPresetSettings(targetRange: activity.preset.settings.targetRange, insulinNeedsScaleFactor: activity.preset.settings.insulinNeedsScaleFactor)
                switch newValue {
                case .indefinite:
                    activity.preset.duration = .indefinite
                case .duration(let duration):
                    activity.preset.duration = .finite(duration)
                default:
                    break
                }
                self = .activity(activity)
            case .custom(var preset):
                preset.settings = TemporaryPresetSettings(targetRange: preset.settings.targetRange, insulinNeedsScaleFactor: preset.settings.insulinNeedsScaleFactor)
                switch newValue {
                case .indefinite:
                    preset.duration = .indefinite
                case .duration(let duration):
                    preset.duration = .finite(duration)
                default:
                    break
                }
                self = .custom(preset)
            }
        }
    }

    public var isScheduled: Bool {
        return nextScheduledStartAfter(Date()) != nil
    }

    public func nextScheduledStartAfter(_ date: Date) -> Date? {
        switch self {
        case .custom(let preset):
            return preset.nextScheduledStartAfter(date)
        case .preMeal, .activity:
            return nil
        }
    }

    public var scheduleStartDate: Date? {
        get {
            switch self {
            case .custom(let preset):
                return preset.scheduleStartDate
            case .preMeal, .activity:
                return nil
            }
        }
        set {
            switch self {
            case .custom(var preset):
                preset.scheduleStartDate = newValue
                self = .custom(preset)
            default:
                break
            }
        }
    }

    public var repeatOptions: PresetScheduleRepeatOptions {
        get {
            switch self {
            case .custom(let preset):
                return preset.repeatOptions ?? .none
            case .preMeal, .activity:
                return .none
            }
        }
        set {
            switch self {
            case .custom(var preset):
                preset.repeatOptions = newValue
                self = .custom(preset)
            default:
                break
            }
        }
    }


    public var name: String {
        get {
            switch self {
            case .custom(let preset): return preset.name
            case .preMeal: return NSLocalizedString("Pre-Meal", comment: "The title of pre-meal preset")
            case .activity(let activity): return activity.activityType.name
            }
        }
        set {
            switch self {
            case .custom(var preset): preset.name = newValue; self = .custom(preset)
            default: break
            }
        }
    }

    public var correctionRange: ClosedRange<LoopQuantity>? {
        get {
            switch self {
            case .custom(let preset): return preset.settings.targetRange
            case .preMeal(let range): return range
            case .activity(let activity): return activity.preset.settings.targetRange
            }
        }

        set {
            switch self {
            case .preMeal:
                self = .preMeal(range: newValue!)
            case .activity(var activity):
                activity.preset.settings = TemporaryPresetSettings(targetRange: newValue, insulinNeedsScaleFactor: activity.preset.settings.insulinNeedsScaleFactor)
                self = .activity(activity)
            case .custom(var preset):
                preset.settings = TemporaryPresetSettings(targetRange: newValue, insulinNeedsScaleFactor: preset.settings.insulinNeedsScaleFactor)
                self = .custom(preset)
            }
        }
    }

    public var insulinSensitivityMultiplier: Double? {
        if case .custom(let preset) = self {
            return preset.settings.insulinSensitivityMultiplier
        } else if case .activity(let activity) = self {
            return activity.preset.settings.insulinSensitivityMultiplier
        } else {
            return nil
        }
    }
    
    public var insulinNeedsScaleFactor: Double {
        get {
            if case .custom(let preset) = self {
                return 1.0 / (preset.settings.insulinSensitivityMultiplier ?? 1)
            } else if case .activity(let activity) = self {
                return 1.0 / (activity.preset.settings.insulinSensitivityMultiplier ?? 1)
            } else {
                return 1.0
            }
        }
        set {
            if case .activity(var activity) = self {
                activity.preset.settings = TemporaryPresetSettings(targetRange: activity.preset.settings.targetRange, insulinNeedsScaleFactor: newValue)
                self = .activity(activity)
            } else if case .custom(var preset) = self {
                preset.settings = TemporaryPresetSettings(targetRange: preset.settings.targetRange, insulinNeedsScaleFactor: newValue)
                self = .custom(preset)
            }
        }
    }

    public var canAdjustSensitivity: Bool {
        switch self {
        case .custom, .activity:
            return true
        case .preMeal:
            return false
        }
    }

    public var allowsIndefiniteDuration: Bool {
        switch self {
        case .custom:
            return true
        case .preMeal, .activity:
            return false
        }
    }
    
    public var canAdjustDuration: Bool {
        switch self {
        case .custom, .activity:
            return true
        case .preMeal:
            return false
        }
    }

    public var canChangeName: Bool {
        switch self {
        case .custom:
            return true
        case .preMeal, .activity:
            return false
        }
    }

    public var allowsScheduling: Bool {
        switch self {
        case .custom:
            return true
        case .preMeal, .activity:
            return false
        }
    }

    public var canBeDeleted: Bool {
        switch self {
        case .custom:
            return true
        case .preMeal, .activity:
            return false
        }
    }

    public var isPreMeal: Bool {
        if case .preMeal = self {
            return true
        }
        return false
    }

    public var dateCreated: Date {
        switch self {
        case .custom:
            return .distantPast // TODO
        case .preMeal:
            return .distantPast.addingTimeInterval(1)
        case .activity:
            return .distantPast
        }
    }
}

extension SelectablePreset {
    public func createOverride(beginningAt: Date = Date()) -> TemporaryScheduleOverride {
        switch self {
        case .custom(let temporaryScheduleOverridePreset):
            return temporaryScheduleOverridePreset.createOverride(enactTrigger: .local, beginningAt: beginningAt)
        case .activity(let activity):
            return activity.preset.createOverride(enactTrigger: .local, beginningAt: beginningAt)
        case .preMeal(let targetRange):
            return TemporaryScheduleOverride(
                context: .preMeal,
                settings: TemporaryPresetSettings(targetRange: targetRange),
                startDate: beginningAt,
                duration: .finite(.hours(1)),
                enactTrigger: .local,
                syncIdentifier: UUID()
            )
        }

    }
}

extension TemporaryScheduleOverride {
    public func createPreset() -> SelectablePreset {
        let range = settings.targetRange

        switch context {
        case .preMeal:
            return .preMeal(range: range!)
        case .activity(let activity):
            return .activity(activity)
        case .custom:
            let preset = TemporaryPreset(
                id: syncIdentifier.uuidString,
                symbol: nil,
                name: NSLocalizedString("Single Use Preset", comment: "The title shown for a single use preset"),
                settings: settings,
                duration: duration
            )
            return .custom(preset)
        case .preset(let preset):
            return .custom(preset)
        }
    }
}


extension PresetExpectedEndTime {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    public var localizedTitle: String {
        switch self {
        case .untilCarbsEntered:
            return NSLocalizedString("on until carbs added", comment: "Preset card pre-meal expected end time")
        case .indefinite:
            return NSLocalizedString("on until turned off", comment: "Preset card indefinite scheduled end time")
        case .scheduled(let date):
            return NSLocalizedString("on until \(Self.timeFormatter.string(from: date))", comment: "Presets card time duration accessibility label")
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .untilCarbsEntered:
            return NSLocalizedString("on until carbs added", comment: "Presets card pre-meal expected end time accessibility label")
        case .indefinite:
            return NSLocalizedString("on until turned off", comment: "Presets card indefinite duration accessibility label")
        case .scheduled(let date):
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .spellOut
            return NSLocalizedString("on until \(Self.timeFormatter.string(from: date))", comment: "Presets card time duration accessibility label")
        }
    }
}

extension PresetDuration {
    public var localizedTitle: String {
        switch self {
        case .untilCarbsEntered:
            return NSLocalizedString("until carbs added", comment: "Preset card pre-meal duration")
        case .indefinite:
            return NSLocalizedString("until turned off", comment: "Preset card indefinite duration")
        case .duration(let duration):
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .short
            return formatter.string(from: duration) ?? ""

        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .untilCarbsEntered:
            return NSLocalizedString("Active until carbs are added", comment: "Presets card pre-meal duration accessibility label")
        case .indefinite:
            return NSLocalizedString("Active until turned off", comment: "Presets card indefinite duration accessibility label")
        case .duration(let duration):
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .spellOut
            return NSLocalizedString("Active for \(formatter.string(from: duration) ?? "")", comment: "Presets card time duration accessibility label")
        }
    }
}
