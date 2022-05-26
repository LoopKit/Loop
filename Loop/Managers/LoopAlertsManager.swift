//
//  LoopAlertsManager.swift
//  Loop
//
//  Created by Rick Pasetto on 6/8/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import Combine
import UserNotifications

/// Class responsible for monitoring "system level" operations and alerting the user to any anomalous situations (e.g. bluetooth off)
public class LoopAlertsManager {
    
    static let managerIdentifier = "Loop"
    
    private lazy var log = DiagnosticLog(category: String(describing: LoopAlertsManager.self))
    
    private var alertManager: AlertManager
    
    private let bluetoothPoweredOffIdentifier = Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: "bluetoothPoweredOff")

    lazy private var cancellables = Set<AnyCancellable>()

    // For testing
    var getCurrentDate = { return Date() }
    
    init(alertManager: AlertManager, bluetoothProvider: BluetoothProvider) {
        self.alertManager = alertManager
        bluetoothProvider.addBluetoothObserver(self, queue: .main)

        NotificationCenter.default.publisher(for: .LoopCompleted)
            .sink { [weak self] _ in
                self?.loopDidComplete()
            }
            .store(in: &cancellables)
    }
        
    private func onBluetoothPermissionDenied() {
        log.default("Bluetooth permission denied")
        let title = NSLocalizedString("Bluetooth Unavailable Alert", comment: "Bluetooth unavailable alert title")
        let body = NSLocalizedString("Loop has detected an issue with your Bluetooth settings, and will not work successfully until Bluetooth is enabled. You will not receive glucose readings, or be able to bolus.", comment: "Bluetooth unavailable alert body.")
        let content = Alert.Content(title: title,
                                      body: body,
                                      acknowledgeActionButtonLabel: NSLocalizedString("Dismiss", comment: "Default alert dismissal"))
        alertManager.issueAlert(Alert(identifier: bluetoothPoweredOffIdentifier, foregroundContent: content, backgroundContent: content, trigger: .immediate))
    }

    private func onBluetoothPoweredOn() {
        log.default("Bluetooth powered on")
        alertManager.retractAlert(identifier: bluetoothPoweredOffIdentifier)
    }

    private func onBluetoothPoweredOff() {
        log.default("Bluetooth powered off")
        let title = NSLocalizedString("Bluetooth Off Alert", comment: "Bluetooth off alert title")
        let bgBody = NSLocalizedString("Loop will not work successfully until Bluetooth is enabled. You will not receive glucose readings, or be able to bolus.", comment: "Bluetooth off background alert body.")
        let bgcontent = Alert.Content(title: title,
                                      body: bgBody,
                                      acknowledgeActionButtonLabel: NSLocalizedString("Dismiss", comment: "Default alert dismissal"))
        let fgBody = NSLocalizedString("Turn on Bluetooth to receive alerts, alarms or sensor glucose readings.", comment: "Bluetooth off foreground alert body")
        let fgcontent = Alert.Content(title: title,
                                      body: fgBody,
                                      acknowledgeActionButtonLabel: NSLocalizedString("Dismiss", comment: "Default alert dismissal"))
        alertManager.issueAlert(Alert(identifier: bluetoothPoweredOffIdentifier,
                                       foregroundContent: fgcontent,
                                       backgroundContent: bgcontent,
                                       trigger: .immediate,
                                       interruptionLevel: .critical))
    }

    func loopDidComplete() {
        clearLoopNotRunningNotifications()
        scheduleLoopNotRunningNotifications()
    }

    func scheduleLoopNotRunningNotifications() {
        // Give a little extra time for a loop-in-progress to complete
        let gracePeriod = TimeInterval(minutes: 0.5)

        var scheduledNotifications: [StoredLoopNotRunningNotification] = []

        for (minutes, isCritical) in [(20.0, false), (40.0, false), (60.0, true), (120.0, true)] {
            let notification = UNMutableNotificationContent()
            let failureInterval = TimeInterval(minutes: minutes)

            let formatter = DateComponentsFormatter()
            formatter.maximumUnitCount = 1
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .full

            if let failureIntervalString = formatter.string(from: failureInterval)?.localizedLowercase {
                notification.body = String(format: NSLocalizedString("Loop has not completed successfully in %@", comment: "The notification alert describing a long-lasting loop failure. The substitution parameter is the time interval since the last loop"), failureIntervalString)
            }

            notification.title = NSLocalizedString("Loop Failure", comment: "The notification title for a loop failure")
            if isCritical, FeatureFlags.criticalAlertsEnabled {
                if #available(iOS 15.0, *) {
                    notification.interruptionLevel = .critical
                }
                notification.sound = .defaultCritical
            } else {
                if #available(iOS 15.0, *) {
                    notification.interruptionLevel = .timeSensitive
                }
                notification.sound = .default
            }
            notification.categoryIdentifier = LoopNotificationCategory.loopNotRunning.rawValue
            notification.threadIdentifier = LoopNotificationCategory.loopNotRunning.rawValue

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: failureInterval + gracePeriod,
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: "\(LoopNotificationCategory.loopNotRunning.rawValue)\(failureInterval)",
                content: notification,
                trigger: trigger
            )

            if let nextTriggerDate = trigger.nextTriggerDate() {
                let scheduledNotification = StoredLoopNotRunningNotification(
                    alertAt: nextTriggerDate,
                    title: notification.title,
                    body: notification.body,
                    timeInterval: failureInterval,
                    isCritical: isCritical)
                scheduledNotifications.append(scheduledNotification)
            }
            UNUserNotificationCenter.current().add(request)
        }
        UserDefaults.appGroup?.loopNotRunningNotifications = scheduledNotifications
    }

    func inferDeliveredLoopNotRunningNotifications() {
        // Infer that any past alerts have been delivered at this point
        let now = getCurrentDate()
        var stillPendingNotifications = [StoredLoopNotRunningNotification]()
        for notification in UserDefaults.appGroup?.loopNotRunningNotifications ?? [] {
            print("Comparing alert \(notification.alertAt) to \(now) (real date = \(Date())")
            if notification.alertAt < now {
                let alertIdentifier = Alert.Identifier(managerIdentifier: "Loop", alertIdentifier: "loopNotLooping")
                let content = Alert.Content(title: notification.title, body: notification.body, acknowledgeActionButtonLabel: "ios-notification-default")
                let interruptionLevel: Alert.InterruptionLevel = notification.isCritical ? .critical : .timeSensitive
                let alert = Alert(identifier: alertIdentifier, foregroundContent: nil, backgroundContent: content, trigger: .immediate, interruptionLevel: interruptionLevel)
                alertManager.recordIssued(alert: alert, at: notification.alertAt)
            } else {
                stillPendingNotifications.append(notification)
            }
        }
        UserDefaults.appGroup?.loopNotRunningNotifications = stillPendingNotifications
    }

    func clearLoopNotRunningNotifications() {
        inferDeliveredLoopNotRunningNotifications()

        // Clear out any existing not-running notifications
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            let loopNotRunningIdentifiers = notifications.filter({
                $0.request.content.categoryIdentifier == LoopNotificationCategory.loopNotRunning.rawValue
            }).map({
                $0.request.identifier
            })

            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: loopNotRunningIdentifiers)
        }
    }
}

// MARK: - BluetoothObserver

extension LoopAlertsManager: BluetoothObserver {
    public func bluetoothDidUpdateState(_ state: BluetoothState) {
        switch state {
        case .poweredOn:
            onBluetoothPoweredOn()
        case .poweredOff:
            onBluetoothPoweredOff()
        case .unauthorized:
            onBluetoothPermissionDenied()
        default:
            return
        }
    }
}
