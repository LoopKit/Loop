//
//  UserNotificationDeviceAlertPresenter.swift
//  LoopKit
//
//  Created by Rick Pasetto on 4/9/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import UserNotifications

protocol UserNotificationCenter {
    func add(_ request: UNNotificationRequest, withCompletionHandler: ((Error?) -> Void)?)
    func removePendingNotificationRequests(withIdentifiers: [String])
    func removeDeliveredNotifications(withIdentifiers: [String])
}

extension UNUserNotificationCenter: UserNotificationCenter {}

class UserNotificationDeviceAlertPresenter: DeviceAlertPresenter {
    
    let alertInBackgroundOnly = true
    let isAppInBackgroundFunc: () -> Bool
    let userNotificationCenter: UserNotificationCenter
    
    init(isAppInBackgroundFunc: @escaping () -> Bool,
         userNotificationCenter: UserNotificationCenter = UNUserNotificationCenter.current()) {
        self.isAppInBackgroundFunc = isAppInBackgroundFunc
        self.userNotificationCenter = userNotificationCenter
    }
        
    func issueAlert(_ alert: DeviceAlert) {
        DispatchQueue.main.async {
            if self.alertInBackgroundOnly && self.isAppInBackgroundFunc() || !self.alertInBackgroundOnly {
                if let request = alert.asUserNotificationRequest() {
                    self.userNotificationCenter.add(request) { error in
                        if let error = error {
                            print("Something went wrong posting the user notification: \(error)")
                        }
                    }
                    // For now, UserNotifications do not not acknowledge...not yet at least
                }
            }
        }
    }
    
    func removePendingAlert(identifier: DeviceAlert.Identifier) {
        DispatchQueue.main.async {
            self.userNotificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier.value])
        }
    }
    
    func removeDeliveredAlert(identifier: DeviceAlert.Identifier) {
        DispatchQueue.main.async {
            self.userNotificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier.value])
        }
    }
}

public extension DeviceAlert {
    
    fileprivate func asUserNotificationRequest() -> UNNotificationRequest? {
        guard let uncontent = getUserNotificationContent() else {
            return nil
        }
        return UNNotificationRequest(identifier: identifier.value,
                                     content: uncontent,
                                     trigger: trigger.asUserNotificationTrigger())
    }
    
    private func getUserNotificationContent() -> UNNotificationContent? {
        guard let content = backgroundContent else {
            return nil
        }
        let userNotificationContent = UNMutableNotificationContent()
        userNotificationContent.title = content.title
        userNotificationContent.body = content.body
        userNotificationContent.sound = content.isCritical ? .defaultCritical : .default
        // TODO: Once we have a final design and approval for custom UserNotification buttons, we'll need to set categoryIdentifier
//        userNotificationContent.categoryIdentifier = LoopNotificationCategory.alert.rawValue
        userNotificationContent.threadIdentifier = identifier.value // Used to match categoryIdentifier, but I /think/ we want multiple threads for multiple alert types, no?
        userNotificationContent.userInfo = [
            LoopNotificationUserInfoKey.managerIDForAlert.rawValue: identifier.managerIdentifier,
            LoopNotificationUserInfoKey.alertTypeID.rawValue: identifier.alertIdentifier
        ]
        return userNotificationContent
    }
}

public extension DeviceAlert.Trigger {
    func asUserNotificationTrigger() -> UNNotificationTrigger? {
        switch self {
        case .immediate:
            return nil
        case .delayed(let timeInterval):
            return UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        case .repeating(let repeatInterval):
            return UNTimeIntervalNotificationTrigger(timeInterval: repeatInterval, repeats: true)
        }
    }
}

