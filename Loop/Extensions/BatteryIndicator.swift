//
//  BatteryIndicator.swift
//  Loop
//
//  Created by Pete Schwamb on 8/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import NightscoutUploadKit
import MinimedKit


// TODO: Remove this when made public in NightscoutUploadKit

extension BatteryIndicator {
    init?(batteryStatus: MinimedKit.BatteryStatus) {
        switch batteryStatus {
        case .low:
            self = .low
        case .normal:
            self = .normal
        default:
            return nil
        }
    }
}
