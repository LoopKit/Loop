//
//  NetBasalContext.swift
//  Loop
//
//  Created by Bharat Mediratta on 6/25/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation

struct NetBasalContext {
    let rate: Double
    let percentage: Double
    let start: Date
    let end: Date
}

extension NetBasalContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "rate": rate,
            "percentage": percentage,
            "start": start,
            "end": end
        ]
    }

    init?(rawValue: RawValue) {
        guard
            let rate       = rawValue["rate"] as? Double,
            let percentage = rawValue["percentage"] as? Double,
            let start      = rawValue["start"] as? Date,
            let end        = rawValue["end"] as? Date
            else {
                return nil
        }

        self.rate = rate
        self.percentage = percentage
        self.start = start
        self.end = end
    }
}
