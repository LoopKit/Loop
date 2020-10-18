//
//  IntentExtensionInfo.swift
//  Loop Intent Extension
//
//  Created by Anna Quinlan on 10/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation

struct IntentExtensionInfo: RawRepresentable {
    typealias RawValue = [String: Any]

    var overridePresetNames: [String]?
    
    init() { }
    
    init(rawValue: RawValue) {
        overridePresetNames = rawValue["overridePresetNames"] as? [String]
    }
    
    init(overridePresetNames: [String]?) {
        self.overridePresetNames = overridePresetNames
    }
    
    var rawValue: RawValue {
        var raw: RawValue = [:]
        
        raw["overridePresetNames"] = overridePresetNames
        
        return raw
    }
}
