//
//  CarbEntryUserInfo.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation

enum AbsorptionTimeType {
    case Fast
    case Medium
    case Slow
}


struct CarbEntryUserInfo {
    let value: Double
    let absorptionTimeType: AbsorptionTimeType
    let startDate: NSDate

    init(value: Double, absorptionTimeType: AbsorptionTimeType, startDate: NSDate) {
        self.value = value
        self.absorptionTimeType = absorptionTimeType
        self.startDate = startDate
    }
}


extension AbsorptionTimeType: RawRepresentable {
    typealias RawValue = Int

    init?(rawValue: RawValue) {
        switch rawValue {
        case 0:
            self = .Fast
        case 1:
            self = .Medium
        case 2:
            self = .Slow
        default:
            return nil
        }
    }

    var rawValue: RawValue {
        switch self {
        case .Fast:
            return 0
        case .Medium:
            return 1
        case .Slow:
            return 2
        }
    }
}


extension CarbEntryUserInfo: RawRepresentable {
    typealias RawValue = [String: AnyObject]

    static let version = 1

    init?(rawValue: RawValue) {
        guard rawValue["v"] as? Int == self.dynamicType.version,
            let value = rawValue["cv"] as? Double,
            absorptionTimeRaw = rawValue["ca"] as? Int,
            absorptionTime = AbsorptionTimeType(rawValue: absorptionTimeRaw),
            startDate = rawValue["sd"] as? NSDate else
        {
            return nil
        }

        self.value = value
        self.startDate = startDate
        self.absorptionTimeType = absorptionTime
    }

    var rawValue: RawValue {
        return [
            "v": self.dynamicType.version,
            "cv": value,
            "ca": absorptionTimeType.rawValue,
            "sd": startDate
        ]
    }
}
