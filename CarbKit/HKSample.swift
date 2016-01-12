//
//  HKSample.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/10/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import HealthKit


public let MetadataKeyAbsorptionTimeMinutes = "com.loudnate.CarbKit.HKMetadataKey.AbsorptionTimeMinutes"


public extension HKSample {
    var absorptionTime: NSTimeInterval? {
        return metadata?[MetadataKeyAbsorptionTimeMinutes] as? NSTimeInterval
    }

    var foodType: String? {
        return metadata?[HKMetadataKeyFoodType] as? String
    }
}
