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
        retryBolusAction.activationMode = .background

        let bolusFailureCategory = UIMutableUserNotificationCategory()
        bolusFailureCategory.identifier = Category.BolusFailure.rawValue
        bolusFailureCategory.setActions([
                retryBolusAction
            ],
            for: .default
        )

        return UIUserNotificationSettings(
            types: [.badge, .sound, .alert],
            categories: [
                bolusFailureCategory
            ]
        )
    }

    static func authorize() {
        UIApplication.shared.registerUserNotificationSettings(userNotificationSettings)
    }

    // MARK: - Notifications

    static func sendBolusFailureNotificationForAmount(_ units: Double, atStartDate startDate: Date) {
        let notification = UILocalNotification()

        notification.alertTitle = NSLocalizedString("Bolus", comment: "The notification title for a bolus failure")
        notification.alertBody = String(format: NSLocalizedString("%@ U bolus may have failed.", comment: "The notification alert describing a possible bolus failure. The substitution parameter is the size of the bolus in units."), NumberFormatter.localizedString(from: NSNumber(value: units), number: .decimal))
        notification.soundName = UILocalNotificationDefaultSoundName

        if startDate.timeIntervalSinceNow >= TimeInterval(minutes: -5) {
            notification.category = Category.BolusFailure.rawValue
        }

        notification.userInfo = [
            UserInfoKey.BolusAmount.rawValue: units,
            UserInfoKey.BolusStartDate.rawValue: startDate
        ]

        UIApplication.shared.presentLocalNotificationNow(notification)
    }

    // Cancel any previous scheduled notifications in the Loop Not Running category
    static func clearLoopNotRunningNotifications() {
        let app = UIApplication.shared

        app.scheduledLocalNotifications?.filter({
            $0.category == Category.LoopNotRunning.rawValue
        }).forEach({
            app.cancelLocalNotification($0)
        })
    }

    static func scheduleLoopNotRunningNotifications() {
        let app = UIApplication.shared

        clearLoopNotRunningNotifications()

        // Give a little extra time for a loop-in-progress to complete
        let gracePeriod = TimeInterval(minutes: 0.5)

        for minutes: Double in [20, 40, 60, 120] {
            let notification = UILocalNotification()
            let failureInterval = TimeInterval(minutes: minutes)

            let formatter = DateComponentsFormatter()
            formatter.maximumUnitCount = 1
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .full

            if let failueIntervalString = formatter.string(from: failureInterval)?.localizedLowercase {
                notification.alertBody = String(format: NSLocalizedString("Loop has not completed successfully in %@", comment: "The notification alert describing a long-lasting loop failure. The substitution parameter is the time interval since the last loop"), failueIntervalString)
            }

            notification.alertTitle = NSLocalizedString("Loop Failure", comment: "The notification title for a loop failure")
            notification.fireDate = Date(timeIntervalSinceNow: failureInterval + gracePeriod)
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

        UIApplication.shared.presentLocalNotificationNow(notification)
    }

    static func sendPumpReservoirEmptyNotification() {
        let notification = UILocalNotification()

        notification.alertTitle = NSLocalizedString("Pump Reservoir Empty", comment: "The notification title for an empty pump reservoir")
        notification.alertBody = NSLocalizedString("Change the pump reservoir now", comment: "The notification alert describing an empty pump reservoir")
        notification.soundName = UILocalNotificationDefaultSoundName
        notification.category = Category.PumpReservoirEmpty.rawValue

        // TODO: Add an action to Suspend the pump

        UIApplication.shared.presentLocalNotificationNow(notification)
    }

    static func sendPumpReservoirLowNotificationForAmount(_ units: Double, andTimeRemaining remaining: TimeInterval?) {
        let notification = UILocalNotification()

        notification.alertTitle = NSLocalizedString("Pump Reservoir Low", comment: "The notification title for a low pump reservoir")

        let unitsString = NumberFormatter.localizedString(from: NSNumber(value: units), number: .decimal)

        let intervalFormatter = DateComponentsFormatter()
        intervalFormatter.allowedUnits = [.hour, .minute]
        intervalFormatter.maximumUnitCount = 1
        intervalFormatter.unitsStyle = .full
        intervalFormatter.includesApproximationPhrase = true
        intervalFormatter.includesTimeRemainingPhrase = true

        if let remaining = remaining, let timeString = intervalFormatter.string(from: remaining) {
            notification.alertBody = String(format: NSLocalizedString("%1$@ U left: %2$@", comment: "Low reservoir alert with time remaining format string. (1: Number of units remaining)(2: approximate time remaining)"), unitsString, timeString)
        } else {
            notification.alertBody = String(format: NSLocalizedString("%1$@ U left", comment: "Low reservoir alert format string. (1: Number of units remaining)"), unitsString)
        }

        notification.soundName = UILocalNotificationDefaultSoundName
        notification.category = Category.PumpReservoirLow.rawValue

        UIApplication.shared.presentLocalNotificationNow(notification)
    }
}
