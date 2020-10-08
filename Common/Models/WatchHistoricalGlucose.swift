//
//  WatchHistoricalGlucose.swift
//  Loop
//
//  Created by Bharat Mediratta on 6/22/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit


struct WatchHistoricalGlucose {
    let samples: [NewGlucoseSample]

    init(with samples: [StoredGlucoseSample]) {
        self.samples = samples.map {
            NewGlucoseSample(date: $0.startDate, quantity: $0.quantity, isDisplayOnly: $0.isDisplayOnly, wasUserEntered: $0.wasUserEntered, syncIdentifier: $0.syncIdentifier, syncVersion: 0)
        }
    }
}


extension WatchHistoricalGlucose: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "d": samples.map { $0.date },
            "v": samples.map { Int16($0.quantity.doubleValue(for: .milligramsPerDeciliter)) },
            "id": samples.map { $0.syncIdentifier },
            "do": samples.map { $0.isDisplayOnly },
            "ue": samples.map { $0.wasUserEntered }
        ]
    }

    init?(rawValue: RawValue) {
        guard
            let dates = rawValue["d"] as? [Date],
            let values = rawValue["v"] as? [Int16],
            let syncIdentifiers = rawValue["id"] as? [String],
            let isDisplayOnly = rawValue["do"] as? [Bool],
            let wasUserEntered = rawValue["ue"] as? [Bool],
            dates.count == values.count,
            dates.count == syncIdentifiers.count,
            dates.count == isDisplayOnly.count,
            dates.count == wasUserEntered.count
        else {
                return nil
        }

        self.samples = (0..<dates.count).map {
            NewGlucoseSample(date: dates[$0], quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(values[$0])), isDisplayOnly: isDisplayOnly[$0], wasUserEntered: wasUserEntered[$0], syncIdentifier: syncIdentifiers[$0], syncVersion: 0)
        }
    }
}
