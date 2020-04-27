//
//  InAppModalDeviceAlertPresenter.swift
//  LoopKit
//
//  Created by Rick Pasetto on 4/9/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import AudioToolbox
import AVFoundation
import os.log


public protocol AlertSoundPlayer {
    func vibrate()
    func play(url: URL)
}

public class InAppModalDeviceAlertPresenter: DeviceAlertPresenter {

    private weak var rootViewController: UIViewController?
    private weak var deviceAlertManagerResponder: DeviceAlertManagerResponder?

    private var alertsShowing: [DeviceAlert.Identifier: (UIAlertController, DeviceAlert)] = [:]
    private var alertsPending: [DeviceAlert.Identifier: (Timer, DeviceAlert)] = [:]

    typealias ActionFactoryFunction = (String?, UIAlertAction.Style, ((UIAlertAction) -> Void)?) -> UIAlertAction
    private let newActionFunc: ActionFactoryFunction
    
    typealias TimerFactoryFunction = (TimeInterval, Bool, (() -> Void)?) -> Timer
    private let newTimerFunc: TimerFactoryFunction

    private let soundPlayer: AlertSoundPlayer

    init(rootViewController: UIViewController,
         deviceAlertManagerResponder: DeviceAlertManagerResponder,
         soundPlayer: AlertSoundPlayer = AVSoundPlayer(),
         newActionFunc: @escaping ActionFactoryFunction = UIAlertAction.init,
         newTimerFunc: TimerFactoryFunction? = nil) {
        self.rootViewController = rootViewController
        self.deviceAlertManagerResponder = deviceAlertManagerResponder
        self.soundPlayer = soundPlayer
        self.newActionFunc = newActionFunc
        self.newTimerFunc = newTimerFunc ?? { timeInterval, repeats, block in
            return Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: repeats) { _ in block?() }
        }
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
        removeDeliveredAlert(identifier: identifier, completion: nil)
    }
    
    // For tests only
    func removeDeliveredAlert(identifier: DeviceAlert.Identifier, completion: (() -> Void)?) {
        DispatchQueue.main.async {
            self.alertsShowing[identifier]?.0.dismiss(animated: true, completion: completion)
            self.clearDeliveredAlert(identifier: identifier)
        }
    }
}

/// Private functions
extension InAppModalDeviceAlertPresenter {
        
    private func schedule(alert: DeviceAlert, interval: TimeInterval, repeats: Bool) {
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
    
    private func show(alert: DeviceAlert) {
        guard let content = alert.foregroundContent else {
            return
        }
        DispatchQueue.main.async {
            if self.isAlertShowing(identifier: alert.identifier) {
                return
            }
            self.playSound(for: alert)
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
        alertController.addAction(newActionFunc(action, .default, { _ in completion() }))
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
    
    private func playSound(for alert: DeviceAlert) {
        guard let soundName = alert.soundName else { return }
        switch soundName {
        case .vibrate:
            soundPlayer.vibrate()
        case .silence:
            break
        default:
            // Assuming in-app alerts should also vibrate.  That way, if the user has "silent mode" on, they still get
            // some kind of haptic feedback
            soundPlayer.vibrate()
            guard let url = DeviceAlertManager.soundURL(for: alert) else { return }
            soundPlayer.play(url: url)
        }
    }
}

private class AVSoundPlayer: AlertSoundPlayer {
    private var soundEffect: AVAudioPlayer?
    private let log = OSLog(category: "AVSoundPlayer")
    
    enum Error: Swift.Error {
        case playFailed
    }
    
    func vibrate() {
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
    }
    
    func play(url: URL) {
        DispatchQueue.main.async {
            do {
                // The AVAudioPlayer has to remain around until the sound completes playing.  A cleaner way might be
                // to wait until that completes, then delete it, but seems overkill.
                let soundEffect = try AVAudioPlayer(contentsOf: url)
                self.soundEffect = soundEffect
                if !soundEffect.play() {
                    self.log.error("couldn't play sound %@", url.absoluteString)
                }
            } catch {
                self.log.error("couldn't play sound %@: %@", url.absoluteString, String(describing: error))
            }
        }
    }
}
