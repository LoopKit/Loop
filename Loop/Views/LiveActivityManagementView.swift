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
    
    @State private var enabled: Bool
    @State private var mode: LiveActivityMode
    @State var isEditingMode = false
    @State private var addPredictiveLine: Bool
    @State private var useLimits: Bool
    @State private var upperLimitChartMmol: Double
    @State private var lowerLimitChartMmol: Double
    @State private var upperLimitChartMg: Double
    @State private var lowerLimitChartMg: Double
    
    init() {
        let liveActivitySettings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
        
        self.enabled = liveActivitySettings.enabled
        self.mode = liveActivitySettings.mode
        self.addPredictiveLine = liveActivitySettings.addPredictiveLine
        self.useLimits = liveActivitySettings.useLimits
        self.upperLimitChartMmol = liveActivitySettings.upperLimitChartMmol
        self.lowerLimitChartMmol = liveActivitySettings.lowerLimitChartMmol
        self.upperLimitChartMg = liveActivitySettings.upperLimitChartMg
        self.lowerLimitChartMg = liveActivitySettings.lowerLimitChartMg
    }
   
    var body: some View {
        VStack {
            List {
                Section {
                    Toggle(NSLocalizedString("Enabled", comment: "Title for enable live activity toggle"), isOn: $enabled)
                    
                    ExpandableSetting(
                        isEditing: $isEditingMode,
                        leadingValueContent: {
                            Text(NSLocalizedString("Mode", comment: "Title for mode live activity toggle"))
                                .foregroundStyle(isEditingMode ? .blue : .primary)
                        },
                        trailingValueContent: {
                            Text(self.mode.name())
                                .foregroundStyle(isEditingMode ? .blue : .primary)
                        },
                        expandedContent: {
                            ResizeablePicker(selection: self.$mode.animation(),
                                             data: LiveActivityMode.all,
                                             formatter: { $0.name() })
                        }
                    )
                }
                
                Section {
                    if mode == .large {
                        Toggle(NSLocalizedString("Add predictive line", comment: "Title for predictive line toggle"), isOn: $addPredictiveLine)
                            .transition(.move(edge: mode == .large ? .top : .bottom))
                    }
                    
                    Toggle(NSLocalizedString("Use BG coloring", comment: "Title for BG coloring"), isOn: $useLimits)
                        .transition(.move(edge: mode == .large ? .top : .bottom))
                    
                    if useLimits {
                        if self.displayGlucosePreference.unit == .millimolesPerLiter {
                            TextInput(label: "Upper limit", value: $upperLimitChartMmol)
                                .transition(.move(edge: useLimits ? .top : .bottom))
                            TextInput(label: "Lower limit", value: $lowerLimitChartMmol)
                                .transition(.move(edge: useLimits ? .top : .bottom))
                        } else {
                            TextInput(label: "Upper limit", value: $upperLimitChartMg)
                                .transition(.move(edge: useLimits ? .top : .bottom))
                            TextInput(label: "Lower limit", value: $lowerLimitChartMg)
                                .transition(.move(edge: useLimits ? .top : .bottom))
                        }
                    }
                }
                
                Section {
                    NavigationLink(
                        destination: LiveActivityBottomRowManagerView(),
                        label: { Text(NSLocalizedString("Bottom row configuration", comment: "Title for Bottom row configuration")) }
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
        settings.enabled = self.enabled
        settings.mode = self.mode
        settings.addPredictiveLine = self.addPredictiveLine
        settings.useLimits = self.useLimits
        settings.upperLimitChartMmol = self.upperLimitChartMmol
        settings.lowerLimitChartMmol = self.lowerLimitChartMmol
        settings.upperLimitChartMg = self.upperLimitChartMg
        settings.lowerLimitChartMg = self.lowerLimitChartMg
        
        UserDefaults.standard.liveActivity = settings
        NotificationCenter.default.post(name: .LiveActivitySettingsChanged, object: settings)
    }
}
