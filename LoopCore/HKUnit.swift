//
//  HKUnit.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/17/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import HealthKit


extension HKUnit {
    public static let milligramsPerDeciliter: HKUnit = {
        return HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
    }()

    public static let millimolesPerLiter: HKUnit = {
        return HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter())
    }()

    public static let milligramsPerDeciliterPerMinute: HKUnit = {
        return HKUnit.milligramsPerDeciliter.unitDivided(by: .minute())
    }()

    public static let millimolesPerLiterPerMinute: HKUnit = {
        return HKUnit.millimolesPerLiter.unitDivided(by: .minute())
    }()

    public static let internationalUnitsPerHour: HKUnit = {
        return HKUnit.internationalUnit().unitDivided(by: .hour())
    }()
}
