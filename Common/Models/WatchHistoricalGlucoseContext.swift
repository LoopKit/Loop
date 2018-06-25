//
//  WatchHistoricalGlucose.swift
//  Loop
//
//  Created by Bharat Mediratta on 6/22/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit

struct WatchHistoricalGlucoseContext {
    let dates: [Date]
    let values: [Double]
    let unit: HKUnit

    var samples: [WatchGlucoseContext] {
        return zip(dates, values).map {
            WatchGlucoseContext(value: $0.1, unit: unit, startDate: $0.0)
        }
    }
}

extension WatchHistoricalGlucoseContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "d": dates,
            "v": values,
            "u": unit.unitString,
        ]
    }

    init?(rawValue: RawValue) {
        guard
            let dates = rawValue["d"] as? [Date],
            let values = rawValue["v"] as? [Double],
            let unitString = rawValue["u"] as? String
        else {
                return nil
        }

        self.dates = dates
        self.values = values
        self.unit = HKUnit(from: unitString)
    }
}
