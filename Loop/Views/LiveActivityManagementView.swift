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
    
    private var enabled: Binding<Bool> =
        Binding(
            get: { (UserDefaults.standard.liveActivity ?? LiveActivitySettings()).enabled },
            set: { newValue in
                var settings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
                settings.enabled = newValue
                
                UserDefaults.standard.liveActivity = settings
                NotificationCenter.default.post(name: .LiveActivitySettingsChanged, object: settings)
            }
        )

    private var addPredictiveLine: Binding<Bool> =
        Binding(
            get: { (UserDefaults.standard.liveActivity ?? LiveActivitySettings()).addPredictiveLine },
            set: { newValue in
                var settings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
                settings.addPredictiveLine = newValue
                
                UserDefaults.standard.liveActivity = settings
                NotificationCenter.default.post(name: .LiveActivitySettingsChanged, object: settings)
            }
        )
    
    private var upperLimitMmol: Binding<Double> =
        Binding(
            get: { (UserDefaults.standard.liveActivity ?? LiveActivitySettings()).upperLimitChartMmol },
            set: { newValue in
                var settings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
                settings.upperLimitChartMmol = newValue
                
                UserDefaults.standard.liveActivity = settings
                NotificationCenter.default.post(name: .LiveActivitySettingsChanged, object: settings)

            }
        )
    
    private var lowerLimitMmol: Binding<Double> =
        Binding(
            get: { (UserDefaults.standard.liveActivity ?? LiveActivitySettings()).lowerLimitChartMmol },
            set: { newValue in
                var settings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
                settings.lowerLimitChartMmol = newValue
                
                UserDefaults.standard.liveActivity = settings
                NotificationCenter.default.post(name: .LiveActivitySettingsChanged, object: settings)

            }
        )
    
    private var upperLimitMg: Binding<Double> =
        Binding(
            get: { (UserDefaults.standard.liveActivity ?? LiveActivitySettings()).upperLimitChartMg },
            set: { newValue in
                var settings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
                settings.upperLimitChartMg = newValue
                
                UserDefaults.standard.liveActivity = settings
                NotificationCenter.default.post(name: .LiveActivitySettingsChanged, object: settings)

            }
        )
    
    private var lowerLimitMg: Binding<Double> =
        Binding(
            get: { (UserDefaults.standard.liveActivity ?? LiveActivitySettings()).lowerLimitChartMg },
            set: { newValue in
                var settings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
                settings.lowerLimitChartMg = newValue
                
                UserDefaults.standard.liveActivity = settings
                NotificationCenter.default.post(name: .LiveActivitySettingsChanged, object: settings)

            }
        )
    
    var body: some View {
        List {
            Toggle(NSLocalizedString("Enabled", comment: "Title for enable live activity toggle"), isOn: enabled)
            Toggle(NSLocalizedString("Add predictive line", comment: "Title for predictive line toggle"), isOn: addPredictiveLine)
            if self.displayGlucosePreference.unit == .millimolesPerLiter {
                TextInput(label: "Upper limit chart", value: upperLimitMmol)
                TextInput(label: "Lower limit chart", value: lowerLimitMmol)
            } else {
                TextInput(label: "Upper limit chart", value: upperLimitMg)
                TextInput(label: "Lower limit chart", value: lowerLimitMg)
            }
            
            Section {
                NavigationLink(
                    destination: LiveActivityBottomRowManagerView(),
                    label: { Text(NSLocalizedString("Bottom row configuration", comment: "Title for Bottom row configuration")) }
                )
            }
        }
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
