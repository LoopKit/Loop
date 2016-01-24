//
//  AbsorptionTimeType+CarbKit.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/24/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import CarbKit


extension AbsorptionTimeType {
    func absorptionTimeFromDefaults(defaults: CarbStore.DefaultAbsorptionTimes) -> NSTimeInterval {
        switch self {
        case .Fast:
            return defaults.fast
        case .Medium:
            return defaults.medium
        case .Slow:
            return defaults.slow
        }
    }
}
