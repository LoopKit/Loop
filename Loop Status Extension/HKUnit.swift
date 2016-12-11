//
//  HKUnit.swift
//  Loop
//
//  Created by Bharat Mediratta on 12/2/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import HealthKit

public extension HKUnit {
    // A formatting helper for determining the preferred decimal style for a given unit
    // This is similar to the LoopKit HKUnit extension, but copied here so that we can
    // avoid a dependency on LoopKit from the Loop Status Extension.
    var preferredMinimumFractionDigits: Int {
        if self.unitString == "mg/dL" {
            return 0
        } else {
            return 1
        }
    }
}
