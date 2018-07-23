//
//  GlucoseEffectVelocity.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit


extension GlucoseEffectVelocity: RawRepresentable {
    public typealias RawValue = [String: Any]

    static let unit = HKUnit.milligramsPerDeciliter.unitDivided(by: .minute())

    public init?(rawValue: RawValue) {
        guard let startDate = rawValue["startDate"] as? Date,
            let doubleValue = rawValue["doubleValue"] as? Double
        else {
            return nil
        }

        self.init(
            startDate: startDate,
            endDate: rawValue["endDate"] as? Date ?? startDate,
            quantity: HKQuantity(unit: type(of: self).unit, doubleValue: doubleValue)
        )
    }

    public var rawValue: RawValue {
        return [
            "startDate": startDate,
            "endDate": endDate,
            "doubleValue": quantity.doubleValue(for: type(of: self).unit)
        ]
    }
}
