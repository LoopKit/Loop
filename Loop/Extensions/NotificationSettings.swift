//
//  NotificationSettings.swift
//  Loop
//
//  Created by Pete Schwamb on 12/21/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import UserNotifications
import LoopKit

extension NotificationSettings.AuthorizationStatus {
    public init(_ authorizationStatus: UNAuthorizationStatus) {
        switch authorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .unknown
        }
    }
}

extension NotificationSettings.NotificationSetting {
    public init(_ notificationSetting: UNNotificationSetting) {
        switch notificationSetting {
        case .notSupported:
            self = .notSupported
        case .disabled:
            self = .disabled
        case .enabled:
            self = .enabled
        @unknown default:
            self = .unknown
        }
    }
}

extension NotificationSettings.AlertStyle {
    public init(_ alertStyle: UNAlertStyle) {
        switch alertStyle {
        case .none:
            self = .none
        case .banner:
            self = .banner
        case .alert:
            self = .alert
        @unknown default:
            self = .unknown
        }
    }
}

extension NotificationSettings.ShowPreviewsSetting {
    public init(_ showPreviewsSetting: UNShowPreviewsSetting) {
        switch showPreviewsSetting {
        case .always:
            self = .always
        case .whenAuthenticated:
            self = .whenAuthenticated
        case .never:
            self = .never
        @unknown default:
            self = .unknown
        }
    }
}
