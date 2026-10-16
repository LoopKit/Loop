//
//  SetBolusUserInfo.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/20/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit


public struct SetBolusUserInfo {
    public let value: Double
    public let startDate: Date
    public let contextDate: Date?
    public let carbEntry: NewCarbEntry?
    public let activationType: BolusActivationType

    public init(value: Double, startDate: Date, contextDate: Date?, carbEntry: NewCarbEntry?, activationType: BolusActivationType) {
        self.value = value
        self.startDate = startDate
        self.contextDate = contextDate
        self.carbEntry = carbEntry
        self.activationType = activationType
    }
}


extension SetBolusUserInfo: RawRepresentable {
    public typealias RawValue = [String: Any]

    public static let version = 1
    public static let name = "SetBolusUserInfo"

    public init?(rawValue: RawValue) {
        guard rawValue["v"] as? Int == type(of: self).version &&
                rawValue["name"] as? String == SetBolusUserInfo.name,
              let value = rawValue["bv"] as? Double,
              let startDate = rawValue["sd"] as? Date,
              let rawActivationType = rawValue["at"] as? BolusActivationType.RawValue,
              let activationType = BolusActivationType(rawValue: rawActivationType)
        else {
            return nil
        }

        self.value = value
        self.startDate = startDate
        self.contextDate = rawValue["cd"] as? Date
        if let rawCarbEntry = rawValue["ce"] {
            guard let carbEntry = (rawCarbEntry as? NewCarbEntry.RawValue).flatMap(NewCarbEntry.init(rawValue:)) else {
                return nil
            }
            self.carbEntry = carbEntry
        } else {
            self.carbEntry = nil
        }
        self.activationType = activationType
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "v": type(of: self).version,
            "name": SetBolusUserInfo.name,
            "bv": value,
            "sd": startDate
        ]

        raw["cd"] = contextDate
        raw["ce"] = carbEntry?.rawValue
        raw["at"] = activationType.rawValue

        return raw
    }
}
