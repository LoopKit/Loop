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
    
    let userNotificationCenter: UserNotificationCenter
    let log = DiagnosticLog(category: "UserNotificationDeviceAlertPresenter")
    
    init(userNotificationCenter: UserNotificationCenter = UNUserNotificationCenter.current()) {
        self.userNotificationCenter = userNotificationCenter
    }
        
    func issueAlert(_ alert: DeviceAlert) {
        DispatchQueue.main.async {
            if let request = alert.asUserNotificationRequest() {
                self.userNotificationCenter.add(request) { error in
                    if let error = error {
                        self.log.error("Something went wrong posting the user notification: %@", error.localizedDescription)
                    }
                }
                // For now, UserNotifications do not not acknowledge...not yet at least
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
        userNotificationContent.sound = getUserNotificationSound()
        // TODO: Once we have a final design and approval for custom UserNotification buttons, we'll need to set categoryIdentifier
//        userNotificationContent.categoryIdentifier = LoopNotificationCategory.alert.rawValue
        userNotificationContent.threadIdentifier = identifier.value // Used to match categoryIdentifier, but I /think/ we want multiple threads for multiple alert types, no?
        userNotificationContent.userInfo = [
            LoopNotificationUserInfoKey.managerIDForAlert.rawValue: identifier.managerIdentifier,
            LoopNotificationUserInfoKey.alertTypeID.rawValue: identifier.alertIdentifier
        ]
        return userNotificationContent
    }
    
    private func getUserNotificationSound() -> UNNotificationSound? {
        guard let content = backgroundContent else {
            return nil
        }
        if let sound = sound {
            switch sound {
            case .vibrate:
                // TODO: Not sure how to "force" UNNotificationSound to "vibrate only"...so for now we just do the default
                break
            case .silence:
                // TODO: Not sure how to "force" UNNotificationSound to "silence"...so for now we just do the default
                break
            default:
                if let actualFileName = DeviceAlertManager.soundURL(for: self)?.lastPathComponent {
                    let unname = UNNotificationSoundName(rawValue: actualFileName)
                    return content.isCritical ? UNNotificationSound.criticalSoundNamed(unname) : UNNotificationSound(named: unname)
                }
            }
        }
        
        return content.isCritical ? .defaultCritical : .default
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
