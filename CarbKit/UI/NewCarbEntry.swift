//
//  NewCarbEntry.swift
//  CarbKit
//
//  Created by Nathan Racklyeft on 1/15/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


struct NewCarbEntry: CarbEntry {
    var value: Double
    var startDate: NSDate
    var foodType: String?
    var absorptionTime: NSTimeInterval?
    let unit = HKUnit.gramUnit()
    let createdByCurrentApp = true
}