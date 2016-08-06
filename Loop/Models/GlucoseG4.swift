//
//  GlucoseG4.swift
//  Loop
//
//  Created by Mark Wilson on 7/21/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import G4ShareSpy
import HealthKit
import LoopKit


extension GlucoseG4 {
    var isValid: Bool {
        return glucose >= 20
    }
}


extension GlucoseG4: GlucoseValue {
    public var quantity: HKQuantity {
        return HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: Double(glucose))
    }

    public var startDate: NSDate {
        return time
    }
}


extension GlucoseG4: SensorDisplayable {
    var stateDescription: String {
        if isValid {
            return "✓"
        } else {
            return String(format: "%02x", glucose)
        }
    }

    var trendType: GlucoseTrend? {
        return GlucoseTrend(rawValue: Int(trend))
    }

    var trendDescription: String {
        return trendType?.description ?? ""
    }
}
