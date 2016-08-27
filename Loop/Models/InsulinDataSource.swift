//
//  InsulinDataSource.swift
//  Loop
//
//  Created by Nathan Racklyeft on 6/10/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


enum InsulinDataSource: Int, CustomStringConvertible {
    case pumpHistory = 0
    case reservoir

    var description: String {
        switch self {
        case .pumpHistory:
            return NSLocalizedString("Event History", comment: "Describing the pump history insulin data source")
        case .reservoir:
            return NSLocalizedString("Reservoir", comment: "Describing the reservoir insulin data source")
        }
    }
}
