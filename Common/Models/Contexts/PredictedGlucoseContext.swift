//
//  PredictedGlucoseContext.swift
//  Loop
//
//  Created by Bharat Mediratta on 6/25/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit


struct PredictedGlucoseContext {
    let values: [Double]
    let unit: HKUnit
    let startDate: Date
    let interval: TimeInterval

    var samples: [GlucoseContext] {
        var result: [GlucoseContext] = []
        for (i, v) in values.enumerated() {
            result.append(GlucoseContext(value: v, unit: unit, startDate: startDate.addingTimeInterval(Double(i) * interval)))
        }
        return result
    }
}


extension PredictedGlucoseContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "values": values,
            "unit": unit.unitString,
            "startDate": startDate,
            "interval": interval
        ]
    }

    init?(rawValue: RawValue) {
        guard
            let values = rawValue["values"] as? [Double],
            let unitString = rawValue["unit"] as? String,
            let startDate = rawValue["startDate"] as? Date,
            let interval = rawValue["interval"] as? TimeInterval
            else {
                return nil
        }

        self.values = values
        self.unit = HKUnit(from: unitString)
        self.startDate = startDate
        self.interval = interval
    }
}
