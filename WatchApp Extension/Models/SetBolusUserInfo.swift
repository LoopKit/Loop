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
    let startDate: NSDate

    init(value: Double, startDate: NSDate) {
        self.value = value
        self.startDate = startDate
    }
}


extension SetBolusUserInfo: RawRepresentable {
    typealias RawValue = [String: AnyObject]

    static let version = 1
    static let name = "SetBolusUserInfo"

    init?(rawValue: RawValue) {
        guard rawValue["v"] as? Int == self.dynamicType.version &&
            rawValue["name"] as? String == SetBolusUserInfo.name,
            let value = rawValue["bv"] as? Double,
            startDate = rawValue["sd"] as? NSDate else
        {
            return nil
        }

        self.value = value
        self.startDate = startDate
    }

    var rawValue: RawValue {
        return [
            "v": self.dynamicType.version,
            "name": SetBolusUserInfo.name,
            "bv": value,
            "sd": startDate
        ]
    }
}
