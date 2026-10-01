//
//  LoopUpdateContext.swift
//  Loop
//
//  Extracted from LoopDataManager so that code shared with other targets — anything that
//  posts a loop-data-updated notification without being the phone's loop — can name the
//  reason for the update.
//

import Foundation

enum LoopUpdateContext: Int {
    case insulin
    case carbs
    case glucose
    case preferences
    case forecast
}

extension Notification.Name {
    static let LoopDataUpdated = Notification.Name(rawValue: "com.loopkit.Loop.LoopDataUpdated")
}

extension LoopUpdateContext {
    static let notificationKey = "com.loudnate.Loop.LoopDataManager.LoopUpdateContext"
}
