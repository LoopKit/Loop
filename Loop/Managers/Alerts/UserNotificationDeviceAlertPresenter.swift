//
//  UserNotificationDeviceAlertPresenter.swift
//  LoopKit
//
//  Created by Rick Pasetto on 4/9/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

class UserNotificationDeviceAlertPresenter: DeviceAlertPresenter {
    
    let userNotificationCenter: UserNotificationCenter
    let log = DiagnosticLog(category: "UserNotificationDeviceAlertPresenter")
    
    init(userNotificationCenter: UserNotificationCenter) {
        self.userNotificationCenter = userNotificationCenter
    }
    
    func issueAlert(_ alert: DeviceAlert) {
        issueAlert(alert, timestamp: Date())
    }

    func issueAlert(_ alert: DeviceAlert, timestamp: Date) {
        DispatchQueue.main.async {
            do {
                let request = try UNNotificationRequest(from: alert, timestamp: timestamp)
                self.userNotificationCenter.add(request) { error in
                    if let error = error {
                        self.log.error("Something went wrong posting the user notification: %@", error.localizedDescription)
                    }
                }
                // For now, UserNotifications do not not acknowledge...not yet at least
            } catch {
                self.log.error("Error issuing alert: %@", error.localizedDescription)
            }
        }
    }
    
    func retractAlert(identifier: DeviceAlert.Identifier) {
        DispatchQueue.main.async {
            self.userNotificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier.value])
            self.userNotificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier.value])
        }
    }
}
