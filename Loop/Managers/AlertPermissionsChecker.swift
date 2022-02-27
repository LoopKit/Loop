//
//  AlertPermissionsChecker.swift
//  Loop
//
//  Created by Rick Pasetto on 6/25/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine
import LoopKit
import SwiftUI

public class AlertPermissionsChecker: ObservableObject {

    private weak var alertManager: AlertManager?
    
    private var isAppInBackground: Bool {
        return UIApplication.shared.applicationState == UIApplication.State.background
    }
    
    private lazy var cancellables = Set<AnyCancellable>()
    private var listeningToNotificationCenter = false

    @Published var notificationCenterSettings: NotificationCenterSettingsFlags = .none
    
    var showWarning: Bool {
        notificationCenterSettings.requiresRiskMitigation
    }
    
    init(alertManager: AlertManager? = nil) {
        self.alertManager = alertManager
        
        // Check on loop complete, but only while in the background.
        NotificationCenter.default.publisher(for: .LoopCompleted)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.isAppInBackground {
                    self.check()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.check()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.check()
            }
            .store(in: &cancellables)
    }
 
    func checkNow() {
        check {
            // Note: we do this, instead of calling notificationCenterSettingsChanged directly, so that we only
            // get called when it _changes_.
            self.listenToNotificationCenter()
        }
    }
    
    private func check(then completion: (() -> Void)? = nil) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                var newSettings = self.notificationCenterSettings
                newSettings.notificationsDisabled = settings.alertSetting == .disabled
                if FeatureFlags.criticalAlertsEnabled {
                    newSettings.criticalAlertsDisabled = settings.criticalAlertSetting == .disabled
                }
                if #available(iOS 15.0, *) {
                    newSettings.scheduledDeliveryEnabled = settings.scheduledDeliverySetting == .enabled
                    newSettings.timeSensitiveNotificationsDisabled = settings.alertSetting != .disabled && settings.timeSensitiveSetting == .disabled
                }
                self.notificationCenterSettings = newSettings
                completion?()
            }
        }
    }

    func gotoSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }
}

fileprivate extension AlertPermissionsChecker {

    private func listenToNotificationCenter() {
        if !listeningToNotificationCenter {
            $notificationCenterSettings
                .receive(on: RunLoop.main)
                .removeDuplicates()
                .sink(receiveValue: notificationCenterSettingsChanged)
                .store(in: &cancellables)
            listeningToNotificationCenter = true
        }
    }
    
    private func notificationCenterSettingsChanged(_ newValue: NotificationCenterSettingsFlags) {
        if !issueOrRetract(alert: Self.riskMitigatingAlert,
                           condition: newValue.requiresRiskMitigation,
                           alreadyIssued: UserDefaults.standard.hasIssuedRiskMitigatingAlert,
                           setAlreadyIssued: {UserDefaults.standard.hasIssuedRiskMitigatingAlert = $0}) {
            _ = issueOrRetract(alert: Self.scheduledDeliveryEnabledAlert,
                               condition: newValue.scheduledDeliveryEnabled,
                               alreadyIssued: UserDefaults.standard.hasIssuedScheduledDeliveryEnabledAlert,
                               setAlreadyIssued: {UserDefaults.standard.hasIssuedScheduledDeliveryEnabledAlert = $0})
        }
    }
    
    private func issueOrRetract(alert: LoopKit.Alert, condition: Bool, alreadyIssued: Bool, setAlreadyIssued: (Bool) -> Void) -> Bool {
        if condition {
            if !alreadyIssued {
                alertManager?.issueAlert(alert)
                setAlreadyIssued(true)
            }
            return true
        } else {
            if alreadyIssued {
                setAlreadyIssued(false)
                alertManager?.retractAlert(identifier: alert.identifier)
            }
            return false
        }
    }
}

fileprivate extension AlertPermissionsChecker {
    
    // MARK: Risk Mitigating Alert
    private static let riskMitigatingAlertIdentifier = Alert.Identifier(managerIdentifier: "LoopAppManager", alertIdentifier: "riskMitigatingAlert")
    private static let riskMitigatingAlertContent = Alert.Content(
        title: NSLocalizedString("Alert Permissions Need Attention",
                                 comment: "Alert Permissions Need Attention alert title"),
        body: String(format: NSLocalizedString("It is important that you always keep %1$@ Notifications, Critical Alerts, and Time Sensitive Notifications turned ON in your phone’s settings to ensure that you get notified by the app.",
                                               comment: "Format for Notifications permissions disabled alert body. (1: app name)"),
                     Bundle.main.bundleDisplayName),
        acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Notifications permissions disabled alert button")
    )
    private static let riskMitigatingAlert = Alert(identifier: riskMitigatingAlertIdentifier,
                                                   foregroundContent: riskMitigatingAlertContent,
                                                   backgroundContent: riskMitigatingAlertContent,
                                                   trigger: .immediate)
    
    // MARK: Scheduled Delivery Enabled Alert
    private static let scheduledDeliveryEnabledAlertIdentifier = Alert.Identifier(managerIdentifier: "LoopAppManager",
                                                                                  alertIdentifier: "scheduledDeliveryEnabledAlert")
    private static let scheduledDeliveryEnabledAlertContent = Alert.Content(
        title: NSLocalizedString("Notifications Delayed",
                                 comment: "Scheduled Delivery Enabled alert title"),
        body: String(format: NSLocalizedString("""
            Notification delivery is set to Scheduled Summary in your phone’s settings.
            
            To avoid delay in receiving notifications from %1$@, we recommend notification delivery be set to Immediate Delivery.
            """,
                                               comment: "Format for Critical Alerts permissions disabled alert body. (1: app name)"),
                     Bundle.main.bundleDisplayName),
        acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Critical Alert permissions disabled alert button")
    )
    private static let scheduledDeliveryEnabledAlert = Alert(identifier: scheduledDeliveryEnabledAlertIdentifier,
                                                             foregroundContent: scheduledDeliveryEnabledAlertContent,
                                                             backgroundContent: scheduledDeliveryEnabledAlertContent,
                                                             trigger: .immediate)
}

fileprivate extension UserDefaults {
    
    private enum Key: String {
        case hasIssuedRiskMitigatingAlert = "com.loopkit.Loop.HasIssuedRiskMitigatingAlert"
        case hasIssuedScheduledDeliveryEnabledAlert = "com.loopkit.Loop.HasIssuedScheduledDeliveryEnabledAlert"
    }
    
    var hasIssuedRiskMitigatingAlert: Bool {
        get {
            return object(forKey: Key.hasIssuedRiskMitigatingAlert.rawValue) as? Bool ?? false
        }
        set {
            set(newValue, forKey: Key.hasIssuedRiskMitigatingAlert.rawValue)
        }
    }

    var hasIssuedScheduledDeliveryEnabledAlert: Bool {
        get {
            return object(forKey: Key.hasIssuedScheduledDeliveryEnabledAlert.rawValue) as? Bool ?? false
        }
        set {
            set(newValue, forKey: Key.hasIssuedScheduledDeliveryEnabledAlert.rawValue)
        }
    }
}

struct NotificationCenterSettingsFlags: OptionSet {
    let rawValue: Int

    static let none = NotificationCenterSettingsFlags([])
    static let notificationsDisabled = NotificationCenterSettingsFlags(rawValue: 1 << 0)
    static let criticalAlertsDisabled = NotificationCenterSettingsFlags(rawValue: 1 << 1)
    static let timeSensitiveNotificationsDisabled = NotificationCenterSettingsFlags(rawValue: 1 << 2)
    static let scheduledDeliveryEnabled = NotificationCenterSettingsFlags(rawValue: 1 << 3)

    static let requiresRiskMitigation: NotificationCenterSettingsFlags = [ .notificationsDisabled, .criticalAlertsDisabled, .timeSensitiveNotificationsDisabled ]
}

extension NotificationCenterSettingsFlags {
    var notificationsDisabled: Bool {
        get {
            contains(.notificationsDisabled)
        }
        set {
            update(.notificationsDisabled, newValue)
        }
    }
    var criticalAlertsDisabled: Bool {
        get {
            contains(.criticalAlertsDisabled)
        }
        set {
            update(.criticalAlertsDisabled, newValue)
        }
    }
    var timeSensitiveNotificationsDisabled: Bool {
        get {
            contains(.timeSensitiveNotificationsDisabled)
        }
        set {
            update(.timeSensitiveNotificationsDisabled, newValue)
        }
    }
    var scheduledDeliveryEnabled: Bool {
        get {
            contains(.scheduledDeliveryEnabled)
        }
        set {
            update(.scheduledDeliveryEnabled, newValue)
        }
    }
    var requiresRiskMitigation: Bool {
        !self.intersection(.requiresRiskMitigation).isEmpty
    }
}

fileprivate extension OptionSet {
    mutating func update(_ element: Self.Element, _ value: Bool) {
        if value {
            insert(element)
        } else {
            remove(element)
        }
    }
}

