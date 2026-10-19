//
//  GetBolusRecommendationUserInfo.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit


public struct GetBolusRecommendationUserInfo {
    public let carbEntry: NewCarbEntry?

    public init(carbEntry: NewCarbEntry?) {
        self.carbEntry = carbEntry
    }
}


extension GetBolusRecommendationUserInfo: RawRepresentable {
    public typealias RawValue = [String: Any]

    static let version = 1
    public static let name = "GetBolusRecommendationUserInfo"

    public init?(rawValue: RawValue) {
        guard rawValue["v"] as? Int == type(of: self).version && rawValue["name"] as? String == GetBolusRecommendationUserInfo.name
        else {
            return nil
        }

        if let rawCarbEntry = rawValue["ce"] {
            guard let carbEntry = (rawCarbEntry as? NewCarbEntry.RawValue).flatMap(NewCarbEntry.init(rawValue:)) else {
                return nil
            }
            self.carbEntry = carbEntry
        } else {
            self.carbEntry = nil
        }
    }

    public var rawValue: RawValue {
        var rval: RawValue = [
            "v": type(of: self).version,
            "name": GetBolusRecommendationUserInfo.name,
        ]
        rval["ce"] = carbEntry?.rawValue
        return rval
    }
}
