//
//  SensorDisplayableContext.swift
//  Loop
//
//  Created by Bharat Mediratta on 6/25/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopUI


struct SensorDisplayableContext: SensorDisplayable {
    let isStateValid: Bool
    let stateDescription: String
    let trendType: GlucoseTrendType?
    let isLocal: Bool
}


extension SensorDisplayableContext: RawRepresentable {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        var raw: RawValue = [
            "isStateValid": isStateValid,
            "stateDescription": stateDescription,
            "isLocal": isLocal
        ]
        raw["trendType"] = trendType?.rawValue

        return raw
    }

    init(_ other: SensorDisplayable) {
        isStateValid = other.isStateValid
        stateDescription = other.stateDescription
        isLocal = other.isLocal
        trendType = other.trendType
    }

    init?(rawValue: RawValue) {
        guard
            let isStateValid     = rawValue["isStateValid"] as? Bool,
            let stateDescription = rawValue["stateDescription"] as? String,
            let isLocal          = rawValue["isLocal"] as? Bool
            else {
                return nil
        }

        self.isStateValid = isStateValid
        self.stateDescription = stateDescription
        self.isLocal = isLocal

        if let rawValue = rawValue["trendType"] as? GlucoseTrendType.RawValue {
            trendType = GlucoseTrendType(rawValue: rawValue)
        } else {
            trendType = nil
        }
    }
}
