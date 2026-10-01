//
//  LoopStallWatchdog.swift
//  WatchApp Extension
//
//  The wrist's two dead-man alarms: the loop stopped, and the hand-back never finished.
//
//  watchOS suspends this app whenever the wrist drops, and a suspended process cannot raise an
//  alarm about itself. So both alarms are PRE-SCHEDULED with UNUserNotificationCenter and pushed
//  forward from outside: while the thing being watched keeps making progress the notification is
//  perpetually re-deferred and never fires, and when it stops, nothing defers it and watchOS
//  delivers it whether or not the app is still alive.
//

import Foundation
import UserNotifications

/// The phone's Loop-Failure ladder relocated to the wrist — same intervals, same escalation,
/// same words. Exactly one of the two ladders is armed at any moment: the phone's is suppressed
/// for the whole loan and this one is disarmed outside a loan, so the user hears one voice, not
/// two saying the same thing.
enum LoopStallWatchdog {
    static let rungs: [(interval: TimeInterval, isCritical: Bool)] = [
        (20 * 60, false), (40 * 60, false), (60 * 60, true), (120 * 60, true),
    ]

    /// The first rung — the single number for anything that reasons about "the" deadline.
    static let interval: TimeInterval = rungs[0].interval

    private static let identifier = "com.loopkit.Loop.watch.loopStallWatchdog"
    private static var rungIdentifiers: [String] { rungs.map { "\(identifier).\(Int($0.interval))" } }

    /// Arm the ladder, or push every rung forward. One identifier per rung, and adding a request
    /// with an existing identifier REPLACES the pending one — that replacement is the whole
    /// dead-man mechanism, so calling this on each landed cycle re-defers the ladder in place.
    /// Distinct identifiers per rung also mean disarming one can never cancel another.
    static func refresh() {
        let center = WristAlerts.scheduler
        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        for rung in rungs {
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Loop Failure", comment: "The notification title for a loop failure")
            content.body = String(format: NSLocalizedString("Loop has not completed successfully in %@", comment: "The notification alert describing a long-lasting loop failure. The substitution parameter is the time interval since the last loop"),
                                  formatter.string(from: rung.interval)?.localizedLowercase ?? "\(Int(rung.interval / 60)) minutes")

            // The late rungs ask for .critical. Without the Critical Alerts entitlement watchOS
            // delivers them as time-sensitive instead, which is the acceptable floor.
            content.interruptionLevel = rung.isCritical ? .critical : .timeSensitive
            content.sound = rung.isCritical ? .defaultCritical : .default
            content.threadIdentifier = identifier
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: rung.interval, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(identifier).\(Int(rung.interval))",
                                             content: content, trigger: trigger))
        }
    }

    /// For a loop that stops ON PURPOSE — hand-back, revoke, end of session. The phone re-arms
    /// its own ladder when it takes the pod back, so coverage transfers rather than lapses.
    static func disarm() {
        let center = WristAlerts.scheduler
        center.removePendingRequests(withIdentifiers: rungIdentifiers)
        center.removeDeliveredRequests(withIdentifiers: rungIdentifiers)
    }
}

/// Fires from outside the app when a hand-back never completes. The watch can be suspended
/// through the whole wait, and a stuck hand-back leaves the pod on the wrist while the user
/// believes Sport Mode has ended.
enum HandbackStuckAlert {
    /// The budget covers two offers and a pod read, so it is minutes rather than seconds. Cut it
    /// short and the watch abandons the hand-back while the phone's commit is still in flight;
    /// the phone then acks a hand-back nobody is waiting for and both devices hold the pod.
    static let interval: TimeInterval = 2 * 60

    private static let identifier = "sportmode.handbackStuck"

    static func arm() {
        let center = WristAlerts.scheduler
        center.removePendingRequests(withIdentifiers: [identifier])
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Couldn't End Sport Mode", comment: "Hand-back-stuck alert title")
        content.body = NSLocalizedString("The iPhone didn't respond, so Sport Mode is still running on your watch. Tap End to try again.", comment: "Hand-back-stuck alert body")
        content.interruptionLevel = .timeSensitive
        content.sound = .default
        content.threadIdentifier = identifier
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func disarm() {
        let center = WristAlerts.scheduler
        center.removePendingRequests(withIdentifiers: [identifier])
        center.removeDeliveredRequests(withIdentifiers: [identifier])
    }
}
