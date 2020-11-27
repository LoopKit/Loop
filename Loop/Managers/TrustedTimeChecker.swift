//
//  TrustedTimeChecker.swift
//  Loop
//
//  Created by Rick Pasetto on 10/14/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import TrueTime
import UIKit

fileprivate extension UserDefaults {
    private enum Key: String {
        case lastSignificantTimeChangeAlert = "com.loopkit.Loop.LastSignificantTimeChangeAlert"
    }
    
    var lastSignificantTimeChangeAlert: Date? {
        get {
            return object(forKey: Key.lastSignificantTimeChangeAlert.rawValue) as? Date
        }
        set {
            set(newValue, forKey: Key.lastSignificantTimeChangeAlert.rawValue)
        }
    }
}

class TrustedTimeChecker {
    private let acceptableTimeDelta = TimeInterval.seconds(120)
    private let minimumAlertFrequency = TimeInterval.minutes(30)

    // For NTP time checking
    private var ntpClient: TrueTimeClient
    private weak var alertManager: AlertManager?
    private lazy var log = DiagnosticLog(category: "TrustedTimeChecker")

    init(_ alertManager: AlertManager) {
        ntpClient = TrueTimeClient.sharedInstance
        #if DEBUG
        if ntpClient.responds(to: #selector(setter: TrueTimeClient.logCallback)) {
            ntpClient.logCallback = { _ in }    // TrueTimeClient is a bit chatty in DEBUG build. This squelches all of its logging.
        }
        #endif
        ntpClient.start()
        self.alertManager = alertManager
        NotificationCenter.default.addObserver(forName: UIApplication.significantTimeChangeNotification,
                                               object: nil, queue: nil) { [weak self] _ in self?.checkTrustedTime() }
        NotificationCenter.default.addObserver(forName: .LoopRunning,
                                               object: nil, queue: nil) { [weak self] _ in self?.checkTrustedTime() }
    }
    
    private func checkTrustedTime() {
        ntpClient.fetchIfNeeded(completion: { [weak self] result in
            guard let self = self else { return }
            switch result {
            case let .success(referenceTime):
                let deviceNow = Date()
                let ntpNow = referenceTime.now()
                let timeDelta = abs(ntpNow.timeIntervalSince(deviceNow))
                let timeSinceLastAlert = abs(ntpNow.timeIntervalSince(UserDefaults.standard.lastSignificantTimeChangeAlert ?? Date.distantPast))
                if timeDelta > self.acceptableTimeDelta, timeSinceLastAlert > self.minimumAlertFrequency {
                    self.log.info("applicationSignificantTimeChange: ntpNow = %@, deviceNow = %@", ntpNow.debugDescription, deviceNow.debugDescription)
                    self.issueTimeChangedAlert()
                    UserDefaults.standard.lastSignificantTimeChangeAlert = ntpNow
                }
            case let .failure(error):
                self.log.error("applicationSignificantTimeChange: Error getting NTP time: %@", error.localizedDescription)
            }
        })
    }

    private func issueTimeChangedAlert() {
        let alertIdentifier = Alert.Identifier(managerIdentifier: "Loop", alertIdentifier: "significantTimeChange")
        let alertTitle = NSLocalizedString("Time Change Detected", comment: "Time change alert title")
        let alertBody = String(format: NSLocalizedString("Your phone’s time has been changed. %1$@ needs accurate time records to make predictions about your glucose and adjust your insulin accordingly.\n\nCheck in your iPhone Settings (General / Date & Time) and verify that Set Automatically is enabled. Failure to resolve could lead to serious under-delivery or over-delivery of insulin.", comment: "Time change alert body. (1: app name)"), Bundle.main.bundleDisplayName)
        let content = Alert.Content(title: alertTitle, body: alertBody, acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Alert acknowledgment OK button"))
        alertManager?.issueAlert(Alert(identifier: alertIdentifier, foregroundContent: content, backgroundContent: content, trigger: .immediate))
    }
}
