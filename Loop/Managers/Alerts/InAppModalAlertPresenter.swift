//
//  InAppModalAlertPresenter.swift
//  LoopKit
//
//  Created by Rick Pasetto on 4/9/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

public class InAppModalAlertPresenter: AlertPresenter {

    private weak var rootViewController: UIViewController?
    private weak var alertManagerResponder: AlertManagerResponder?

    private var alertsShowing: [Alert.Identifier: (UIAlertController, Alert)] = [:]
    private var alertsPending: [Alert.Identifier: (Timer, Alert)] = [:]

    typealias ActionFactoryFunction = (String?, UIAlertAction.Style, ((UIAlertAction) -> Void)?) -> UIAlertAction
    private let newActionFunc: ActionFactoryFunction
    
    typealias TimerFactoryFunction = (TimeInterval, Bool, (() -> Void)?) -> Timer
    private let newTimerFunc: TimerFactoryFunction

    private let soundPlayer: AlertSoundPlayer

    init(rootViewController: UIViewController,
         alertManagerResponder: AlertManagerResponder,
         soundPlayer: AlertSoundPlayer = DeviceAVSoundPlayer(),
         newActionFunc: @escaping ActionFactoryFunction = UIAlertAction.init,
         newTimerFunc: TimerFactoryFunction? = nil) {
        self.rootViewController = rootViewController
        self.alertManagerResponder = alertManagerResponder
        self.soundPlayer = soundPlayer
        self.newActionFunc = newActionFunc
        self.newTimerFunc = newTimerFunc ?? { timeInterval, repeats, block in
            return Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: repeats) { _ in block?() }
        }
    }
        
    public func issueAlert(_ alert: Alert) {
        switch alert.trigger {
        case .immediate:
            show(alert: alert)
        case .delayed(let interval):
            schedule(alert: alert, interval: interval, repeats: false)
        case .repeating(let interval):
            schedule(alert: alert, interval: interval, repeats: true)
        }
    }
    
    public func retractAlert(identifier: Alert.Identifier) {
        DispatchQueue.main.async {
            self.alertsPending[identifier]?.0.invalidate()
            self.clearPendingAlert(identifier: identifier)
            self.removeDeliveredAlert(identifier: identifier, completion: nil)
        }
    }
        
    func removeDeliveredAlert(identifier: Alert.Identifier, completion: (() -> Void)?) {
        self.alertsShowing[identifier]?.0.dismiss(animated: true, completion: completion)
        self.clearDeliveredAlert(identifier: identifier)
    }
}

/// Private functions
extension InAppModalAlertPresenter {
        
    private func schedule(alert: Alert, interval: TimeInterval, repeats: Bool) {
        guard alert.foregroundContent != nil else {
            return
        }
        DispatchQueue.main.async {
            if self.isAlertPending(identifier: alert.identifier) {
                return
            }
            let timer = self.newTimerFunc(interval, repeats) { [weak self] in
                self?.show(alert: alert)
                if !repeats {
                    self?.clearPendingAlert(identifier: alert.identifier)
                }
            }
            self.addPendingAlert(alert: alert, timer: timer)
        }
    }
    
    private func show(alert: Alert) {
        guard let content = alert.foregroundContent else {
            return
        }
        DispatchQueue.main.async {
            if self.isAlertShowing(identifier: alert.identifier) {
                return
            }
            self.playSound(for: alert)
            let alertController = self.presentAlert(title: content.title,
                                                    message: content.body,
                                                    action: content.acknowledgeActionButtonLabel,
                                                    isCritical: content.isCritical) { [weak self] in
                self?.clearDeliveredAlert(identifier: alert.identifier)
                self?.alertManagerResponder?.acknowledgeAlert(identifier: alert.identifier)
            }
            self.addDeliveredAlert(alert: alert, controller: alertController)
        }
    }
    
    private func addPendingAlert(alert: Alert, timer: Timer) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.alertsPending[alert.identifier] = (timer, alert)
    }

    private func addDeliveredAlert(alert: Alert, controller: UIAlertController) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.alertsShowing[alert.identifier] = (controller, alert)
    }
    
    private func clearPendingAlert(identifier: Alert.Identifier) {
        dispatchPrecondition(condition: .onQueue(.main))
        alertsPending[identifier] = nil
    }

    private func clearDeliveredAlert(identifier: Alert.Identifier) {
        dispatchPrecondition(condition: .onQueue(.main))
        alertsShowing[identifier] = nil
    }
    
    private func isAlertPending(identifier: Alert.Identifier) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return alertsPending.index(forKey: identifier) != nil
    }
    
    private func isAlertShowing(identifier: Alert.Identifier) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return alertsShowing.index(forKey: identifier) != nil
    }

    private func presentAlert(title: String, message: String, action: String, isCritical: Bool, completion: @escaping () -> Void) -> UIAlertController {
        dispatchPrecondition(condition: .onQueue(.main))
        // For now, this is a simple alert with an "OK" button
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(newActionFunc(action, isCritical ? .destructive : .default, { _ in completion() }))
        rootViewController?.topmostViewController.present(alertController, animated: true)
        return alertController
    }
        
    private func playSound(for alert: Alert) {
        guard let sound = alert.sound else { return }
        switch sound {
        case .vibrate:
            soundPlayer.vibrate()
        case .silence:
            break
        default:
            // Assuming in-app alerts should also vibrate.  That way, if the user has "silent mode" on, they still get
            // some kind of haptic feedback
            soundPlayer.vibrate()
            guard let url = AlertManager.soundURL(for: alert) else { return }
            soundPlayer.play(url: url)
        }
    }
}
