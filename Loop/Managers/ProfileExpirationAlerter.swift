//
//  ProfileExpirationAlerter.swift
//  Loop
//
//  Created by Pete Schwamb on 8/21/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import UserNotifications
import LoopCore


class ProfileExpirationAlerter {
    
    static let expirationAlertWindow: TimeInterval = .days(20)

    static func alertIfNeeded(viewControllerToPresentFrom: UIViewController) {
        
        let now = Date()
        
        guard let profileExpiration = Bundle.main.profileExpiration, now > profileExpiration - expirationAlertWindow else {
            return
        }
        
        let timeUntilExpiration = profileExpiration.timeIntervalSince(now)
        
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
        
        let dialog = UIAlertController(
            title: NSLocalizedString("Profile Expires Soon", comment: "The title for notification of upcoming profile expiration"),
            message: String(format: NSLocalizedString("%1$@ will stop working in %2$@. You will need to update before that, with a new provisioning profile.", comment: "Format string for body for notification of upcoming provisioning profile expiration. (1: app name) (2: amount of time until expiration"), Bundle.main.bundleDisplayName, timeUntilExpirationStr!),
            preferredStyle: .alert)
        dialog.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Text for ok action on notification of upcoming profile expiration"), style: .default, handler: nil))
        dialog.addAction(UIAlertAction(title: NSLocalizedString("More Info", comment: "Text for more info action on notification of upcoming profile expiration"), style: .default, handler: { (_) in
            UIApplication.shared.open(URL(string: "https://loopkit.github.io/loopdocs/build/updating/")!)
        }))
        viewControllerToPresentFrom.present(dialog, animated: true, completion: nil)
        
        UserDefaults.appGroup?.lastProfileExpirationAlertDate = now
    }
}
