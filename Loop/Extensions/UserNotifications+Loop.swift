//
//  UserNotifications+Loop.swift
//  Loop
//
//  Created by Darin Krauss on 5/27/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UserNotifications

extension UNUserNotificationCenter {
    func generateDiagnosticReport(_ completion: @escaping (_ report: String) -> Void) {
        getNotificationSettings() { notificationSettings in
            let report: [String] = [
                "## NotificationSettings",
                "",
                "* authorizationStatus: \(String(describing: notificationSettings.authorizationStatus))",
                "* soundSetting: \(String(describing: notificationSettings.soundSetting))",
                "* badgeSetting: \(String(describing: notificationSettings.badgeSetting))",
                "* alertSetting: \(String(describing: notificationSettings.alertSetting))",
                "* notificationCenterSetting: \(String(describing: notificationSettings.notificationCenterSetting))",
                "* lockScreenSetting: \(String(describing: notificationSettings.lockScreenSetting))",
                "* carPlaySetting: \(String(describing: notificationSettings.carPlaySetting))",
                "* alertStyle: \(String(describing: notificationSettings.alertStyle))",
                "* showPreviewsSetting: \(String(describing: notificationSettings.showPreviewsSetting))",
                "* criticalAlertSetting: \(String(describing: notificationSettings.criticalAlertSetting))",
                "* providesAppNotificationSettings: \(String(describing: notificationSettings.providesAppNotificationSettings))",
                "* announcementSetting: \(String(describing: notificationSettings.announcementSetting))",
            ]
            completion(report.joined(separator: "\n"))
        }
    }
}

extension UNAuthorizationStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .provisional:
            return "provisional"
        case .ephemeral:
            return "ephemeral"
        @unknown default:
            return "unknown"
        }
    }
}

extension UNShowPreviewsSetting: CustomStringConvertible {
    public var description: String {
        switch self {
        case .always:
            return "always"
        case .whenAuthenticated:
            return "whenAuthenticated"
        case .never:
            return "never"
        @unknown default:
            return "unknown"
        }
    }
}

extension UNNotificationSetting: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notSupported:
            return "notSupported"
        case .disabled:
            return "disabled"
        case .enabled:
            return "enabled"
        @unknown default:
            return "unknown"
        }
    }
}

extension UNAlertStyle: CustomStringConvertible {
    public var description: String {
        switch self {
        case .none:
            return "none"
        case .banner:
            return "banner"
        case .alert:
            return "alert"
        @unknown default:
            return "unknown"
        }
    }
}
