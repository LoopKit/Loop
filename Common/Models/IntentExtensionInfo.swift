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
    var presetNameToSet: String?
    
    init() { }
    
    init(rawValue: RawValue) {
        overridePresetNames = rawValue["overridePresetNames"] as? [String]
        presetNameToSet = rawValue["presetNameToSet"] as? String
    }
    
    var rawValue: RawValue {
        var raw: RawValue = [:]
        
        raw["overridePresetNames"] = overridePresetNames
        raw["presetNameToSet"] = presetNameToSet
        
        return raw
    }
}
