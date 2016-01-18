//
//  HKUnit.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/17/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import HealthKit


extension HKUnit {
    static func milligramsPerDeciliterUnit() -> HKUnit {
        return HKUnit.gramUnitWithMetricPrefix(.Milli).unitDividedByUnit(HKUnit.literUnitWithMetricPrefix(.Deci))
    }

    static func millimolesPerLiterUnit() -> HKUnit {
        return HKUnit.moleUnitWithMetricPrefix(.Milli, molarMass: HKUnitMolarMassBloodGlucose).unitDividedByUnit(HKUnit.literUnit())
    }
}
