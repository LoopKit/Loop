//
//  WatchAlertPresenter.swift
//  WatchApp Extension
//
//  LoopKit alerts on the wrist: while the watch holds the pod it is the only device that
//  hears the pump. Delivered through `WristAlerts.scheduler`, one identifier per alert.
//

import Foundation
import LoopKit
import LoopCore
import UserNotifications

enum WatchAlertPresenter {
    /// Namespaced apart from the dead-man ladder's identifiers.
    static func requestIdentifier(for identifier: LoopKit.Alert.Identifier) -> String {
        return "\(requestPrefix)\(identifier.value)"
    }

    private static let requestPrefix = "sportmode.alert."

    static func isWristAlert(_ requestIdentifier: String) -> Bool {
        requestIdentifier.hasPrefix(requestPrefix)
    }

    /// Uses `backgroundContent`; a `.repeating` trigger becomes a repeating notification.
    static func present(_ alert: LoopKit.Alert) {
        let content = UNMutableNotificationContent()
        content.title = alert.backgroundContent.title
        content.body = alert.backgroundContent.body
        content.threadIdentifier = alert.identifier.managerIdentifier
        // Stock's keys and acknowledge category, so an OK on the wrist reaches the alert's manager.
        content.categoryIdentifier = alert.categoryIdentifier ?? LoopNotificationCategory.alert.rawValue
        content.userInfo = [LoopNotificationUserInfoKey.managerIDForAlert.rawValue: alert.identifier.managerIdentifier,
                            LoopNotificationUserInfoKey.alertTypeID.rawValue: alert.identifier.alertIdentifier]

        // The watch has the time-sensitive entitlement, not Critical Alerts: that is its highest level.
        switch alert.interruptionLevel {
        case .critical, .timeSensitive:
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
            // Repeating triggers under 60 s are silently dropped.
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, repeatInterval), repeats: true)
        }

        WristAlerts.scheduler.add(UNNotificationRequest(identifier: requestIdentifier(for: alert.identifier),
                                                        content: content,
                                                        trigger: trigger))
    }

    /// Withdraws a pending or delivered alert when the condition clears.
    static func retract(_ identifier: LoopKit.Alert.Identifier) {
        let request = requestIdentifier(for: identifier)
        WristAlerts.scheduler.removePendingRequests(withIdentifiers: [request])
        WristAlerts.scheduler.removeDeliveredRequests(withIdentifiers: [request])
    }

    // MARK: - Acknowledgement

    /// Stock's device-alert category: OK, and a dismissal that also acknowledges.
    static func registerCategory() {
        let ok = UNNotificationAction(identifier: NotificationManager.Action.acknowledgeAlert.rawValue,
                                      title: NSLocalizedString("OK", comment: "The title of the notification action to acknowledge a device alert"),
                                      options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: LoopNotificationCategory.alert.rawValue, actions: [ok],
                                   intentIdentifiers: [], options: .customDismissAction)
        ])
    }

    /// OK and dismissal acknowledge, as on the phone; opening the alert does not.
    static func acknowledges(_ actionIdentifier: String) -> Bool {
        actionIdentifier == NotificationManager.Action.acknowledgeAlert.rawValue
            || actionIdentifier == UNNotificationDismissActionIdentifier
    }

    static func alertIdentifier(in userInfo: [AnyHashable: Any]) -> LoopKit.Alert.Identifier? {
        guard let manager = userInfo[LoopNotificationUserInfoKey.managerIDForAlert.rawValue] as? String,
              let alert = userInfo[LoopNotificationUserInfoKey.alertTypeID.rawValue] as? String else { return nil }
        return LoopKit.Alert.Identifier(managerIdentifier: manager, alertIdentifier: alert)
    }

    /// Through the alert's own manager, as stock's `AlertManager` does; a failure puts it back.
    static func acknowledge(_ identifier: LoopKit.Alert.Identifier, with responder: AlertResponder,
                            content: UNNotificationContent) async {
        do {
            try await responder.acknowledgeAlert(alertIdentifier: identifier.alertIdentifier)
            SportLog.event("alert", "ACKNOWLEDGED \(identifier.value) on the wrist — passed to its manager")
            retract(identifier)
        } catch {
            SportLog.event("alert", "acknowledge FAILED for \(identifier.value) — \(error) — alert put back")
            WristAlerts.scheduler.add(UNNotificationRequest(identifier: requestIdentifier(for: identifier),
                                                            content: content, trigger: nil))
        }
    }

    /// What the wrist may present with, logged at loan start: during a loan it is the only alarm.
    static func logAuthorization(_ context: String) {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            func name(_ setting: UNNotificationSetting) -> String {
                switch setting {
                case .enabled: return "on"
                case .disabled: return "OFF"
                case .notSupported: return "n/a"
                @unknown default: return "?"
                }
            }
            let status: String
            switch s.authorizationStatus {
            case .authorized: status = "authorized"
            case .denied: status = "DENIED"
            case .notDetermined: status = "NOT DETERMINED"
            case .provisional: status = "provisional"
            case .ephemeral: status = "ephemeral"
            @unknown default: status = "unknown"
            }
            SportLog.event("alert", "notification authorization (\(context)): \(status) · alerts \(name(s.alertSetting)) · sound \(name(s.soundSetting)) · time-sensitive \(name(s.timeSensitiveSetting)) · critical \(name(s.criticalAlertSetting))")
        }
    }
}
