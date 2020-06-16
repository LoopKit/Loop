//
//  NotificationsCriticalAlertPermissionsViewModel.swift
//  LoopUI
//
//  Created by Rick Pasetto on 6/11/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI

public class NotificationsCriticalAlertPermissionsViewModel: ObservableObject {
    
    @Published var notificationsPermissionsGiven = true
    @Published var criticalAlertsPermissionsGiven = true

    public init() {
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) {
            [weak self] _ in
            self?.updateState()
        }
        updateState()
    }
    
    private func updateState() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            self.notificationsPermissionsGiven = settings.alertSetting == .enabled
            self.criticalAlertsPermissionsGiven = settings.criticalAlertSetting == .enabled
        }
    }
    
    public func gotoSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }
}
