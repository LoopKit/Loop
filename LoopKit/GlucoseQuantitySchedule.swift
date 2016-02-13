//
//  GlucoseQuantitySchedule.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


public class GlucoseQuantitySchedule: DailyQuantitySchedule {
    public override init?(unit: HKUnit, dailyItems: [RepeatingScheduleValue<Double>], timeZone: NSTimeZone? = nil) {
        super.init(unit: unit, dailyItems: dailyItems, timeZone: timeZone)

        guard unit == HKUnit.milligramsPerDeciliterUnit() || unit == HKUnit.millimolesPerLiterUnit() else {
            return nil
        }
    }
}


public typealias InsulinSensitivitySchedule = GlucoseQuantitySchedule
