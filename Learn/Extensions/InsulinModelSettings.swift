//
//  InsulinModelSettings.swift
//  Learn
//
//  Created by Pete Schwamb on 4/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopCore
import LoopKit

extension InsulinModelSettings {
    typealias RawValue = [String: Any]
    
    var modelName: String {
        switch self {
        case .exponentialPreset:
            return "exponentialPreset"
        case .walsh:
            return "walsh"
        }
    }
    
    init?(rawValue: RawValue) {
        guard let modelName = rawValue["modelName"] as? String else {
            return nil
        }
        
        switch modelName {
        case "exponentialPreset":
            guard
                let presetRaw = rawValue["preset"] as? String,
                let preset = ExponentialInsulinModelPreset(rawValue: presetRaw)
            else {
                return nil
            }
            self = .exponentialPreset(preset)
        case "walsh":
            guard
                let actionDuration = rawValue["actionDuration"] as? TimeInterval,
                let delay = rawValue["delay"] as? TimeInterval
            else {
                return nil
            }
            self = .walsh(WalshInsulinModel(actionDuration: actionDuration, delay: delay))
        default:
            return nil
        }
    }
    
    var rawValue: RawValue {
        var rval: RawValue = [
            "modelName": modelName,
        ]
        
        switch self {
        case .exponentialPreset(let preset):
            rval["preset"] = preset.rawValue
        case .walsh(let model):
            rval["actionDuration"] = model.actionDuration
            rval["delay"] = model.delay
        }
        return rval
    }
}
