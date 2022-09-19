//
//  CrashRecoveryManager.swift
//  Loop
//
//  Created by Pete Schwamb on 9/17/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

class CrashRecoveryManager {

    private let log = DiagnosticLog(category: "CrashRecoveryManager")

    let managerIdentifier = "CrashRecoveryManager"

    private let crashAlertIdentifier = "CrashAlert"

    var doseRecoveredFromCrash: AutomaticDoseRecommendation?

    let alertIssuer: AlertIssuer

    var pendingCrashRecovery: Bool {
        return doseRecoveredFromCrash != nil
    }

    init(alertIssuer: AlertIssuer) {
        self.alertIssuer = alertIssuer

        doseRecoveredFromCrash = UserDefaults.appGroup?.inFlightAutomaticDose

        if doseRecoveredFromCrash != nil {
            issueCrashAlert()
        }
    }

    func dosingStarted(dose: AutomaticDoseRecommendation) {
        UserDefaults.appGroup?.inFlightAutomaticDose = dose
    }

    func dosingFinished() {
        UserDefaults.appGroup?.inFlightAutomaticDose = nil
    }

    private func issueCrashAlert() {
        let title = NSLocalizedString("Loop Crashed", comment: "Title for crash recovery alert")
        let modalBody = NSLocalizedString("Oh no! Loop crashed while dosing, and insulin adjustments have been paused until this dialog is closed. Dosing history may not be accurate. Please review Insulin Delivery charts, and monitor your blood glucose carefully.", comment: "Modal body for crash recovery alert")
        let modalContent = Alert.Content(title: title,
                                         body: modalBody,
                                         acknowledgeActionButtonLabel: NSLocalizedString("Continue", comment: "Default alert dismissal"))
        let notificationBody = NSLocalizedString("Insulin adjustments have been disabled!", comment: "Notification body for crash recovery alert")
        let notificationContent = Alert.Content(title: title,
                                                body: notificationBody,
                                                acknowledgeActionButtonLabel: NSLocalizedString("Continue", comment: "Default alert dismissal"))

        let identifier = Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: crashAlertIdentifier)

        let alert = Alert(identifier: identifier,
                         foregroundContent: modalContent,
                         backgroundContent: notificationContent,
                         trigger: .immediate,
                         interruptionLevel: .critical)

        self.alertIssuer.issueAlert(alert)
    }
}

extension CrashRecoveryManager: AlertResponder {
    func acknowledgeAlert(alertIdentifier: LoopKit.Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        UserDefaults.appGroup?.inFlightAutomaticDose = nil
        doseRecoveredFromCrash = nil
    }
}

