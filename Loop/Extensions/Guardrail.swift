//
//  Guardrail.swift
//  Loop
//
//  Created by Michael Pangburn on 4/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit


extension Guardrail where Value == HKQuantity {
    static let suspendThreshold = Guardrail(absoluteBounds: 54...180, recommendedBounds: 71...120, unit: .milligramsPerDeciliter)
}

