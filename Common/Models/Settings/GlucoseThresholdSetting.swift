//
//  GlucoseThreshold.swift
//  Loop
//
//  Created by Pete Schwamb on 1/1/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit


struct GlucoseThresholdSetting {
    let unit: HKUnit
    let value: Double

    var quantity: HKQuantity {
        return HKQuantity(unit: unit, doubleValue: value)
    }
}


extension GlucoseThresholdSetting: RawRepresentable {
    typealias RawValue = [String: Any]

    init?(rawValue: RawValue) {
        guard let unitsStr = rawValue["units"] as? String, let value = rawValue["value"] as? Double else {
            return nil
        }
        self.unit = HKUnit(from: unitsStr)
        self.value = value
    }
    
    var rawValue: RawValue {
        return [
            "value": value,
            "units": unit.unitString
        ]
    }
}


extension GlucoseThresholdSetting: Equatable {
    static func ==(lhs: GlucoseThresholdSetting, rhs: GlucoseThresholdSetting) -> Bool {
        return lhs.value == rhs.value
    }
}
