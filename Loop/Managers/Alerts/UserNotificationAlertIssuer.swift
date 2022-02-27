//
//  UserNotificationAlertIssuer.swift
//  LoopKit
//
//  Created by Rick Pasetto on 4/9/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import UIKit

class UserNotificationAlertIssuer: AlertIssuer {
    
    let userNotificationCenter: UserNotificationCenter
    let log = DiagnosticLog(category: "UserNotificationAlertIssuer")
    
    init(userNotificationCenter: UserNotificationCenter) {
        self.userNotificationCenter = userNotificationCenter
    }
    
    func issueAlert(_ alert: Alert) {
        issueAlert(alert, timestamp: Date())
    }

    func issueAlert(_ alert: Alert, timestamp: Date) {
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
    
    func retractAlert(identifier: Alert.Identifier) {
        DispatchQueue.main.async {
            self.userNotificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier.value])
            self.userNotificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier.value])
        }
    }
}

extension UserNotificationAlertIssuer: AlertManagerResponder {
    func acknowledgeAlert(identifier: Alert.Identifier) {
        DispatchQueue.main.async {
            self.log.debug("Removing notification %@ from delivered notifications", identifier.value)
            self.userNotificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier.value])
        }
    }
}

fileprivate extension Alert {

    enum Error: String, Swift.Error {
        case noBackgroundContent
    }

    func getUserNotificationContent(timestamp: Date) throws -> UNNotificationContent {
        guard let content = backgroundContent else {
            throw Error.noBackgroundContent
        }
        let userNotificationContent = UNMutableNotificationContent()
        userNotificationContent.title = content.title
        userNotificationContent.body = content.body
        userNotificationContent.sound = userNotificationSound
        if #available(iOS 15.0, *) {
            userNotificationContent.interruptionLevel = interruptionLevel.userNotificationInterruptLevel
        }
        // TODO: Once we have a final design and approval for custom UserNotification buttons, we'll need to set categoryIdentifier
//        userNotificationContent.categoryIdentifier = LoopNotificationCategory.alert.rawValue
        userNotificationContent.threadIdentifier = identifier.value // Used to match categoryIdentifier, but I /think/ we want multiple threads for multiple alert types, no?
        userNotificationContent.userInfo = [
            LoopNotificationUserInfoKey.managerIDForAlert.rawValue: identifier.managerIdentifier,
            LoopNotificationUserInfoKey.alertTypeID.rawValue: identifier.alertIdentifier,
        ]
        return userNotificationContent
    }
    
    private var userNotificationSound: UNNotificationSound? {
        guard backgroundContent != nil else {
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
                if let actualFileName = AlertManager.soundURL(for: self)?.lastPathComponent {
                    let unname = UNNotificationSoundName(rawValue: actualFileName)
                    return interruptionLevel == .critical ? UNNotificationSound.criticalSoundNamed(unname) : UNNotificationSound(named: unname)
                }
            }
        }

        return interruptionLevel == .critical ? .defaultCritical : .default
    }
}

fileprivate extension Alert.InterruptionLevel {
    @available(iOS 15.0, *)
    var userNotificationInterruptLevel: UNNotificationInterruptionLevel {
        switch self {
        case .critical:
            return .critical
        case .timeSensitive:
            return .timeSensitive
        case .active:
            return .active
        }
    }
}

fileprivate extension UNNotificationRequest {
    convenience init(from alert: Alert, timestamp: Date) throws {
        let content = try alert.getUserNotificationContent(timestamp: timestamp)
        self.init(identifier: alert.identifier.value,
                  content: content,
                  trigger: UNTimeIntervalNotificationTrigger(from: alert.trigger))
    }
}

fileprivate extension UNTimeIntervalNotificationTrigger {
    convenience init?(from alertTrigger: Alert.Trigger) {
        switch alertTrigger {
        case .immediate:
            return nil
        case .delayed(let timeInterval):
            self.init(timeInterval: timeInterval, repeats: false)
        case .repeating(let repeatInterval):
            self.init(timeInterval: repeatInterval, repeats: true)
        }
    }
}
