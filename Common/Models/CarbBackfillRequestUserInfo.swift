//
//  CarbBackfillRequestUserInfo.swift
//  Loop
//
//  Created by Darin Krauss on 8/14/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation

struct CarbBackfillRequestUserInfo {
    let version = 1
    let startDate: Date
}

extension CarbBackfillRequestUserInfo: RawRepresentable {
    typealias RawValue = [String: Any]

    static let name = "CarbBackfillRequestUserInfo"

    init?(rawValue: RawValue) {
        guard
            rawValue["v"] as? Int == version,
            rawValue["name"] as? String == CarbBackfillRequestUserInfo.name,
            let startDate = rawValue["sd"] as? Date
            else {
                return nil
        }

        self.startDate = startDate
    }

    var rawValue: RawValue {
        return [
            "v": version,
            "name": CarbBackfillRequestUserInfo.name,
            "sd": startDate
        ]
    }
}
