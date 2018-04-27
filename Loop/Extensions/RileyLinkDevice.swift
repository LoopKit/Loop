//
//  RileyLinkDevice.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import HealthKit
import MinimedKit
import RileyLinkKit
import RileyLinkBLEKit


extension RileyLinkDevice.Status {
    func device(settings: PumpSettings?, pumpState: PumpState?) -> HKDevice {
        return HKDevice(
            name: name,
            manufacturer: "Medtronic",
            model: pumpState?.pumpModel?.rawValue,
            hardwareVersion: nil,
            firmwareVersion: radioFirmwareVersion?.description,
            softwareVersion: String(RileyLinkKitVersionNumber),
            localIdentifier: settings?.pumpID,
            udiDeviceIdentifier: nil
        )
    }
}
