//
//  WristAlertScheduler.swift
//  WatchApp Extension
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  The seam wrist alarms are armed through; tests check identifier discipline, not delivery.
//

import Foundation
import UserNotifications

/// The three calls the wrist's alarms need. Production code goes through `WristAlerts.scheduler`
/// rather than reaching for the notification centre directly, or its arming is invisible to tests.
protocol WristAlertScheduling: AnyObject {
    func add(_ request: UNNotificationRequest)
    func removePendingRequests(withIdentifiers identifiers: [String])
    func removeDeliveredRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: WristAlertScheduling {
    // The real centre, minus the completion handler nothing here acts on.
    func add(_ request: UNNotificationRequest) {
        add(request, withCompletionHandler: nil)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredRequests(withIdentifiers identifiers: [String]) {
        removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

enum WristAlerts {
    /// The live scheduler. Tests substitute a recording double; nothing else should replace it.
    static var scheduler: WristAlertScheduling = UNUserNotificationCenter.current()
}
