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
import LoopUI
import ShareClient


extension ShareGlucose: GlucoseValue {
    public var startDate: Date {
        return timestamp
    }

    public var quantity: HKQuantity {
        return HKQuantity(unit: HKUnit.milligramsPerDeciliter(), doubleValue: Double(glucose))
    }
}


extension ShareGlucose: SensorDisplayable {
    public var isStateValid: Bool {
        return glucose >= 20
    }

    public var trendType: GlucoseTrend? {
        return GlucoseTrend(rawValue: Int(trend))
    }

    public var isLocal: Bool {
        return false
    }
}

extension SensorDisplayable {
    public var stateDescription: String {
        if isStateValid {
            return NSLocalizedString("OK", comment: "Sensor state description for the valid state")
        } else {
            return NSLocalizedString("Needs Attention", comment: "Sensor state description for the non-valid state")
        }
    }
}
