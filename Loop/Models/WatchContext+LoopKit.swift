//
//  WatchContext+LoopKit.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import InsulinKit
import LoopKit
import xDripG5


extension WatchContext {
    convenience init(glucose: GlucoseValue?, eventualGlucose: GlucoseValue?, glucoseUnit: HKUnit?) {
        self.init()

        self.glucose = glucose?.quantity
        self.glucoseDate = glucose?.startDate
        self.eventualGlucose = eventualGlucose?.quantity
        self.preferredGlucoseUnit = glucoseUnit
    }
}
