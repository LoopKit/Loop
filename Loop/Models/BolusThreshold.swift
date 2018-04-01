//
//  BolusThreshold.swift
//  Loop
//
//  Created by David Daniels on 3/25/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//



import Foundation
import HealthKit

struct BolusThreshold: RawRepresentable {
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


extension BolusThreshold: Equatable {
    static func ==(lhs: BolusThreshold, rhs: BolusThreshold) -> Bool {
        return lhs.value == rhs.value
    }
}

