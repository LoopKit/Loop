//
//  WatchDatedRange.swift
//  WatchApp Extension
//
//  Created by Bharat Mediratta on 6/26/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


struct WatchDatedRange {
    public let startDate: Date
    public let endDate: Date
    public let minValue: Double
    public let maxValue: Double

    public init(startDate: Date, endDate: Date, minValue: Double, maxValue: Double) {
        self.startDate = startDate
        self.endDate = endDate
        self.minValue = minValue
        self.maxValue = maxValue
    }
}


extension WatchDatedRange: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "sd": startDate,
            "ed": endDate,
            "mi": minValue,
            "ma": maxValue
        ]
    }

    init?(rawValue: RawValue) {
        guard
            let startDate = rawValue["sd"] as? Date,
            let endDate = rawValue["ed"] as? Date,
            let minValue = rawValue["mi"] as? Double,
            let maxValue = rawValue["ma"] as? Double
            else {
                return nil
        }

        self.startDate = startDate
        self.endDate = endDate
        self.minValue = minValue
        self.maxValue = maxValue
    }
}
