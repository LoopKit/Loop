//
//  DoseEntry.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/31/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


enum DoseUnit {
    case UnitsPerHour
    case Units
}


struct DoseEntry {
    let startDate: NSDate
    let endDate: NSDate
    let value: Double
    let unit: DoseUnit
    let description: String?
}
