//
//  GlucoseRangeSchedule.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit


extension GlucoseRangeSchedule {
    var workoutModeEnabled: Bool? {
        guard let override = temporaryOverride else {
            return false
        }

        return override.endDate.timeIntervalSinceNow > 0
    }
}
