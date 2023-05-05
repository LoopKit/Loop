//
//  HowMuteAlertWorkView.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2022-12-09.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct HowMuteAlertWorkView: View {
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.guidanceColors) private var guidanceColors

    var body: some View {
        NavigationView {
            List {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("""
Mute Alerts allows you to temporarily silence your alerts and alarms.

When using Mute Alerts, also consider the impact of using iOS Focus Modes.
""", comment: "Description of how mute alerts work"))
                    .fixedSize(horizontal: false, vertical: true)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "speaker.slash.fill")
                                .foregroundColor(.white)
                                .padding(5)
                                .background(guidanceColors.warning)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            
                            Text(NSLocalizedString("Loop Mute Alerts", comment: "Section title for description that mute alerts is temporary"))
                                .bold()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Text(NSLocalizedString("""
All Tidepool Loop alerts, including Critical Alerts, will be silenced for up to 4 hours.

After the mute period ends, your alert sounds will resume.
""", comment: "Description that mute alerts is temporary"))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom)
                        
                        HStack(spacing: 10) {
                            Image(systemName: "moon.fill")
                                .foregroundColor(.accentColor)
                            
                            Text(NSLocalizedString("iOS Focus Mode", comment: "Section title for description of how mute alerts work with focus mode"))
                                .bold()
                        }
                        Text(NSLocalizedString("If iOS Focus Mode is ON and Mute Alerts is OFF, Critical Alerts will still be delivered, but non-Critical Alerts will be silenced until Loop is added to each Focus mode as an Allowed App.", comment: "Description of how mute alerts works with focus mode"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(.systemFill), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .insetGroupedListStyle()
            .navigationTitle(NSLocalizedString("Using Mute Alerts", comment: "View title for how mute alerts work"))
            .navigationBarItems(trailing: closeButton)
        }
    }

    private var closeButton: some View {
        Button(action: dismiss) {
            Text(NSLocalizedString("Close", comment: "Button title to close view"))
        }
    }
}

struct HowMuteAlertWorkView_Previews: PreviewProvider {
    static var previews: some View {
        HowMuteAlertWorkView()
    }
}
