//
//  TransmitterGlucose.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import LoopKit
import HealthKit
import xDripG5


struct TransmitterGlucose: GlucoseValue {
    let glucoseMessage: GlucoseRxMessage
    let startTime: NSTimeInterval

    init?(glucoseMessage: GlucoseRxMessage, startTime: NSTimeInterval?) {

        guard glucoseMessage.state > 5 && glucoseMessage.glucose >= 20, let startTime = startTime else {
            return nil
        }

        self.glucoseMessage = glucoseMessage
        self.startTime = startTime
    }

    var quantity: HKQuantity {
        return HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: Double(glucoseMessage.glucose))
    }

    var startDate: NSDate {
        return NSDate(timeIntervalSince1970: startTime).dateByAddingTimeInterval(NSTimeInterval(glucoseMessage.timestamp))
    }
}