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
   
    var body: some View {
        VStack {
            List {
                Section {
                    Toggle(NSLocalizedString("Enabled", comment: "Title for enable live activity toggle"), isOn: $viewModel.enabled)
                    
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
                }
                
                Section {
                    if viewModel.mode == .large {
                        Toggle(NSLocalizedString("Add predictive line", comment: "Title for predictive line toggle"), isOn: $viewModel.addPredictiveLine)
                            .transition(.move(edge: viewModel.mode == .large ? .top : .bottom))
                    }
                    
                    Toggle(NSLocalizedString("Use BG coloring", comment: "Title for BG coloring"), isOn: $viewModel.useLimits)
                        .transition(.move(edge: viewModel.mode == .large ? .top : .bottom))
                    
                    if self.displayGlucosePreference.unit == .millimolesPerLiter {
                        TextInput(label: "Upper limit", value: $viewModel.upperLimitChartMmol)
                            .transition(.move(edge: viewModel.useLimits ? .top : .bottom))
                        TextInput(label: "Lower limit", value: $viewModel.lowerLimitChartMmol)
                            .transition(.move(edge: viewModel.useLimits ? .top : .bottom))
                    } else {
                        TextInput(label: "Upper limit", value: $viewModel.upperLimitChartMg)
                            .transition(.move(edge: viewModel.useLimits ? .top : .bottom))
                        TextInput(label: "Lower limit", value: $viewModel.lowerLimitChartMg)
                            .transition(.move(edge: viewModel.useLimits ? .top : .bottom))
                    }
                }
                
                Section {
                    NavigationLink(
                        destination: LiveActivityBottomRowManagerView(),
                        label: { Text(NSLocalizedString("Bottom row configuration", comment: "Title for Bottom row configuration")) }
                    )
                }
                
                Section {
                    Toggle(NSLocalizedString("Always enabled", comment: "Title for always enabled live activity toggle"), isOn: $viewModel.alwaysEnabled)
                    if !viewModel.alwaysEnabled {
                        Toggle(NSLocalizedString("Show when low is predicted", comment: "Title for show when low is predicted toggle"), isOn: $viewModel.showWhenLowIsPredicted)
                            .transition(.move(edge: viewModel.alwaysEnabled ? .top : .bottom))
                        Toggle(NSLocalizedString("Show when high is predicted", comment: "Title for show when high is predicted toggle"), isOn: $viewModel.showWhenHighIsPredicted)
                            .transition(.move(edge: viewModel.alwaysEnabled ? .top : .bottom))
                    }
                } footer: {
                    Text(NSLocalizedString("Here you can setup how the Live Activity behaves. Low and High values are based on the upper and lower limits", comment: "Body for always enabled live activity toggle"))
                        .font(.footnote)
                }
                
                
            }
            .animation(.easeInOut, value: UUID())
            .insetGroupedListStyle()
            
            Spacer()
            Button(action: save) {
                Text(NSLocalizedString("Save", comment: ""))
            }
            .buttonStyle(ActionButtonStyle())
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
        settings.alwaysEnabled = viewModel.alwaysEnabled
        settings.showWhenLowIsPredicted = viewModel.showWhenLowIsPredicted
        settings.showWhenHighIsPredicted = viewModel.showWhenHighIsPredicted
        settings.upperLimitChartMmol = viewModel.upperLimitChartMmol
        settings.lowerLimitChartMmol = viewModel.lowerLimitChartMmol
        settings.upperLimitChartMg = viewModel.upperLimitChartMg
        settings.lowerLimitChartMg = viewModel.lowerLimitChartMg
        
        UserDefaults.standard.liveActivity = settings
        NotificationCenter.default.post(name: .LiveActivitySettingsChanged, object: settings)
    }
}
