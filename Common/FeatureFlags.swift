//
//  FeatureFlags.swift
//  Loop
//
//  Created by Michael Pangburn on 5/19/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation


let FeatureFlags = FeatureFlagConfiguration()

struct FeatureFlagConfiguration: Decodable {
    let sensitivityOverridesEnabled: Bool

    fileprivate init() {
        // Swift compiler config is inverse, since the default state is enabled.
        #if FEATURE_OVERRIDES_DISABLED
        self.sensitivityOverridesEnabled = false
        #else
        self.sensitivityOverridesEnabled = true
        #endif
    }
}
