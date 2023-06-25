//
//  ApplicationFactorStrategy.swift
//  Loop
//
//  Created by Jonas Björkert on 2023-06-03.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore

protocol ApplicationFactorStrategy {
    func calculateDosingFactor(
        for glucose: HKQuantity,
        correctionRangeSchedule: GlucoseRangeSchedule,
        settings: LoopSettings
    ) -> Double
}
