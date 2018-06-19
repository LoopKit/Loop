//
//  AbsorptionTimeType+CarbKit.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/24/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import LoopKit


extension AbsorptionTimeType {
    func absorptionTimeFromDefaults(_ defaults: CarbStore.DefaultAbsorptionTimes) -> TimeInterval {
        switch self {
        case .fast:
            return defaults.fast
        case .medium:
            return defaults.medium
        case .slow:
            return defaults.slow
        }
    }
}
