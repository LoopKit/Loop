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


@available(iOS 9.0, *)
extension HKDevice {
    convenience init(rileyLinkDevice: RileyLinkDevice) {
        self.init(
            name: rileyLinkDevice.name,
            manufacturer: "@ps2",
            model: "RileyLink",
            hardwareVersion: "1.0",
            firmwareVersion: "0.0.1",
            softwareVersion: "\(RileyLinkKitVersionNumber)/\(MinimedKitVersionNumber)/\(NSBundle.mainBundle().shortVersionString)",
            localIdentifier: nil,
            UDIDeviceIdentifier: nil
        )
    }
}
