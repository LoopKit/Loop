//
//  GlucoseRangeSchedule.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit


extension GlucoseRangeSchedule {
    func minQuantity(at date: Date) -> LoopQuantity {
        return LoopQuantity(unit: unit, doubleValue: value(at: date).minValue)
    }
    func maxQuantity(at date: Date) -> LoopQuantity {
        return LoopQuantity(unit: unit, doubleValue: value(at: date).maxValue)
    }
}
