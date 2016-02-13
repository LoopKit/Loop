//
//  CarbRatioSchedule.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


public class CarbRatioSchedule: DailyQuantitySchedule {
    public override init?(unit: HKUnit, dailyItems: [RepeatingScheduleValue<Double>], timeZone: NSTimeZone? = nil) {
        super.init(unit: unit, dailyItems: dailyItems, timeZone: timeZone)

        guard unit == HKUnit.gramUnit() else {
            return nil
        }
    }
}
