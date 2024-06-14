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

protocol AlertPermissionsCheckerDelegate: AnyObject {
    func notificationsPermissions(requiresRiskMitigation: Bool, scheduledDeliveryEnabled: Bool, permissions: NotificationCenterSettingsFlags)
}

public class AlertPermissionsChecker: ObservableObject {

    private var isAppInBackground: Bool {
        return UIApplication.shared.applicationState == UIApplication.State.background
    }

    private lazy var cancellables = Set<AnyCancellable>()
    private var listeningToNotificationCenter = false

    @Published var notificationCenterSettings: NotificationCenterSettingsFlags = .none

    var showWarning: Bool {
        notificationCenterSettings.requiresRiskMitigation
    }

    weak var delegate: AlertPermissionsCheckerDelegate?

    init() {
        // Check on loop complete, but only while in the background.
        NotificationCenter.default.publisher(for: .LoopCycleCompleted)
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
                    newSettings.timeSensitiveDisabled = settings.alertSetting != .disabled && settings.timeSensitiveSetting == .disabled
                }
                self.notificationCenterSettings = newSettings
                completion?()
            }
        }
    }

    static func gotoSettings() {
        // TODO with iOS 16 this API changes to UIApplication.openNotificationSettingsURLString
        if #available(iOS 15.4, *) {
            UIApplication.shared.open(URL(string: UIApplicationOpenNotificationSettingsURLString)!)
        } else {
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        }
    }
}

extension AlertPermissionsChecker {
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

    // MARK: Unsafe Notification Permissions Alert
    
    enum UnsafeNotificationPermissionAlert: Hashable, CaseIterable {
        case notificationsDisabled
        case criticalAlertsDisabled
        case timeSensitiveDisabled
        case criticalAlertsAndNotificationDisabled
        case criticalAlertsAndTimeSensitiveDisabled
        
        var alertTitle: String {
            switch self {
            case .criticalAlertsAndNotificationDisabled, .criticalAlertsAndTimeSensitiveDisabled:
                NSLocalizedString("Turn On Critical Alerts and Time Sensitive Notifications", comment: "Both Critical Alerts and Time Sensitive Notifications disabled alert title")
            case .criticalAlertsDisabled:
                NSLocalizedString("Turn On Critical Alerts", comment: "Critical alerts disabled alert title")
            case .timeSensitiveDisabled, .notificationsDisabled:
                NSLocalizedString("Turn On Time Sensitive Notifications ", comment: "Time sensitive notifications disabled alert title")
            }
        }
        
        var notificationTitle: String {
            switch self {
            case .criticalAlertsAndNotificationDisabled, .criticalAlertsAndTimeSensitiveDisabled:
                NSLocalizedString("Turn On Critical Alerts and Time Sensitive Notifications", comment: "Both Critical Alerts and Time Sensitive Notifications disabled notification title")
            case .criticalAlertsDisabled:
                NSLocalizedString("Turn On Critical Alerts", comment: "Critical alerts disabled notification title")
            case .timeSensitiveDisabled, .notificationsDisabled:
                NSLocalizedString("Turn On Time Sensitive Notifications", comment: "Time sensitive notifications disabled alert title")
            }
        }
        
        var bannerTitle: String {
            switch self {
            case .criticalAlertsAndNotificationDisabled, .criticalAlertsAndTimeSensitiveDisabled:
                NSLocalizedString("Critical Alerts and Time Sensitive Notifications are turned OFF", comment: "Both Critical Alerts and Time Sensitive Notifications disabled banner title")
            case .criticalAlertsDisabled:
                NSLocalizedString("Critical Alerts are turned OFF", comment: "Critical alerts disabled banner title")
            case .timeSensitiveDisabled, .notificationsDisabled:
                NSLocalizedString("Time Sensitive Alerts are turned OFF", comment: "Time sensitive notifications disabled banner title")
            }
        }
        
        var alertBody: String {
            switch self {
            case .notificationsDisabled:
                NSLocalizedString("Time Sensitive Alerts are turned OFF. You may not get sound, visual or vibration alerts regarding critical safety information.\n\nTo fix the issue, tap ‘Settings’ and make sure Notifications are turned ON.", comment: "Notifications disabled alert body")
            case .criticalAlertsAndNotificationDisabled:
                NSLocalizedString("Critical Alerts and Time Sensitive Notifications are turned off. You may not get sound, visual or vibration alerts regarding critical safety information.\n\nTo fix the issue, tap ‘Settings’ and make sure Notifications and Critical Alerts are turned ON.", comment: "Both Notifications and Critical Alerts disabled alert body")
            case .criticalAlertsAndTimeSensitiveDisabled:
                NSLocalizedString("Critical Alerts and Time Sensitive Notifications are turned off. You may not get sound, visual or vibration alerts regarding critical safety information.\n\nTo fix the issue, tap ‘Settings’ and make sure Critical Alerts and Time Sensitive Notifications are turned ON.", comment: "Both Critical Alerts and Time Sensitive Notifications disabled alert body")
            case .criticalAlertsDisabled:
                NSLocalizedString("Critical Alerts are turned off. You may not get sound, visual or vibration alerts regarding critical safety information.\n\nTo fix the issue, tap ‘Settings’ and make sure Critical Alerts are turned ON.", comment: "Critical alerts disabled alert body")
            case .timeSensitiveDisabled:
                NSLocalizedString("Time Sensitive Alerts are turned OFF. You may not get sound, visual or vibration alerts regarding critical safety information.\n\nTo fix the issue, tap ‘Settings’ and make sure Time Sensitive Notifications are turned ON.", comment: "Time sensitive notifications disabled alert body")
            }
        }
        
        var notificationBody: String {
            switch self {
            case .criticalAlertsAndNotificationDisabled, .criticalAlertsAndTimeSensitiveDisabled:
                NSLocalizedString("Critical Alerts and Time Sensitive Notifications are turned OFF. Go to the App to fix the issue now.", comment: "Both Critical Alerts and Time Sensitive Notifications disabled notification body")
            case .criticalAlertsDisabled:
                NSLocalizedString("Critical Alerts are turned OFF. Go to the App to fix the issue now.", comment: "Critical alerts disabled notification body")
            case .timeSensitiveDisabled, .notificationsDisabled:
                NSLocalizedString("Time Sensitive notifications are turned OFF. Go to the App to fix the issue now.", comment: "Time sensitive notifications disabled notification body")
            }
        }
        
        var bannerBody: String {
            switch self {
            case .notificationsDisabled:
                NSLocalizedString("Fix now by turning Notifications ON.", comment: "Notifications disabled banner body")
            case .criticalAlertsAndNotificationDisabled:
                NSLocalizedString("Fix now by turning Notifications and Critical Alerts ON.", comment: "Both Critical Alerts and Notifications disabled banner body")
            case .criticalAlertsAndTimeSensitiveDisabled:
                NSLocalizedString("Fix now by turning Critical Alerts and Time Sensitive Notifications ON.", comment: "Both Critical Alerts and Time Sensitive Notifications disabled banner body")
            case .criticalAlertsDisabled:
                NSLocalizedString("Fix now by turning Critical Alerts ON.", comment: "Critical alerts disabled banner body")
            case .timeSensitiveDisabled:
                NSLocalizedString("Fix now by turning Time Sensitive Notifications ON.", comment: "Time sensitive notifications disabled banner body")
            }
        }
        
        var alertIdentifier: LoopKit.Alert.Identifier {
            switch self {
            case .notificationsDisabled:
                Alert.Identifier(managerIdentifier: "LoopAppManager", alertIdentifier: "unsafeNotificationPermissionsAlert")
            case .criticalAlertsAndNotificationDisabled:
                Alert.Identifier(managerIdentifier: "LoopAppManager", alertIdentifier: "unsafeCriticalAlertAndNotificationPermissionsAlert")
            case .criticalAlertsAndTimeSensitiveDisabled:
                Alert.Identifier(managerIdentifier: "LoopAppManager", alertIdentifier: "unsafeCriticalAlertAndTimeSensitivePermissionsAlert")
            case .criticalAlertsDisabled:
                Alert.Identifier(managerIdentifier: "LoopAppManager", alertIdentifier: "unsafeCrititalAlertPermissionsAlert")
            case .timeSensitiveDisabled:
                Alert.Identifier(managerIdentifier: "LoopAppManager", alertIdentifier: "unsafeTimeSensitiveNotificationPermissionsAlert")
            }
        }
        
        var alertContent: LoopKit.Alert.Content {
            Alert.Content(
                title: alertTitle,
                body: alertBody,
                acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Notifications permissions disabled alert button")
            )
        }
        
        var alert: LoopKit.Alert {
            Alert(
                identifier: alertIdentifier,
                foregroundContent: nil,
                backgroundContent: alertContent,
                trigger: .immediate
            )
        }
        
        init?(permissions: NotificationCenterSettingsFlags) {
            switch permissions {
            case .notificationsDisabled:
                self = .notificationsDisabled
            case .timeSensitiveDisabled, NotificationCenterSettingsFlags(rawValue: 5):
                self = .timeSensitiveDisabled
            case .criticalAlertsDisabled:
                self = .criticalAlertsDisabled
            case NotificationCenterSettingsFlags(rawValue: 3):
                self = .criticalAlertsAndNotificationDisabled
            case NotificationCenterSettingsFlags(rawValue: 6):
                self = .criticalAlertsAndTimeSensitiveDisabled
            default:
                return nil
            }
        }
    }

    static func constructUnsafeNotificationPermissionsInAppAlert(alert: UnsafeNotificationPermissionAlert, acknowledgementCompletion: @escaping () -> Void ) -> UIAlertController {
        dispatchPrecondition(condition: .onQueue(.main))
        let alertController = UIAlertController(title: alert.alertTitle,
                                                message: alert.alertBody,
                                                preferredStyle: .alert)
        let titleImageAttachment = NSTextAttachment()
        titleImageAttachment.image = UIImage(systemName: "exclamationmark.triangle.fill")?.withTintColor(.critical)
        titleImageAttachment.bounds = CGRect(x: titleImageAttachment.bounds.origin.x, y: -10, width: 40, height: 35)
        let titleWithImage = NSMutableAttributedString(attachment: titleImageAttachment)
        titleWithImage.append(NSMutableAttributedString(string: "\n\n", attributes: [.font: UIFont.systemFont(ofSize: 8)]))
        titleWithImage.append(NSMutableAttributedString(string: alert.alertTitle, attributes: [.font: UIFont.preferredFont(forTextStyle: .headline)]))
        alertController.setValue(titleWithImage, forKey: "attributedTitle")
        
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Label of button that navigation user to iOS Settings"),
                                                style: .default,
                                                handler: { _ in
            AlertPermissionsChecker.gotoSettings()
            acknowledgementCompletion()
        }))
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Close", comment: "The button label of the action used to dismiss the unsafe notification permission alert"),
                                                style: .cancel,
                                                handler: { _ in acknowledgementCompletion()
        }))
        return alertController
    }

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
    static let scheduledDeliveryEnabledAlert = Alert(identifier: scheduledDeliveryEnabledAlertIdentifier,
                                                     foregroundContent: scheduledDeliveryEnabledAlertContent,
                                                     backgroundContent: scheduledDeliveryEnabledAlertContent,
                                                     trigger: .immediate)

    private func notificationCenterSettingsChanged(_ newValue: NotificationCenterSettingsFlags) {
        delegate?.notificationsPermissions(requiresRiskMitigation: newValue.requiresRiskMitigation, scheduledDeliveryEnabled: newValue.scheduledDeliveryEnabled, permissions: newValue)
    }
}

struct NotificationCenterSettingsFlags: OptionSet {
    let rawValue: Int

    static let none = NotificationCenterSettingsFlags([])
    static let notificationsDisabled = NotificationCenterSettingsFlags(rawValue: 1 << 0)
    static let criticalAlertsDisabled = NotificationCenterSettingsFlags(rawValue: 1 << 1)
    static let timeSensitiveDisabled = NotificationCenterSettingsFlags(rawValue: 1 << 2)
    static let scheduledDeliveryEnabled = NotificationCenterSettingsFlags(rawValue: 1 << 3)

    static let requiresRiskMitigation: NotificationCenterSettingsFlags = [ .notificationsDisabled, .criticalAlertsDisabled, .timeSensitiveDisabled ]
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
    var timeSensitiveDisabled: Bool {
        get {
            contains(.timeSensitiveDisabled)
        }
        set {
            update(.timeSensitiveDisabled, newValue)
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
