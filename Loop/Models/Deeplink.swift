//
//  Deeplink.swift
//  Loop
//
//  Created by Noah Brauner on 8/9/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation

enum Deeplink: String, CaseIterable {
    case carbEntry = "carb-entry"
    case bolus = "manual-bolus"
    case preMeal = "pre-meal-preset"
    case customPresets = "custom-presets"
    
    init?(url: URL?) {
        guard let url, let host = url.host, let deeplink = Deeplink.allCases.first(where: { $0.rawValue == host }) else {
            return nil
        }
        
        self = deeplink
    }
}
