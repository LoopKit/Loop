//
//  NSUserActivity.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


extension NSUserActivity {
    /// Activity of viewing the current status of the Loop
    static let viewLoopStatusActivityType = "ViewLoopStatus"

    class func forViewLoopStatus() -> NSUserActivity {
        return NSUserActivity(activityType: viewLoopStatusActivityType)
    }

    static let didAddCarbEntryOnWatchActivityType = "com.loopkit.Loop.AddCarbEntryOnWatch"

    class func forDidAddCarbEntryOnWatch() -> NSUserActivity {
        let activity = NSUserActivity(activityType: didAddCarbEntryOnWatchActivityType)
        activity.isEligibleForSearch = true
        activity.isEligibleForHandoff = false
        activity.isEligibleForPublicIndexing = false
        if #available(iOS 12.0, watchOSApplicationExtension 5.0, *) {
            activity.isEligibleForPrediction = true
        }
        activity.requiredUserInfoKeys = []
        activity.title = NSLocalizedString("Add Carb Entry", comment: "Title of the user activity for adding carbs")
        return activity
    }
    
    static let didEnableOverrideOnWatchActivityType = "com.loopkit.Loop.EnableOverrideOnWatch"

    class func forDidEnableOverrideOnWatch() -> NSUserActivity {
        let activity = NSUserActivity(activityType: didEnableOverrideOnWatchActivityType)
        activity.isEligibleForSearch = true
        activity.isEligibleForHandoff = false
        activity.isEligibleForPublicIndexing = false
        if #available(iOS 12.0, watchOSApplicationExtension 5.0, *) {
            activity.isEligibleForPrediction = true
        }
        activity.requiredUserInfoKeys = []
        activity.title = NSLocalizedString("Enable Override Preset", comment: "Title of the user activity for enabling an override preset")
        return activity
    }
}
