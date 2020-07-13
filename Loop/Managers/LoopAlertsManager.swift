//
//  LoopAlertsManager.swift
//  Loop
//
//  Created by Rick Pasetto on 6/8/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

/// Class responsible for monitoring "system level" operations and alerting the user to any anomalous situations (e.g. bluetooth off)
public class LoopAlertsManager {
    
    public enum BluetoothState {
        case on
        case off
        case unauthorized
    }
    
    static let managerIdentifier = "Loop"
    
    private lazy var log = DiagnosticLog(category: String(describing: LoopAlertsManager.self))
    
    private weak var alertManager: AlertManager?
    
    private let bluetoothPoweredOffIdentifier = Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: "bluetoothPoweredOff")
    
    init(alertManager: AlertManager, bluetoothStateManager: BluetoothStateManager) {
        self.alertManager = alertManager
        bluetoothStateManager.addBluetoothStateObserver(self)
    }
        
    private func onBluetoothPermissionDenied() {
        log.default("Bluetooth permission denied")
        let title = NSLocalizedString("Bluetooth Unavailable Alert", comment: "Bluetooth unavailable alert title")
        let body = NSLocalizedString("Loop has detected an issue with your Bluetooth settings, and will not work successfully until Bluetooth is enabled. You will not receive glucose readings, or be able to bolus.", comment: "Bluetooth unavailable alert body.")
        let content = Alert.Content(title: title,
                                      body: body,
                                      acknowledgeActionButtonLabel: NSLocalizedString("Dismiss", comment: "Default alert dismissal"))
        alertManager?.issueAlert(Alert(identifier: bluetoothPoweredOffIdentifier, foregroundContent: content, backgroundContent: content, trigger: .immediate))
    }

    private func onBluetoothPoweredOn() {
        log.default("Bluetooth powered on")
        alertManager?.retractAlert(identifier: bluetoothPoweredOffIdentifier)
    }

    private func onBluetoothPoweredOff() {
        log.default("Bluetooth powered off")
        let title = NSLocalizedString("Bluetooth Off Alert", comment: "Bluetooth off alert title")
        let bgBody = NSLocalizedString("Loop will not work successfully until Bluetooth is enabled. You will not recieve glucose readings, or be able to bolus.", comment: "Bluetooth off background alert body.")
        let bgcontent = Alert.Content(title: title,
                                      body: bgBody,
                                      acknowledgeActionButtonLabel: NSLocalizedString("Dismiss", comment: "Default alert dismissal"))
        let fgBody = NSLocalizedString("Turn on Bluetooth to receive alerts, alarms or sensor glucose readings.", comment: "Bluetooth off foreground alert body")
        let fgcontent = Alert.Content(title: title,
                                      body: fgBody,
                                      acknowledgeActionButtonLabel: NSLocalizedString("Dismiss", comment: "Default alert dismissal"))
        alertManager?.issueAlert(Alert(identifier: bluetoothPoweredOffIdentifier, foregroundContent: fgcontent, backgroundContent: bgcontent, trigger: .immediate))
    }

}

// MARK: - Bluetooth State Observer

extension LoopAlertsManager: BluetoothStateManagerObserver {
    public func bluetoothStateManager(_ bluetoothStateManager: BluetoothStateManager,
                                      bluetoothStateDidUpdate bluetoothState: BluetoothStateManager.BluetoothState)
    {
        switch bluetoothState {
        case .poweredOn:
            onBluetoothPoweredOn()
        case .poweredOff:
            onBluetoothPoweredOff()
        case .denied:
            onBluetoothPermissionDenied()
        default:
            return
        }
    }
}
