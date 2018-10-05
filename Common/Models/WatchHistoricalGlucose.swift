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
            NewGlucoseSample(date: $0.startDate, quantity: $0.quantity, isDisplayOnly: false, syncIdentifier: $0.syncIdentifier, syncVersion: 0)
        }
    }
}


extension WatchHistoricalGlucose: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "d": samples.map { $0.date },
            "v": samples.map { Int16($0.quantity.doubleValue(for: .milligramsPerDeciliter)) },
            "id": samples.map { $0.syncIdentifier }
        ]
    }

    init?(rawValue: RawValue) {
        guard
            let dates = rawValue["d"] as? [Date],
            let values = rawValue["v"] as? [Int16],
            let syncIdentifiers = rawValue["id"] as? [String],
            dates.count == values.count,
            dates.count == syncIdentifiers.count
        else {
                return nil
        }

        self.samples = (0..<dates.count).map {
            NewGlucoseSample(date: dates[$0], quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(values[$0])), isDisplayOnly: false, syncIdentifier: syncIdentifiers[$0], syncVersion: 0)
        }
    }
}
