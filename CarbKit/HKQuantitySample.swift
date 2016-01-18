//
//  HKQuantitySample.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/10/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import HealthKit


let MetadataKeyAbsorptionTimeMinutes = "com.loudnate.CarbKit.HKMetadataKey.AbsorptionTimeMinutes"



extension HKQuantitySample: CarbEntry {
    public var value: Double {
        return quantity.doubleValueForUnit(HKUnit.gramUnit())
    }

    public var unit: HKUnit {
        return HKUnit.gramUnit()
    }

    public var foodType: String? {
        return metadata?[HKMetadataKeyFoodType] as? String
    }

    public var absorptionTime: NSTimeInterval? {
        return metadata?[MetadataKeyAbsorptionTimeMinutes] as? NSTimeInterval
    }

    public var createdByCurrentApp: Bool {
        return sourceRevision.source == HKSource.defaultSource()
    }
}