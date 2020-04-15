//
//  InAppUserAlertHandler.swift
//  LoopKit
//
//  Created by Rick Pasetto on 4/9/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

public class InAppModalDeviceAlertHandler: DeviceAlertHandler {
    
    private weak var rootViewController: UIViewController?
    private weak var deviceAlertManagerResponder: DeviceAlertManagerResponder?
    
    private var alertsShowing: [DeviceAlert.Identifier: (UIAlertController, DeviceAlert)] = [:]
    private var alertsPending: [DeviceAlert.Identifier: (Timer, DeviceAlert)] = [:]
    
    init(rootViewController: UIViewController, deviceAlertManagerResponder: DeviceAlertManagerResponder) {
        self.rootViewController = rootViewController
        self.deviceAlertManagerResponder = deviceAlertManagerResponder
    }
        
    public func issueAlert(_ alert: DeviceAlert) {
        switch alert.trigger {
        case .immediate:
            show(alert: alert)
        case .delayed(let interval):
            schedule(alert: alert, interval: interval, repeats: false)
        case .repeating(let interval):
            schedule(alert: alert, interval: interval, repeats: true)
        }
    }
    
    public func removePendingAlert(identifier: DeviceAlert.Identifier) {
        DispatchQueue.main.async {
            self.alertsPending[identifier]?.0.invalidate()
            self.clearPendingAlert(identifier: identifier)
        }
    }
    
    public func removeDeliveredAlert(identifier: DeviceAlert.Identifier) {
        DispatchQueue.main.async {
            self.alertsShowing[identifier]?.0.dismiss(animated: true)
            self.clearDeliveredAlert(identifier: identifier)
        }
    }
}

/// Private functions
extension InAppModalDeviceAlertHandler {
        
    private func schedule(alert: DeviceAlert, interval: TimeInterval, repeats: Bool) {
        guard alert.foregroundContent != nil else {
            return
        }
        DispatchQueue.main.async {
            if self.isAlertPending(identifier: alert.identifier) {
                return
            }
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { [weak self] timer in
                self?.show(alert: alert)
                if !repeats {
                    self?.clearPendingAlert(identifier: alert.identifier)
                }
            }
            self.addPendingAlert(alert: alert, timer: timer)
        }
    }
    
    private func show(alert: DeviceAlert) {
        guard let content = alert.foregroundContent else {
            return
        }
        DispatchQueue.main.async {
            if self.isAlertShowing(identifier: alert.identifier) {
                return
            }
            let alertController = self.presentAlert(title: content.title, message: content.body, action: content.acknowledgeActionButtonLabel) { [weak self] in
                self?.clearDeliveredAlert(identifier: alert.identifier)
                self?.deviceAlertManagerResponder?.acknowledgeDeviceAlert(identifier: alert.identifier)
            }
            self.addDeliveredAlert(alert: alert, controller: alertController)
        }
    }
    
    private func addPendingAlert(alert: DeviceAlert, timer: Timer) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.alertsPending[alert.identifier] = (timer, alert)
    }

    private func addDeliveredAlert(alert: DeviceAlert, controller: UIAlertController) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.alertsShowing[alert.identifier] = (controller, alert)
    }
    
    private func clearPendingAlert(identifier: DeviceAlert.Identifier) {
        dispatchPrecondition(condition: .onQueue(.main))
        alertsPending[identifier] = nil
    }

    private func clearDeliveredAlert(identifier: DeviceAlert.Identifier) {
        dispatchPrecondition(condition: .onQueue(.main))
        alertsShowing[identifier] = nil
    }
    
    private func isAlertPending(identifier: DeviceAlert.Identifier) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return alertsPending.index(forKey: identifier) != nil
    }
    
    private func isAlertShowing(identifier: DeviceAlert.Identifier) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return alertsShowing.index(forKey: identifier) != nil
    }

    private func presentAlert(title: String, message: String, action: String, completion: @escaping () -> Void) -> UIAlertController {
        dispatchPrecondition(condition: .onQueue(.main))
        // For now, this is a simple alert with an "OK" button
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: action, style: .default, handler: { _ in completion() }))
        topViewController(controller: rootViewController)?.present(alertController, animated: true)
        return alertController
    }
    
    // Helper function pulled from SO...may be outdated, especially in the SwiftUI world
    private func topViewController(controller: UIViewController?) -> UIViewController? {
        if let tabController = controller as? UITabBarController {
            return topViewController(controller: tabController.selectedViewController)
        }
        if let navController = controller as? UINavigationController {
            return topViewController(controller: navController.visibleViewController)
        }
        if let presented = controller?.presentedViewController {
            return topViewController(controller: presented)
        }
        return controller
    }
    
}
