//
//  GlucoseBackfillRequestUserInfo.swift
//  Loop
//
//  Created by Bharat Mediratta on 6/21/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation

struct GlucoseBackfillRequestUserInfo {
    let version = 1
    let startDate: Date
}

extension GlucoseBackfillRequestUserInfo: RawRepresentable {
    typealias RawValue = [String: Any]

    static let name = "GlucoseBackfillRequestUserInfo"

    init?(rawValue: RawValue) {
        guard
            rawValue["v"] as? Int == version,
            rawValue["name"] as? String == GlucoseBackfillRequestUserInfo.name,
            let startDate = rawValue["sd"] as? Date
        else {
            return nil
        }

        self.startDate = startDate
    }

    var rawValue: RawValue {
        return [
            "v": version,
            "name": GlucoseBackfillRequestUserInfo.name,
            "sd": startDate
        ]
    }
}
