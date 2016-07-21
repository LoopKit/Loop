//
//  PumpModel.swift
//  Loop
//
//  Created by Jerermy Lucas on 7/16/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import MinimedKit

extension PumpModel {
    private var size: Int {
        return Int(rawValue)! / 100
    }
    
    var reservoirCapacity: Int {
        switch size {
        case 5:
            return 176
		case 7:
            return 300
		default:
            fatalError("Unknown reservoir capacity for PumpModel.\(self)")
        }
    }
}