//
//  WristAlertScheduler.swift
//  WatchApp Extension
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  The seam every pre-scheduled wrist alarm is armed and disarmed through.
//
//  Delivery itself can never be asserted: `UNUserNotificationCenter.add` is silently dropped when
//  the process is not authorized, and a test host cannot obtain authorization. What routing
//  through this protocol does keep testable is identifier discipline — re-arming an identifier
//  defers that alarm rather than stacking a second one, and every alarm owns a distinct
//  identifier so disarming one cannot cancel another.
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
