//
//  HKDevice.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/7/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import HealthKit
import MinimedKit
import RileyLinkKit


extension HKDevice {
    convenience init(rileyLinkDevice: RileyLinkDevice) {
        // TODO: Don't hard-code this information here. Can we read firmware version from the pump?
        self.init(
            name: rileyLinkDevice.name,
            manufacturer: "Medtronic",
            model: "Revel",
            hardwareVersion: "723",
            firmwareVersion: "2.4A 1.1 0B 0B",
            softwareVersion: "RileyLink: \(RileyLinkKitVersionNumber), MinimedKit: \(MinimedKitVersionNumber), Naterade: \(NSBundle.mainBundle().shortVersionString)",
            localIdentifier: nil,
            UDIDeviceIdentifier: nil
        )
    }
}
