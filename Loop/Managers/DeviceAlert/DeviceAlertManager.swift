//
//  DeviceAlertManager.swift
//  Loop
//
//  Created by Rick Pasetto on 4/9/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

protocol DeviceAlertManagerResponder: class {
    /// Method for our Handlers to call to kick off alert response.  Differs from DeviceAlertResponder because here we need the whole `Identifier`.
    func acknowledgeDeviceAlert(identifier: DeviceAlert.Identifier)
}

/// Main (singleton-ish) class that is responsible for:
/// - managing the different targets (handlers) that will post alerts
/// - managing the different responders that might acknowledge the alert
/// - serializing alerts to storage
/// - etc.
public final class DeviceAlertManager {

    var handlers: [DeviceAlertPresenter] = []
    var responders: [String: Weak<DeviceAlertResponder>] = [:]
    
    public init(rootViewController: UIViewController,
                handlers: [DeviceAlertPresenter]? = nil) {
        self.handlers = handlers ??
            [UserNotificationDeviceAlertPresenter(),
             InAppModalDeviceAlertPresenter(rootViewController: rootViewController, deviceAlertManagerResponder: self)]
    }
    
    public func addAlertResponder(key: String, alertResponder: DeviceAlertResponder) {
        responders[key] = Weak(alertResponder)
    }
    
    public func removeAlertResponder(key: String) {
        responders.removeValue(forKey: key)
    }
}

extension DeviceAlertManager: DeviceAlertManagerResponder {
    func acknowledgeDeviceAlert(identifier: DeviceAlert.Identifier) {
        if let responder = responders[identifier.managerIdentifier]?.value {
            responder.acknowledgeAlert(alertIdentifier: identifier.alertIdentifier)
        }
    }
}

extension DeviceAlertManager: DeviceAlertPresenter {

    public func issueAlert(_ alert: DeviceAlert) {
        handlers.forEach { $0.issueAlert(alert) }
    }
    public func removePendingAlert(identifier: DeviceAlert.Identifier) {
        handlers.forEach { $0.removePendingAlert(identifier: identifier) }
    }
    public func removeDeliveredAlert(identifier: DeviceAlert.Identifier) {
        handlers.forEach { $0.removeDeliveredAlert(identifier: identifier) }
    }
}


