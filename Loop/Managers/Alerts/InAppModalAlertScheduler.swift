//
//  InAppModalAlertScheduler.swift
//  LoopKit
//
//  Created by Rick Pasetto on 4/9/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKit

public class InAppModalAlertScheduler {

    private weak var alertPresenter: AlertPresenter?
    private weak var alertManagerResponder: AlertManagerResponder?

    private var alertsPresented: [Alert.Identifier: (UIAlertController, Alert)] = [:]
    private var alertsPending: [Alert.Identifier: (Timer, Alert)] = [:]

    typealias ActionFactoryFunction = (String?, UIAlertAction.Style, ((UIAlertAction) -> Void)?) -> UIAlertAction
    private let newActionFunc: ActionFactoryFunction
    
    typealias TimerFactoryFunction = (TimeInterval, Bool, (() -> Void)?) -> Timer
    private let newTimerFunc: TimerFactoryFunction

    init(alertPresenter: AlertPresenter?,
         alertManagerResponder: AlertManagerResponder,
         newActionFunc: @escaping ActionFactoryFunction = UIAlertAction.init,
         newTimerFunc: TimerFactoryFunction? = nil)
    {
        self.alertPresenter = alertPresenter
        self.alertManagerResponder = alertManagerResponder
        self.newActionFunc = newActionFunc
        self.newTimerFunc = newTimerFunc ?? { timeInterval, repeats, block in
            return Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: repeats) { _ in block?() }
        }
    }

    public func scheduleAlert(_ alert: Alert) {
        switch alert.trigger {
        case .immediate:
            show(alert: alert)
        case .delayed(let interval):
            schedule(alert: alert, interval: interval, repeats: false)
        case .repeating(let interval):
            schedule(alert: alert, interval: interval, repeats: true)
        }
    }
    
    public func unscheduleAlert(identifier: Alert.Identifier) {
        DispatchQueue.main.async {
            self.removePendingAlert(identifier: identifier)
            self.removePresentedAlert(identifier: identifier)
        }
    }

    func removePresentedAlert(identifier: Alert.Identifier, completion: (() -> Void)? = nil) {
        guard let alertPresented = alertsPresented[identifier] else {
            completion?()
            return
        }
        alertPresenter?.dismissAlert(alertPresented.0, animated: true, completion: completion)
        clearPresentedAlert(identifier: identifier)
    }

    func removePendingAlert(identifier: Alert.Identifier) {
        guard let alertPending = alertsPending[identifier] else { return }
        alertPending.0.invalidate()
        clearPendingAlert(identifier: identifier)
    }
}

/// Private functions
extension InAppModalAlertScheduler {

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
            if self.isAlertPresented(identifier: alert.identifier) {
                return
            }
            let alertController = self.constructAlert(title: content.title,
                                                      message: content.body,
                                                      action: content.acknowledgeActionButtonLabel,
                                                      isCritical: alert.interruptionLevel == .critical) { [weak self] in
                // the completion is called after the alert is acknowledged
                self?.clearPresentedAlert(identifier: alert.identifier)
                self?.alertManagerResponder?.acknowledgeAlert(identifier: alert.identifier)
            }
            self.alertPresenter?.present(alertController, animated: true) { [weak self] in
                // the completion is called after the alert is presented
                self?.addPresentedAlert(alert: alert, controller: alertController)
            }
        }
    }
    
    private func addPendingAlert(alert: Alert, timer: Timer) {
        dispatchPrecondition(condition: .onQueue(.main))
        alertsPending[alert.identifier] = (timer, alert)
    }

    private func addPresentedAlert(alert: Alert, controller: UIAlertController) {
        dispatchPrecondition(condition: .onQueue(.main))
        alertsPresented[alert.identifier] = (controller, alert)
    }
    
    private func clearPendingAlert(identifier: Alert.Identifier) {
        dispatchPrecondition(condition: .onQueue(.main))
        alertsPending[identifier] = nil
    }

    private func clearPresentedAlert(identifier: Alert.Identifier) {
        dispatchPrecondition(condition: .onQueue(.main))
        alertsPresented[identifier] = nil
    }

    private func isAlertPending(identifier: Alert.Identifier) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return alertsPending.index(forKey: identifier) != nil
    }
    
    private func isAlertPresented(identifier: Alert.Identifier) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return alertsPresented.index(forKey: identifier) != nil
    }

    private func constructAlert(title: String, message: String, action: String, isCritical: Bool, acknowledgeCompletion: @escaping () -> Void) -> UIAlertController {
        dispatchPrecondition(condition: .onQueue(.main))
        // For now, this is a simple alert with an "OK" button
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(newActionFunc(action, .default, { _ in acknowledgeCompletion() }))
        return alertController
    }
}
