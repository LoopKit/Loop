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
        case detectedSystemTimeOffset = "com.loopkit.Loop.DetectedSystemTimeOffset"
    }
    
    var detectedSystemTimeOffset: TimeInterval? {
        get {
            return object(forKey: Key.detectedSystemTimeOffset.rawValue) as? TimeInterval
        }
        set {
            set(newValue, forKey: Key.detectedSystemTimeOffset.rawValue)
        }
    }
}

class TrustedTimeChecker {
    private let acceptableTimeDelta = TimeInterval.seconds(120)

    // For NTP time checking
    private var ntpClient: TrueTimeClient
    private weak var alertManager: AlertManager?
    private lazy var log = DiagnosticLog(category: "TrustedTimeChecker")

    var detectedSystemTimeOffset: TimeInterval {
        didSet {
            UserDefaults.standard.detectedSystemTimeOffset = detectedSystemTimeOffset
        }
    }

    init(alertManager: AlertManager? = nil) {
        ntpClient = TrueTimeClient.sharedInstance
        #if DEBUG
        if ntpClient.responds(to: #selector(setter: TrueTimeClient.logCallback)) {
            ntpClient.logCallback = { _ in }    // TrueTimeClient is a bit chatty in DEBUG build. This squelches all of its logging.
        }
        #endif
        ntpClient.start()
        self.alertManager = alertManager
        self.detectedSystemTimeOffset = UserDefaults.standard.detectedSystemTimeOffset ?? 0
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                               object: nil, queue: nil) { [weak self] _ in self?.checkTrustedTime() }
        NotificationCenter.default.addObserver(forName: .LoopRunning,
                                               object: nil, queue: nil) { [weak self] _ in self?.checkTrustedTime() }
        checkTrustedTime()
    }
    
    private func checkTrustedTime() {
        ntpClient.fetchIfNeeded(completion: { [weak self] result in
            guard let self = self else { return }
            switch result {
            case let .success(referenceTime):
                let deviceNow = Date()
                let ntpNow = referenceTime.now()
                let timeDelta = ntpNow.timeIntervalSince(deviceNow)

                if abs(timeDelta) > self.acceptableTimeDelta {
                    self.log.default("applicationSignificantTimeChange: ntpNow = %@, deviceNow = %@", ntpNow.debugDescription, deviceNow.debugDescription)
                    self.detectedSystemTimeOffset = timeDelta
                    self.issueTimeChangedAlert()
                } else {
                    self.detectedSystemTimeOffset = 0
                    self.retractTimeChangedAlert()
                }
            case let .failure(error):
                self.log.error("applicationSignificantTimeChange: Error getting NTP time: %@", error.localizedDescription)
            }
        })
    }

    private var alertIdentifier: Alert.Identifier {
        Alert.Identifier(managerIdentifier: "Loop", alertIdentifier: "significantTimeChange")
    }

    private func issueTimeChangedAlert() {
        let alertTitle = String(format: NSLocalizedString("%1$@ Time Settings Need Attention", comment: "Time change alert title"), UIDevice.current.model)
        let alertBody = String(format: NSLocalizedString("Your %1$@’s time has been changed. %2$@ needs accurate time records to make predictions about your glucose and adjust your insulin accordingly.\n\nCheck in your %1$@ Settings (General / Date & Time) and verify that 'Set Automatically' is turned ON. Failure to resolve could lead to serious under-delivery or over-delivery of insulin.", comment: "Time change alert body. (1: app name)"), UIDevice.current.model, Bundle.main.bundleDisplayName)
        let content = Alert.Content(title: alertTitle, body: alertBody, acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Alert acknowledgment OK button"))
        alertManager?.issueAlert(Alert(identifier: alertIdentifier, foregroundContent: content, backgroundContent: content, trigger: .immediate))
    }

    private func retractTimeChangedAlert() {
        alertManager?.retractAlert(identifier: alertIdentifier)
    }
}
