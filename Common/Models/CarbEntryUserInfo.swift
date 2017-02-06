//
//  CarbEntryUserInfo.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation

enum AbsorptionTimeType {
    case fast
    case medium
    case slow
}


struct CarbEntryUserInfo {
    let value: Double
    let absorptionTimeType: AbsorptionTimeType
    let startDate: Date

    init(value: Double, absorptionTimeType: AbsorptionTimeType, startDate: Date) {
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
            self = .fast
        case 1:
            self = .medium
        case 2:
            self = .slow
        default:
            return nil
        }
    }

    var rawValue: RawValue {
        switch self {
        case .fast:
            return 0
        case .medium:
            return 1
        case .slow:
            return 2
        }
    }
}


extension CarbEntryUserInfo: RawRepresentable {
    typealias RawValue = [String: Any]

    static let version = 1
    static let name = "CarbEntryUserInfo"

    init?(rawValue: RawValue) {
        guard rawValue["v"] as? Int == type(of: self).version && rawValue["name"] as? String == CarbEntryUserInfo.name,
            let value = rawValue["cv"] as? Double,
            let absorptionTimeRaw = rawValue["ca"] as? Int,
            let absorptionTime = AbsorptionTimeType(rawValue: absorptionTimeRaw),
            let startDate = rawValue["sd"] as? Date else
        {
            return nil
        }

        self.value = value
        self.startDate = startDate
        self.absorptionTimeType = absorptionTime
    }

    var rawValue: RawValue {
        return [
            "v": type(of: self).version,
            "name": CarbEntryUserInfo.name,
            "cv": value,
            "ca": absorptionTimeType.rawValue,
            "sd": startDate
        ]
    }
}
