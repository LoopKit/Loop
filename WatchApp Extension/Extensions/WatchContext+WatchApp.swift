//
//  WatchContext.swift
//  Loop
//
//  Created by Bharat Mediratta on 12/16/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

extension WatchContext {
    var glucoseTrend: GlucoseTrend? {
        if let glucoseTrendRawValue = glucoseTrendRawValue {
            return GlucoseTrend(rawValue: glucoseTrendRawValue)
        } else {
            return nil
        }
    }

    var activeInsulin: HKQuantity? {
        guard let value = iob else {
            return nil
        }

        return HKQuantity(unit: .internationalUnit(), doubleValue: value)
    }

    var activeCarbohydrates: HKQuantity? {
        guard let value = cob else {
            return nil
        }

        return HKQuantity(unit: .gram(), doubleValue: value)
    }

    var reservoirVolume: HKQuantity? {
        guard let value = reservoir else {
            return nil
        }

        return HKQuantity(unit: .internationalUnit(), doubleValue: value)
    }
}
