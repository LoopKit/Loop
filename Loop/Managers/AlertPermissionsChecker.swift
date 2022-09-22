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
    func notificationsPermissions(requiresRiskMitigation: Bool, scheduledDeliveryEnabled: Bool)
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
    static let unsafeNotificationPermissionsAlertIdentifier = Alert.Identifier(managerIdentifier: "LoopAppManager", alertIdentifier: "unsafeNotificationPermissionsAlert")

    private static let unsafeNotificationPermissionsAlertContent = Alert.Content(
        title: NSLocalizedString("Warning! Safety notifications are turned OFF",
                                 comment: "Alert Permissions Need Attention alert title"),
        body: String(format: NSLocalizedString("You may not get sound, visual or vibration alerts regarding critical safety information.\n\nTo fix the issue, tap ‘Settings’ and make sure Notifications, Critical Alerts and Time Sensitive Notifications are turned ON.",
                                               comment: "Format for Notifications permissions disabled alert body. (1: app name)"),
                     Bundle.main.bundleDisplayName),
        acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Notifications permissions disabled alert button")
    )

    static let unsafeNotificationPermissionsAlert = Alert(identifier: unsafeNotificationPermissionsAlertIdentifier,
                                                          foregroundContent: nil,
                                                          backgroundContent: unsafeNotificationPermissionsAlertContent,
                                                          trigger: .immediate)

    static func constructUnsafeNotificationPermissionsInAppAlert(acknowledgementCompletion: @escaping () -> Void ) -> UIAlertController {
        dispatchPrecondition(condition: .onQueue(.main))
        let alertController = UIAlertController(title: Self.unsafeNotificationPermissionsAlertContent.title,
                                                message: Self.unsafeNotificationPermissionsAlertContent.body,
                                                preferredStyle: .alert)
        let titleImageAttachment = NSTextAttachment()
        titleImageAttachment.image = UIImage(systemName: "exclamationmark.triangle.fill")?.withTintColor(.critical)
        titleImageAttachment.bounds = CGRect(x: titleImageAttachment.bounds.origin.x, y: -10, width: 40, height: 35)
        let titleWithImage = NSMutableAttributedString(attachment: titleImageAttachment)
        titleWithImage.append(NSMutableAttributedString(string: "\n\n", attributes: [.font: UIFont.systemFont(ofSize: 8)]))
        titleWithImage.append(NSMutableAttributedString(string: Self.unsafeNotificationPermissionsAlertContent.title, attributes: [.font: UIFont.preferredFont(forTextStyle: .headline)]))
        alertController.setValue(titleWithImage, forKey: "attributedTitle")

        let messageImageAttachment = NSTextAttachment()
        messageImageAttachment.image = UIImage(named: "notification-permissions-on")
        messageImageAttachment.bounds = CGRect(x: 0, y: -12, width: 228, height: 126)
        let messageWithImageAttributed = NSMutableAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: 8)])
        messageWithImageAttributed.append(NSMutableAttributedString(string: Self.unsafeNotificationPermissionsAlertContent.body, attributes: [.font: UIFont.preferredFont(forTextStyle: .footnote)]))
        messageWithImageAttributed.append(NSMutableAttributedString(string: "\n\n", attributes: [.font: UIFont.systemFont(ofSize: 12)]))
        messageWithImageAttributed.append(NSMutableAttributedString(attachment: messageImageAttachment))
        alertController.setValue(messageWithImageAttributed, forKey: "attributedMessage")

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
        delegate?.notificationsPermissions(requiresRiskMitigation: newValue.requiresRiskMitigation, scheduledDeliveryEnabled: newValue.scheduledDeliveryEnabled)
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
