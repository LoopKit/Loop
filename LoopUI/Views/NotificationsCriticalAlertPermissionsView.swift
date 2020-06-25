//
//  NotificationsCriticalAlertPermissionsView.swift
//  LoopUI
//
//  Created by Rick Pasetto on 6/11/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKitUI
import SwiftUI

public struct NotificationsCriticalAlertPermissionsView: View, HorizontalSizeClassOverride {
    @Environment(\.dismiss) var dismiss

    private let backButtonText: String
    @ObservedObject private var viewModel: NotificationsCriticalAlertPermissionsViewModel

    public init(backButtonText: String = "", viewModel: NotificationsCriticalAlertPermissionsViewModel) {
        self.backButtonText = backButtonText
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationView {
            List {
                manageNotificationsSection
                manageCriticalAlertsSection
                notificationAndCriticalAlertPermissionSupportSection
            }
            .listStyle(GroupedListStyle())
            .navigationBarTitle(Text(LocalizedString("Alert Permissions", comment: "Notification & Critical Alert Permissions screen title")))
            .navigationBarBackButtonHidden(false)
            .navigationBarHidden(false)
            .navigationBarItems(leading: dismissButton)
            .environment(\.horizontalSizeClass, horizontalOverride)
        }
    }
    
}

extension NotificationsCriticalAlertPermissionsView {
    
    private var dismissButton: some View {
        Button( action: { self.dismiss() }) {
            Text(backButtonText)
        }
    }

    private var manageNotificationsSection: some View {
        Section {
            Button( action: { self.viewModel.gotoSettings() } ) {
                HStack {
                    Text(LocalizedString("Manage Notifications in Settings", comment: "Manage Notifications in Settings button text"))
                    if !viewModel.notificationsPermissionsGiven {
                        Spacer()
                        Text(LocalizedString("⚠️", comment: "Warning symbol"))
                    }
                }
            }
            DescriptiveText(label: LocalizedString("""
                Notifications can appear while you are using another app on your iPhone, or while your iPhone is locked.

                Notifications let you know about issues Tidepool Loop has without needing to open the app.
                You can customize when you want to recieve notificiations, and how they should be delivered inside Tidepool Loop.
                """, comment: "Manage Notifications in Settings descriptive text"))
        }
    }
    
    private var manageCriticalAlertsSection: some View {
        Section {
            Button( action: { self.viewModel.gotoSettings() } ) {
                HStack {
                    Text(LocalizedString("Manage Critical Alerts in Settings", comment: "Manage Critical Alerts in Settings button text"))
                    if !viewModel.criticalAlertsPermissionsGiven {
                        Spacer()
                        Text(LocalizedString("⚠️", comment: "Warning symbol"))
                    }
                }
            }
            DescriptiveText(label: LocalizedString("""
                Critical Alerts will always play a sound and appear on the Lock screen even if your iPhone is muted or Do Not Disturb is on.
                """, comment: "Manage Notifications in Settings descriptive text"))
        }
    }
    
    private var notificationAndCriticalAlertPermissionSupportSection: some View {
        Section(header: SectionHeader(label: LocalizedString("Support", comment: "Section title for Support"))) {
            NavigationLink(destination: Text("Get help with Notification & Critical Alert Permissions screen")) {
                Text(LocalizedString("Get help with Notification & Critical Alert Permissions", comment: "Get help with Notification & Critical Alert Permissions support button text"))
            }
            DescriptiveText(label: LocalizedString("Text description here.", comment: ""))
        }
    }

}

struct NotificationsCriticalAlertPermissionsView_Previews: PreviewProvider {
    static var previews: some View {
        return Group {
            NotificationsCriticalAlertPermissionsView(viewModel: NotificationsCriticalAlertPermissionsViewModel())
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE"))
                .previewDisplayName("SE light")
            NotificationsCriticalAlertPermissionsView(viewModel: NotificationsCriticalAlertPermissionsViewModel())
                .colorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone XS Max"))
                .previewDisplayName("XS Max dark")
        }
    }
}
