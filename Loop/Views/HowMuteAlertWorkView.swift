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
    @Environment(\.appName) private var appName

    var body: some View {
        NavigationView {
            List {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What are examples of Critical and Time Sensitive alerts?")
                            .bold()
                        
                        Text("iOS Critical Alerts and Time Sensitive Alerts are types of Apple notifications. They are used for high-priority events. Some examples include:")
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Critical Alerts")
                                    .bold()
                                
                                Text("Urgent Low")
                                    .bulleted()
                                Text("Sensor Failed")
                                    .bulleted()
                                Text("Reservoir Empty")
                                    .bulleted()
                                Text("Pump Expired")
                                    .bulleted()
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Time Sensitive Alerts")
                                    .bold()
                                
                                Text("High Glucose")
                                    .bulleted()
                                Text("Transmitter Low Battery")
                                    .bulleted()
                            }
                        }
                        
                        Spacer()
                    }
                    .font(.footnote)
                    .foregroundColor(.black.opacity(0.6))
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(.systemFill), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "How can I temporarily silence all %1$@ app sounds?",
                                    comment: "Title text for temporarily silencing all sounds (1: app name)"
                                ),
                                appName
                            )
                        )
                        .bold()
                        
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Use the Mute Alerts feature. It allows you to temporarily silence all of your alerts and alarms via the %1$@ app, including Critical Alerts and Time Sensitive Alerts.",
                                    comment: "Description text for temporarily silencing all sounds (1: app name)"
                                ),
                                appName
                            )
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How can I silence non-Critical Alerts?")
                            .bold()
                        
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Turn off the volume on your iOS device or add %1$@ as an allowed app to each Focus Mode. Time Sensitive and Critical Alerts will still sound, but non-Critical Alerts will be silenced.",
                                    comment: "Description text for temporarily silencing non-critical alerts (1: app name)"
                                ),
                                appName
                            )
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How can I silence only Time Sensitive and Non-Critical alerts?")
                            .bold()
                        
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "For safety purposes, you should allow Critical Alerts, Time Sensitive and Notification Permissions (non-critical alerts) on your device to continue using %1$@ and cannot turn off individual alarms.",
                                    comment: "Description text for silencing time sensitive and non-critical alerts (1: app name)"
                                ),
                                appName
                            )
                        )
                    }
                }
                .padding(.vertical, 8)
            }
            .insetGroupedListStyle()
            .navigationTitle(NSLocalizedString("Managing Alerts", comment: "View title for how mute alerts work"))
            .navigationBarItems(trailing: closeButton)
        }
    }

    private var closeButton: some View {
        Button(action: dismiss) {
            Text(NSLocalizedString("Close", comment: "Button title to close view"))
        }
    }
}

private extension Text {
    func bulleted(color: Color = .accentColor.opacity(0.5)) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "circle.fill")
                .resizable()
                .frame(width: 8, height: 8)
                .foregroundColor(color)
            
            self
        }
    }
}

struct HowMuteAlertWorkView_Previews: PreviewProvider {
    static var previews: some View {
        HowMuteAlertWorkView()
    }
}
