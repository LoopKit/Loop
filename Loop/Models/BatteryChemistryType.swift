//
//  BatteryChemistryType.swift
//  Loop
//
//  Created by Jerermy Lucas on 11/15/16 pattern derived from Nathan Racklyeft.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

enum BatteryChemistryType: Int, CustomStringConvertible {
    case alkline = 0
    case lithium
    
    var description: String {
        switch self {
        case .alkline:
            return NSLocalizedString("Alkline", comment: "Describing the battery chemistry as Alkline")
        case .lithium:
            return NSLocalizedString("Lithium", comment: "Describing the battery chemistry as Lithium")
        }
    }
}
