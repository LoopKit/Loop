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
    @State private var upperLimitMmol: Double
    @State private var lowerLimitMmol: Double
    @State private var upperLimitMg: Double
    @State private var lowerLimitMg: Double
    
    init() {
        let liveActivitySettings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
        
        self.enabled = liveActivitySettings.enabled
        self.mode = liveActivitySettings.mode
        self.addPredictiveLine = liveActivitySettings.addPredictiveLine
        self.useLimits = liveActivitySettings.useLimits
        self.upperLimitMmol = liveActivitySettings.upperLimitChartMmol
        self.lowerLimitMmol = liveActivitySettings.lowerLimitChartMmol
        self.upperLimitMg = liveActivitySettings.upperLimitChartMg
        self.lowerLimitMg = liveActivitySettings.lowerLimitChartMg
    }
   
    var body: some View {
        List {
            Section {
                Toggle(NSLocalizedString("Enabled", comment: "Title for enable live activity toggle"), isOn: $enabled)
                    .onChange(of: enabled) { newValue in
                        self.mutate { settings in
                            settings.enabled = newValue
                        }
                    }
                
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
                .onChange(of: self.mode) { newValue in
                    self.mutate { settings in
                        settings.mode = newValue
                    }
                }
            }
            
            if mode == .large {
                Section {
                    Toggle(NSLocalizedString("Add predictive line", comment: "Title for predictive line toggle"), isOn: $addPredictiveLine)
                        .transition(.move(edge: mode == .large ? .top : .bottom))
                        .onChange(of: addPredictiveLine) { newValue in
                            self.mutate { settings in
                                settings.addPredictiveLine = newValue
                            }
                        }
                    Toggle(NSLocalizedString("Use BG coloring", comment: "Title for BG coloring"), isOn: $useLimits)
                        .transition(.move(edge: mode == .large ? .top : .bottom))
                        .onChange(of: useLimits) { newValue in
                            self.mutate { settings in
                                settings.useLimits = newValue
                            }
                        }
                    
                    if useLimits {
                        if self.displayGlucosePreference.unit == .millimolesPerLiter {
                            TextInput(label: "Upper limit chart", value: $upperLimitMmol)
                                .transition(.move(edge: useLimits ? .top : .bottom))
                            TextInput(label: "Lower limit chart", value: $lowerLimitMmol)
                                .transition(.move(edge: useLimits ? .top : .bottom))
                        } else {
                            TextInput(label: "Upper limit chart", value: $upperLimitMg)
                                .transition(.move(edge: useLimits ? .top : .bottom))
                            TextInput(label: "Lower limit chart", value: $lowerLimitMg)
                                .transition(.move(edge: useLimits ? .top : .bottom))
                        }
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
    
    private func mutate(_ updater: (inout LiveActivitySettings) -> Void) {
        var settings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
        
        updater(&settings)
        
        UserDefaults.standard.liveActivity = settings
        NotificationCenter.default.post(name: .LiveActivitySettingsChanged, object: settings)
    }
}
