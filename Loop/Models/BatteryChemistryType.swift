//
//  BatteryChemistryType.swift
//  Loop
//
//  Created by Jerermy Lucas on 11/15/16 pattern derived from Nathan Racklyeft.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

enum BatteryChemistryType: Int, CustomStringConvertible {
    case alkaline = 0
    case lithium
    
    var description: String {
        switch self {
        case .alkaline:
            return NSLocalizedString("Alkaline", comment: "Describing the battery chemistry as Alkaline")
        case .lithium:
            return NSLocalizedString("Lithium", comment: "Describing the battery chemistry as Lithium")
        }
    }
}
