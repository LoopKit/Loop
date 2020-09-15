//
//  UIDevice+Loop.swift
//  Loop
//
//  Created by Darin Krauss on 5/27/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKit

extension UIDevice {

    // https://stackoverflow.com/questions/26028918/how-to-determine-the-current-iphone-device-model
    var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        let modelCode = withUnsafePointer(to: &info.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) } }
        return modelCode ?? "unknown"
    }

    public var deviceSettings: StoredDosingDecision.DeviceSettings {
        return StoredDosingDecision.DeviceSettings(name: name,
                                                   systemName: systemName,
                                                   systemVersion: systemVersion,
                                                   model: model,
                                                   modelIdentifier: modelIdentifier,
                                                   batteryLevel: isBatteryMonitoringEnabled ? batteryLevel : nil,
                                                   batteryState: isBatteryMonitoringEnabled ? batteryState.batteryState : nil)
    }
}

extension UIDevice {
    func generateDiagnosticReport(_ completion: @escaping (_ report: String) -> Void) {
        var report: [String] = [
            "## Device",
            "",
            "* name: \(name)",
            "* systemName: \(systemName)",
            "* systemVersion: \(systemVersion)",
            "* model: \(model)",
            "* modelIdentifier: \(modelIdentifier)",
        ]
        if isBatteryMonitoringEnabled {
            report += [
                "* batteryLevel: \(batteryLevel)",
                "* batteryState: \(String(describing: batteryState))",
            ]
        }
        completion(report.joined(separator: "\n"))
    }
}

extension UIDevice.BatteryState {
    public var batteryState: StoredDosingDecision.DeviceSettings.BatteryState {
        switch self {
        case .unknown:
            return .unknown
        case .unplugged:
            return .unplugged
        case .charging:
            return .charging
        case .full:
            return .full
        @unknown default:
            return .unknown
        }
    }
}

extension UIDevice.BatteryState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return "unknown"
        case .unplugged:
            return "unplugged"
        case .charging:
            return "charging"
        case .full:
            return "full"
        @unknown default:
            return "unknown"
        }
    }
}
