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
        let content = Alert.Content(title: NSLocalizedString("Bluetooth Permission Denied", comment: "Bluetooth permission denied alert title"),
                                      body: NSLocalizedString("Loop needs permission to access your iPhone’s Bluetooth connection in order for the app to communicate with your pump and CGM sensor. You will be unable to use the app to receive CGM information and send commands to your pump until Bluetooth permissions are enabled.",
                                                              comment: "Bluetooth permission denied alert body"),
                                      acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Default alert dismissal"))
        alertManager?.issueAlert(Alert(identifier: bluetoothPoweredOffIdentifier, foregroundContent: content, backgroundContent: content, trigger: .immediate))
    }

    private func onBluetoothPoweredOn() {
        log.default("Bluetooth powered on")
        alertManager?.retractAlert(identifier: bluetoothPoweredOffIdentifier)
    }

    private func onBluetoothPoweredOff() {
        log.default("Bluetooth powered off")
        let body = NSLocalizedString("You have turned Bluetooth off. Loop cannot communicate with your pump and CGM sensor when Bluetooth is off. To resume automation, turn Bluetooth on.", comment: "Bluetooth off alert body")
        let bgcontent = Alert.Content(title: NSLocalizedString("Bluetooth Off Alert", comment: "Bluetooth off background alert title"),
                                      body: body,
                                      acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Default alert dismissal"))
        let fgcontent = Alert.Content(title: NSLocalizedString("Bluetooth Off", comment: "Bluetooth off foreground alert title"),
                                      body: body,
                                      acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Default alert dismissal"))
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
