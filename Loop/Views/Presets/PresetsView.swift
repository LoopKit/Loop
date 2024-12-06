//
//  PresetsView.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Foundation

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

struct PresetsView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var viewModel: PresetsViewModel

    @State private var editMode: EditMode = .inactive
    @State private var showingMenu: Bool = false
    @State var showTraining: Bool = false


    var isDescending: Bool { !viewModel.presetsSortAscending }

    init(viewModel: PresetsViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var presetsSorted: [SelectablePreset] {
        viewModel.allPresets
            .filter { $0.id != viewModel.activeOverride?.presetId }
            .sorted(by: {
            switch (viewModel.selectedSortOption) {
            case .name:
                return ($0.name.lowercased() < $1.name.lowercased()) != isDescending
            case .dateCreated:
                return ($0.dateCreated > $1.dateCreated) != isDescending
            default:
                return ((viewModel.lastUsed(id: $0.id) ?? .distantPast) > (viewModel.lastUsed(id: $1.id) ?? .distantPast)) != isDescending
            }
        })
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    if !viewModel.hasCompletedTraining {
                        PresetsTrainingCard(showTraining: $showTraining)
                    }

                    if let activePreset = viewModel.activePreset {
                        PresetCard(
                            activePreset,
                            expectedEndTime: viewModel.activeOverride?.expectedEndTime
                        )
                    }

                    // All Presets Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("All Presets")
                                .font(.title2.bold())
                            Spacer()

                            Button("Sort") {
                                showingMenu.toggle()
                            }
                            .popover(isPresented: $showingMenu) {
                                sortMenu
                            }

                            Button(action: {}) {
                                Image(systemName: "plus")
                            }.disabled(!viewModel.hasCompletedTraining)
                        }

                        LazyVStack(spacing: 12) {
                            ForEach(presetsSorted) { preset in
                                PresetCard(preset)
                                    .background(Color.white)
                                    .cornerRadius(12)
                            }
                        }
                    }

                    // Support Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Support")
                            .font(.title2.bold())

                        NavigationLink(destination: EmptyView()) {
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

                        if viewModel.hasCompletedTraining {
                            NavigationLink(destination: PresetsTrainingView { viewModel.hasCompletedTraining = true }) {
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
            }
            .background(Color(UIColor.secondarySystemBackground))
            .navigationTitle(Text("Presets", comment: "Presets screen title"))
            .navigationBarItems(trailing: dismissButton)
        }

        .sheet(isPresented: $showTraining) {
            PresetsTrainingView {
                viewModel.hasCompletedTraining = true
            }
        }
        .onAppear { // TODO: Remove this
            viewModel.hasCompletedTraining = false
        }
    }

    private var sortMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sort By")
                    .font(.headline)
                Spacer()
                Button(action: {
                    viewModel.presetsSortAscending.toggle()
                }) {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
            .padding(.horizontal)
            .padding(.top, 20)
            Divider()

            ForEach(PresetSortOption.allCases, id: \.self) { option in
                Button(action: {
                    viewModel.selectedSortOption = option
                    showingMenu = false
                }) {
                    HStack {
                        if viewModel.selectedSortOption == option {
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
        }.bold()
    }

    private var editButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                editMode.toggle()
            }
        }) {
            Text(editMode.title)
                .textCase(nil)
        }
    }
}

extension PresetCard {
    init (_ preset: SelectablePreset, expectedEndTime: PresetExpectedEndTime? = nil) {
        self.init(
            icon: preset.icon,
            presetName: preset.name,
            duration: preset.duration,
            insulinSensitivityMultiplier: preset.insulinSensitivityMultiplier,
            correctionRange: preset.correctionRange,
            guardrail: preset.guardrail,
            expectedEndTime: expectedEndTime
        )
    }
}
