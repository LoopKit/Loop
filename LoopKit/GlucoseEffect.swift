//
//  GlucoseEffect.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/24/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


public struct GlucoseEffect: SampleValue {
    public let startDate: NSDate
    public let quantity: HKQuantity

    public init(startDate: NSDate, quantity: HKQuantity) {
        self.startDate = startDate
        self.quantity = quantity
    }
}
