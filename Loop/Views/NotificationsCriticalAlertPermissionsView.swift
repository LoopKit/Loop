//
//  NotificationsCriticalAlertPermissionsView.swift
//  LoopUI
//
//  Created by Rick Pasetto on 6/11/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKitUI
import SwiftUI

public struct NotificationsCriticalAlertPermissionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appName) private var appName

    private let backButtonText: String
    @ObservedObject private var viewModel: NotificationsCriticalAlertPermissionsViewModel

    // TODO: This screen is used in both the 'old Settings UI' and the 'new Settings UI'.  This is temporary.
    // In the old UI, it is a "top level" navigation view.  In the new UI, it is just part of the "flow".  This
    // enum tries to make this clear, for now.
    public enum PresentationMode {
        case topLevel, flow
    }
    private let mode: PresentationMode
    
    public init(backButtonText: String = "", mode: PresentationMode = .topLevel, viewModel: NotificationsCriticalAlertPermissionsViewModel) {
        self.backButtonText = backButtonText
        self.viewModel = viewModel
        self.mode = mode
    }
    
    public var body: some View {
        switch mode {
        case .flow: return AnyView(content())
        case .topLevel: return AnyView(navigationContent())
        }
    }
    
    private func navigationContent() -> some View {
        return NavigationView {
            content()
        }
    }
    
    private func content() -> some View {
        List {
            manageNotificationsSection
            manageCriticalAlertsSection
            notificationAndCriticalAlertPermissionSupportSection
        }
        .insetGroupedListStyle()
        .navigationBarTitle(Text(NSLocalizedString("Alert Permissions", comment: "Notification & Critical Alert Permissions screen title")))
        .navigationBarItems(leading: dismissButton)
    }
}

extension NotificationsCriticalAlertPermissionsView {
    
    // TODO: Remove this when the new SettingsView is in place
    private var dismissButton: some View {
        Button( action: { self.dismiss() }) {
            Text(backButtonText)
        }
    }

    private var manageNotificationsSection: some View {
        Section(header: Spacer(),
                footer: DescriptiveText(label: NSLocalizedString("""
            Notifications appear on your Lock screen or pop up while you’re using other apps.
            
            Notifications give you important \(appName) app information without requiring you to open the app.  You can customize when and how you want to receive these notifications.
            """, comment: "Manage Notifications in Settings descriptive text")))
        {
            Button( action: { self.viewModel.gotoSettings() } ) {
                HStack {
                    Text(NSLocalizedString("Manage Notifications in Settings", comment: "Manage Notifications in Settings button text"))
                    if !viewModel.notificationsPermissionsGiven {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.warning)
                    }
                }
            }
            .accentColor(.primary)
        }
    }
    
    private var manageCriticalAlertsSection: some View {
        Section(footer:      DescriptiveText(label: NSLocalizedString("""
            Critical Alerts will always play a sound and appear on the Lock screen even if your iPhone is muted or Do Not Disturb is on.
            """, comment: "Manage Notifications in Settings descriptive text")))
        {
            Button( action: { self.viewModel.gotoSettings() } ) {
                HStack {
                    Text(NSLocalizedString("Manage Critical Alerts in Settings", comment: "Manage Critical Alerts in Settings button text"))
                    if !viewModel.criticalAlertsPermissionsGiven {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.critical)
                    }
                }
            }
            .accentColor(.primary)
        }
    }
    
    private var notificationAndCriticalAlertPermissionSupportSection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Support", comment: "Section title for Support"))) {
            NavigationLink(destination: Text("Get help with Notification & Critical Alert Permissions screen")) {
                Text(NSLocalizedString("Get help with Notification & Critical Alert Permissions", comment: "Get help with Notification & Critical Alert Permissions support button text"))
            }
        }
    }

}

struct NotificationsCriticalAlertPermissionsView_Previews: PreviewProvider {
    static var previews: some View {
        return Group {
            NotificationsCriticalAlertPermissionsView(viewModel: NotificationsCriticalAlertPermissionsViewModel(criticalAlertsPermissionsGiven: false))
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
