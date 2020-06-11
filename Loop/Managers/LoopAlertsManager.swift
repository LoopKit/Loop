//
//  LoopAlertsManager.swift
//  Loop
//
//  Created by Rick Pasetto on 6/8/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import CoreBluetooth
import LoopKit

/// Class responsible for monitoring "system level" operations and alerting the user to any anomalous situations (e.g. bluetooth off)
class LoopAlertsManager: NSObject {
    private var bluetoothCentralManager: CBCentralManager!
    private lazy var log = DiagnosticLog(category: String(describing: LoopAlertsManager.self))
    private weak var alertManager: AlertManager?
    private let bluetoothPoweredOffIdentifier = Alert.Identifier(managerIdentifier: "Loop", alertIdentifier: "bluetoothPoweredOff")

    init(alertManager: AlertManager) {
        super.init()
        bluetoothCentralManager = CBCentralManager(delegate: self, queue: nil)
        self.alertManager = alertManager
    }
}

// MARK: CBCentralManagerDelegate implementation

extension LoopAlertsManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unauthorized:
            switch central.authorization {
            case .denied:
                onBluetoothPermissionDenied()
            default:
                break
            }
        case .poweredOn:
            onBluetoothPoweredOn()
        case .poweredOff:
            onBluetoothPoweredOff()
        default:
            break
        }
    }
    
    private func onBluetoothPermissionDenied() {
        log.default("Bluetooth permission denied")
        let content = Alert.Content(title: NSLocalizedString("Bluetooth Permission Denied", comment: "Bluetooth permission denied alert title"),
                                      body: NSLocalizedString("You must accept permission to use bluetooth to receive alerts, alarms or sensor glucose readings, and communicate with your pump.",
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
        let bgcontent = Alert.Content(title: NSLocalizedString("Bluetooth Off Alert", comment: "Bluetooth off background alert title"),
                                      body: NSLocalizedString("Turn on Bluetooth to receive alerts, alarms or sensor glucose readings, and communicate with your pump.", comment: "Bluetooth off alert body"),
                                      acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Default alert dismissal"))
        let fgcontent = Alert.Content(title: NSLocalizedString("Bluetooth Off", comment: "Bluetooth off foreground alert title"),
                                      body: NSLocalizedString("Turn on Bluetooth to receive alerts, alarms or sensor glucose readings, and communicate with your pump.", comment: "Bluetooth off alert body"),
                                      acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Default alert dismissal"))
        alertManager?.issueAlert(Alert(identifier: bluetoothPoweredOffIdentifier, foregroundContent: fgcontent, backgroundContent: bgcontent, trigger: .immediate))
    }

}
