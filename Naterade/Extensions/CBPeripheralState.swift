//
//  CBPeripheralState.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import CoreBluetooth


extension CBPeripheralState {
    var description: String {
        switch self {
        case .Connected:
            return NSLocalizedString("Connected", comment: "The connected state")
        case .Connecting:
            return NSLocalizedString("Connecting", comment: "The in-progress connecting state")
        case .Disconnected:
            return NSLocalizedString("Disconnected", comment: "The disconnected state")
        case .Disconnecting:
            return NSLocalizedString("Disconnecting", comment: "The in-progress disconnecting state")
        }
    }
}