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
    public var quantity: HKQuantity
    public var startDate: NSDate
    public var foodType: String?
    public var absorptionTime: NSTimeInterval?
    public let createdByCurrentApp = true

    public init(quantity: HKQuantity, startDate: NSDate, foodType: String?, absorptionTime: NSTimeInterval?) {
        self.quantity = quantity
        self.startDate = startDate
        self.foodType = foodType
        self.absorptionTime = absorptionTime
    }
}