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

    /// One alarm `interval` from now, replacing any pending one under `identifier`. Time-sensitive
    /// is the highest level the watch is entitled to; no Critical Alerts.
    static func arm(_ identifier: String, thread: String? = nil, after interval: TimeInterval, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = .timeSensitive
        content.sound = .default
        content.threadIdentifier = thread ?? identifier
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        scheduler.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// Withdraws the alarms, pending and delivered.
    static func disarm(_ identifiers: [String]) {
        scheduler.removePendingRequests(withIdentifiers: identifiers)
        scheduler.removeDeliveredRequests(withIdentifiers: identifiers)
    }
}
