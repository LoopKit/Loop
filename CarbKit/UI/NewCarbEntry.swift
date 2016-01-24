//
//  NewCarbEntry.swift
//  CarbKit
//
//  Created by Nathan Racklyeft on 1/15/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


public struct NewCarbEntry: CarbEntry {
    public var value: Double
    public var startDate: NSDate
    public var foodType: String?
    public var absorptionTime: NSTimeInterval?
    public let unit = HKUnit.gramUnit()
    public let createdByCurrentApp = true

    public init(value: Double, startDate: NSDate, foodType: String?, absorptionTime: NSTimeInterval?) {
        self.value = value
        self.startDate = startDate
        self.foodType = foodType
        self.absorptionTime = absorptionTime
    }
}