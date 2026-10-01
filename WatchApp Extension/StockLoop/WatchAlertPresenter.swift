//
//  WatchAlertPresenter.swift
//  WatchApp Extension
//
//  Putting a LoopKit alert on the wrist.
//
//  While the watch holds the pod it is the only device that can hear the pump. A pod fault, an
//  occlusion or an empty reservoir arrives here as a `LoopKit.Alert`, and the wearer has to be
//  told: the phone's own alert manager is not watching a pump it does not have.
//
//  Delivery goes through `WristAlerts.scheduler`, the same seam the dead-man ladder uses, so
//  arming is visible to tests. Delivery itself can never be asserted — the notification centre
//  drops a request silently when the process is not authorised — but identifier discipline can:
//  an alert re-issued under the same identifier replaces its pending copy instead of stacking a
//  second one, and retracting one alert cannot cancel another.
//

import Foundation
import LoopKit
import UserNotifications

enum WatchAlertPresenter {
    /// Namespaced so a retraction cannot reach the dead-man ladder's identifiers, which are
    /// owned by `LoopStallWatchdog` and live in a different family.
    static func requestIdentifier(for identifier: LoopKit.Alert.Identifier) -> String {
        return "sportmode.alert.\(identifier.value)"
    }

    /// Present an alert on the wrist now, or at its scheduled moment.
    ///
    /// `backgroundContent` is the text used: the wrist has no foreground alert presentation of
    /// its own, so what the user sees is always the notification. A `.repeating` trigger is
    /// honoured as a repeating notification — the pod alerts that use it are the ones the user
    /// must not be able to sleep through.
    static func present(_ alert: LoopKit.Alert) {
        let content = UNMutableNotificationContent()
        content.title = alert.backgroundContent.title
        content.body = alert.backgroundContent.body
        content.threadIdentifier = alert.identifier.managerIdentifier

        // Without the Critical Alerts entitlement watchOS delivers a .critical request as
        // time-sensitive instead, which is the acceptable floor rather than a failure.
        switch alert.interruptionLevel {
        case .critical:
            content.interruptionLevel = .critical
            content.sound = .defaultCritical
        case .timeSensitive:
            content.interruptionLevel = .timeSensitive
            content.sound = .default
        case .active:
            content.interruptionLevel = .active
            content.sound = .default
        }

        let trigger: UNNotificationTrigger?
        switch alert.trigger {
        case .immediate:
            trigger = nil
        case .delayed(let interval):
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        case .repeating(let repeatInterval):
            // The notification centre refuses a repeating trigger under 60 s and drops the
            // request silently, so a shorter interval is raised to the floor rather than lost.
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, repeatInterval), repeats: true)
        }

        WristAlerts.scheduler.add(UNNotificationRequest(identifier: requestIdentifier(for: alert.identifier),
                                                        content: content,
                                                        trigger: trigger))
    }

    /// Withdraw an alert, pending or already delivered. A driver retracts when the condition
    /// clears — an occlusion alarm left standing on the wrist after the pod recovered is worse
    /// than one that never fired, because the next one carries no weight.
    static func retract(_ identifier: LoopKit.Alert.Identifier) {
        let request = requestIdentifier(for: identifier)
        WristAlerts.scheduler.removePendingRequests(withIdentifiers: [request])
        WristAlerts.scheduler.removeDeliveredRequests(withIdentifiers: [request])
    }
}
