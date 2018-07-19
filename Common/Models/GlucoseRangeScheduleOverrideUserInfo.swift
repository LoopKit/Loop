//
//  GlucoseRangeScheduleOverrideUserInfo.swift
//  Loop
//
//  Created by Michael Pangburn on 12/30/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation


struct GlucoseRangeScheduleOverrideUserInfo {
    enum Context: Int {
        case workout
        case preMeal

        static var allContexts: [Context] {
            return [.workout, .preMeal]
        }
    }

    let context: Context
    let startDate: Date
    let endDate: Date?

    var effectiveEndDate: Date {
        return endDate ?? .distantFuture
    }

    var dateInterval: DateInterval {
        return DateInterval(start: startDate, end: effectiveEndDate)
    }
}

extension GlucoseRangeScheduleOverrideUserInfo: RawRepresentable {
    typealias RawValue = [String: Any]

    static let version = 1
    static let name = "GlucoseRangeScheduleOverrideUserInfo"

    init?(rawValue: RawValue) {
        guard rawValue["v"] as? Int == type(of: self).version && rawValue["name"] as? String == GlucoseRangeScheduleOverrideUserInfo.name,
            let contextRawValue = rawValue["context"] as? Int,
            let context = Context(rawValue: contextRawValue),
            let startDate = rawValue["startDate"] as? Date else
        {
            return nil
        }

        self.context = context
        self.startDate = startDate
        self.endDate = rawValue["endDate"] as? Date
    }

    var rawValue: RawValue {
        var raw: RawValue = [
            "v": type(of: self).version,
            "name": type(of: self).name,
            "context": context.rawValue,
            "startDate": startDate
        ]

        if let endDate = endDate {
            raw["endDate"] = endDate
        }

        return raw
    }

    /// The "raw value" of an override message intended to clear any active override
    static let clearOverride: RawValue = [
        "v": version,
        "name": name
    ]
}
