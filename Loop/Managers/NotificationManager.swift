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
    
    @MainActor
    static func sendRemoteCommandSuccessNotification(for command: RemoteCommand) async {
        let notification = UNMutableNotificationContent()

        notification.title = NSLocalizedString("Remote Command Success", comment: "The notification title for the remote command success")

        //TODO: Improve the success messages -- need descriptive messages for each command
        notification.body = formatNotificationBody(String(describing: command))
        notification.sound = .default
        
        notification.categoryIdentifier = LoopNotificationCategory.remoteCommandSuccess.rawValue

        /*
         TODO: It seems we want to show all success messages and not limit like this.
         Ex: Think of a caregiver issues a 9 unit command then a 1 unit command.
         Suppressing the 9 unit notification could lead to treatment mistakes for onsight caregiver.
         */
        let request = UNNotificationRequest(
            // Only support 1 remote notification at once
            identifier: LoopNotificationCategory.remoteCommandSuccess.rawValue,
            content: notification,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
    
    @MainActor
    static func sendRemoteCommandFailureNotification(for error: Error) async {
        let notification = UNMutableNotificationContent()

        notification.title = NSLocalizedString("Remote Command Error", comment: "The notification title for the remote command error")

        //TODO: The error messages may be truncated if we don't use the types here.
        //We may need a layer down to show error messages and here just fail the command.
        //Or consider unrwapping NSError when able: https://stackoverflow.com/questions/39176196/how-to-provide-a-localized-description-with-an-error-type-in-swift
        notification.body = formatNotificationBody(error.localizedDescription)
        notification.sound = .default
        
        notification.categoryIdentifier = LoopNotificationCategory.remoteCommandFailure.rawValue

        let request = UNNotificationRequest(
            // Only support 1 notification at once
            identifier: LoopNotificationCategory.remoteCommandFailure.rawValue,
            content: notification,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
    
    private static func formatNotificationBody(_ body: String) -> String {
        let fullStopCharacter = NSLocalizedString(".", comment: "Full stop character")
        let sentenceFormat = NSLocalizedString("%1@%2@", comment: "Adds a full-stop to a statement (1: statement, 2: full stop character)")
        
        return [body].compactMap({ $0 }).map({
            // Avoids the double period at the end of a sentence.
            $0.hasSuffix(fullStopCharacter) ? $0 : String(format: sentenceFormat, $0, fullStopCharacter)
        }).joined(separator: " ")
    }
}
