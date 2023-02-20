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
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.appName) private var appName

    private let backButtonText: String
    @ObservedObject private var checker: AlertPermissionsChecker

    // TODO: This screen is used in both the 'old Settings UI' and the 'new Settings UI'.  This is temporary.
    // In the old UI, it is a "top level" navigation view.  In the new UI, it is just part of the "flow".  This
    // enum tries to make this clear, for now.
    public enum PresentationMode {
        case topLevel, flow
    }
    private let mode: PresentationMode
    
    public init(backButtonText: String = "", mode: PresentationMode = .topLevel, checker: AlertPermissionsChecker) {
        self.backButtonText = backButtonText
        self.checker = checker
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
            Section(footer: DescriptiveText(label: String(format: NSLocalizedString("""
                Notifications give you important %1$@ app information without requiring you to open the app.
                
                Keep these turned ON in your phone’s settings to ensure you receive %1$@ Notifications, Critical Alerts, and Time Sensitive Notifications.
                """, comment: "Alert Permissions descriptive text (1: app name)"), appName)))
            {
                manageNotifications
                notificationsEnabledStatus
                if #available(iOS 15.0, *) {
                    if !checker.notificationCenterSettings.notificationsDisabled {
                        notificationDelivery
                    }
                }
                criticalAlertsStatus
                if #available(iOS 15.0, *) {
                    if !checker.notificationCenterSettings.notificationsDisabled {
                        timeSensitiveStatus
                    }
                }
            }
            notificationAndCriticalAlertPermissionSupportSection
        }
        .insetGroupedListStyle()
        .navigationBarTitle(Text(NSLocalizedString("Alert Permissions", comment: "Notification & Critical Alert Permissions screen title")))
    }
}

extension NotificationsCriticalAlertPermissionsView {
        
    @ViewBuilder
    private func onOff(_ val: Bool) -> some View {
        if val {
            Text("On", comment: "Notification Setting Status is On")
        } else {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.critical)
                Text("Off", comment: "Notification Setting Status is Off")
            }
        }
    }
    
    private var manageNotifications: some View {
        Button( action: { AlertPermissionsChecker.gotoSettings() } ) {
            HStack {
                Text(NSLocalizedString("Manage Permissions in Settings", comment: "Manage Permissions in Settings button text"))
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.gray).font(.footnote)
            }
        }
        .accentColor(.primary)
    }
    
    private var notificationsEnabledStatus: some View {
        HStack {
            Text("Notifications", comment: "Notifications Status text")
            Spacer()
            onOff(!checker.notificationCenterSettings.notificationsDisabled)
        }
    }
        
    private var criticalAlertsStatus: some View {
        HStack {
            Text("Critical Alerts", comment: "Critical Alerts Status text")
            Spacer()
            onOff(!checker.notificationCenterSettings.criticalAlertsDisabled)
        }
    }

    @available(iOS 15.0, *)
    private var timeSensitiveStatus: some View {
        HStack {
            Text("Time Sensitive Notifications", comment: "Time Sensitive Status text")
            Spacer()
            onOff(!checker.notificationCenterSettings.timeSensitiveNotificationsDisabled)
        }
    }
    
    @available(iOS 15.0, *)
    private var notificationDelivery: some View {
        HStack {
            Text("Notification Delivery", comment: "Notification Delivery Status text")
            Spacer()
            if checker.notificationCenterSettings.scheduledDeliveryEnabled {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.critical)
                Text("Scheduled", comment: "Scheduled Delivery status text")
            } else {
                Text("Immediate", comment: "Immediate Delivery status text")
            }
        }
    }

    private var notificationAndCriticalAlertPermissionSupportSection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Support", comment: "Section title for Support"))) {
            NavigationLink(destination: Text("Get help with Alert Permissions")) {
                Text(NSLocalizedString("Get help with Alert Permissions", comment: "Get help with Alert Permissions support button text"))
            }
        }
    }
}


struct NotificationsCriticalAlertPermissionsView_Previews: PreviewProvider {
    static var previews: some View {
        return Group {
            NotificationsCriticalAlertPermissionsView(checker: AlertPermissionsChecker())
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE"))
                .previewDisplayName("SE light")
            NotificationsCriticalAlertPermissionsView(checker: AlertPermissionsChecker())
                .colorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone XS Max"))
                .previewDisplayName("XS Max dark")
        }
    }
}
