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

struct LiveActivityManagementView: View {
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
    
    var body: some View {
        List {
            Toggle(NSLocalizedString("Enabled", comment: "Title for enable live activity toggle"), isOn: enabled)
            Toggle(NSLocalizedString("Add predictive line", comment: "Title for predictive line toggle"), isOn: addPredictiveLine)
            NavigationLink(
                destination: LiveActivityBottomRowManagerView(),
                label: { Text(NSLocalizedString("Bottom row configuration", comment: "Title for Bottom row configuration")) }
            )
        }
            .insetGroupedListStyle()
            .navigationBarTitle(Text(NSLocalizedString("Live activity", comment: "Live activity screen title")))
    }
}

#Preview {
    LiveActivityManagementView()
}
