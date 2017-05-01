//
//  GlucoseThreshold.swift
//  Loop
//
//  Created by Pete Schwamb on 1/1/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit

struct GlucoseThreshold: RawRepresentable {
    typealias RawValue = [String: Any]
    
    let value: Double
    let unit: HKUnit
    
    public var quantity: HKQuantity {
        return HKQuantity(unit: unit, doubleValue: value)
    }
    
    public init(unit: HKUnit, value: Double) {
        self.value = value
        self.unit = unit
    }
    
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


extension GlucoseThreshold: Equatable {
    static func ==(lhs: GlucoseThreshold, rhs: GlucoseThreshold) -> Bool {
        return lhs.value == rhs.value
    }
}
