//
//  WatchPredictedGlucose.swift
//  WatchApp Extension
//
//  Created by Bharat Mediratta on 6/26/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

public struct WatchPredictedGlucose: Equatable {
    public let values: [PredictedGlucoseValue]

    public init?(values: [PredictedGlucoseValue]) {
        guard values.count > 1 else {
            return nil
        }
        self.values = values
    }
}


extension WatchPredictedGlucose: RawRepresentable {
    public typealias RawValue = [String: Any]

    public var rawValue: RawValue {

        return [
            "v": values.map { Int16($0.quantity.doubleValue(for: .milligramsPerDeciliter).clamped(to: Double(Int16.min)...Double(Int16.max))) },
            "d": values[0].startDate,
            "i": values[1].startDate.timeIntervalSince(values[0].startDate)
        ]
    }

    public init?(rawValue: RawValue) {
        guard
            let values = rawValue["v"] as? [Int16],
            let firstDate = rawValue["d"] as? Date,
            let interval = rawValue["i"] as? TimeInterval
            else {
                return nil
        }

        self.values = values.enumerated().map { tuple in
            PredictedGlucoseValue(startDate: firstDate + Double(tuple.0) * interval,
                                  quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(tuple.1)))
        }
    }
}
