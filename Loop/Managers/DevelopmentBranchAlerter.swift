//
//  DevelopmentBranchAlerter.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import UIKit

enum DevelopmentBranchAlerter {

    // The LoopWorkspace superproject branch this warning applies to.
    private static let developmentBranchName = "dev"

    private static let switchToMainURL = URL(string: "https://loopkit.github.io/loopdocs/faqs/loop-faqs/#how-do-i-return-to-the-released-version")!

    private static let acknowledgedDateKey = "com.loopkit.Loop.DevelopmentBranchAlerter.acknowledgedDate"
    private static let reminderInterval: TimeInterval = 7 * 24 * 60 * 60

    /// Presents a warning when this is a build from the development branch, at most once a week
    /// once acknowledged.
    static func alertIfNeeded(viewControllerToPresentFrom: UIViewController) {
        guard FeatureFlags.devBranchWarningEnabled else {
            return
        }

        guard BuildDetails.default.workspaceGitBranch == developmentBranchName else {
            return
        }

        if let acknowledged = UserDefaults.standard.object(forKey: acknowledgedDateKey) as? Date,
           Date().timeIntervalSince(acknowledged) < reminderInterval {
            return
        }

        let alert = UIAlertController(
            title: NSLocalizedString("Warning", comment: "Title of the warning shown at launch on development builds"),
            message: NSLocalizedString("This is the development version of Loop, built from the dev branch. Any updates on this branch may contain new, untested features, and may be unsafe. If you are not a tester, please do not use this branch, and switch to main.", comment: "Body of the warning shown at launch on development builds"),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(
            title: NSLocalizedString("I'm a tester", comment: "Button that dismisses the development build warning"),
            style: .default,
            handler: { _ in
                UserDefaults.standard.set(Date(), forKey: acknowledgedDateKey)
            }
        ))

        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Switch to main", comment: "Button on the development build warning that opens documentation about switching branches"),
            style: .default,
            handler: { _ in
                UIApplication.shared.open(switchToMainURL)
            }
        ))

        viewControllerToPresentFrom.present(alert, animated: true)
    }
}
