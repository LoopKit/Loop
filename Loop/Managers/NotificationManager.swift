//
//  NotificationManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import UserNotifications
import LoopKit

enum NotificationManager {

    enum Action: String {
        case retryBolus
        case acknowledgeAlert
    }
}

extension NotificationManager {
    private static var notificationCategories: Set<UNNotificationCategory> {
        var categories = [UNNotificationCategory]()

        let retryBolusAction = UNNotificationAction(
            identifier: Action.retryBolus.rawValue,
            title: NSLocalizedString("Retry", comment: "The title of the notification action to retry a bolus command"),
            options: []
        )

        categories.append(UNNotificationCategory(
            identifier: LoopNotificationCategory.bolusFailure.rawValue,
            actions: [retryBolusAction],
            intentIdentifiers: [],
            options: []
        ))
        
        let acknowledgeAlertAction = UNNotificationAction(
            identifier: Action.acknowledgeAlert.rawValue,
            title: NSLocalizedString("OK", comment: "The title of the notification action to acknowledge a device alert"),
            options: .foreground
        )
        
        categories.append(UNNotificationCategory(
            identifier: LoopNotificationCategory.alert.rawValue,
            actions: [acknowledgeAlertAction],
            intentIdentifiers: [],
            options: .customDismissAction
        ))

        return Set(categories)
    }

    static func getAuthorization(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(settings.authorizationStatus)
        }
    }

    static func authorize(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        var authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        if FeatureFlags.criticalAlertsEnabled {
            authOptions.insert(.criticalAlert)
        }
        
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: authOptions) { (granted, error) in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                completion(settings.authorizationStatus)
                guard settings.authorizationStatus == .authorized else {
                    return
                }
            }
        }
        center.setNotificationCategories(notificationCategories)
    }
    

    // MARK: - Notifications
    
    static func sendRemoteCommandExpiredNotification(timeExpired: TimeInterval) {
        let notification = UNMutableNotificationContent()

        notification.title = NSLocalizedString("Remote Command Expired", comment: "The notification title for the remote command expiration error")

        notification.body = String(format: NSLocalizedString("The remote command expired %.0f minutes ago.", comment: "The notification body for a remote command expiration. (1: Expiration in minutes)"), fabs(timeExpired / 60.0))
        notification.sound = .default
         
        notification.categoryIdentifier = LoopNotificationCategory.remoteCommandExpired.rawValue

        let request = UNNotificationRequest(
            // Only support 1 expiration notification at once
            identifier: LoopNotificationCategory.remoteCommandExpired.rawValue,
            content: notification,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    static func sendBolusFailureNotification(for error: PumpManagerError, units: Double, at startDate: Date, activationType: BolusActivationType) {
        let notification = UNMutableNotificationContent()

        notification.title = NSLocalizedString("Bolus Issue", comment: "The notification title for a bolus issue")

        let fullStopCharacter = NSLocalizedString(".", comment: "Full stop character")
        let sentenceFormat = NSLocalizedString("%1@%2@", comment: "Adds a full-stop to a statement (1: statement, 2: full stop character)")

        let body = [error.errorDescription, error.failureReason, error.recoverySuggestion].compactMap({ $0 }).map({
            // Avoids the double period at the end of a sentence.
            $0.hasSuffix(fullStopCharacter) ? $0 : String(format: sentenceFormat, $0, fullStopCharacter)
        }).joined(separator: " ")

        notification.body = body
        notification.sound = .default

        if startDate.timeIntervalSinceNow >= TimeInterval(minutes: -5) {
            notification.categoryIdentifier = LoopNotificationCategory.bolusFailure.rawValue
        }

        notification.userInfo = [
            LoopNotificationUserInfoKey.bolusAmount.rawValue: units,
            LoopNotificationUserInfoKey.bolusStartDate.rawValue: startDate,
            LoopNotificationUserInfoKey.bolusActivationType.rawValue: activationType.rawValue
        ]

        let request = UNNotificationRequest(
            // Only support 1 bolus notification at once
            identifier: LoopNotificationCategory.bolusFailure.rawValue,
            content: notification,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
    
    static func sendRemoteBolusNotification(amount: Double) {
        let notification = UNMutableNotificationContent()
        let quantityFormatter = QuantityFormatter()
        quantityFormatter.setPreferredNumberFormatter(for: .internationalUnit())
        guard let amountDescription = quantityFormatter.numberFormatter.string(from: amount) else {
            return
        }
        notification.title =  String(format: NSLocalizedString("Remote Bolus Entry: %@ U", comment: "The notification title for a remote bolus. (1: Bolus amount)"), amountDescription)
        
        let body = "Success!"

        notification.body = body
        notification.sound = .default

        let request = UNNotificationRequest(
            identifier: LoopNotificationCategory.remoteBolus.rawValue,
            content: notification,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
    
    static func sendRemoteBolusFailureNotification(for error: Error, amount: Double) {
        let notification = UNMutableNotificationContent()
        let quantityFormatter = QuantityFormatter()
        quantityFormatter.setPreferredNumberFormatter(for: .internationalUnit())
        guard let amountDescription = quantityFormatter.numberFormatter.string(from: amount) else {
            return
        }

        notification.title =  String(format: NSLocalizedString("Remote Bolus Entry: %@ U", comment: "The notification title for a remote failure. (1: Bolus amount)"), amountDescription)
        notification.body = error.localizedDescription
        notification.sound = .default

        let request = UNNotificationRequest(
            identifier: LoopNotificationCategory.remoteBolusFailure.rawValue,
            content: notification,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
    
    static func sendRemoteCarbEntryNotification(amountInGrams: Double) {
        let notification = UNMutableNotificationContent()

        let leadingBody = remoteCarbEntryNotificationBody(amountInGrams: amountInGrams)
        let extraBody = "Success!"
        
        let body = [leadingBody, extraBody].joined(separator: "\n")

        notification.body = body
        notification.sound = .default

        let request = UNNotificationRequest(
            identifier: LoopNotificationCategory.remoteCarbs.rawValue,
            content: notification,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
    
    static func sendRemoteCarbEntryFailureNotification(for error: Error, amountInGrams: Double) {
        let notification = UNMutableNotificationContent()
        
        let leadingBody = remoteCarbEntryNotificationBody(amountInGrams: amountInGrams)
        let extraBody = error.localizedDescription

        let body = [leadingBody, extraBody].joined(separator: "\n")
        
        notification.body = body
        notification.sound = .default

        let request = UNNotificationRequest(
            identifier: LoopNotificationCategory.remoteCarbsFailure.rawValue,
            content: notification,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
    
    private static func remoteCarbEntryNotificationBody(amountInGrams: Double) -> String {
        return String(format: NSLocalizedString("Remote Carbs Entry: %d grams", comment: "The carb amount message for a remote carbs entry notification. (1: Carb amount in grams)"), Int(amountInGrams))
    }
}
