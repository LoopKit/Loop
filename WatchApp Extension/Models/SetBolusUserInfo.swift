//
//  SetBolusUserInfo.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/20/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


struct SetBolusUserInfo {
    let value: Double
    let startDate: Date

    init(value: Double, startDate: Date) {
        self.value = value
        self.startDate = startDate
    }
}


extension SetBolusUserInfo: RawRepresentable {
    typealias RawValue = [String: Any]

    static let version = 1
    static let name = "SetBolusUserInfo"

    init?(rawValue: RawValue) {
        guard rawValue["v"] as? Int == type(of: self).version &&
            rawValue["name"] as? String == SetBolusUserInfo.name,
            let value = rawValue["bv"] as? Double,
            let startDate = rawValue["sd"] as? Date else
        {
            return nil
        }

        self.value = value
        self.startDate = startDate
    }

    var rawValue: RawValue {
        return [
            "v": type(of: self).version,
            "name": SetBolusUserInfo.name,
            "bv": value,
            "sd": startDate
        ]
    }
}
