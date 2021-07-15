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

class AlertPermissionsChecker {
    private static let notificationsPermissionsAlertIdentifier = Alert.Identifier(managerIdentifier: "LoopAppManager",
                                                                                  alertIdentifier: "notificationsPermissionsAlert")
    private static let notificationsPermissionsAlertContent = Alert.Content(
        title: NSLocalizedString("Notifications Disabled",
                                 comment: "Notifications permissions disabled alert title"),
        body: String(format: NSLocalizedString("Keep Notifications turned ON in your phone’s settings to ensure that you can receive %1$@ notifications.",
                                               comment: "Format for Notifications permissions disabled alert body. (1: app name)"),
                     Bundle.main.bundleDisplayName),
        acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Notifications permissions disabled alert button")
    )
    private static let notificationsPermissionsAlert = Alert(identifier: notificationsPermissionsAlertIdentifier,
                                                             foregroundContent: notificationsPermissionsAlertContent,
                                                             backgroundContent: notificationsPermissionsAlertContent,
                                                             trigger: .immediate)
    
    private static let criticalAlertPermissionsAlertIdentifier = Alert.Identifier(managerIdentifier: "LoopAppManager",
                                                                                  alertIdentifier: "criticalAlertPermissionsAlert")
    private static let criticalAlertPermissionsAlertContent = Alert.Content(
        title: NSLocalizedString("Critical Alerts Disabled",
                                 comment: "Critical Alert permissions disabled alert title"),
        body: String(format: NSLocalizedString("Keep Critical Alerts turned ON in your phone’s settings to ensure that you can receive %1$@ critical alerts.",
                                               comment: "Format for Critical Alerts permissions disabled alert body. (1: app name)"),
                     Bundle.main.bundleDisplayName),
        acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Critical Alert permissions disabled alert button")
    )
    private static let criticalAlertPermissionsAlert = Alert(identifier: criticalAlertPermissionsAlertIdentifier,
                                                             foregroundContent: criticalAlertPermissionsAlertContent,
                                                             backgroundContent: criticalAlertPermissionsAlertContent,
                                                             trigger: .immediate)

    private weak var alertManager: AlertManager?
    
    private var isAppInBackground: Bool {
        return UIApplication.shared.applicationState == UIApplication.State.background
    }
    
    private lazy var cancellables = Set<AnyCancellable>()

    init(alertManager: AlertManager) {
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
        
        // Check on app resume
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.check()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.check()
            }
            .store(in: &cancellables)
    }

    func check() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let notificationsPermissions = settings.alertSetting
                let criticalAlertsPermissions = settings.criticalAlertSetting
                
                if notificationsPermissions == .disabled {
                    self.maybeNotifyNotificationPermissionsDisabled()
                } else {
                    self.notificationsPermissionsEnabled()
                }
                if FeatureFlags.criticalAlertsEnabled {
                    if criticalAlertsPermissions == .disabled {
                        self.maybeNotifyCriticalAlertPermissionsDisabled()
                    } else {
                        self.criticalAlertPermissionsEnabled()
                    }
                }
            }
        }
    }
    
    private func maybeNotifyNotificationPermissionsDisabled() {
        if !UserDefaults.standard.hasIssuedNotificationsPermissionsAlert {
            alertManager?.issueAlert(AlertPermissionsChecker.notificationsPermissionsAlert)
            UserDefaults.standard.hasIssuedNotificationsPermissionsAlert = true
        }
    }
    
    private func notificationsPermissionsEnabled() {
        alertManager?.retractAlert(identifier: AlertPermissionsChecker.notificationsPermissionsAlertIdentifier)
        UserDefaults.standard.hasIssuedNotificationsPermissionsAlert = false
    }
    
    private func maybeNotifyCriticalAlertPermissionsDisabled() {
        if !UserDefaults.standard.hasIssuedCriticalAlertPermissionsAlert {
            alertManager?.issueAlert(AlertPermissionsChecker.criticalAlertPermissionsAlert)
            UserDefaults.standard.hasIssuedCriticalAlertPermissionsAlert = true
        }
    }
    
    private func criticalAlertPermissionsEnabled() {
        alertManager?.retractAlert(identifier: AlertPermissionsChecker.criticalAlertPermissionsAlertIdentifier)
        UserDefaults.standard.hasIssuedCriticalAlertPermissionsAlert = false
    }
    
}

extension UserDefaults {
    
    private enum Key: String {
        case hasIssuedNotificationsPermissionsAlert = "com.loopkit.Loop.HasIssuedNotificationsPermissionsAlert"
        case hasIssuedCriticalAlertPermissionsAlert = "com.loopkit.Loop.HasIssuedCriticalAlertPermissionsAlert"
    }
    
    var hasIssuedNotificationsPermissionsAlert: Bool {
        get {
            return object(forKey: Key.hasIssuedNotificationsPermissionsAlert.rawValue) as? Bool ?? false
        }
        set {
            set(newValue, forKey: Key.hasIssuedNotificationsPermissionsAlert.rawValue)
        }
    }
    
    var hasIssuedCriticalAlertPermissionsAlert: Bool {
        get {
            return object(forKey: Key.hasIssuedCriticalAlertPermissionsAlert.rawValue) as? Bool ?? false
        }
        set {
            set(newValue, forKey: Key.hasIssuedCriticalAlertPermissionsAlert.rawValue)
        }
    }
}
