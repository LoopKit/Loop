//
//  AppExpirationAlerter.swift
//  Loop
//
//  Created by Pete Schwamb on 8/21/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import UserNotifications
import LoopCore


class AppExpirationAlerter {
    
    static let expirationAlertWindow: TimeInterval = .days(20)
    static let settingsPageExpirationWarningModeWindow: TimeInterval = .days(3)

    static func alertIfNeeded(viewControllerToPresentFrom: UIViewController) {
        
        let now = Date()

        guard let profileExpiration = BuildDetails.default.profileExpiration else {
            return
        }
        
        let expirationDate = calculateExpirationDate(profileExpiration: profileExpiration)
        
        let timeUntilExpiration = expirationDate.timeIntervalSince(now)
        
        if timeUntilExpiration > expirationAlertWindow {
            return
        }

        let minimumTimeBetweenAlerts: TimeInterval = timeUntilExpiration > .hours(24) ? .days(2) : .hours(1)
        
        if let lastAlertDate = UserDefaults.appGroup?.lastProfileExpirationAlertDate {
            guard now > lastAlertDate + minimumTimeBetweenAlerts else {
                return
            }
        }
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropLeading
        formatter.maximumUnitCount = 1
        let timeUntilExpirationStr = formatter.string(from: timeUntilExpiration)
        
        let alertMessage = createVerboseAlertMessage(timeUntilExpirationStr: timeUntilExpirationStr!)
        
        var dialog: UIAlertController
        if isTestFlightBuild() {
            dialog = UIAlertController(
                title: NSLocalizedString("TestFlight Expires Soon", comment: "The title for notification of upcoming TestFlight expiration"),
                message: alertMessage,
                preferredStyle: .alert)
            dialog.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Text for ok action on notification of upcoming TestFlight expiration"), style: .default, handler: nil))
            dialog.addAction(UIAlertAction(title: NSLocalizedString("More Info", comment: "Text for more info action on notification of upcoming TestFlight expiration"), style: .default, handler: { (_) in
                UIApplication.shared.open(URL(string: "https://loopkit.github.io/loopdocs/gh-actions/gh-update/")!)
            }))

        } else {
            dialog = UIAlertController(
                title: NSLocalizedString("Profile Expires Soon", comment: "The title for notification of upcoming profile expiration"),
                message: alertMessage,
                preferredStyle: .alert)
            dialog.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Text for ok action on notification of upcoming profile expiration"), style: .default, handler: nil))
            dialog.addAction(UIAlertAction(title: NSLocalizedString("More Info", comment: "Text for more info action on notification of upcoming profile expiration"), style: .default, handler: { (_) in
                UIApplication.shared.open(URL(string: "https://loopkit.github.io/loopdocs/build/updating/")!)
            }))
        }
        viewControllerToPresentFrom.present(dialog, animated: true, completion: nil)
        
        UserDefaults.appGroup?.lastProfileExpirationAlertDate = now
    }
    
    static func createVerboseAlertMessage(timeUntilExpirationStr:String) -> String {
        if isTestFlightBuild() {
            return String(format: NSLocalizedString("%1$@ will stop working in %2$@. You will need to rebuild before that.", comment: "Format string for body for notification of upcoming expiration. (1: app name) (2: amount of time until expiration"), Bundle.main.bundleDisplayName, timeUntilExpirationStr)
        } else {
            return String(format: NSLocalizedString("%1$@ will stop working in %2$@. You will need to update before that, with a new provisioning profile.", comment: "Format string for body for notification of upcoming provisioning profile expiration. (1: app name) (2: amount of time until expiration"), Bundle.main.bundleDisplayName, timeUntilExpirationStr)
        }
    }
    
    static func isNearExpiration(expirationDate:Date) -> Bool {
        return expirationDate.timeIntervalSinceNow < settingsPageExpirationWarningModeWindow
    }
    
    static func createProfileExpirationSettingsMessage(expirationDate:Date) -> String {
        let nearExpiration = isNearExpiration(expirationDate: expirationDate)
        let maxUnitCount = nearExpiration ? 2 : 1 // only include hours in the msg if near expiration
        let readableRelativeTime: String? = relativeTimeFormatter(maxUnitCount: maxUnitCount).string(from: expirationDate.timeIntervalSinceNow)
        let relativeTimeRemaining: String = readableRelativeTime ?? NSLocalizedString("Unknown time", comment: "Unknown amount of time in settings' profile expiration section")
        let verboseMessage = createVerboseAlertMessage(timeUntilExpirationStr: relativeTimeRemaining)
        let conciseMessage = relativeTimeRemaining + NSLocalizedString(" remaining", comment: "remaining time in setting's profile expiration section")
        return nearExpiration ? verboseMessage : conciseMessage
    }
    
    private static func relativeTimeFormatter(maxUnitCount:Int) -> DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        let includeHours = maxUnitCount == 2
        formatter.allowedUnits = includeHours ? [.day, .hour] :  [.day]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropLeading
        formatter.maximumUnitCount = maxUnitCount
        return formatter
    }
    
    static func buildDate() -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE MMM d HH:mm:ss 'UTC' yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX") // Set locale to ensure parsing works
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        
        guard let dateString = BuildDetails.default.buildDateString,
              let date = dateFormatter.date(from: dateString) else {
            return nil
        }
        
        return date
    }
    
    static func isTestFlightBuild() -> Bool {
        // If the target environment is a simulator, then
        // this is not a TestFlight distribution. Return false.
        #if targetEnvironment(simulator)
        return false
        #else

        // If an "embedded.mobileprovision" is present in the main bundle, then
        // this is an Xcode, Ad-Hoc, or Enterprise distribution. Return false.
        if Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil {
            return false
        }

        // If an app store receipt is not present in the main bundle, then we cannot
        // say whether this is a TestFlight or App Store distribution. Return false.
        guard let receiptName = Bundle.main.appStoreReceiptURL?.lastPathComponent else {
            return false
        }

        // A TestFlight distribution presents a "sandboxReceipt", while an App Store
        // distribution presents a "receipt". Return true if we have a TestFlight receipt.
        return "sandboxReceipt".caseInsensitiveCompare(receiptName) == .orderedSame
        #endif
    }

    static func calculateExpirationDate(profileExpiration: Date) -> Date {
        let isTestFlight = isTestFlightBuild()
        
        if isTestFlight, let buildDate = buildDate() {
            let testflightExpiration = Calendar.current.date(byAdding: .day, value: 90, to: buildDate)!
            
            return testflightExpiration
        } else {
            return profileExpiration
        }
    }
}
