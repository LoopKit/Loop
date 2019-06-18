//
//  FeatureFlags.swift
//  Loop
//
//  Created by Michael Pangburn on 5/19/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation


let FeatureFlags: FeatureFlagConfiguration = {
    guard
        let path = Bundle.main.path(forResource: "FeatureFlags", ofType: "plist"),
        let data = FileManager.default.contents(atPath: path),
        let configuration = try? PropertyListDecoder().decode(FeatureFlagConfiguration.self, from: data)
    else {
        return FeatureFlagConfiguration()
    }

    return configuration
}()

struct FeatureFlagConfiguration: Decodable {
    let sensitivityOverridesEnabled: Bool

    fileprivate init() {
        self.sensitivityOverridesEnabled = false
    }
}
