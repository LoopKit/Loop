//
//  LoopNotificationsView.swift
//  LoopUI
//
//  Created by Rick Pasetto on 6/5/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKitUI
import SwiftUI

public struct LoopNotificationsView: View, HorizontalSizeClassOverride {
    @Environment(\.dismiss) var dismiss
    
    private let backButtonText: String
    @ObservedObject private var viewModel: LoopNotificationsViewModel
    
    private let notificationAndCriticalAlertPermissionScreen =
        NotificationsCriticalAlertPermissionsView(viewModel: NotificationsCriticalAlertPermissionsViewModel())
    
    public init(backButtonText: String = "", viewModel: LoopNotificationsViewModel) {
        self.backButtonText = backButtonText
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationView {
            VStack {
                List {
                    notificationAndCriticalAlertPermissionSection
                    supportSection
                }
                .listStyle(GroupedListStyle())
                .navigationBarTitle(Text(LocalizedString("Loop Notifications", comment: "Loop Notifications settings screen title")))
                .navigationBarBackButtonHidden(false)
                .navigationBarHidden(false)
                .navigationBarItems(leading: dismissButton)
                .environment(\.horizontalSizeClass, horizontalOverride)
            }
        }
    }
    
    private var dismissButton: some View {
        Button( action: { self.dismiss() }) {
            Text(backButtonText)
        }
    }
            
    private var notificationAndCriticalAlertPermissionSection: some View {
        Section(header: SectionHeader(label: LocalizedString("Tidepool Loop Notifications", comment: "Section title for Tidepool Loop notifications"))) {
            NavigationLink(destination: notificationAndCriticalAlertPermissionScreen) {
                Text(LocalizedString("Notification & Critical Alert Permissions", comment: "Notification & Critical Alert Permissions button text"))
            }
        }
    }
    
    private var supportSection: some View {
        Section(header: SectionHeader(label: LocalizedString("Support", comment: "Section title for Support"))) {
            NavigationLink(destination: Text("Get help with Loop Notifications screen")) {
                Text(LocalizedString("Get help with Loop Notifications", comment: "Get help with Loop notifications support button text"))
            }
            DescriptiveText(label: LocalizedString("Text description here.", comment: ""))
        }
    }
}

struct LoopNotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        return Group {
            LoopNotificationsView(backButtonText: "Settings", viewModel: LoopNotificationsViewModel())
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE"))
                .previewDisplayName("SE light")
            LoopNotificationsView(backButtonText: "Settings", viewModel: LoopNotificationsViewModel())
                .colorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone XS Max"))
                .previewDisplayName("XS Max dark")
        }
    }
}
