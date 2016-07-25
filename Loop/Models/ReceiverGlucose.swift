//
//  ReceiverGlucose.swift
//  Loop
//
//  Created by Mark Wilson on 7/21/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import HealthKit
import LoopKit
import xDripG4Share


struct ReceiverGlucose: GlucoseValue {
    let glucoseRecord: GlucoseG4

    init?(glucoseRecord: GlucoseG4) {
        guard glucoseRecord.glucose >= 20 else {
            return nil
        }

        self.glucoseRecord = glucoseRecord
    }

    var quantity: HKQuantity {
        return HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: Double(glucoseRecord.glucose))
    }

    var startDate: NSDate {
        return glucoseRecord.time
    }

    var displayOnly: Bool {
        return glucoseRecord.isDisplayOnly
    }
}