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
    
    @State private var trainingCompletion: PresetsTrainingCompletion = PresetsTrainingCompletion()
    @State private var editMode: EditMode = .inactive
    @State private var showingMenu: Bool = false
    @State private var presentCreateView: Bool = false
    @State private var activeSheet: ActiveSheet?
    @State private var navigationPath = NavigationPath()

    @AppStorage("presetsSortAscending") private var presetsSortAscending: Bool = true
    @AppStorage("presetsSortOrder") private var selectedSortOption: PresetSortOption = .name

    var isDescending: Bool { !presetsSortAscending }

    var addDismissButton: Bool = true

    var presetsSorted: [SelectablePreset] {
        temporaryPresetsManager.selectablePresets
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

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 20) {
                    if let activePreset = temporaryPresetsManager.selectablePresets.first(where: { $0.id == temporaryPresetsManager.activePreset?.id })
                    {
                        PresetCard(
                            activePreset,
                            guardrail: settingsManager.guardrailForPreset(activePreset),
                            expectedEndTime: temporaryPresetsManager.activeOverride?.expectedEndTime
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
                            
                            Button(action: {
                                presentCreateView = true;
                            }) {
                                Image(systemName: "plus")
                            }
                            .disabled(!trainingCompletion.isComplete)
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
                                    guardrail: settingsManager.guardrailForPreset(preset)
                                    
                                )
                                .cornerRadius(12)
                                .onTapGesture {
                                    activeSheet = .presetDetent(preset)
                                }
                                .disabled(preset.id.hasPrefix("activity-") && trainingCompletion.completedChapters[.introduction] != true)
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
                                Image(systemName: "list.bullet")
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.presets)
                                    .cornerRadius(8)
                                
                                Text("Presets Performance History")
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
                                    Text("Review Presets Training")
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
                }
                .padding()
                .animation(.default, value: temporaryPresetsManager.activeOverride)
            }
            .background(Color(UIColor.secondarySystemBackground))
            .navigationTitle(Text("Presets", comment: "Presets screen title"))
            .navigationBarItems(trailing: addDismissButton ? dismissButton : nil)
            .navigationDestination(for: NavigationDestination.self) { route in
                switch route {
                case .presetsHistory:
                    PresetsHistoryView()
                }
            }
        }
        .onAppear {
            if trainingCompletion.completedChapters[.entry] != true {
                activeSheet = .training()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .presetDetent(let preset):
                PresetDetentView(preset: preset, didTapEdit: {
                    if case .activity(_) = preset, !trainingCompletion.isComplete {
                        activeSheet = .training(editPresetWhenComplete: preset)
                    } else {
                        activeSheet = .editPreset(preset)
                    }
                })
            case .editPreset(let preset):
                Group {
                    if let scheduledRange {
                        EditPresetView(
                            preset: preset,
                            scheduledRange: scheduledRange,
                            onSave: { updatedPreset in
                                settingsManager.savePreset(updatedPreset)
                                Task {
                                    await temporaryPresetsManager.scheduleNextPresetReminder()
                                }
                            },
                            onDelete: { preset in
                                settingsManager.deletePreset(preset)
                                Task {
                                    await temporaryPresetsManager.scheduleNextPresetReminder()
                                }
                            }
                        )
                    }
                }
            case .training(let navigationPath, let startingAt, let editPresetWhenComplete):
                PresetsTrainingView(navigationPath: navigationPath, startingAt: startingAt, trainingCompletion: trainingCompletion) {
                    if let editPresetWhenComplete {
                        activeSheet = .editPreset(editPresetWhenComplete)
                    }
                }
            }
        }
        .sheet(isPresented: $presentCreateView) {
            CreatePresetView()
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
    init (_ preset: SelectablePreset, guardrail: Guardrail<LoopQuantity>, expectedEndTime: PresetExpectedEndTime? = nil) {
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
            activityPresetIsModified: activityPresetIsModified
        )
    }
}
