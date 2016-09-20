//
//  ShareGlucose+GlucoseKit.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/8/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import ShareClient


extension ShareGlucose: GlucoseValue {
    public var startDate: Date {
        return timestamp
    }

    public var quantity: HKQuantity {
        return HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: Double(glucose))
    }
}


extension ShareGlucose: SensorDisplayable {
    var isStateValid: Bool {
        return glucose >= 20
    }

    var trendType: GlucoseTrend? {
        return GlucoseTrend(rawValue: Int(trend))
    }
}
