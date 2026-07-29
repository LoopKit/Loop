//
//  LiveActivityManagementView.swift
//  Loop
//
//  Created by Bastiaan Verhaar on 04/07/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI
import LoopCore
import HealthKit

struct LiveActivityManagementView: View {
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @StateObject private var viewModel = LiveActivityManagementViewModel()
    @State private var previousViewModel = LiveActivityManagementViewModel()
    
    @State private var isDirty = false
   
    var body: some View {
        VStack {
            List {
                Section(header: Text("Lock Screen / Dynamic Island / CarPlay")) {
                    Toggle(NSLocalizedString("Enabled", comment: "Title for enable live activity toggle"), isOn: $viewModel.enabled)
                        .onChange(of: viewModel.enabled) { _ in
                            self.isDirty = previousViewModel.enabled != viewModel.enabled
                        }
                }

                Section(header: Text("Select Lock Screen Display Options")){
                    ExpandableSetting(
                        isEditing: $viewModel.isEditingMode,
                        leadingValueContent: {
                            Text(NSLocalizedString("Mode", comment: "Title for mode live activity toggle"))
                                .foregroundStyle(viewModel.isEditingMode ? .blue : .primary)
                        },
                        trailingValueContent: {
                            Text(viewModel.mode.name())
                                .foregroundStyle(viewModel.isEditingMode ? .blue : .primary)
                        },
                        expandedContent: {
                            ResizeablePicker(selection: self.$viewModel.mode.animation(),
                                             data: LiveActivityMode.all,
                                             formatter: { $0.name() })
                        }
                    )
                    .onChange(of: viewModel.mode) { _ in
                        self.isDirty = previousViewModel.mode != viewModel.mode
                    }
                }
                
                Section(header: Text("Display Control Options")) {
                    Toggle(NSLocalizedString("Display prediction in plot", comment: "Title for prediction line toggle"), isOn: $viewModel.addPredictiveLine)
                        .transition(.move(edge: viewModel.mode == .large ? .top : .bottom))
                        .onChange(of: viewModel.addPredictiveLine) { _ in
                            self.isDirty = previousViewModel.addPredictiveLine != viewModel.addPredictiveLine
                        }
                    
                    Toggle(NSLocalizedString("Display colors for glucose", comment: "Title for glucose coloring"), isOn: $viewModel.useLimits)
                        .transition(.move(edge: viewModel.mode == .large ? .top : .bottom))
                        .onChange(of: viewModel.useLimits) { _ in
                            self.isDirty = previousViewModel.useLimits != viewModel.useLimits
                        }
                    
                    if self.viewModel.useLimits {
                        if self.displayGlucosePreference.unit == .millimolesPerLiter {
                            TextInput(label: "Upper limit", value: $viewModel.upperLimitChartMmol)
                                .transition(.move(edge: viewModel.useLimits ? .top : .bottom))
                                .onChange(of: viewModel.upperLimitChartMmol) { _ in
                                    self.isDirty = previousViewModel.upperLimitChartMmol != viewModel.upperLimitChartMmol
                                }
                            TextInput(label: "Lower limit", value: $viewModel.lowerLimitChartMmol)
                                .transition(.move(edge: viewModel.useLimits ? .top : .bottom))
                                .onChange(of: viewModel.lowerLimitChartMmol) { _ in
                                    self.isDirty = previousViewModel.lowerLimitChartMmol != viewModel.lowerLimitChartMmol
                                }
                        } else {
                            TextInput(label: "Upper limit", value: $viewModel.upperLimitChartMg)
                                .transition(.move(edge: viewModel.useLimits ? .top : .bottom))
                                .onChange(of: viewModel.upperLimitChartMg) { _ in
                                    self.isDirty = previousViewModel.upperLimitChartMg != viewModel.upperLimitChartMg
                                }
                            TextInput(label: "Lower limit", value: $viewModel.lowerLimitChartMg)
                                .transition(.move(edge: viewModel.useLimits ? .top : .bottom))
                                .onChange(of: viewModel.lowerLimitChartMg) { _ in
                                    self.isDirty = previousViewModel.lowerLimitChartMg != viewModel.lowerLimitChartMg
                           }
                        }
                    }
                }
                
                Section(header: Text("Configure Lock Screen / Carplay Row")) {
                    NavigationLink(
                        destination: LiveActivityBottomRowManagerView(),
                        label: { Text(NSLocalizedString("Configure Display", comment: "")) }
                    )
                }
            }
            .animation(.easeInOut, value: UUID())
            .insetGroupedListStyle()
            
            Spacer()
            Button(action: save) {
                Text(NSLocalizedString("Save", comment: ""))
            }
            .buttonStyle(ActionButtonStyle())
            .disabled(!isDirty)
            .padding([.bottom, .horizontal])
        }
            .navigationBarTitle(Text(NSLocalizedString("Live activity", comment: "Live activity screen title")))
    }
    
    @ViewBuilder
    private func TextInput(label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(NSLocalizedString(label, comment: "no comment"))
            Spacer()
            TextField("", value: value, format: .number)
                .multilineTextAlignment(.trailing)
            Text(self.displayGlucosePreference.unit.localizedShortUnitString)
        }
    }
    
    private func save() {
        var settings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
        settings.enabled = viewModel.enabled
        settings.mode = viewModel.mode
        settings.addPredictiveLine = viewModel.addPredictiveLine
        settings.useLimits = viewModel.useLimits
        settings.upperLimitChartMmol = viewModel.upperLimitChartMmol
        settings.lowerLimitChartMmol = viewModel.lowerLimitChartMmol
        settings.upperLimitChartMg = viewModel.upperLimitChartMg
        settings.lowerLimitChartMg = viewModel.lowerLimitChartMg
        
        UserDefaults.standard.liveActivity = settings
        NotificationCenter.default.post(name: .LiveActivitySettingsChanged, object: settings)
        
        self.isDirty = false
        previousViewModel = LiveActivityManagementViewModel()
    }
}
