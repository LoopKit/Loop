//
//  RileyLinkDevice.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import HealthKit
import MinimedKit
import RileyLinkKit


extension RileyLinkDevice {
    var device: HKDevice? {
        return HKDevice(
            name: name,
            manufacturer: "Medtronic",
            model: pumpState?.pumpModel?.rawValue,
            hardwareVersion: nil,
            firmwareVersion: firmwareVersion,
            softwareVersion: String(RileyLinkKitVersionNumber),
            localIdentifier: pumpState?.pumpID,
            udiDeviceIdentifier: nil
        )
    }
}
