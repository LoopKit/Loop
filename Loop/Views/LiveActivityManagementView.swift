//
//  LiveActivityManagementView.swift
//  Loop
//
//  Created by Bastiaan Verhaar on 04/07/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopCore

struct LiveActivityManagementView: View {
    
    private var enabled: Binding<Bool> {
        Binding(
            get: {  UserDefaults.standard.liveActivity?.enabled ?? false },
            set: { newValue in
                mutate { settings in
                    settings.enabled = newValue
                }
            }
        )
    }

    var body: some View {
        List {
            Toggle(NSLocalizedString("Enabled", comment: "Title for missed meal notifications toggle"), isOn: enabled)
        }
            .insetGroupedListStyle()
            .navigationBarTitle(Text(NSLocalizedString("Live activity", comment: "Live activity screen title")))
    }
    
    func mutate(_ updater: (inout LiveActivitySettings) -> Void) {
        var settings = UserDefaults.standard.liveActivity
        if settings == nil {
            settings = LiveActivitySettings()
        }
        
        updater(&settings!)
        
        UserDefaults.standard.liveActivity = settings
        NotificationCenter.default.post(name: .LiveActivitySettingsChanged, object: settings)
    }
}

#Preview {
    LiveActivityManagementView()
}
