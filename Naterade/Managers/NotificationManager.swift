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
        case LoopNotRunning
        case PumpBatteryLow
        case PumpReservoirEmpty
        case PumpReservoirLow
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

    static func scheduleLoopNotRunningNotifications() {
        let app = UIApplication.sharedApplication()

        // Cancel any previous scheduled notifications
        app.scheduledLocalNotifications?.filter({ $0.category == Category.LoopNotRunning.rawValue }).forEach({ app.cancelLocalNotification($0) })

        // Give a little extra time for a loop-in-progress to complete
        let gracePeriod = NSTimeInterval(minutes: 0.5)

        for minutes: Double in [20, 40, 60, 120] {
            let notification = UILocalNotification()
            let failureInterval = NSTimeInterval(minutes: minutes)

            let formatter = NSDateComponentsFormatter()
            formatter.maximumUnitCount = 1
            formatter.allowedUnits = [.Hour, .Minute]
            formatter.unitsStyle = .Full
            formatter.stringFromTimeInterval(failureInterval)?.localizedLowercaseString

            if let failueIntervalString = formatter.stringFromTimeInterval(failureInterval) {
                notification.alertBody = String(format: NSLocalizedString("Loop has not completed successfully in %@", comment: "The notification alert describing a long-lasting loop failure. The substitution parameter is the time interval since the last loop"), failueIntervalString)
            }

            notification.alertTitle = NSLocalizedString("Loop Failure", comment: "The notification title for a loop failure")
            notification.fireDate = NSDate(timeIntervalSinceNow: failureInterval + gracePeriod)
            notification.soundName = UILocalNotificationDefaultSoundName
            notification.category = Category.LoopNotRunning.rawValue

            app.scheduleLocalNotification(notification)
        }
    }

    static func sendPumpBatteryLowNotification() {
        let notification = UILocalNotification()

        notification.alertTitle = NSLocalizedString("Pump Battery Low", comment: "The notification title for a low pump battery")
        notification.alertBody = NSLocalizedString("Change the pump battery immediately", comment: "The notification alert describing a low pump battery")
        notification.soundName = UILocalNotificationDefaultSoundName
        notification.category = Category.PumpBatteryLow.rawValue

        UIApplication.sharedApplication().presentLocalNotificationNow(notification)
    }

    static func sendPumpReservoirEmptyNotification() {
        let notification = UILocalNotification()

        notification.alertTitle = NSLocalizedString("Pump Reservoir Empty", comment: "The notification title for an empty pump reservoir")
        notification.alertBody = NSLocalizedString("Change the pump reservoir now", comment: "The notification alert describing an empty pump reservoir")
        notification.soundName = UILocalNotificationDefaultSoundName
        notification.category = Category.PumpReservoirEmpty.rawValue

        // TODO: Add an action to Suspend the pump

        UIApplication.sharedApplication().presentLocalNotificationNow(notification)
    }

    static func sendPumpReservoirLowNotificationForAmount(units: Double, andTimeRemaining remaining: NSTimeInterval) {
        let notification = UILocalNotification()

        notification.alertTitle = NSLocalizedString("Pump Reservoir Low", comment: "The notification title for a low pump reservoir")

        let unitsString = NSNumberFormatter.localizedStringFromNumber(units, numberStyle: .DecimalStyle)

        let intervalFormatter = NSDateComponentsFormatter()
        intervalFormatter.allowedUnits = [.Hour, .Minute]
        intervalFormatter.maximumUnitCount = 1
        intervalFormatter.unitsStyle = .Full
        intervalFormatter.includesApproximationPhrase = true
        intervalFormatter.includesTimeRemainingPhrase = true

        guard let timeString = intervalFormatter.stringFromTimeInterval(remaining) else {
            return
        }

        notification.alertBody = NSLocalizedString("\(unitsString) U left: \(timeString)", comment: "")

        notification.soundName = UILocalNotificationDefaultSoundName
        notification.category = Category.PumpReservoirLow.rawValue

        UIApplication.sharedApplication().presentLocalNotificationNow(notification)
    }
}
