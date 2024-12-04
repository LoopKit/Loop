//
//  WatchContext+LoopKit.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit
import LoopAlgorithm

extension WatchContext {
    convenience init(glucose: GlucoseSampleValue?, glucoseUnit: LoopUnit?) {
        self.init()

        self.glucose = glucose?.quantity
        self.glucoseCondition = glucose?.condition
        self.glucoseDate = glucose?.startDate
        self.glucoseIsDisplayOnly = glucose?.isDisplayOnly
        self.glucoseWasUserEntered = glucose?.wasUserEntered
        self.displayGlucoseUnit = glucoseUnit
    }
}
