//
//  PresetsViewModel.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopAlgorithm
import LoopKit

enum PresetDurationType: Equatable {
    case untilCarbsEntered
    case duration(TimeInterval)
    case indefinite
}

enum PresetExpectedEndTime {
    case untilCarbsEntered
    case scheduled(Date)
    case indefinite
}

extension TemporaryScheduleOverride {
    var expectedEndTime: PresetExpectedEndTime? {
        switch context {
        case .preMeal: return .untilCarbsEntered
        case .legacyWorkout, .custom, .preset:
            switch duration {
            case .indefinite: return .indefinite
            case .finite: return .scheduled(scheduledEndDate)
            }
        }
    }

    var presetId: String {
        switch context {
        case .preMeal: return "preMeal"
        case .legacyWorkout: return "legacyWorkout"
        case .custom: return self.syncIdentifier.uuidString
        case .preset(let preset): return preset.id.uuidString
        }
    }
}

enum PresetIcon {
    case emoji(String)
    case image(String, Color)
}

typealias RangeSafetyClassification = (lower: SafetyClassification, upper: SafetyClassification)

enum SelectablePreset: Hashable, Identifiable {

    func hash(into hasher: inout Hasher) {
        switch self {
        case .custom(let preset):
            hasher.combine(preset)
        case .legacyWorkout(let range, _):
            hasher.combine("legacyWorkout")
            hasher.combine(range)
        case .preMeal(let range, _):
            hasher.combine("preMeal")
            hasher.combine(range)
        }
    }

    static func == (lhs: SelectablePreset, rhs: SelectablePreset) -> Bool {
        switch (lhs, rhs) {
        case (.custom(let lhsPreset), .custom(let rhsPreset)):
            return lhsPreset == rhsPreset
        case (.legacyWorkout(let lhsRange, _), .legacyWorkout(let rhsRange, _)):
            return lhsRange == rhsRange
        case (.preMeal(let lhsRange, _), .legacyWorkout(let rhsRange, _)):
            return lhsRange == rhsRange
        default:
            return false
        }
    }
    
    var id: String {
        switch self {
        case .custom(let preset): return preset.id.uuidString
        case .legacyWorkout: return "legacyWorkout"
        case .preMeal: return "preMeal"
        }
    }

    case custom(TemporaryScheduleOverridePreset)
    case preMeal(range: ClosedRange<LoopQuantity>, guardrail: Guardrail<LoopQuantity>?)
    case legacyWorkout(range: ClosedRange<LoopQuantity>, guardrail: Guardrail<LoopQuantity>?)

    var icon: PresetIcon {
        switch self {
        case .custom(let preset): return .emoji(preset.symbol)
        case .preMeal: return .image("Pre-Meal", .carbTintColor)
        case .legacyWorkout: return .image("workout", .glucoseTintColor)
        }
    }

    var duration: PresetDurationType {
        switch self {
        case .custom(let preset):
            switch preset.duration {
            case .indefinite:
                return .indefinite
            case .finite(let duration):
                return .duration(duration)
            }
        case .preMeal: return .untilCarbsEntered
        case .legacyWorkout: return .indefinite
        }
    }

    var name: String {
        switch self {
            case .custom(let preset): return preset.name
            case .preMeal: return "Pre-Meal"
            case .legacyWorkout: return "Workout"
        }
    }

    var correctionRange: ClosedRange<LoopQuantity>? {
        switch self {
        case .custom(let preset): return preset.settings.targetRange
        case .preMeal(let range, _): return range
        case .legacyWorkout(let range, _): return range
        }
    }

    var insulinSensitivityMultiplier: Double? {
        if case .custom(let preset) = self {
            return preset.settings.insulinSensitivityMultiplier
        } else {
            return nil
        }
    }

    var guardrail: Guardrail<LoopQuantity>? {
        switch self {
        case .custom:
            return nil
        case .preMeal(_, let guardrail):
            return guardrail
        case .legacyWorkout(_, let guardrail):
            return guardrail
        }
    }

    var dateCreated: Date {
        switch self {
        case .custom:
            return .distantPast // TODO
        case .preMeal:
            return .distantPast.addingTimeInterval(1)
        case .legacyWorkout:
            return .distantPast
        }
    }
    
    func title(font: Font, iconSize: Double) -> some View {
        HStack(spacing: 6) {
            switch icon {
            case .emoji(let emoji):
                Text(emoji)
            case .image(let name, let iconColor):
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(iconColor)
                    .frame(width: UIFontMetrics.default.scaledValue(for: iconSize), height: UIFontMetrics.default.scaledValue(for: iconSize))
            }

            Text(name)
                .font(font)
                .fontWeight(.semibold)
        }
    }
}

@MainActor
@Observable
public class PresetsViewModel {

    // MARK: Training
    @ObservationIgnored @AppStorage("hasCompletedPresetsTraining") var hasCompletedTraining: Bool = false
    @ObservationIgnored @AppStorage("presetsSortOrder") var selectedSortOption: PresetSortOption = .name
    @ObservationIgnored @AppStorage("presetsSortDirectionReversed") var presetsSortAscending: Bool = true

    @ObservationIgnored var correctionRangeOverrides: CorrectionRangeOverrides?
    
    let temporaryPresetsManager: TemporaryPresetsManager

    var customPresets: [TemporaryScheduleOverridePreset]
    var pendingPreset: SelectablePreset?

    public private(set) var preMealGuardrail: Guardrail<LoopQuantity>?
    public private(set) var legacyWorkoutGuardrail: Guardrail<LoopQuantity>?

    private var presetHistory: TemporaryScheduleOverrideHistory

    var activeOverride: TemporaryScheduleOverride? {
        temporaryPresetsManager.preMealOverride ?? temporaryPresetsManager.scheduleOverride
    }

    var activePreset: SelectablePreset? {
        return allPresets.first(where: { $0.id == activeOverride?.presetId })
    }

    var allPresets: [SelectablePreset] {
        var presets: [SelectablePreset] = []

        if let preMealTargetRange = correctionRangeOverrides?.preMeal {
            presets.append(.preMeal(
                range: preMealTargetRange,
                guardrail: preMealGuardrail
            ))
        }

        if let legacyWorkoutTargetRange = correctionRangeOverrides?.workout {
            presets.append(.legacyWorkout(
                range: legacyWorkoutTargetRange,
                guardrail: legacyWorkoutGuardrail
            ))
        }

        presets.append(contentsOf: customPresets.map { .custom($0)} )

        return presets
    }

    var lastUsed: [String: Date]?

    func lastUsed(id: String) -> Date? {
        if lastUsed == nil {
            let enacts = presetHistory.getOverrideHistory(startDate: .distantPast, endDate: Date())
            lastUsed = [:]
            for enact in enacts {
                var id: String
                switch enact.context {
                    case .preMeal: id = "preMeal"
                    case .legacyWorkout: id = "legacyWorkout"
                    case .preset(let preset): id = preset.id.uuidString
                    case .custom: continue
                }
                lastUsed![id] = max(lastUsed![id] ?? .distantPast, enact.startDate)
            }
        }
        return lastUsed![id]
    }

    init(
        customPresets: [TemporaryScheduleOverridePreset],
        correctionRangeOverrides: CorrectionRangeOverrides?,
        presetsHistory: TemporaryScheduleOverrideHistory,
        preMealGuardrail: Guardrail<LoopQuantity>?,
        legacyWorkoutGuardrail: Guardrail<LoopQuantity>?,
        temporaryPresetsManager: TemporaryPresetsManager
    ) {
        self.customPresets = customPresets
        self.correctionRangeOverrides = correctionRangeOverrides
        self.presetHistory = presetsHistory
        self.preMealGuardrail = preMealGuardrail
        self.legacyWorkoutGuardrail = legacyWorkoutGuardrail
        self.temporaryPresetsManager = temporaryPresetsManager
    }
    
    func startPreset(_ preset: SelectablePreset) {
        switch preset {
        case .custom(let temporaryScheduleOverridePreset):
            temporaryPresetsManager.scheduleOverride = temporaryScheduleOverridePreset.createOverride(enactTrigger: .local)
        case .preMeal:
            temporaryPresetsManager.enablePreMealOverride(for: .hours(1))
        case .legacyWorkout:
            temporaryPresetsManager.enableLegacyWorkoutOverride(for: .indefinite)
        }
    }
    
    func endPreset() {
        if case .preMeal(_, _) = activePreset {
            temporaryPresetsManager.preMealOverride = nil
        } else {
            temporaryPresetsManager.scheduleOverride = nil
        }
    }
    
    func updateActivePresetDuration(newEndDate: Date) {
        temporaryPresetsManager.updateActiveOverrideDuration(newEndDate: newEndDate)
    }
}
