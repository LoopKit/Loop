//
//  StoredCarbEntry.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/22/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//


import HealthKit


struct StoredCarbEntry: CarbEntry {

    let sample: HKQuantitySample

    init(sample: HKQuantitySample) {
        self.sample = sample
    }

    // MARK: - SampleValue

    var startDate: NSDate {
        return sample.startDate
    }

    var quantity: HKQuantity {
        return sample.quantity
    }

    // MARK: - CarbEntry

    var foodType: String? {
        return sample.foodType
    }

    var absorptionTime: NSTimeInterval? {
        return sample.absorptionTime
    }

    var createdByCurrentApp: Bool {
        return sample.createdByCurrentApp
    }
}
