//
//  PresetsView.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopAlgorithm
import LoopKit
import LoopKitUI
import SwiftUI
import LoopCore

enum PresetSortOption: Int, CaseIterable {
    case name
    case lastUsed
    case dateCreated

    var description: String {
        switch self {
        case .name:
            return NSLocalizedString("Name", comment: "Preset sorting option description for sorting by name")
        case .lastUsed:
            return NSLocalizedString("Last Used", comment: "Preset sorting option description for sorting by last used")
        case .dateCreated:
            return NSLocalizedString("Date Created", comment: "Preset sorting option description for sorting by date created")
        }
    }
}

// Define an enum to represent the active sheet
enum ActiveSheet: Identifiable {
    case editPreset(SelectablePreset) // For EditPresetView
    case presetDetent(SelectablePreset) // For PresetDetentView
    case training(navigationPath: [PresetsTraining.Step] = [], startingAt: PresetsTraining.Chapter? = nil, editPresetWhenComplete: SelectablePreset? = nil)

    var id: String {
        switch self {
        case .editPreset(let preset):
            return "edit_\(preset.id)" // Assuming Preset has an id
        case .presetDetent(let preset):
            return "detent_\(preset.id)"
        case .training:
            return "training"
        }
    }
}

struct PresetsView: View {

    // Define navigation routes
    enum NavigationDestination: Hashable {
        case presetsHistory
    }

    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @Environment(\.appName) private var appName
    @Environment(\.settingsManager) private var settingsManager
    @Environment(\.temporaryPresetsManager) private var temporaryPresetsManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var trainingCompletion: PresetsTrainingCompletion
    @State private var editMode: EditMode = .inactive
    @State private var showingMenu: Bool = false
    @State private var presentCreateView: Bool = false
    @State private var presentTrainingNeededAlert: Bool = false
    @State private var showPresetsTrainingSheet: Bool = false
    @State private var activeSheet: ActiveSheet?
    @State private var navigationPath = NavigationPath()
    
    private let carbStore: CarbStore
    private let doseStore: DoseStore
    private let glucoseStore: GlucoseStore
    private let trainingContent: [MediaContent]
    private let automationHistory: () -> [AutomationHistoryEntry]

    @AppStorage("presetsSortAscending") private var presetsSortAscending: Bool = true
    @AppStorage("presetsSortOrder") private var selectedSortOption: PresetSortOption = .name
    
    init(
        roundBasalRate: ((Double) -> Double)?,
        carbStore: CarbStore,
        doseStore: DoseStore,
        glucoseStore: GlucoseStore,
        trainingContent: [MediaContent],
        automationHistory: @escaping () -> [AutomationHistoryEntry]
    ) {
        self.trainingCompletion = PresetsTrainingCompletion(allowDebugFeatures: FeatureFlags.allowDebugFeatures)
        self.roundBasalRate = roundBasalRate
        self.carbStore = carbStore
        self.doseStore = doseStore
        self.glucoseStore = glucoseStore
        self.trainingContent = trainingContent
        self.automationHistory = automationHistory
    }

    var isDescending: Bool { !presetsSortAscending }

    var presetsSorted: [SelectablePreset] {
        temporaryPresetsManager.listedPresets
            .filter { $0.id != temporaryPresetsManager.activeOverride?.presetId }
            .sorted(by: {
            switch (selectedSortOption) {
            case .name:
                return ($0.name.lowercased() < $1.name.lowercased()) != isDescending
            case .dateCreated:
                return ($0.dateCreated > $1.dateCreated) != isDescending
            default:
                return ((temporaryPresetsManager.lastUsed(id: $0.id) ?? .distantPast) > (temporaryPresetsManager.lastUsed(id: $1.id) ?? .distantPast)) != isDescending
            }
        })
    }

    var scheduledRange: ClosedRange<LoopQuantity>? {
        settingsManager.therapySettings.glucoseTargetRangeSchedule?.quantityRange(at: Date())
    }
    
    let roundBasalRate: ((Double) -> Double)?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 20) {
                    if let activePreset = temporaryPresetsManager.selectablePresets.first(where: { $0.id == temporaryPresetsManager.activePreset?.id })
                    {
                        PresetCard(
                            activePreset,
                            guardrail: settingsManager.correctionRangeGuardrailForPreset(activePreset),
                            expectedEndTime: temporaryPresetsManager.activeOverride?.expectedEndTime,
                            activePresetId: { temporaryPresetsManager.activePreset?.id },
                            effectiveCorrectionRange: temporaryPresetsManager.effectiveCorrectionRange
                        )
                        .onTapGesture {
                            activeSheet = .presetDetent(activePreset)
                        }
                    }
                    
                    // All Presets Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("All Presets")
                                .font(.headline.weight(.semibold))
                                .accessibilityIdentifier("text_AllPresets")
                            Spacer()
                            
                            Button("Sort") {
                                showingMenu.toggle()
                            }
                            .popover(isPresented: $showingMenu) {
                                sortMenu
                            }
                            
                            Button(action: createPreset) {
                                Image(systemName: "plus")
                            }
                            .foregroundStyle(trainingCompletion.isComplete ? Color.accentColor : Color.secondary)
                        }
                        .padding(.horizontal, 10)
                        
                        LazyVStack(spacing: 12) {
                            if !trainingCompletion.isComplete {
                                PresetsTrainingCard(trainingCompletion: trainingCompletion)
                                    .onTapGesture {
                                        activeSheet = .training()
                                    }
                            }
                            
                            ForEach(presetsSorted) { preset in
                                PresetCard(
                                    preset,
                                    guardrail: settingsManager.correctionRangeGuardrailForPreset(preset),
                                    activePresetId: { temporaryPresetsManager.activePreset?.id },
                                    effectiveCorrectionRange: temporaryPresetsManager.effectiveCorrectionRange
                                )
                                .cornerRadius(12)
                                .onTapGesture {
                                    activeSheet = .presetDetent(preset)
                                }
                            }

                            if presetsSorted.isEmpty {
                                createPresetButton
                            }
                        }
                    }

                    // Support Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Support")
                            .font(.headline.weight(.semibold))
                            .padding(.horizontal, 10)
                        
                        NavigationLink(value: NavigationDestination.presetsHistory) {
                            HStack {
                                Image("performance-history-empty")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                
                                Text("Performance History")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(10)
                        .foregroundStyle(.primary)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(Color(UIColor.tertiarySystemBackground))
                            .stroke(Color(UIColor.secondarySystemBackground), lineWidth: 1)
                            .frame(maxWidth: .infinity))
                        
                        if trainingCompletion.isComplete {
                            Button {
                                activeSheet = .training()
                            } label: {
                                HStack {
                                    Image("book")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                    
                                    Text("Learning Hub")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(10)
                            .foregroundStyle(.primary)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(Color(UIColor.tertiarySystemBackground))
                                .stroke(Color(UIColor.secondarySystemBackground), lineWidth: 1)
                                .frame(maxWidth: .infinity))
                        }
                    }

                    // Options Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Options", comment: "Presets screen section header for display options")
                            .font(.headline.weight(.semibold))
                            .padding(.horizontal, 10)

                        activityPresetsToggle
                    }
                }
                .padding()
                .animation(.default, value: temporaryPresetsManager.activeOverride)
            }
            .background(Color(UIColor.secondarySystemBackground))
            .navigationTitle(Text("Presets", comment: "Presets screen title"))
            .navigationBarItems(trailing: dismissButton)
            .navigationDestination(for: NavigationDestination.self) { route in
                switch route {
                case .presetsHistory:
                    PresetsHistoryView(
                        temporaryPresetsManager: temporaryPresetsManager,
                        glucoseStore: glucoseStore,
                        carbStore: carbStore,
                        doseStore: doseStore,
                        automationHistory: automationHistory
                    )
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .presetDetent(let preset):
                PresetDetentView(preset: preset, roundBasalRate: roundBasalRate, didTapEdit: {
                    activeSheet = .editPreset(preset)
                })
            case .editPreset(let preset):
                Group {
                    if let scheduledRange {
                        EditPresetView(
                            preset: preset,
                            scheduledRange: scheduledRange,
                            trainingCompletion: trainingCompletion,
                            onSave: { updatedPreset in
                                settingsManager.savePreset(updatedPreset)
                                Task {
                                    await temporaryPresetsManager.scheduleNextPresetReminder()
                                }
                            },
                            onDelete: { preset in
                                settingsManager.deletePreset(preset)
                                Task {
                                    await temporaryPresetsManager.unschedulePresetReminderIfNeeded(preset)
                                    await temporaryPresetsManager.scheduleNextPresetReminder()
                                }
                            },
                            correctionRangeGuardrailForPreset: settingsManager.correctionRangeGuardrailForPreset,
                            impactForInsulinMultiplier: { settingsManager.therapySettings.impact(for: $0) },
                            showPresetsTrainingSheet: { showPresetsTrainingSheet = true },
                            suspendThreshold: { settingsManager.settings.suspendThreshold }
                        )
                        .sheet(isPresented: $showPresetsTrainingSheet) {
                            PresetsTrainingView(
                                trainingCompletionConfiguration: .trainingCompletion(trainingCompletion),
                                trainingContent: trainingContent
                            )
                        }
                    }
                }
            case .training(let navigationPath, let startingAt, let editPresetWhenComplete):
                PresetsTrainingView(
                    navigationPath: navigationPath,
                    startingAt: startingAt,
                    trainingCompletionConfiguration: .trainingCompletion(trainingCompletion),
                    trainingContent: trainingContent
                ) {
                    if let editPresetWhenComplete {
                        activeSheet = .editPreset(editPresetWhenComplete)
                    }
                }
            }
        }
        .sheet(isPresented: $presentCreateView) {
            CreatePresetView(
                createPreset: settingsManager.createPreset,
                impactForInsulinMultiplier: { settingsManager.therapySettings.impact(for: $0) },
                scheduleNextPresetReminder: temporaryPresetsManager.scheduleNextPresetReminder,
                scheduledRange: { scheduledRange },
                setScheduleOverride: { temporaryPresetsManager.scheduleOverride = $0 },
                suspendThreshold: { settingsManager.settings.suspendThreshold }
            )
        }
        .alert(isPresented: $presentTrainingNeededAlert) {
            trainingNeededAlert
        }
        .onChange(of: temporaryPresetsManager.showsActivityPresets, initial: true) { _, showsActivityPresets in
            trainingCompletion.exerciseRequired = showsActivityPresets
        }
    }

    private func createPreset() {
        if trainingCompletion.isComplete {
            presentCreateView = true
        } else {
            presentTrainingNeededAlert = true
        }
    }

    private var createPresetButton: some View {
        Button(action: createPreset) {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 44))
                Text("Create New Preset", comment: "Button shown in place of the preset list when there are no presets")
                    .font(.headline)
            }
            .foregroundStyle(trainingCompletion.isComplete ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.tertiarySystemBackground)))
        }
        .accessibilityIdentifier("button_CreateNewPreset")
    }

    private var activityPresetsToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { temporaryPresetsManager.showsActivityPresets },
                set: { newValue in withAnimation { temporaryPresetsManager.showsActivityPresets = newValue } }
            )) {
                Text("Show Activity Presets", comment: "Title of the toggle that shows or hides the built-in activity presets")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor.tertiarySystemBackground))
                .stroke(Color(UIColor.secondarySystemBackground), lineWidth: 1)
                .frame(maxWidth: .infinity))
            .accessibilityIdentifier("toggle_ShowActivityPresets")

            Text(activityPresetsFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
        }
    }

    private var activityPresetsFooter: String {
        let names = ListFormatter.localizedString(byJoining: ActivityPreset.ActivityType.allCases.map(\.name))
        return String(format: NSLocalizedString("%1$@. While hidden, the Presets for Exercise training chapter is optional.", comment: "Footer under the Show Activity Presets toggle. (1: list of activity preset names)"), names)
    }

    private var trainingNeededAlert: SwiftUI.Alert {
        Alert(title: Text("Training Required for New Presets", comment: "Preset training needed alert title"),
              message: Text("To create a new preset, you must complete the required training.", comment: "Preset training needed alert message"),
              primaryButton: startNeededTrainingButton,
              secondaryButton: closeButton)
    }
    
    private var startNeededTrainingButton: SwiftUI.Alert.Button {
        .cancel(Text("Close", comment: "Preset training needed alert cancel button"))
    }

    private var closeButton: SwiftUI.Alert.Button {
        .default(Text("Start Required Training", comment: "CPreset training needed alert start training button")) {
            activeSheet = .training()
        }
    }

    private var sortMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sort By")
                    .font(.headline)
                Spacer()
                Button(action: {
                    presetsSortAscending.toggle()
                }) {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
            .padding(.horizontal)
            .padding(.top, 20)
            Divider()

            ForEach(PresetSortOption.allCases, id: \.self) { option in
                Button(action: {
                    selectedSortOption = option
                    showingMenu = false
                }) {
                    HStack {
                        if selectedSortOption == option {
                            Image(systemName: "checkmark")
                        } else {
                            Image(systemName: "checkmark")
                                .hidden()
                        }
                        Text(option.description)
                            .font(.body)
                    }
                    .padding(.horizontal)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, option == PresetSortOption.allCases.last ? 12 : 0)
                if option != PresetSortOption.allCases.last {
                    Divider()
                }
            }
        }
        .frame(width: 200)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .presentationCompactAdaptation(.popover)
    }

    private var dismissButton: some View {
        Button("Done") {
            dismiss()
        }
        .bold()
        .accessibilityIdentifier("button_done")
    }
}

extension PresetCard {
    init (_ preset: SelectablePreset, guardrail: Guardrail<LoopQuantity>, expectedEndTime: PresetExpectedEndTime? = nil, activePresetId: @escaping () -> String?, effectiveCorrectionRange: @escaping () -> ClosedRange<LoopQuantity>?) {
        var activityPresetIsModified: Bool? = nil
        if case let .activity(activityPreset) = preset {
            activityPresetIsModified = activityPreset.isModifiedFromDefault
        }
        
        self.init(
            presetId: preset.id,
            icon: preset.icon,
            presetName: preset.name,
            duration: preset.duration,
            insulinMultiplier: preset.insulinNeedsScaleFactor,
            correctionRange: preset.correctionRange,
            guardrail: guardrail,
            expectedEndTime: expectedEndTime,
            isScheduled: preset.isScheduled,
            activityPresetIsModified: activityPresetIsModified,
            activePresetId: activePresetId,
            effectiveCorrectionRange: effectiveCorrectionRange
        )
    }
}
