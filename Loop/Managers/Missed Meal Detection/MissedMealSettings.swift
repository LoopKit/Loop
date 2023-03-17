//
//  MissedMealSettings.swift
//  Loop
//
//  Created by Anna Quinlan on 11/28/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

public struct MissedMealSettings {
    /// Minimum grams of unannounced carbs that must be detected for a notification to be delivered
    public static let minCarbThreshold: Double = 15 // grams
    /// Maximum grams of unannounced carbs that the algorithm will search for
    public static let maxCarbThreshold: Double = 80 // grams
    /// Minimum threshold for glucose rise over the detection window
    static let glucoseRiseThreshold = 2.0 // mg/dL/m
    /// Minimum time from now that must have passed for the meal to be detected
    public static let minRecency = TimeInterval(minutes: 15)
    /// Maximum time from now that a meal can be detected
    public static let maxRecency = TimeInterval(hours: 2)
    /// Maximum delay allowed in missed meal notification time to avoid
    /// notifying the user during an autobolus
    public static let maxNotificationDelay = TimeInterval(minutes: 4)
}
