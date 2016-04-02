//
//  NotificationManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


struct NotificationManager {
    enum Category: String {
        case BolusFailure
    }

    enum Action: String {
        case RetryBolus
    }

    enum UserInfoKey: String {
        case BolusAmount
        case BolusStartDate
    }

    static var userNotificationSettings: UIUserNotificationSettings {
        let retryBolusAction = UIMutableUserNotificationAction()
        retryBolusAction.title = NSLocalizedString("Retry", comment: "The title of the notification action to retry a bolus command")
        retryBolusAction.identifier = Action.RetryBolus.rawValue
        retryBolusAction.activationMode = .Background

        let bolusFailureCategory = UIMutableUserNotificationCategory()
        bolusFailureCategory.identifier = Category.BolusFailure.rawValue
        bolusFailureCategory.setActions([
                retryBolusAction
            ],
            forContext: .Default
        )

        return UIUserNotificationSettings(
            forTypes: [.Badge, .Sound, .Alert],
            categories: [
                bolusFailureCategory
            ]
        )
    }

    static func authorize() {
        UIApplication.sharedApplication().registerUserNotificationSettings(userNotificationSettings)
    }

    // MARK: - Notifications

    static func sendBolusFailureNotificationForAmount(units: Double, atDate startDate: NSDate) {
        let notification = UILocalNotification()

        notification.alertTitle = NSLocalizedString("Bolus", comment: "The notification title for a bolus failure")
        notification.alertBody = String(format: NSLocalizedString("%@ U bolus may have failed.", comment: "The notification alert describing a possible bolus failure. The substitution parameter is the size of the bolus in units."), NSNumberFormatter.localizedStringFromNumber(units, numberStyle: .DecimalStyle))
        notification.soundName = UILocalNotificationDefaultSoundName

        if startDate.timeIntervalSinceNow >= NSTimeInterval(minutes: -5) {
            notification.category = Category.BolusFailure.rawValue
        }

        notification.userInfo = [
            UserInfoKey.BolusAmount.rawValue: units,
            UserInfoKey.BolusStartDate.rawValue: startDate
        ]

        UIApplication.sharedApplication().presentLocalNotificationNow(notification)
    }
}
