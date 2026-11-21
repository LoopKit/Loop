//
//  UserNotificationAlertScheduler.swift
//  LoopKit
//
//  Created by Rick Pasetto on 4/9/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import UIKit
import AudioToolbox

public protocol UserNotificationCenter {
    func add(_ request: UNNotificationRequest, withCompletionHandler: ((Error?) -> Void)?)
    func removePendingNotificationRequests(withIdentifiers: [String])
    func removeDeliveredNotifications(withIdentifiers: [String])
    func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void)
    func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void)
}
extension UNUserNotificationCenter: UserNotificationCenter {}

extension UserNotificationCenter {
    func addNotificationRequest(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            getPendingNotificationRequests { continuation.resume(returning: $0) }
        }
    }
}

public class UserNotificationAlertScheduler {
    
    let userNotificationCenter: UserNotificationCenter
    let log = DiagnosticLog(category: "UserNotificationAlertScheduler")
    
    init(userNotificationCenter: UserNotificationCenter) {
        self.userNotificationCenter = userNotificationCenter
    }
    
    func scheduleAlert(_ alert: Alert, muted: Bool = false) {
        scheduleAlert(alert, timestamp: Date(), muted: muted)
    }

    func scheduleAlert(_ alert: Alert, timestamp: Date, muted: Bool = false) {
        DispatchQueue.main.async {
            let content = alert.getUserNotificationContent(timestamp: timestamp, muted: muted)
            let request = UNNotificationRequest(identifier: alert.identifier.value,
                      content: content,
                      trigger: UNTimeIntervalNotificationTrigger(from: alert.trigger))

            self.userNotificationCenter.add(request) { error in
                if let error = error {
                    self.log.error("Something went wrong posting the user notification: %@", error.localizedDescription)
                }
            }
            // For now, UserNotifications do not not acknowledge...not yet at least
        }
    }
    
    func unscheduleAlert(identifier: Alert.Identifier) {
        DispatchQueue.main.async {
            self.userNotificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier.value])
            self.userNotificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier.value])
        }
    }

    func alertWasAcknowledged(identifier: Alert.Identifier) {
        DispatchQueue.main.async {
            self.log.debug("Removing notification %@ from delivered notifications", identifier.value)
            self.userNotificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier.value])
        }
    }
}

fileprivate extension Alert {
    func getUserNotificationContent(timestamp: Date, muted: Bool) -> UNNotificationContent {
        let userNotificationContent = UNMutableNotificationContent()
        userNotificationContent.title = backgroundContent.title
        userNotificationContent.body = backgroundContent.body
        userNotificationContent.sound = userNotificationSound(muted: muted)
        userNotificationContent.interruptionLevel = interruptionLevel.userNotificationInterruptLevel
        userNotificationContent.categoryIdentifier = categoryIdentifier ?? ""
        userNotificationContent.threadIdentifier = identifier.value // Used to match categoryIdentifier, but I /think/ we want multiple threads for multiple alert types, no?
        userNotificationContent.userInfo = [
            LoopNotificationUserInfoKey.managerIDForAlert.rawValue: identifier.managerIdentifier,
            LoopNotificationUserInfoKey.alertTypeID.rawValue: identifier.alertIdentifier,
        ]

        if let metadata {
            for (key, value) in metadata {
                guard let value = value.wrapped as? String else { continue }
                userNotificationContent.userInfo[key] = value
            }
        }
    
        return userNotificationContent
    }
    
    private func userNotificationSound(muted: Bool) -> UNNotificationSound? {
        guard !muted else { return interruptionLevel == .critical ? .defaultCriticalSound(withAudioVolume: 0) : nil }
        
        switch sound {
        case .vibrate:
            guard interruptionLevel == .critical else {
                AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
                return nil
            }
            // setting the audio volume of critical alert to 0 only vibrates
            return .defaultCriticalSound(withAudioVolume: 0)
        default:
            if let actualFileName = AlertManager.soundURL(for: self)?.lastPathComponent {
                let unname = UNNotificationSoundName(rawValue: actualFileName)
                return interruptionLevel == .critical ? UNNotificationSound.criticalSoundNamed(unname) : UNNotificationSound(named: unname)
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
