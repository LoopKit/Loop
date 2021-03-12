//
//  WatchContext+LoopKit.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

extension WatchContext {
    convenience init(glucose: GlucoseSampleValue?, glucoseUnit: HKUnit?) {
        self.init()

        self.glucose = glucose?.quantity
        self.glucoseDate = glucose?.startDate
        self.glucoseIsDisplayOnly = glucose?.isDisplayOnly
        self.glucoseWasUserEntered = glucose?.wasUserEntered
        self.displayGlucoseUnit = glucoseUnit
    }
}
